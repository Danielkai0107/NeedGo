// lib/screens/parent_view.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import '../styles/map_styles.dart';
import '../components/full_screen_popup.dart';
import '../components/create_edit_task_bottom_sheet.dart' as new_task_sheet;
import '../components/task_detail_sheet.dart';
import '../components/location_info_sheet.dart';
import '../components/map_marker_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum BottomSheetType {
  none,
  taskDetail,
  applicantsList,
  applicantProfile,
  myPostsList,
  createEditPost,
  profileEditing,
}

class ParentView extends StatefulWidget {
  const ParentView({Key? key}) : super(key: key);

  @override
  State<ParentView> createState() => _ParentViewState();
}

class _ParentViewState extends State<ParentView> {
  final _firestore = FirebaseFirestore.instance;
  final TextEditingController _contentCtrl = TextEditingController();
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 14;
  LatLng? _myLocation;
  List<Map<String, dynamic>> _myPosts = [];
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _profileForm = {};
  List<Map<String, dynamic>> _locationSuggestions = [];
  Set<String> _availableCategories = {};
  Set<String> _selectedCategories = {};
  bool _showCategoryFilter = false;
  List<Map<String, dynamic>> _systemLocations = [];
  Map<String, dynamic>? _selectedLocation;
  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;

  // 新的地圖標記管理
  Set<Marker> _markers = {};
  MarkerData? _selectedMarker;
  Map<String, dynamic> _postForm = {
    'name': '',
    'content': '',
    'lat': null,
    'lng': null,
  };
  BottomSheetType _currentBottomSheet = BottomSheetType.none;
  String? _editingPostId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locationSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _currentApplicants = [];
  Map<String, dynamic>? _selectedApplicant;

  @override
  void initState() {
    super.initState();

    // 延遲初始化，避免在 widget 還沒準備好時就開始載入
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationSearchCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // 在 _initializeData 中加入錯誤處理
  Future<void> _initializeData() async {
    if (!mounted) return;

    try {
      // 依序初始化，每步都檢查 mounted
      if (mounted) await _loadSystemLocations();
      if (mounted) await _findAndRecenter();
      if (mounted) await _loadMyProfile();
      if (mounted) await _loadMyPosts();

      // 延遲再次載入
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        await _loadMyPosts();
        // 確保初始化完成後更新標記
        _updateMarkers();
      }
    } catch (e) {
      print('初始化失敗: $e');
      // 不要在這裡顯示 SnackBar，可能導致問題
    }
  }

  /// 获取当前定位
  Future<void> _findAndRecenter() async {
    // 1. 申请定位权限
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請在系統設定允許定位權限')));
      return;
    }

    // 2. 取到当前位置
    final pos = await Geolocator.getCurrentPosition();
    final newLatLng = LatLng(pos.latitude, pos.longitude);

    // 3. 更新 state
    setState(() => _myLocation = newLatLng);

