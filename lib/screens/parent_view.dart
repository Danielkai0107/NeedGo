// lib/screens/parent_view.dart
// 更新後的 ParentView，使用底部滑動彈窗

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../styles/map_styles.dart';
import '../data/parks_data.dart';
import '../services/auth_service.dart';
import '../components/draggable_bottom_sheet.dart'; // 引入新組件

class ParentView extends StatefulWidget {
  const ParentView({Key? key}) : super(key: key);

  @override
  State<ParentView> createState() => _ParentViewState();
}

class _ParentViewState extends State<ParentView> {
  final _authService = AuthService();
  final _firestore = FirebaseFirestore.instance;
  final TextEditingController _contentCtrl = TextEditingController();

  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 14;
  LatLng? _myLocation;

  List<Map<String, dynamic>> _myPosts = [];
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _profileForm = {};

  bool _isEditingPost = false;
  String? _editingPostId;

  // 搜索建议
  List<Map<String, dynamic>> _locationSuggestions = [];

  bool _isMyPostsListVisible = false;

  // 合并用：静态公园 or 自己的任务
  Map<String, dynamic>? _selectedLocation;
  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;

  bool _isProfileEditing = false;
  bool _isCreatingPost = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locationSearchCtrl = TextEditingController();

  // 底部彈窗相關變量
  bool _isTaskDetailVisible = false;
  bool _isApplicantsListVisible = false;
  List<Map<String, dynamic>> _currentApplicants = [];
  Map<String, dynamic>? _selectedApplicant;
  bool _isApplicantProfileVisible = false;

  Map<String, dynamic> _postForm = {
    'name': '',
    'content': '',
    'lat': null,
    'lng': null,
  };

  static const String _apiKey =
      'AIzaSyCne1CQNTGm_a3DFxcN59lYhKGlj5McqqE'; // 请替换成你的 key

  @override
  void initState() {
    super.initState();
    _findAndRecenter();
    _loadMyProfile();
    _loadMyPosts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationSearchCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  /// 获取当前定位
  /// 把这个方法放在你的 State 里，替换现有的 _findAndRecenter 或者 _findAndRecenter
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

  /// 通用：点击静态公园或自己任务的 Marker 调用
  void _selectLocationMarker(
    Map<String, dynamic> loc, {
    bool isStatic = false,
  }) {
    setState(() {
      _selectedLocation = {...loc, 'isStatic': isStatic};
      _travelInfo = null;
      _isTaskDetailVisible = true; // 顯示底部彈窗
    });
    _calculateTravelInfo(LatLng(loc['lat'], loc['lng']));
  }

  void _closeLocationPopup() {
    setState(() {
      _selectedLocation = null;
      _travelInfo = null;
      _isTaskDetailVisible = false;
      _isApplicantsListVisible = false;
      _isApplicantProfileVisible = false;
    });
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
    if (input.isEmpty) {
      setState(() => _locationSuggestions = []);
      return;
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}'
      '&key=$_apiKey'
      '&language=zh-TW&components=country:tw',
    );
    final resp = await http.get(url);
    final preds = jsonDecode(resp.body)['predictions'] as List;
    setState(() {
      _locationSuggestions = preds
          .map(
            (p) => {'description': p['description'], 'place_id': p['place_id']},
          )
          .toList();
    });
  }