    // 4. 地图移动到定位点并放大
    if (mounted) {
      _mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(newLatLng, 16));
    }
  }

  // 舊的 _selectLocationMarker 和 _closeLocationPopup 方法已移除
  // 現在使用直接的 showModalBottomSheet 方式

  Future<void> _loadSystemLocations() async {
    try {
      final snapshot = await _firestore.collection('systemLocations').get();
      final locations = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // 提取所有類別
      final categories = locations
          .map((loc) => loc['category']?.toString() ?? '')
          .where((cat) => cat.isNotEmpty)
          .toSet();

      setState(() {
        _systemLocations = locations;
        _availableCategories = categories;
        _selectedCategories = Set.from(categories); // 預設全選
      });

      print('載入了 ${locations.length} 個系統地點，${categories.length} 個類別');

      // 載入系統地點後更新標記
      _updateMarkers();
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  /// 计算路程
  Future<void> _calculateTravelInfo(LatLng dest) async {
    if (_myLocation == null) return;
    setState(() => _isLoadingTravel = true);
    final o = '${_myLocation!.latitude},${_myLocation!.longitude}';
    final d = '${dest.latitude},${dest.longitude}';
    final modes = ['driving', 'walking', 'transit'];
    final info = <String, String>{};
    for (var m in modes) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$o&destinations=$d&mode=$m&key=$_apiKey',
        );
        final resp = await http.get(url);
        final row = jsonDecode(resp.body)['rows'][0]['elements'][0];
        info[m] = '${row['duration']['text']} (${row['distance']['text']})';
      } catch (_) {
        info[m] = '無法計算';
      }
    }
    setState(() {
      _travelInfo = info;
      _isLoadingTravel = false;
    });
  }

  /// 搜地点建议
  Future<void> _fetchLocationSuggestions(String input) async {
    print('🔍 開始搜尋地點: "$input"');

    if (input.isEmpty) {
      setState(() => _locationSuggestions = []);
      print('🔍 輸入為空，清空建議列表');
      return;
    }

    // 檢查 API Key
    if (_apiKey.isEmpty) {
      print('❌ Google Maps API Key 未設定或為空');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google Maps API Key 未設定')));
      return;
    }

    print('✅ API Key 已設定: ${_apiKey.substring(0, 10)}...');

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&key=$_apiKey'
        '&language=zh-TW&components=country:tw',
      );

      print('🌐 API URL: $url');

      final resp = await http.get(url);
      print('📡 HTTP 狀態碼: ${resp.statusCode}');
      print(
        '📡 回應內容: ${resp.body.length > 200 ? resp.body.substring(0, 200) + '...' : resp.body}',
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        print('📊 API 狀態: ${data['status']}');

        if (data['status'] == 'OK') {
          final preds = data['predictions'] as List;
          setState(() {
            _locationSuggestions = preds
                .map(
                  (p) => {
                    'description': p['description'],
                    'place_id': p['place_id'],
                  },
                )
                .toList();
          });
          print('✅ 成功載入 ${_locationSuggestions.length} 個地點建議');

          // 顯示前 3 個建議的詳細信息
          for (int i = 0; i < _locationSuggestions.length && i < 3; i++) {
            print('   ${i + 1}. ${_locationSuggestions[i]['description']}');
          }
        } else {
          print('❌ API 錯誤: ${data['status']}');
          if (data['error_message'] != null) {
            print('❌ 錯誤訊息: ${data['error_message']}');
          }

          // 顯示用戶友好的錯誤訊息
          String errorMsg = 'API 錯誤';
          switch (data['status']) {
            case 'REQUEST_DENIED':
              errorMsg = 'API Key 無效或服務未啟用';
              break;
            case 'OVER_QUERY_LIMIT':
              errorMsg = 'API 呼叫次數超過限制';
              break;
            case 'INVALID_REQUEST':
              errorMsg = '請求格式無效';
              break;
            default:
              errorMsg = '服務暫時無法使用: ${data['status']}';
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMsg)));
        }
      } else {
        print('❌ HTTP 錯誤: ${resp.statusCode}');
        print('❌ 錯誤內容: ${resp.body}');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('網路請求失敗: ${resp.statusCode}')));
      }
    } catch (e, stackTrace) {
      print('❌ 搜尋地點異常: $e');
      print('❌ 堆疊追蹤: $stackTrace');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('搜尋失敗: $e')));
    }
  }

  /// 选中建议；填入表单
  Future<void> _selectLocation(Map<String, dynamic> place) async {
    _locationSearchCtrl.text = place['description'];

    // ✅ 先清空建議列表
    setState(() => _locationSuggestions = []);

    final detailUrl = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${place['place_id']}&key=$_apiKey&fields=geometry,formatted_address,name',
    );

    try {
      final resp = await http.get(detailUrl);
      final result = jsonDecode(resp.body)['result'];
      final loc = result['geometry']['location'];
      final formattedAddress =
          result['formatted_address'] ?? place['description'];

      // 如果任務名稱為空，自動填入地點名稱
      if (_postForm['name']?.toString().trim().isEmpty == true) {
        _nameCtrl.text = place['description'];
        _postForm['name'] = place['description'];
      }

      // 將地址信息保存到 address 字段
      _postForm['address'] = formattedAddress;

      setState(() {
        _postForm['lat'] = loc['lat'];
        _postForm['lng'] = loc['lng'];
      });
    } catch (e) {
      print('獲取地點詳情失敗: $e');
      // 即使失敗也要更新基本信息
      setState(() {
        _postForm['address'] = place['description'];
      });
    }
  }

  /// 打开"以此静态点位发任务"表单
  void _startCreatePostFromStatic() {
    final loc = _selectedLocation!;

    // 關閉當前彈窗
    setState(() {
      _selectedLocation = null;
      _travelInfo = null;
      _currentBottomSheet = BottomSheetType.none;
    });

    // 使用新的任務創建流程，但預填地址資訊
    _showCreateTaskSheetWithLocation(loc);
  }

  /// 顯示帶有預設地址的新建任務彈窗
  void _showCreateTaskSheetWithLocation(Map<String, dynamic> location) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // 禁用外部拖拽，避免與內部 DraggableScrollableSheet 衝突
      backgroundColor: Colors.transparent,
      useSafeArea: true, // 使用安全區域
      isDismissible: true, // 允許點擊外部關閉
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        existingTask: {
          // 預填地址資訊，其他欄位留空
          'address': location['address'] ?? location['name'],
          'lat': location['lat'],
          'lng': location['lng'],
          // 其他欄位使用預設值
          'title': '',
          'content': '',
          'price': 0,
          'images': <String>[],
        },
        onSubmit: (taskData) async {
          Navigator.of(context).pop(); // 先關閉彈窗
          await _saveNewTaskData(taskData);
        },
      ),
    );
  }

  /// 手动新建任务
  void _startCreatePostManually() {
    _showCreateTaskSheet();
  }

  Future<void> _saveNewPost() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    // 表單驗證
    if (_postForm['name']?.toString().trim().isEmpty == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入任務名稱')));
      return;
    }

    if (_postForm['lat'] == null || _postForm['lng'] == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請選擇任務地點')));
      return;
    }

    try {
      // 確保座標是正確的數字類型
      final lat = _postForm['lat'] is String
          ? double.parse(_postForm['lat'])
          : _postForm['lat'].toDouble();
      final lng = _postForm['lng'] is String
          ? double.parse(_postForm['lng'])
          : _postForm['lng'].toDouble();

      final data = {
        'name': _postForm['name'].toString().trim(),
        'content': _postForm['content']?.toString().trim() ?? '',
        'address': _postForm['address']?.toString().trim() ?? '',
        'lat': lat, // 確保是 double 類型
        'lng': lng, // 確保是 double 類型
        'userId': u.uid,
        'applicants': [],
        'createdAt': Timestamp.now(),
        'status': 'open',
      };

      print('準備保存到資料庫的數據: $data');
      print('座標類型檢查 - lat: ${lat.runtimeType}, lng: ${lng.runtimeType}');

      await _firestore.collection('posts').add(data);

      // 重新載入資料
      await _loadMyPosts();

      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _editingPostId = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('任務創建成功！')));

      // 創建成功後移動地圖到新任務位置
      final newLatLng = LatLng(lat, lng);
      _mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(newLatLng, 15));
    } catch (e) {
      print('創建任務失敗: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('創建任務失敗：$e')));
    }
  }

  Future<void> _deletePost(String id) async {
    await _firestore.doc('posts/$id').delete();
    await _loadMyPosts();
    // 不再需要 _closeLocationPopup()，新的彈窗系統會自動處理
  }

  /// 加载 Parent 个人档
  Future<void> _loadMyProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      final doc = await _firestore.doc('user/${u.uid}').get(); // ✅ 改用 user 集合
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _profile = data;
          _profileForm = Map.from(_profile);
        });
      } else if (mounted) {
        setState(() {
          _profile = {
            'name': '未設定',
            'phoneNumber': '',
            'email': '',
            'lineId': '',
            'socialLinks': {},
            'publisherResume': '',
            'avatarUrl': '',
          };
          _profileForm = Map.from(_profile);
        });
      }
    } catch (e) {
      print('載入個人資料失敗: $e');
      if (mounted) {
        setState(() {
          _profile = {
            'name': '未設定',
            'phoneNumber': '',
            'email': '',
            'lineId': '',
            'socialLinks': {},
            'publisherResume': '',
            'avatarUrl': '',
          };
          _profileForm = Map.from(_profile);
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ref = _firestore.doc('user/${u.uid}'); // ✅ 改用 user 集合
    try {
      await ref.set(_profileForm, SetOptions(merge: true));
      setState(() => _currentBottomSheet = BottomSheetType.none);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('個人資料更新成功')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    }
  }

  /// 加载 Parent 自己的任务
  Future<void> _loadMyPosts() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      print('❌ 用戶未登入');
      return;
    }

    try {
      print('🔄 正在載入用戶 ${u.uid} 的任務...');

      final snap = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: u.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      print('📊 Firestore 查詢結果: ${snap.docs.length} 個文檔');

      final ps = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;

        // 確保座標是正確的數字類型
        if (m['lat'] != null) {
          m['lat'] = m['lat'] is String
              ? double.parse(m['lat'])
              : m['lat'].toDouble();
        }
        if (m['lng'] != null) {
          m['lng'] = m['lng'] is String
              ? double.parse(m['lng'])
              : m['lng'].toDouble();
        }

        print('✅ 載入任務: ${m['name']} (ID: ${d.id})');
        return m;
      }).toList();

      // 手動按創建時間排序
      ps.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return bTime.compareTo(aTime);
      });

      print('🎯 總共載入了 ${ps.length} 個任務');

      if (mounted) {
        setState(() {
          _myPosts = ps;
        });
        print('🔄 UI 已更新，_myPosts.length = ${_myPosts.length}');

        // 更新地圖標記
        _updateMarkers();
      }
    } catch (e) {
      print('❌ 載入任務失敗: $e');
      if (mounted) {
        setState(() {
          _myPosts = [];
        });
      }
    }
  }

  /// 編輯完成後更新 Firestore
  Future<void> _saveEditedPost() async {
    if (_editingPostId == null) return;

    // 表單驗證
    if (_postForm['name']?.toString().trim().isEmpty == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請輸入任務名稱')));
      return;
    }

    if (_postForm['lat'] == null || _postForm['lng'] == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請選擇任務地點')));
      return;
    }

    try {
      await _firestore.doc('posts/$_editingPostId').update({
        'name': _postForm['name'].toString().trim(),
        'content': _postForm['content']?.toString().trim() ?? '',
        'address': _postForm['address']?.toString().trim() ?? '',
        'lat': _postForm['lat'],
        'lng': _postForm['lng'],
      });
      await _loadMyPosts();
      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _editingPostId = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('任務更新成功！')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新任務失敗：$e')));
    }
  }

  /// 點彈窗裡的「編輯任務」
  void _startEditPost() {
    final loc = _selectedLocation!;
    setState(() {
      // 關閉當前任務彈窗
      _currentBottomSheet = BottomSheetType.none;
      _selectedLocation = null;
      _travelInfo = null;

      // 打開編輯模式
      _currentBottomSheet = BottomSheetType.createEditPost;
      _editingPostId = loc['id'];
      _postForm = {
        'name': loc['name'],
        'content': loc['content'],
        'address': loc['address'],
        'lat': loc['lat'],
        'lng': loc['lng'],
      };

      // 安全地预填所有输入框
      _nameCtrl.text = loc['name']?.toString() ?? '';
      _contentCtrl.text = loc['content']?.toString() ?? '';
      _locationSearchCtrl.text =
          loc['address']?.toString() ?? loc['name']?.toString() ?? '';
    });
  }

  /// 加载应徵者详细信息
  Future<void> _loadApplicantDetails(List applicantIds) async {
    try {
      final applicants = <Map<String, dynamic>>[];

      for (String applicantId in applicantIds) {
        var doc = await _firestore
            .doc('user/$applicantId') // ✅ 改用 user 集合
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = applicantId;
          applicants.add(data);
        }
      }

      setState(() => _currentApplicants = applicants);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加載應徵者資料失敗：$e')));
    }
  }

  /// 显示应徵者列表
  void _showApplicantsList() async {
    final applicants = _selectedLocation!['applicants'] as List? ?? [];
    if (applicants.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前沒有應徵者')));
      return;
    }

    await _loadApplicantDetails(List<String>.from(applicants));
    setState(() {
      _currentBottomSheet = BottomSheetType.applicantsList;
    });
  }

  /// 显示应徵者详细资料
  void _showApplicantProfile(Map<String, dynamic> applicant) {
    setState(() {
      _selectedApplicant = applicant;
      _currentBottomSheet = BottomSheetType.applicantProfile;
    });
  }

  /// 接受应徵者
  Future<void> _acceptApplicant(String postId, String applicantId) async {
    try {
      await _firestore.doc('posts/$postId').update({
        'acceptedApplicant': applicantId,
        'status': 'accepted',
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已接受此應徵者')));

      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _selectedLocation = null;
      });

      await _loadMyPosts();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('接受應徵者失敗：$e')));
    }
  }

  /// 拒绝应徵者
  Future<void> _rejectApplicant(String postId, String applicantId) async {
    try {
      final postDoc = await _firestore.doc('posts/$postId').get();
      if (postDoc.exists) {
        final data = postDoc.data()!;
        final applicants = List<String>.from(data['applicants'] ?? []);
        applicants.remove(applicantId);

        await _firestore.doc('posts/$postId').update({
          'applicants': applicants,
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已拒絕此應徵者')));

        _currentApplicants.removeWhere(
          (applicant) => applicant['id'] == applicantId,
        );

        setState(() {
          if (_currentApplicants.isEmpty) {
            _currentBottomSheet = BottomSheetType.none;
          }
        });

        await _loadMyPosts();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拒絕應徵者失敗：$e')));
    }
  }

  Set<Marker> _buildStaticParkMarkers() {
    final markers = <Marker>{};

    for (var location in _systemLocations) {
      if (!_selectedCategories.contains(location['category'])) continue;

      // 檢查該地點附近（100米內）是否有自己的任務
      final locationCoord = LatLng(location['lat'], location['lng']);
      bool hasOwnTaskNearby = false;

      for (var task in _myPosts) {
        final taskCoord = LatLng(task['lat'], task['lng']);
        final distance = _calculateDistance(locationCoord, taskCoord);

        if (distance <= 100) {
          // 100米內
          hasOwnTaskNearby = true;
          break;
        }
      }

      // 如果附近有自己的任務，隱藏系統地點標記避免重疊
      if (hasOwnTaskNearby) {
        continue;
      }

      markers.add(
        Marker(
          markerId: MarkerId('system_${location['id']}'),
          position: LatLng(location['lat'], location['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () => _showLocationInfoSheetDirect({
            'name': location['name'],
            'lat': location['lat'],
            'lng': location['lng'],
            'address': location['address'],
            'category': location['category'],
          }),
        ),
      );
    }

    return markers;
  }

  /// 計算兩點之間的距離（米）
  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  Set<Marker> _buildMyPostMarkers() {
    print('建立任務標記，共 ${_myPosts.length} 個任務');
    final markers = <Marker>{};
    for (var post in _myPosts) {
      try {
        // 檢查必要的字段是否存在
        if (post['id'] == null || post['lat'] == null || post['lng'] == null) {
          continue;
        }
        final lat = post['lat'];
        final lng = post['lng'];
        // 檢查座標是否為有效數字
        if (lat is! num || lng is! num) {
          continue;
        }
        final position = LatLng(lat.toDouble(), lng.toDouble());
        final marker = Marker(
          markerId: MarkerId(post['id']),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          onTap: () {
            _showTaskDetailSheetDirect({
              'id': post['id'],
              'name': post['name'],
              'title': post['title'] ?? post['name'], // 向下兼容
              'content': post['content'],
              'address': post['address'],
              'applicants': post['applicants'],
              'lat': lat.toDouble(),
              'lng': lng.toDouble(),
              'userId': post['userId'],
              'createdAt': post['createdAt'],
              'status': post['status'],
              'date': post['date'],
              'time': post['time'],
              'price': post['price'],
              'images': post['images'],
            });
          },
        );
        markers.add(marker);
      } catch (e) {
        print('創建標記時出錯: ${post['name']} - $e');
      }
    }
    print('成功創建 ${markers.length} 個任務標記');
    return markers;
  }

  Set<Marker> _buildMyLocationMarker() {
    return _myLocation == null
        ? {}
        : {
            Marker(
              markerId: const MarkerId('my_location'),
              position: _myLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          };
  }

  Widget _buildCategoryFilter() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showCategoryFilter ? null : 0,
      child: _showCategoryFilter
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一個按鈕：全選/取消按鈕（加陰影）

                  // 類別按鈕區域 - 每個按鈕都加陰影
                  ..._availableCategories.map((category) {
                    final isSelected = _selectedCategories.contains(category);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        // 新增 Container 包裝
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(60),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: FilterChip(
                          label: Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey[800],
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategories.add(category);
                              } else {
                                _selectedCategories.remove(category);
                              }
                            });
                            // 重新更新地圖標記
                            _updateMarkers();
                          },
                          selectedColor: Colors.orange[600],
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: isSelected
                                ? Colors.orange[600]!
                                : Colors.grey[300]!,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(60),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: FilterChip(
                      label: Text(
                        _selectedCategories.length ==
                                _availableCategories.length
                            ? '全部取消'
                            : '全部選取',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      selected: false,
                      onSelected: (_) {
                        setState(() {
                          if (_selectedCategories.length ==
                              _availableCategories.length) {
                            _selectedCategories.clear();
                          } else {
                            _selectedCategories = Set.from(
                              _availableCategories,
                            );
                          }
                        });
                        // 重新更新地圖標記
                        _updateMarkers();
                      },
                      backgroundColor: Colors.blue[50],
                      side: BorderSide(color: Colors.blue[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(60),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// 顯示角色切換確認對話框
  void _showRoleSwitchDialog(BuildContext context, String targetRole) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.switch_account, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('切換角色'),
            ],
          ),
          content: Text(
            '確定要切換為$targetRole嗎？',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('取消', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _switchToRole('/player');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('確定切換'),
            ),
          ],
        );
      },
    );
  }

  /// 執行角色切換
  void _switchToRole(String route) {
    Navigator.pushReplacementNamed(context, route);
  }

  /// 顯示新建任務彈窗（使用新的 5 步驟流程）
  void _showCreateTaskSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // 禁用外部拖拽，避免與內部 DraggableScrollableSheet 衝突
      backgroundColor: Colors.transparent,
      useSafeArea: true, // 使用安全區域
      isDismissible: true, // 允許點擊外部關閉
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        onSubmit: (taskData) async {
          Navigator.of(context).pop(); // 先關閉彈窗
          await _saveNewTaskData(taskData);
        },
      ),
    );
  }

  /// 顯示編輯任務彈窗（使用新的 5 步驟流程）
  void _showEditTaskSheet() {
    // 將現有任務資料轉換為格式
    final existingTask = _myPosts.firstWhere(
      (task) => task['id'] == _editingPostId,
      orElse: () => _postForm,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // 禁用外部拖拽，避免與內部 DraggableScrollableSheet 衝突
      backgroundColor: Colors.transparent,
      useSafeArea: true, // 使用安全區域
      isDismissible: true, // 允許點擊外部關閉
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        existingTask: existingTask,
        onSubmit: (updatedTaskData) async {
          Navigator.of(context).pop(); // 先關閉彈窗
          await _saveEditedTaskData(updatedTaskData);
        },
      ),
    );
  }

  /// 上傳圖片到 Firebase Storage
  Future<List<String>> _uploadImagesToStorage(
    List<Uint8List> images,
    String taskId,
  ) async {
    final List<String> imageUrls = [];
    final storage = FirebaseStorage.instance;

    for (int i = 0; i < images.length; i++) {
      try {
        // 檢查圖片大小（限制為 5MB）
        if (images[i].length > 5 * 1024 * 1024) {
          print('⚠️ 圖片 $i 太大 (${images[i].length} bytes)，跳過上傳');
          continue;
        }

        // 創建檔案路徑：tasks/{taskId}/image_{index}.jpg
        final String fileName =
            'image_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final String filePath = 'tasks/$taskId/$fileName';

        print('📤 開始上傳圖片 $i: $filePath');

        // 上傳圖片並設置超時
        final Reference ref = storage.ref().child(filePath);
        final UploadTask uploadTask = ref.putData(
          images[i],
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'max-age=60',
          ),
        );

        // 等待上傳完成（設置超時）
        final TaskSnapshot snapshot = await uploadTask.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            uploadTask.cancel();
            throw TimeoutException('圖片上傳超時', const Duration(seconds: 30));
          },
        );

        // 檢查上傳狀態
        if (snapshot.state == TaskState.success) {
          // 取得下載 URL
          final String downloadUrl = await snapshot.ref
              .getDownloadURL()
              .timeout(const Duration(seconds: 10));
          imageUrls.add(downloadUrl);
          print('✅ 圖片 $i 上傳成功: $downloadUrl');
        } else {
          print('❌ 圖片 $i 上傳狀態異常: ${snapshot.state}');
        }
      } catch (e) {
        print('❌ 圖片 $i 上傳失敗: $e');
        // 即使某張圖片上傳失敗，繼續上傳其他圖片

        // 如果是網路相關錯誤，可以考慮重試一次
        if (e.toString().contains('network') ||
            e.toString().contains('timeout')) {
          print('🔄 網路錯誤，嘗試重新上傳圖片 $i');
          try {
            final String fileName =
                'image_${i}_retry_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final String filePath = 'tasks/$taskId/$fileName';
            final Reference ref = storage.ref().child(filePath);

            final UploadTask retryUploadTask = ref.putData(
              images[i],
              SettableMetadata(contentType: 'image/jpeg'),
            );

            final TaskSnapshot retrySnapshot = await retryUploadTask.timeout(
              const Duration(seconds: 15),
            );

            if (retrySnapshot.state == TaskState.success) {
              final String downloadUrl = await retrySnapshot.ref
                  .getDownloadURL();
              imageUrls.add(downloadUrl);
              print('✅ 圖片 $i 重試上傳成功: $downloadUrl');
            }
          } catch (retryError) {
            print('❌ 圖片 $i 重試上傳也失敗: $retryError');
          }
        }
      }
    }

    print('📷 圖片上傳完成，成功: ${imageUrls.length}/${images.length}');
    return imageUrls;
  }

  /// 保存新任務資料（新格式）
  Future<void> _saveNewTaskData(new_task_sheet.TaskData taskData) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      print('❌ 用戶未登入，無法創建任務');
      return;
    }

    // 添加輸入驗證
    if (taskData.title.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('任務標題不能為空')));
      }
      return;
    }

    if (taskData.lat == null || taskData.lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('請選擇任務地點')));
      }
      return;
    }

    try {
      print('🔄 開始創建任務: ${taskData.title}');

      // 先創建基本任務資料（不包含圖片）
      final data = {
        'title': taskData.title.trim(),
        'name': taskData.title.trim(), // 向下兼容
        'date': taskData.date?.toIso8601String(),
        'time': taskData.time != null
            ? {'hour': taskData.time!.hour, 'minute': taskData.time!.minute}
            : null,
        'content': taskData.content.trim(),
        'images': <String>[], // 先設為空陣列，稍後更新
        'price': taskData.price,
        'address': taskData.address?.trim(),
        'lat': taskData.lat,
        'lng': taskData.lng,
        'userId': u.uid,
        'applicants': [],
        'createdAt': Timestamp.now(),
        'status': 'open',
      };

      print('📝 任務資料準備完成，開始上傳到 Firebase');

      // 創建任務文檔並取得 ID
      final DocumentReference docRef = await _firestore
          .collection('posts')
          .add(data)
          .timeout(const Duration(seconds: 10));
      final String taskId = docRef.id;

      print('✅ 任務文檔創建成功，ID: $taskId');

      // 如果有圖片，上傳到 Firebase Storage
      List<String> imageUrls = [];
      if (taskData.images.isNotEmpty && mounted) {
        print('📷 開始上傳 ${taskData.images.length} 張圖片...');

        // 顯示上傳進度提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在上傳 ${taskData.images.length} 張圖片...'),
            duration: const Duration(seconds: 3),
          ),
        );

        try {
          imageUrls = await _uploadImagesToStorage(taskData.images, taskId);
          print('✅ 圖片上傳完成，共 ${imageUrls.length} 張');

          // 更新任務文檔的圖片 URL
          if (imageUrls.isNotEmpty && mounted) {
            await docRef
                .update({'images': imageUrls})
                .timeout(const Duration(seconds: 10));
            print('✅ 任務圖片 URL 更新完成');
          }
        } catch (imageError) {
          print('⚠️ 圖片上傳失敗，但任務已創建: $imageError');
          // 圖片上傳失敗不影響任務創建
        }
      }

      // 重新載入任務列表
      if (mounted) {
        print('🔄 重新載入任務列表');
        await _loadMyPosts();
      }

      // 安全更新 UI 狀態
      if (mounted) {
        setState(() {
          _currentBottomSheet = BottomSheetType.none;
          _editingPostId = null;
        });

        final successMessage = taskData.images.isNotEmpty
            ? '任務創建成功！已上傳 ${imageUrls.length} 張圖片'
            : '任務創建成功！';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );

        // 移動地圖到新任務位置
        if (taskData.lat != null && taskData.lng != null) {
          try {
            final newLatLng = LatLng(taskData.lat!, taskData.lng!);
            _mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(newLatLng, 15));
          } catch (mapError) {
            print('⚠️ 地圖移動失敗: $mapError');
            // 地圖移動失敗不影響整體流程
          }
        }
      }

      print('✅ 任務創建流程完成');
    } catch (e, stackTrace) {
      print('❌ 創建任務錯誤詳情: $e');
      print('❌ 堆疊追蹤: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('創建任務失敗：${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 保存編輯後的任務資料（新格式）
  Future<void> _saveEditedTaskData(new_task_sheet.TaskData taskData) async {
    if (_editingPostId == null) return;

    try {
      // 處理圖片：合併現有圖片和新圖片
      List<String> allImageUrls = List<String>.from(taskData.existingImageUrls);

      // 如果有新圖片，上傳到 Firebase Storage
      if (taskData.images.isNotEmpty) {
        print('開始上傳 ${taskData.images.length} 張新圖片...');

        // 顯示上傳進度提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('正在上傳 ${taskData.images.length} 張圖片...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        final newImageUrls = await _uploadImagesToStorage(
          taskData.images,
          _editingPostId!,
        );
        allImageUrls.addAll(newImageUrls);
        print('圖片上傳完成，共 ${newImageUrls.length} 張新圖片');
      }

      // 準備更新資料
      final data = <String, dynamic>{
        'title': taskData.title,
        'name': taskData.title, // 向下兼容
        'date': taskData.date?.toIso8601String(),
        'time': taskData.time != null
            ? {'hour': taskData.time!.hour, 'minute': taskData.time!.minute}
            : null,
        'content': taskData.content,
        'images': allImageUrls, // 更新為完整的圖片 URL 列表
        'price': taskData.price,
        'address': taskData.address,
        'lat': taskData.lat,
        'lng': taskData.lng,
        // 不更新 userId, applicants, createdAt, status
      };

      await _firestore.doc('posts/$_editingPostId').update(data);
      await _loadMyPosts();

      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _editingPostId = null;
      });

      final successMessage = taskData.images.isNotEmpty
          ? '任務更新成功！已上傳 ${taskData.images.length} 張新圖片'
          : '任務更新成功！';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      print('更新任務錯誤詳情: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新任務失敗：$e')));
    }
  }

  /// 更新地圖標記
  void _updateMarkers() {
    if (!mounted) return;

    final allMarkers = <Marker>{};

    // 添加系統地點標記（考慮類別過濾）
    allMarkers.addAll(_buildStaticParkMarkers());

    // 添加我的任務標記
    allMarkers.addAll(_buildMyPostMarkers());

    // 添加我的位置標記
    allMarkers.addAll(_buildMyLocationMarker());

    setState(() {
      _markers = allMarkers;
    });
  }

  /// 處理標記點擊
  void _handleMarkerTap(MarkerData markerData) {
    setState(() {
      _selectedMarker = markerData;
      _selectedLocation = markerData.data;
    });

    // 根據標記類型顯示不同的彈窗
    if (markerData.type == MarkerType.custom) {
      // 自定義任務標記 - 顯示任務詳情
      _showTaskDetailSheet(markerData);
    } else if (markerData.type == MarkerType.preset ||
        markerData.type == MarkerType.activePreset) {
      // 系統地點標記 - 顯示地點資訊
      _showLocationInfoSheet(markerData);
    }
  }

  /// 顯示任務詳情彈窗
  void _showTaskDetailSheet(MarkerData markerData) {
    // 移動地圖到任務位置
    _moveMapToLocation(markerData.position);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: markerData.data,
        isParentView: true,
        currentLocation: _myLocation,
        onTaskUpdated: () {
          _loadMyPosts();
          _updateMarkers();
        },
        onEditTask: () {
          Navigator.of(context).pop();
          _editingPostId = markerData.data['id'];
          _showEditTaskSheet();
        },
        onDeleteTask: () async {
          Navigator.of(context).pop();
          await _deletePost(markerData.data['id']);
        },
      ),
    );
  }

  /// 移動地圖到指定位置
  void _moveMapToLocation(LatLng position) {
    _mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(position, 16));
  }

  /// 顯示地點資訊彈窗
  void _showLocationInfoSheet(MarkerData markerData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: markerData.data,
        isParentView: true,
        currentLocation: _myLocation,
        onCreateTaskAtLocation: () {
          Navigator.of(context).pop();
          _startCreatePostFromStatic();
        },
      ),
    );
  }

  /// 直接顯示地點資訊彈窗（不通過 MarkerData）
  void _showLocationInfoSheetDirect(Map<String, dynamic> locationData) {
    // 移動地圖到地點位置
    _moveMapToLocation(LatLng(locationData['lat'], locationData['lng']));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: true,
        currentLocation: _myLocation,
        onCreateTaskAtLocation: () {
          Navigator.of(context).pop();
          _showCreateTaskSheetWithLocation(locationData);
        },
      ),
    );
  }

  /// 直接顯示任務詳情彈窗（不通過 MarkerData）
  void _showTaskDetailSheetDirect(Map<String, dynamic> taskData) {
    // 移動地圖到任務位置
    _moveMapToLocation(LatLng(taskData['lat'], taskData['lng']));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: taskData,
        isParentView: true,
        currentLocation: _myLocation,
        onTaskUpdated: () {
          _loadMyPosts();
          _updateMarkers();
        },
        onEditTask: () {
          Navigator.of(context).pop();
          _editingPostId = taskData['id'];
          _showEditTaskSheet();
        },
        onDeleteTask: () async {
          Navigator.of(context).pop();
          await _deletePost(taskData['id']);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('總標記數量: ${_markers.length}');

    return Scaffold(
      body: Stack(
        children: [
          // Google 地圖
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            onMapCreated: (c) {
              _mapCtrl = c;
              c.setMapStyle(mapStyleJson);

              // 地圖創建後立即重新載入任務
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  _loadMyPosts();
                  _loadSystemLocations(); // 新增這行
                }
              });
            },
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            zoomGesturesEnabled: true,
          ),

          // 添加調試信息按鈕（開發時使用）
          if (true) // 設為 false 來隱藏調試按鈕
            Positioned(
              top: 50,
              left: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.red[100],
                child: const Icon(Icons.info, color: Colors.red),
                onPressed: () async {
                  final u = FirebaseAuth.instance.currentUser;
                  final allPosts = await _firestore.collection('posts').get();
                  final myPosts = await _firestore
                      .collection('posts')
                      .where('userId', isEqualTo: u?.uid)
                      .get();

                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('調試信息'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('當前用戶 UID: ${u?.uid}'),
                            Text('總任務數量: ${allPosts.docs.length}'),
                            Text('我的任務數量: ${myPosts.docs.length}'),
                            Text('本地任務數量: ${_myPosts.length}'),
                            Text('標記數量: ${_markers.length}'),
                            const SizedBox(height: 10),
                            const Text('所有任務:'),
                            for (var doc in allPosts.docs)
                              Text(
                                '- ${doc.data()['name']}: ${doc.data()['userId']}',
                              ),
                            const SizedBox(height: 10),
                            const Text('我的任務:'),
                            for (var post in _myPosts)
                              Text(
                                '- ${post['name']}: (${post['lat']}, ${post['lng']})',
                              ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('關閉'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _loadMyPosts();
                          },
                          child: const Text('重新載入'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          Positioned(
            bottom: 100,
            left: 0, // 從左邊 20px 開始
            width: 320, // 固定寬度 300px
            child: _buildCategoryFilter(),
          ),

          // 篩選選單按鈕
          Positioned(
            bottom: 40, // 動態調整位置
            left: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 新增：篩選切換按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'filter',
                  mini: false,
                  child: Icon(
                    _showCategoryFilter
                        ? Icons
                              .close // 選單打開時顯示 X
                        : Icons.filter_list,
                  ), // 選單關閉時顯示篩選圖標
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () {
                    setState(() {
                      _showCategoryFilter = !_showCategoryFilter;
                    });
                  },
                ),
              ],
            ),
          ),

          // 工具按鈕
          Positioned(
            bottom: 40, // 動態調整位置
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'switch',
                  mini: false,
                  child: const Icon(Icons.switch_account),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => _showRoleSwitchDialog(context, '陪伴者'),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'loc',
                  mini: false,
                  child: const Icon(Icons.my_location),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () async {
                    var perm = await Geolocator.checkPermission();
                    if (perm == LocationPermission.denied) {
                      perm = await Geolocator.requestPermission();
                    }
                    if (perm == LocationPermission.denied ||
                        perm == LocationPermission.deniedForever) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('請在系統設定允許定位權限')),
                      );
                      return;
                    }

                    final pos = await Geolocator.getCurrentPosition();
                    final newLatLng = LatLng(pos.latitude, pos.longitude);

                    setState(() => _myLocation = newLatLng);
                    _updateMarkers(); // 更新標記以包含新的位置
                    _mapCtrl.animateCamera(
                      CameraUpdate.newLatLngZoom(newLatLng, 16),
                    );
                  },
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'create',
                  mini: false,
                  child: const Icon(Icons.add),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: _startCreatePostManually,
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'profile',
                  mini: false,
                  child: const Icon(Icons.person),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => setState(
                    () => _currentBottomSheet = BottomSheetType.profileEditing,
                  ),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'list',
                  mini: false,
                  child: const Icon(Icons.list),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => setState(
                    () => _currentBottomSheet = BottomSheetType.myPostsList,
                  ),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'logout',
                  mini: false,
                  child: const Icon(Icons.logout),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    Navigator.pushReplacementNamed(context, '/');
                  },
                ),
              ],
            ),
          ),

          // 舊的任務詳情彈窗已移除，改用新的 showModalBottomSheet 方式
          // 應徵者列表底部彈窗
          if (_currentBottomSheet == BottomSheetType.applicantsList)
            Positioned.fill(
              child: FullScreenPopup(
                title: '應徵者列表',
                onClose: () =>
                    setState(() => _currentBottomSheet = BottomSheetType.none),
                child: ApplicantsListBottomSheet(
                  applicants: _currentApplicants,
                  onApplicantTap: _showApplicantProfile,
                ),
              ),
            ),
          // 應徵者詳情底部彈窗
          if (_currentBottomSheet == BottomSheetType.applicantProfile &&
              _selectedApplicant != null)
            Positioned.fill(
              child: FullScreenPopup(
                title: '應徵者資料',
                onClose: () =>
                    setState(() => _currentBottomSheet = BottomSheetType.none),
                child: ApplicantProfileBottomSheet(
                  applicant: _selectedApplicant!,
                  onAccept: () => _acceptApplicant(
                    _selectedLocation!['id'],
                    _selectedApplicant!['id'],
                  ),
                  onReject: () => _rejectApplicant(
                    _selectedLocation!['id'],
                    _selectedApplicant!['id'],
                  ),
                  onBack: () => setState(
                    () => _currentBottomSheet = BottomSheetType.applicantsList,
                  ),
                ),
              ),
            ),

          // 我的任務列表底部彈窗
          if (_currentBottomSheet == BottomSheetType.myPostsList)
            Positioned.fill(
              child: FullScreenPopup(
                title: '我的任務列表',
                onClose: () {
                  setState(() => _currentBottomSheet = BottomSheetType.none);
                },
                child: MyTasksListBottomSheet(
                  tasks: _myPosts,
                  onTaskTap: (task) {
                    // 关闭任务列表，使用新的任务详情UI
                    setState(() {
                      _currentBottomSheet = BottomSheetType.none;
                    });

                    // 移動地圖到任務位置並显示新的任务详情弹窗
                    _moveMapToLocation(LatLng(task['lat'], task['lng']));

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      enableDrag: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => TaskDetailSheet(
                        taskData: {...task, 'id': task['id']},
                        isParentView: true,
                        currentLocation: _myLocation,
                        onTaskUpdated: () {
                          _loadMyPosts();
                          _updateMarkers();
                        },
                        onEditTask: () {
                          Navigator.of(context).pop();
                          _editingPostId = task['id'];
                          _showEditTaskSheet();
                        },
                        onDeleteTask: () async {
                          Navigator.of(context).pop();
                          await _deletePost(task['id']);
                        },
                      ),
                    );
                  },
                  onEditTask: (task) {
                    // 设置编辑任务ID和数据
                    _editingPostId = task['id'];

                    // 关闭任务列表
                    setState(() {
                      _currentBottomSheet = BottomSheetType.none;
                    });

                    // 显示编辑弹窗
                    _showEditTaskSheet();
                  },
                  onDeleteTask: (taskId) async {
                    try {
                      await _firestore.doc('posts/$taskId').delete();
                      await _loadMyPosts();

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('任務已刪除')));

                      // 如果删除后没有任务了，保持在列表页面
                      if (_myPosts.isEmpty) {
                        // 不关闭弹窗，让用户看到空状态
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
                    }
                  },
                  onCreateNew: () {
                    // 关闭任务列表
                    setState(() {
                      _currentBottomSheet = BottomSheetType.none;
                      _editingPostId = null;
                    });

                    // 显示新建任务弹窗
                    _showCreateTaskSheet();
                  },
                ),
              ),
            ),

          // 創建/編輯任務底部彈窗已移至 showModalBottomSheet 方式

          // 編輯個人資料底部彈窗
          if (_currentBottomSheet == BottomSheetType.profileEditing)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯個人資料',
                onClose: () =>
                    setState(() => _currentBottomSheet = BottomSheetType.none),
                child: EditProfileBottomSheet(
                  profileForm: _profileForm,
                  isParentView: true,
                  onSave: _saveProfile,
                  onCancel: () => setState(
                    () => _currentBottomSheet = BottomSheetType.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