  /// 选中建议；填入表单
  Future<void> _selectLocation(Map<String, dynamic> place) async {
    _locationSearchCtrl.text = place['description'];
    setState(() => _locationSuggestions = []);
    final detailUrl = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${place['place_id']}&key=$_apiKey',
    );
    final resp = await http.get(detailUrl);
    final loc = jsonDecode(resp.body)['result']['geometry']['location'];
    setState(() {
      _postForm['lat'] = loc['lat'];
      _postForm['lng'] = loc['lng'];
    });
  }

  /// 打开"以此静态点位发任务"表单
  void _startCreatePostFromStatic() {
    final loc = _selectedLocation!;
    setState(() {
      _isCreatingPost = true;
      _isTaskDetailVisible = false; // 關閉任務詳情彈窗
      _postForm = {
        'name': loc['name'],
        'content': '',
        'lat': loc['lat'],
        'lng': loc['lng'],
      };
      _nameCtrl.text = loc['name']?.toString() ?? '';
      _contentCtrl.clear();
      _locationSearchCtrl.text = loc['name']?.toString() ?? '';
      _selectedLocation = null;
      _travelInfo = null;
    });
  }

  /// 手动新建任务
  void _startCreatePostManually() {
    setState(() {
      _isCreatingPost = true;
      _postForm = {'name': '', 'content': '', 'lat': null, 'lng': null};
      _nameCtrl.clear();
      _contentCtrl.clear();
      _locationSearchCtrl.clear();
    });
  }

  void _cancelCreatePost() => setState(() => _isCreatingPost = false);

  Future<void> _saveNewPost() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final data = {
      'name': _postForm['name'],
      'content': _postForm['content'],
      'lat': _postForm['lat'],
      'lng': _postForm['lng'],
      'userId': u.uid,
      'applicants': [],
      'createdAt': Timestamp.now(),
    };
    await _firestore.collection('posts').add(data);
    await _loadMyPosts();
    setState(() => _isCreatingPost = false);
  }

  Future<void> _deletePost(String id) async {
    await _firestore.doc('posts/$id').delete();
    await _loadMyPosts();
    _closeLocationPopup();
  }

  /// 加载 Parent 个人档
  Future<void> _loadMyProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final doc = await _firestore.doc('parents/${u.uid}').get();
    if (doc.exists) {
      setState(() {
        _profile = doc.data()!;
        _profileForm = Map.from(_profile);
      });
    }
  }

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ref = _firestore.doc('parents/${u.uid}');
    try {
      await ref.set(_profileForm, SetOptions(merge: true));
      setState(() => _isProfileEditing = false);
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('儲存失敗')));
    }
  }

  /// 加载 Parent 自己的任务
  Future<void> _loadMyPosts() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final snap = await _firestore
        .collection('posts')
        .where('userId', isEqualTo: u.uid)
        .get();
    final ps = snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
    setState(() => _myPosts = ps);
  }

  /// 編輯完成後更新 Firestore
  Future<void> _saveEditedPost() async {
    if (_editingPostId == null) return;
    await _firestore.doc('posts/$_editingPostId').update({
      'name': _postForm['name'],
      'content': _postForm['content'],
      'lat': _postForm['lat'],
      'lng': _postForm['lng'],
    });
    await _loadMyPosts();
    setState(() {
      _isEditingPost = false;
      _editingPostId = null;
    });
  }

  /// 點彈窗裡的「編輯任務」
  void _startEditPost() {
    final loc = _selectedLocation!;
    setState(() {
      // 關閉當前任務彈窗
      _isTaskDetailVisible = false;
      _selectedLocation = null;
      _travelInfo = null;

      // 打開編輯模式
      _isEditingPost = true;
      _editingPostId = loc['id'];
      _postForm = {
        'name': loc['name'],
        'content': loc['content'],
        'lat': loc['lat'],
        'lng': loc['lng'],
      };

      // 安全地预填所有输入框
      _nameCtrl.text = loc['name']?.toString() ?? '';
      _contentCtrl.text = loc['content']?.toString() ?? '';
      _locationSearchCtrl.text = loc['name']?.toString() ?? '';
    });
  }

  /// 加载应徵者详细信息
  Future<void> _loadApplicantDetails(List applicantIds) async {
    try {
      final applicants = <Map<String, dynamic>>[];

      for (String applicantId in applicantIds) {
        var doc = await _firestore.doc('players/$applicantId').get();
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = applicantId;
          data['userType'] = 'player';
          applicants.add(data);
          continue;
        }

        doc = await _firestore.doc('groups/$applicantId').get();
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = applicantId;
          data['userType'] = 'group';
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
    final applicants = _selectedLocation!['applicants'] as List?;
    if (applicants == null || applicants.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前沒有應徵者')));
      return;
    }

    await _loadApplicantDetails(List<String>.from(applicants));
    setState(() {
      _isTaskDetailVisible = false;
      _isApplicantsListVisible = true;
    });
  }

  /// 显示应徵者详细资料
  void _showApplicantProfile(Map<String, dynamic> applicant) {
    setState(() {
      _selectedApplicant = applicant;
      _isApplicantsListVisible = false;
      _isApplicantProfileVisible = true;
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
        _isApplicantProfileVisible = false;
        _isApplicantsListVisible = false;
        _isTaskDetailVisible = false;
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
          _isApplicantProfileVisible = false;
          if (_currentApplicants.isEmpty) {
            _isApplicantsListVisible = false;
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
    return {
      for (var p in [...taipeiParks, ...newTaipeiParks])
        Marker(
          markerId: MarkerId(
            'park_${p.location.latitude}_${p.location.longitude}',
          ),
          position: p.location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () => _selectLocationMarker({
            'name': p.name,
            'lat': p.location.latitude,
            'lng': p.location.longitude,
          }, isStatic: true),
        ),
    };
  }

  Set<Marker> _buildMyPostMarkers() {
    return {
      for (var post in _myPosts)
        Marker(
          markerId: MarkerId(post['id']),
          position: LatLng(post['lat'], post['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          onTap: () => _selectLocationMarker({
            'id': post['id'],
            'name': post['name'],
            'content': post['content'],
            'applicants': post['applicants'],
            'lat': post['lat'],
            'lng': post['lng'],
          }, isStatic: false),
        ),
    };
  }

  Set<Marker> _buildMyLocationMarker() {
    return _myLocation == null
        ? {}
        : {
            Marker(
              markerId: const MarkerId('me'),
              position: _myLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
            ),
          };
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      ..._buildMyLocationMarker(),
      ..._buildStaticParkMarkers(),
      ..._buildMyPostMarkers(),
    };

    return Scaffold(
      body: Stack(
        children: [
          // Google 地圖
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            onMapCreated: (c) => _mapCtrl = c..setMapStyle(mapStyleJson),
            markers: markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
          ),

          // 工具按鈕
          Positioned(
            top: 100,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'loc',
                  mini: false,
                  child: const Icon(Icons.my_location),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
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
                    borderRadius: BorderRadius.circular(56), // 半徑 12
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
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: () => setState(() => _isProfileEditing = true),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'list',
                  mini: false,
                  child: const Icon(Icons.list),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: () => setState(() => _isMyPostsListVisible = true),
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'logout',
                  mini: false,
                  child: const Icon(Icons.logout),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: () async {
                    await _authService.signOut();
                    Navigator.pushReplacementNamed(context, '/');
                  },
                ),
              ],
            ),
          ),

          // 任務詳情底部彈窗
          if (_isTaskDetailVisible && _selectedLocation != null)
            Positioned.fill(
              // 添加這行
              child: DraggableBottomSheet(
                title: _selectedLocation!['name'],
                onClose: _closeLocationPopup,
                child: TaskDetailBottomSheet(
                  task: _selectedLocation!,
                  travelInfo: _travelInfo,
                  isLoadingTravel: _isLoadingTravel,
                  onEdit: _startEditPost,
                  onDelete: () => _deletePost(_selectedLocation!['id']),
                  onViewApplicants: _showApplicantsList,
                  onCreateFromStatic: _startCreatePostFromStatic,
                ),
              ),
            ), // 添加這行
          // 應徵者列表底部彈窗
          if (_isApplicantsListVisible)
            Positioned.fill(
              // 添加這行
              child: DraggableBottomSheet(
                title: '應徵者列表',
                onClose: () => setState(() {
                  _isApplicantsListVisible = false;
                  _isTaskDetailVisible = true;
                }),
                child: ApplicantsListBottomSheet(
                  applicants: _currentApplicants,
                  onApplicantTap: _showApplicantProfile,
                ),
              ),
            ), // 添加這行
          // 應徵者詳情底部彈窗
          if (_isApplicantProfileVisible && _selectedApplicant != null)
            Positioned.fill(
              // 添加這行
              child: DraggableBottomSheet(
                title: '應徵者資料',
                onClose: () => setState(() {
                  _isApplicantProfileVisible = false;
                  _isApplicantsListVisible = true;
                }),
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
                  onBack: () => setState(() {
                    _isApplicantProfileVisible = false;
                    _isApplicantsListVisible = true;
                  }),
                ),
              ),
            ), // 添加這行
          // 我的任務列表底部彈窗
          if (_isMyPostsListVisible)
            Positioned.fill(
              // 添加這行
              child: DraggableBottomSheet(
                title: '我的任務列表',
                onClose: () => setState(() => _isMyPostsListVisible = false),
                child: _myPosts.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.assignment_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '您還沒有發布任何任務',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '點擊右下角的 + 按鈕來新增第一個任務吧！',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _myPosts.length,
                        itemBuilder: (context, index) {
                          final post = _myPosts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: Colors.orange[600],
                                  size: 28,
                                ),
                              ),
                              title: Text(
                                post['name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (post['content']?.toString().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      post['content'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people,
                                        size: 16,
                                        color: Colors.blue[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(post['applicants'] as List?)?.length ?? 0} 人應徵',
                                        style: TextStyle(
                                          color: Colors.blue[600],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                              onTap: () async {
                                final taskLatLng = LatLng(
                                  post['lat'].toDouble(),
                                  post['lng'].toDouble(),
                                );
                                await _mapCtrl.animateCamera(
                                  CameraUpdate.newLatLngZoom(taskLatLng, 16),
                                );
                                setState(() => _isMyPostsListVisible = false);
                                await Future.delayed(
                                  const Duration(milliseconds: 500),
                                );
                                _selectLocationMarker({
                                  'id': post['id'],
                                  'name': post['name'],
                                  'content': post['content'],
                                  'applicants': post['applicants'],
                                  'lat': post['lat'],
                                  'lng': post['lng'],
                                }, isStatic: false);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ), // 添加這行
          // 創建/編輯任務底部彈窗
          if (_isCreatingPost || _isEditingPost)
            Positioned.fill(
              child: DraggableBottomSheet(
                title: _isEditingPost ? '編輯任務' : '新增任務',
                maxHeight: 0.95, // 設置最大高度，因為表單內容較多
                onClose: () => setState(() {
                  _isCreatingPost = false;
                  _isEditingPost = false;
                  _editingPostId = null;
                }),
                child: CreateEditTaskBottomSheet(
                  isEditing: _isEditingPost,
                  taskForm: _postForm,
                  nameController: _nameCtrl,
                  contentController: _contentCtrl,
                  locationSearchController: _locationSearchCtrl,
                  locationSuggestions: _locationSuggestions,
                  onLocationSearch: _fetchLocationSuggestions,
                  onLocationSelect: _selectLocation,
                  onSave: () async {
                    if (_isEditingPost) {
                      await _saveEditedPost();
                    } else {
                      await _saveNewPost();
                    }
                  },
                  onCancel: () => setState(() {
                    _isCreatingPost = false;
                    _isEditingPost = false;
                    _editingPostId = null;
                  }),
                ),
              ),
            ),

          // 編輯個人資料底部彈窗
          if (_isProfileEditing)
            Positioned.fill(
              child: DraggableBottomSheet(
                title: '編輯個人資料',
                maxHeight: 0.9,
                onClose: () => setState(() => _isProfileEditing = false),
                child: EditProfileBottomSheet(
                  profileForm: _profileForm,
                  onSave: _saveProfile,
                  onCancel: () => setState(() => _isProfileEditing = false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
