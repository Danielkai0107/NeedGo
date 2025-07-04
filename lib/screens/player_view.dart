// lib/screens/player_view.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../styles/map_styles.dart';
import '../components/full_screen_popup.dart';
import '../components/task_detail_sheet.dart';
import '../components/location_info_sheet.dart';
import '../utils/custom_snackbar.dart';
import '../services/chat_service.dart';

enum BottomSheetType {
  none,
  locationDetail,
  newPostNotification,
  myApplications,
  notificationPanel,
  profileView,
  profileEditor,
  basicInfoEdit,
  contactInfoEdit,
  resumeEdit,
}

class PlayerView extends StatefulWidget {
  const PlayerView({Key? key}) : super(key: key);

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 16; // 設置為中等縮放
  LatLng? _myLocation;
  final _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _postsSub;
  List<Map<String, dynamic>> _allPosts = [];
  Timestamp? _listenerAttachedTs;

  BottomSheetType _currentBottomSheet = BottomSheetType.none;
  List<Map<String, dynamic>> _systemLocations = [];
  Set<String> _availableCategories = {};
  Set<String> _selectedCategories = {};
  bool _showCategoryFilter = false;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _profileForm = {};
  String? _profileStatusType;
  String? _profileStatusMessage;
  Map<String, dynamic>? _newPostToShow;
  bool _isApplying = false;
  Map<String, List<Map<String, dynamic>>> _clusteredPosts = {};

  // 新的地圖標記管理
  Set<Marker> _markers = {};

  Map<String, List<Map<String, dynamic>>> _clusterPostsByLocation() {
    final clusters = <String, List<Map<String, dynamic>>>{};
    final currentUser = FirebaseAuth.instance.currentUser;
    final processedPosts = <String>{};

    // 只處理活躍的任務（排除自己發布的、過期的、已完成的）
    final activePosts = _allPosts
        .where(
          (post) =>
              post['userId'] != currentUser?.uid && _shouldShowTaskOnMap(post),
        )
        .toList();

    print('聚合處理 - 總任務數: ${_allPosts.length}, 有效任務數: ${activePosts.length}');

    for (var post in activePosts) {
      if (processedPosts.contains(post['id'])) continue;
      final postLat = post['lat'] as double;
      final postLng = post['lng'] as double;
      final cluster = <Map<String, dynamic>>[post];
      processedPosts.add(post['id']);

      for (var otherPost in activePosts) {
        if (processedPosts.contains(otherPost['id'])) continue;

        final otherLat = otherPost['lat'] as double;
        final otherLng = otherPost['lng'] as double;

        // 計算距離（米）
        final distance = Geolocator.distanceBetween(
          postLat,
          postLng,
          otherLat,
          otherLng,
        );

        // 如果距離小於50米，加入同一聚合
        if (distance <= 50) {
          cluster.add(otherPost);
          processedPosts.add(otherPost['id']);
        }
      }

      // 使用第一個任務的ID作為聚合鍵
      final clusterId = 'cluster_${post['id']}';
      clusters[clusterId] = cluster;
    }

    return clusters;
  }

  List<Map<String, dynamic>> get _myApplications {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    return _allPosts.where((p) {
      final apps = List<String>.from(p['applicants'] ?? []);
      return apps.contains(user.uid);
    }).toList();
  }

  // 新增通知相关变量
  List<Map<String, dynamic>> _newPosts = [];
  int _unreadCount = 0;
  Timer? _notificationTimer;
  DateTime? _lastCheckTime;
  Set<String> _readNotificationIds = {}; // 已讀通知 ID 集合

  // 任務計時器相關
  Timer? _taskTimer;
  static const Duration _checkInterval = Duration(minutes: 1); // 每分鐘檢查一次

  // 頭像上傳狀態
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayerData();
    });

    // 啟動任務計時器
    _startTaskTimer();
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _notificationTimer?.cancel();
    _taskTimer?.cancel(); // 停止任務計時器
    _mapCtrl.dispose(); // 新增：清理地圖控制器
    super.dispose();
  }

  /// 載入已讀通知 ID
  Future<void> _loadReadNotificationIds() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'read_notifications_${u.uid}'; // 為每個用戶分別保存
      final readIds = prefs.getStringList(key) ?? [];

      setState(() {
        _readNotificationIds = readIds.toSet();
      });

      print('📚 載入已讀通知 ID: ${_readNotificationIds.length} 個');
    } catch (e) {
      print('❌ 載入已讀通知 ID 失敗: $e');
    }
  }

  /// 保存已讀通知 ID
  Future<void> _saveReadNotificationIds() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'read_notifications_${u.uid}'; // 為每個用戶分別保存
      await prefs.setStringList(key, _readNotificationIds.toList());

      print('💾 保存已讀通知 ID: ${_readNotificationIds.length} 個');
    } catch (e) {
      print('❌ 保存已讀通知 ID 失敗: $e');
    }
  }

  /// 標記通知為已讀
  Future<void> _markNotificationAsRead(String notificationId) async {
    if (_readNotificationIds.add(notificationId)) {
      await _saveReadNotificationIds();
      print('📖 標記通知為已讀: $notificationId');
    }
  }

  /// 檢查通知是否已讀
  bool _isNotificationRead(String notificationId) {
    return _readNotificationIds.contains(notificationId);
  }

  // 改善初始化順序
  Future<void> _initializePlayerData() async {
    if (!mounted) return;

    try {
      if (mounted) await _loadSystemLocations();
      if (mounted) await _findAndRecenter();
      if (mounted) await _loadReadNotificationIds(); // 載入已讀通知 ID

      // 延遲設置監聽器
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        FirebaseAuth.instance.authStateChanges().listen((user) async {
          if (!mounted) return; // 新增檢查

          if (user != null) {
            if (mounted) _loadProfile(user.uid);
            if (mounted) await _loadMyProfile();
            if (mounted) await _loadReadNotificationIds(); // 用戶登入時重新載入已讀通知
            if (mounted) _initializeNotificationSystem();
            if (mounted) _attachPostsListener();
          } else {
            _cleanup();
          }
        });
      }
    } catch (e) {
      print('初始化失敗: $e');
    }
  }

  /// 加载 Player 个人档案（新增）
  Future<void> _loadMyProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      final doc = await _firestore.doc('user/${u.uid}').get();
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
            'applicantResume': '', // Player 用的是 applicantResume
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
            'applicantResume': '',
            'avatarUrl': '',
          };
          _profileForm = Map.from(_profile);
        });
      }
    }
  }

  void _cleanup() {
    _postsSub?.cancel();
    _notificationTimer?.cancel();
    if (mounted) {
      setState(() {
        _allPosts = [];
        _newPosts.clear();
        _unreadCount = 0;
      });
    }
  }

  /// 計算兩點間距離（公里）
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  /// 啟動任務計時器
  void _startTaskTimer() {
    _taskTimer = Timer.periodic(_checkInterval, (timer) {
      if (mounted) {
        _checkAndUpdateExpiredTasks();
      }
    });
    print('🕒 Player任務計時器已啟動，每 ${_checkInterval.inMinutes} 分鐘檢查一次');
  }

  /// 檢查並更新過期任務（Player視角）
  Future<void> _checkAndUpdateExpiredTasks() async {
    if (_allPosts.isEmpty) return;

    print('🔍 Player檢查任務是否過期...');

    List<String> expiredTaskIds = [];

    for (var task in _allPosts) {
      if (_isTaskExpiredNow(task) && task['status'] != 'expired') {
        expiredTaskIds.add(task['id']);
      }
    }

    // 批量更新過期任務
    for (String taskId in expiredTaskIds) {
      await _markTaskAsExpired(taskId);
    }

    // 清理已過期任務的通知
    _cleanupExpiredNotifications();

    if (expiredTaskIds.isNotEmpty && mounted) {
      // 重新載入任務以反映狀態變化
      _updateMarkers();

      // 顯示過期通知
      CustomSnackBar.showWarning(context, '有 ${expiredTaskIds.length} 個任務已過期');
    }
  }

  /// 檢查任務是否已過期（基於精確時間）
  bool _isTaskExpiredNow(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDateTime;
      final date = task['date'];
      final time = task['time'];

      // 解析日期
      if (date is String) {
        taskDateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDateTime = date;
      } else {
        return false;
      }

      // 如果有時間資訊，使用精確時間
      if (time != null && time is Map) {
        final hour = time['hour'] ?? 0;
        final minute = time['minute'] ?? 0;
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          hour,
          minute,
        );
      } else {
        // 如果沒有時間資訊，設定為當天 23:59
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          23,
          59,
        );
      }

      final now = DateTime.now();
      return now.isAfter(taskDateTime);
    } catch (e) {
      print('檢查任務過期時間失敗: $e');
      return false;
    }
  }

  /// 將任務標記為過期（Player視角）
  Future<void> _markTaskAsExpired(String taskId) async {
    try {
      print('⏰ Player檢測到任務過期 (ID: $taskId)');

      // 更新資料庫中的任務狀態
      await _firestore.doc('posts/$taskId').update({
        'status': 'expired',
        'isActive': false, // 從地圖上隱藏
        'updatedAt': Timestamp.now(),
        'expiredAt': Timestamp.now(),
      });

      print('✅ 任務狀態已更新為過期');
    } catch (e) {
      print('❌ 更新任務過期狀態失敗: $e');
    }
  }

  /// 清理已過期任務的通知
  void _cleanupExpiredNotifications() {
    if (_newPosts.isEmpty) return;

    final beforeCount = _newPosts.length;

    // 移除已過期或已完成的任務通知
    _newPosts.removeWhere((post) => !_shouldShowTaskOnMap(post));

    final afterCount = _newPosts.length;
    final removedCount = beforeCount - afterCount;

    if (removedCount > 0) {
      print('🗑️ 清理了 $removedCount 個已過期任務的通知');

      if (mounted) {
        setState(() {
          _unreadCount = _newPosts.length;
        });
      }
    }
  }

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

      if (mounted) {
        // 新增 mounted 檢查
        setState(() {
          _systemLocations = locations;
          _availableCategories = categories;
          _selectedCategories = Set.from(categories); // 預設全選
        });
      }

      print('載入了 ${locations.length} 個系統地點，${categories.length} 個類別');

      // 載入系統地點後更新標記
      _updateMarkers();
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  // 在 _loadProfile 方法中檢查設定
  Future<void> _loadProfile(String uid) async {
    try {
      final doc = await _firestore.doc('user/$uid').get(); // ✅ 改用 user 集合
      if (doc.exists && mounted) {
        setState(() => _profile = doc.data()!);
      }
    } catch (e) {
      print('載入個人資料失敗: $e');
    }
  }

  /// 檢查歷史通知（登入時檢查登入前的新貼文）
  Future<void> _checkHistoricalNotifications() async {
    if (_lastCheckTime == null || !mounted) return; // 新增 mounted 檢查

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) return; // 新增 mounted 檢查

    try {
      print('檢查歷史通知，從 $_lastCheckTime 開始');

      final snapshot = await _firestore
          .collection('posts')
          .where(
            'createdAt',
            isGreaterThan: Timestamp.fromDate(_lastCheckTime!),
          )
          .orderBy('createdAt', descending: true)
          .get();

      print('找到 ${snapshot.docs.length} 個歷史新貼文');

      if (snapshot.docs.isNotEmpty && mounted) {
        // 新增 mounted 檢查
        final historicalPosts = snapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return data;
            })
            .where(
              (post) =>
                  post['userId'] != currentUser.uid && // 排除自己發布的
                  !_isNotificationRead(post['id']) && // 排除已讀的通知
                  _shouldShowTaskOnMap(post), // 排除已過期和已完成的任務
            )
            .toList();

        if (mounted) {
          // 新增 mounted 檢查
          setState(() {
            _newPosts.addAll(historicalPosts);
            _unreadCount = _newPosts.length;
          });
        }

        print('已添加 ${historicalPosts.length} 個歷史通知（排除自己發布的）');
      }
    } catch (e) {
      print('檢查歷史通知失敗: $e');
    }
  }

  void _attachPostsListener() {
    if (!mounted) return; // 新增檢查

    // 先檢查歷史通知
    _checkHistoricalNotifications();

    // 設定監聽器附加時間（用於後續新貼文檢測）
    _listenerAttachedTs = Timestamp.now();

    _postsSub = _firestore.collection('posts').snapshots().listen((snap) {
      if (!mounted) return; // 新增檢查

      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data() as Map);
        m['id'] = d.id;
        return m;
      }).toList();

      list.sort((a, b) {
        final ta = a['createdAt'] as Timestamp?;
        final tb = b['createdAt'] as Timestamp?;
        return (tb?.seconds ?? 0).compareTo(ta?.seconds ?? 0);
      });

      if (mounted) {
        // 新增 mounted 檢查
        setState(() => _allPosts = list);

        // 更新地圖標記
        _updateMarkers();

        // 輸出調試信息
        final activeTasks = list
            .where((task) => _shouldShowTaskOnMap(task))
            .length;
        final totalTasks = list.length;
        print('總任務數: $totalTasks, 有效任務數: $activeTasks');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || !mounted) return; // 新增 mounted 檢查

      // 處理即時新增的貼文（登入後新發布的）
      // 處理即時新增的貼文（登入後新發布的）
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.added &&
            _listenerAttachedTs != null &&
            (change.doc['createdAt'] as Timestamp).compareTo(
                  _listenerAttachedTs!,
                ) >
                0) {
          final newPost = {
            'id': change.doc.id,
            ...Map<String, dynamic>.from(change.doc.data() as Map),
          };

          // 排除自己發布的案件
          if (newPost['userId'] == currentUser.uid) continue;

          // 排除已過期和已完成的任務
          if (!_shouldShowTaskOnMap(newPost)) {
            print(
              '🚫 跳過無效任務通知: ${newPost['title'] ?? newPost['name']} (狀態: ${newPost['status']})',
            );
            continue;
          }

          // 檢查通知是否已讀
          final notificationId = newPost['id'];
          if (_isNotificationRead(notificationId)) {
            print('📖 跳過已讀通知: $notificationId');
            continue;
          }

          // 添加到通知列表
          if (mounted) {
            // 新增 mounted 檢查
            setState(() {
              _newPosts.insert(0, newPost);
              _unreadCount = _newPosts.length;
            });
          }

          // 如果當前沒有彈窗，顯示即時通知
          if (mounted && // 新增 mounted 檢查
              _currentBottomSheet == BottomSheetType.none) {
            setState(() {
              _newPostToShow = newPost;
              _currentBottomSheet = BottomSheetType.newPostNotification;
            });
          }
        }
      }
    });
  }

  /// 初始化通知系统
  void _initializeNotificationSystem() {
    // 只需要初始化時間記錄
    _lastCheckTime = DateTime.now().subtract(const Duration(hours: 24));
    print('初始化通知系統，最後檢查時間: $_lastCheckTime');
  }

  /// 获取并更新当前位置
  Future<void> _findAndRecenter() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請在系統設定允許定位權限')));
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      final coord = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = coord);
      _updateMarkers(); // 更新標記以包含新的位置
      _mapCtrl.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: coord, zoom: _zoom, tilt: 60.0),
        ),
      );
    } catch (_) {}
  }

  /// 点击任意 Marker（静态或动态）都会调用它
  void _selectLocationMarker(
    Map<String, dynamic> loc, {
    bool isStatic = false,
  }) {
    // 新增 isStatic 參數
    // 調試信息：檢查傳遞給任務詳情彈窗的數據
    print('選中的位置數據: $loc');
    print('地址字段: ${loc['address']}');
    print('地址字段類型: ${loc['address'].runtimeType}');

    // 如果是任務（有 userId），使用新的 TaskDetailSheet
    if (loc['userId'] != null && !isStatic) {
      // 檢查任務是否有效（未過期且未完成）
      if (!_shouldShowTaskOnMap(loc)) {
        CustomSnackBar.showWarning(context, '此任務已過期或不可用');
        return;
      }

      // 移動地圖到任務位置
      _moveMapToLocation(LatLng(loc['lat'], loc['lng']));

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (context) => TaskDetailSheet(
          taskData: loc,
          isParentView: false,
          currentLocation: _myLocation,
          onTaskUpdated: () {
            // 重新載入任務列表和更新標記
            if (mounted) {
              setState(() {
                // 可能需要重新載入 _allPosts
              });
              _updateMarkers();
            }
          },
        ),
      );
      return; // 直接返回，不執行後續邏輯
    }

    // 系統地點，使用新的 LocationInfoSheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: loc,
        isParentView: false,
        currentLocation: _myLocation,
      ),
    );
  }

  Future<void> _applyToPost(String postId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || _isApplying) return;
    setState(() => _isApplying = true);
    await _firestore.doc('posts/$postId').update({
      'applicants': FieldValue.arrayUnion([u.uid]),
    });
    setState(() {
      _isApplying = false;
    });
  }

  Future<void> _cancelApplication(String postId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    await _firestore.doc('posts/$postId').update({
      'applicants': FieldValue.arrayRemove([u.uid]),
    });
  }

  void _openProfileView() {
    setState(() {
      _currentBottomSheet = BottomSheetType.profileView;
    });
  }

  void _openProfileEditor() {
    _profileForm = Map<String, dynamic>.from(_profile);
    _profileStatusType = null;
    _profileStatusMessage = null;
    setState(() {
      _currentBottomSheet = BottomSheetType.profileEditor;
    });
  }

  void _closeProfileEditor() =>
      setState(() => _currentBottomSheet = BottomSheetType.none);

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ref = _firestore.doc('user/${u.uid}');
    try {
      await ref.set(_profileForm, SetOptions(merge: true));

      // 重新載入個人資料資料
      await _loadMyProfile();

      setState(() {
        _profile = Map.from(_profileForm);
        _profileStatusType = 'success';
        _profileStatusMessage = '履歷更新成功';
      });

      // 根據當前彈窗類型決定返回邏輯
      if (_currentBottomSheet == BottomSheetType.basicInfoEdit ||
          _currentBottomSheet == BottomSheetType.contactInfoEdit ||
          _currentBottomSheet == BottomSheetType.resumeEdit) {
        // 從分區塊編輯返回檢視頁面
        setState(() => _currentBottomSheet = BottomSheetType.profileView);
      } else {
        // 從完整編輯頁面延遲關閉
        Future.delayed(const Duration(seconds: 1), _closeProfileEditor);
      }
    } catch (e) {
      setState(() {
        _profileStatusType = 'error';
        _profileStatusMessage = '儲存失敗：$e';
      });
    }
  }

  // 直接選擇並上傳頭像
  Future<void> _pickAndUploadAvatar() async {
    if (_isUploadingAvatar) return; // 防止重複操作

    try {
      setState(() => _isUploadingAvatar = true);

      final ImagePicker picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _isUploadingAvatar = false);
        return;
      }

      final bytes = await picked.readAsBytes();

      // 進行自動裁切
      final croppedImage = await _performAutoCrop(bytes);

      if (croppedImage != null) {
        // 上傳頭像
        await _uploadAvatarToFirebase(croppedImage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('選擇圖片失敗：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  // 自動裁切方法
  Future<Uint8List?> _performAutoCrop(Uint8List imageBytes) async {
    try {
      // 使用 dart:ui 套件計算正方形裁切
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width;
      final height = image.height;
      final size = math.min(width, height);
      final offsetX = (width - size) / 2;
      final offsetY = (height - size) / 2;

      // 創建畫布進行裁切
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final srcRect = Rect.fromLTWH(
        offsetX,
        offsetY,
        size.toDouble(),
        size.toDouble(),
      );
      final destRect = Rect.fromLTWH(0, 0, 300, 300); // 固定輸出尺寸為 300x300

      canvas.drawImageRect(image, srcRect, destRect, Paint());

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(300, 300);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        return byteData.buffer.asUint8List();
      } else {
        throw '無法處理圖片';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('自動裁切失敗：$e')));
      }
      return null;
    }
  }

  // 上傳頭像到 Firebase Storage
  Future<void> _uploadAvatarToFirebase(Uint8List imageBytes) async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;

      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/${u.uid}.jpg',
      );

      await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final avatarUrl = await storageRef.getDownloadURL();

      // 更新 Firestore 中的頭像 URL
      await _firestore.doc('user/${u.uid}').update({'avatarUrl': avatarUrl});

      // 重新載入個人資料
      await _loadMyProfile();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('頭像更新成功！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('頭像上傳失敗：$e')));
      }
    }
  }

  void _acceptNewPost() {
    if (_newPostToShow != null) {
      _selectLocationMarker(_newPostToShow!, isStatic: false); // 新增參數
      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _newPostToShow = null;
      });
    }
  }

  void _closeNewPostNotification() {
    setState(() {
      _currentBottomSheet = BottomSheetType.none;
      _newPostToShow = null;
    });
  }

  void _openMyApplications() =>
      setState(() => _currentBottomSheet = BottomSheetType.myApplications);
  void _closeMyApplications() =>
      setState(() => _currentBottomSheet = BottomSheetType.none);

  // 修改：檢查靜態地點是否被聚合覆蓋
  bool _isStaticLocationCoveredByCluster(Map<String, dynamic> staticLocation) {
    for (var clusterPosts in _clusteredPosts.values) {
      if (clusterPosts.isEmpty) continue;

      // 使用聚合中第一個任務的位置代表聚合位置
      final clusterLat = clusterPosts.first['lat'] as double;
      final clusterLng = clusterPosts.first['lng'] as double;
      final staticLat = staticLocation['lat'] as double;
      final staticLng = staticLocation['lng'] as double;

      // 計算距離
      final distance = Geolocator.distanceBetween(
        staticLat,
        staticLng,
        clusterLat,
        clusterLng,
      );

      // 如果距離小於50米，認為被覆蓋
      if (distance <= 50) {
        return true;
      }
    }
    return false;
  }

  Set<Marker> _buildStaticParkMarkers() {
    // 先計算聚合結果
    _clusteredPosts = _clusterPostsByLocation();

    return {
      for (var location in _systemLocations)
        if (_selectedCategories.contains(location['category']) &&
            !_isStaticLocationCoveredByCluster(location)) // 新增條件：未被聚合覆蓋
          Marker(
            markerId: MarkerId('system_${location['id']}'),
            position: LatLng(location['lat'], location['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            onTap: () => _selectLocationMarker({
              'name': location['name'],
              'lat': location['lat'],
              'lng': location['lng'],
              'address': location['address'],
              'category': location['category'],
              'content': null,
              'applicants': <String>[],
              'userId': null,
              'id': null,
            }, isStatic: true),
          ),
    };
  }

  Set<Marker> _buildPostMarkers() {
    // 使用已計算的聚合結果（在 _buildStaticParkMarkers 中計算）
    final markers = <Marker>{};

    for (var entry in _clusteredPosts.entries) {
      final posts = entry.value;
      if (posts.isEmpty) continue;

      // posts 已經在聚合時過濾過了，這裡不需要再次過濾
      if (posts.isEmpty) continue;

      // 使用第一個任務的位置作為代表位置
      final representativePost = posts.first;
      final position = LatLng(
        representativePost['lat'],
        representativePost['lng'],
      );

      // 統一使用 LocationInfoSheet，顯示該地點的所有任務
      final onTapAction = () => _showLocationInfoWithTasks(posts);

      markers.add(
        Marker(
          markerId: MarkerId('cluster_${entry.key}'),
          position: position,
          icon: posts.length > 1
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                )
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueYellow,
                ),
          onTap: onTapAction,
        ),
      );
    }

    return markers;
  }

  // 檢查任務是否應該在地圖上顯示（Player View）
  bool _shouldShowTaskOnMap(Map<String, dynamic> task) {
    // 檢查 isActive 欄位
    if (task['isActive'] == false) return false;

    // 檢查任務狀態
    final status = task['status'] ?? 'open';
    if (status == 'completed' || status == 'expired' || status == '已完成')
      return false;

    // 檢查是否已完成
    if (task['isCompleted'] == true) return false;

    // 檢查是否過期
    if (_isTaskExpired(task)) return false;

    return true;
  }

  // 檢查任務是否過期（Player View） - 更新為支持多種過期時間格式
  bool _isTaskExpired(Map<String, dynamic> task) {
    final now = DateTime.now();

    // 檢查明確的過期標記
    if (task['isExpired'] == true) {
      return true;
    }

    // 檢查多種可能的過期時間字段
    final expiryFields = [
      'expiryDate',
      'dueDate',
      'endDate',
      'expireTime',
      'date',
    ];

    for (String field in expiryFields) {
      if (task[field] != null) {
        try {
          DateTime? expiryDate;

          if (task[field] is Timestamp) {
            // Firestore Timestamp
            expiryDate = (task[field] as Timestamp).toDate();
          } else if (task[field] is String) {
            // ISO 8601 字符串
            expiryDate = DateTime.parse(task[field] as String);
          } else if (task[field] is int) {
            // Unix timestamp (milliseconds)
            expiryDate = DateTime.fromMillisecondsSinceEpoch(
              task[field] as int,
            );
          } else if (task[field] is DateTime) {
            expiryDate = task[field] as DateTime;
          }

          if (expiryDate != null) {
            // 如果是 date 字段，結合 time 字段獲取精確時間
            if (field == 'date' &&
                task['time'] != null &&
                task['time'] is Map) {
              final time = task['time'] as Map;
              final hour = time['hour'] ?? 23;
              final minute = time['minute'] ?? 59;
              expiryDate = DateTime(
                expiryDate.year,
                expiryDate.month,
                expiryDate.day,
                hour,
                minute,
              );
            } else if (field == 'date') {
              // 如果只有日期沒有時間，設定為當天結束
              expiryDate = DateTime(
                expiryDate.year,
                expiryDate.month,
                expiryDate.day,
                23,
                59,
              );
            }

            if (now.isAfter(expiryDate)) {
              print(
                '任務已過期: ${task['title'] ?? task['name'] ?? task['id']} (過期時間: $expiryDate)',
              );
              return true;
            }
          }
        } catch (e) {
          print(
            '解析任務過期時間失敗: ${task['title'] ?? task['id']}, 字段: $field, 錯誤: $e',
          );
        }
      }
    }

    return false;
  }

  /// 顯示聚合地點的 LocationInfoSheet 與任務列表
  void _showLocationInfoWithTasks(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) return;

    // 篩選有效任務（排除已過期和已完成的任務）
    final validTasks = tasks
        .where((task) => _shouldShowTaskOnMap(task))
        .toList();

    if (validTasks.isEmpty) {
      // 如果篩選後沒有有效任務，顯示提示
      CustomSnackBar.showWarning(context, '此地點目前沒有有效任務');
      return;
    }

    // 使用第一個有效任務的位置作為代表地點
    final representativeTask = validTasks.first;
    final position = LatLng(
      representativeTask['lat'],
      representativeTask['lng'],
    );

    // 移動地圖到該位置
    _moveMapToLocation(position);

    // 建立地點資料結構
    final locationData = {
      'name': _getLocationNameForTasks(validTasks),
      'lat': representativeTask['lat'],
      'lng': representativeTask['lng'],
      'address': representativeTask['address'] ?? '地址未設定',
      'category': '任務地點',
    };

    print('傳遞給LocationInfoSheet的任務數量: ${validTasks.length}');
    print('原始任務數量: ${tasks.length}');

    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: false,
        currentLocation: _myLocation,
        availableTasksAtLocation: validTasks, // 傳遞篩選後的任務
        onTaskSelected: (taskData) {
          // 關閉 LocationInfoSheet
          Navigator.of(context).pop();

          // 先清除任何現有的 SnackBar
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }

          // 顯示 TaskDetailSheet
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            enableDrag: true,
            backgroundColor: Colors.transparent,
            builder: (context) => TaskDetailSheet(
              taskData: taskData,
              isParentView: false,
              currentLocation: _myLocation,
              onTaskUpdated: () {
                // 重新載入任務列表和更新標記
                if (mounted) {
                  setState(() {
                    // 可能需要重新載入 _allPosts
                  });
                  _updateMarkers();
                }
              },
            ),
          );
        },
      ),
    );
  }

  /// 為任務群組生成地點名稱
  String _getLocationNameForTasks(List<Map<String, dynamic>> tasks) {
    if (tasks.length == 1) {
      return tasks.first['title'] ?? tasks.first['name'] ?? '任務地點';
    } else {
      return '此地點的任務 (${tasks.length}個)';
    }
  }

  // 新增方法：
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

  /// 构建通知按钮（带红点）
  Widget _buildNotificationButton() {
    return Stack(
      children: [
        FloatingActionButton(
          backgroundColor: _unreadCount > 0 ? Colors.orange[600] : Colors.white,
          foregroundColor: _unreadCount > 0 ? Colors.white : Colors.black,
          heroTag: 'notifications',
          mini: false,
          child: Icon(Icons.notifications),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(56),
          ),
          onPressed: _openNotificationPanel,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  /// 顯示通知列表
  void _showNotificationsList() {
    print('🔔 打開通知列表，當前通知數量: ${_newPosts.length}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 標題欄
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // 標題列
                        Row(
                          children: [
                            Icon(
                              Icons.notifications_active,
                              color: Colors.orange[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '最新案件通知 (${_newPosts.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_newPosts.isNotEmpty)
                              TextButton(
                                onPressed: () async {
                                  // 標記所有通知為已讀
                                  for (final post in _newPosts) {
                                    await _markNotificationAsRead(post['id']);
                                  }

                                  setState(() {
                                    _newPosts.clear();
                                    _unreadCount = 0;
                                  });
                                  setModalState(() {
                                    _newPosts.clear();
                                    _unreadCount = 0;
                                  });
                                  Navigator.pop(context);
                                  CustomSnackBar.showSuccess(
                                    context,
                                    '所有通知已清除',
                                  );
                                },
                                child: const Text('全部清除'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  // 通知列表
                  Expanded(
                    child: _newPosts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '目前沒有新案件',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '我們會即時通知您最新的工作機會',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _newPosts.length,
                            itemBuilder: (context, index) {
                              final post =
                                  _newPosts[_newPosts.length -
                                      1 -
                                      index]; // 反向顯示
                              return _buildNotificationItem(post);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 查看通知中的案件詳情
  void _viewNotificationPostDetails(Map<String, dynamic> post) async {
    // 標記通知為已讀
    await _markNotificationAsRead(post['id']);

    // 關閉通知列表
    Navigator.of(context).pop();

    // 移動地圖到任務位置並显示任务详情彈窗
    _moveMapToLocation(LatLng(post['lat'], post['lng']));

    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: post,
        isParentView: false,
        currentLocation: _myLocation,
        onTaskUpdated: () {
          // 重新載入任務列表和更新標記
          if (mounted) {
            setState(() {
              // 可能需要重新載入 _allPosts
            });
            _updateMarkers();
          }
        },
      ),
    );

    // 从新案件列表中移除已查看的案件
    setState(() {
      _newPosts.removeWhere((p) => p['id'] == post['id']);
      _unreadCount = _newPosts.length;
    });
  }

  /// 建立通知項目
  Widget _buildNotificationItem(Map<String, dynamic> post) {
    final createdAt = (post['createdAt'] as Timestamp?)?.toDate();
    final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '剛剛';

    return Dismissible(
      key: Key(post['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      onDismissed: (direction) async {
        // 標記通知為已讀
        await _markNotificationAsRead(post['id']);

        setState(() {
          _newPosts.removeWhere((p) => p['id'] == post['id']);
          _unreadCount = _newPosts.length;
        });
        CustomSnackBar.showSuccess(context, '通知已移除');
      },
      child: GestureDetector(
        onTap: () => _viewNotificationPostDetails(post),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange[200]!, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 圖標
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[600],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.work_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              // 內容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '新的工作機會',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.grey[400],
                          size: 12,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      post['name'] ?? '未命名案件',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (post['content']?.toString().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        post['content'],
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: Colors.orange[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 计算时间差
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
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
                _switchToRole('/parent');
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

  /// 更新地圖標記 - 使用Player專用的聚合邏輯
  void _updateMarkers() {
    if (!mounted) return;

    final allMarkers = <Marker>{};

    // 添加系統地點標記
    allMarkers.addAll(_buildStaticParkMarkers());

    // 添加聚合任務標記
    allMarkers.addAll(_buildPostMarkers());

    // 添加用戶位置標記
    if (_myLocation != null) {
      allMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    setState(() {
      _markers = allMarkers;
    });
  }

  /// 移動地圖到指定位置
  void _moveMapToLocation(LatLng position) {
    _mapCtrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: _zoom, tilt: 60.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: _zoom,
              tilt: 60.0, // 固定仰角60度
            ),
            onMapCreated: (c) => _mapCtrl = c..setMapStyle(mapStyleJson),
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            buildingsEnabled: false, // 隱藏3D建築
            zoomGesturesEnabled: true, // 允許縮放手勢
            tiltGesturesEnabled: false, // 禁用仰角調整手勢
            minMaxZoomPreference: const MinMaxZoomPreference(
              14,
              22,
            ), // 縮放範圍14-22
          ),

          // 類別篩選器
          Positioned(
            bottom: 160,
            left: 0,
            width: 320,
            child: _buildCategoryFilter(),
          ),

          // 1. 左上角 (Top-Left) – 設定入口
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 個人資料設定按鈕 - 使用者頭貼+認證標籤
                  GestureDetector(
                    onTap: _openProfileView,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: Stack(
                        children: [
                          // 用戶頭像
                          CircleAvatar(
                            radius: 34,
                            backgroundImage:
                                (_profile['avatarUrl']?.toString().isNotEmpty ==
                                    true)
                                ? NetworkImage(_profile['avatarUrl'])
                                : null,
                            child:
                                (_profile['avatarUrl']?.toString().isEmpty !=
                                    false)
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 38,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          // 頭像上傳loading遮罩
                          if (_isUploadingAvatar)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          // 認證標籤
                          if (_profile['isVerified'] == true &&
                              !_isUploadingAvatar)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.blue[700],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.verified_user_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 角色資訊和切換按鈕
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 當前身份
                      Text(
                        '陪伴者',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 角色切換按鈕
                      InkWell(
                        onTap: () => _showRoleSwitchDialog(context, '發布者'),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            '角色切換',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 2. 右上角 (Top-Right) – 操作群組
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 聊天室按鈕
                StreamBuilder<int>(
                  stream: ChatService.getPlayerUnreadCount(),
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.data ?? 0;

                    return FloatingActionButton(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      heroTag: 'chat',
                      mini: true,
                      child: Stack(
                        children: [
                          const Icon(Icons.chat_rounded),
                          // 如果有未讀訊息，顯示紅點
                          if (unreadCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    unreadCount > 9
                                        ? '9+'
                                        : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(56),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, '/chat');
                      },
                    );
                  },
                ),
                const SizedBox(width: 12),
                // 通知按鈕
                Stack(
                  children: [
                    FloatingActionButton(
                      backgroundColor: _unreadCount > 0
                          ? Colors.orange[600]
                          : Colors.white,
                      foregroundColor: _unreadCount > 0
                          ? Colors.white
                          : Colors.black,
                      heroTag: 'notifications',
                      mini: true,
                      child: const Icon(Icons.notifications_rounded),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(56),
                      ),
                      onPressed: _openNotificationPanel,
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        right: -2, // 往右2px（相對於parent的位置）
                        top: -2, // 往上2px（相對於parent的位置）
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // 登出按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'logout',
                  mini: true,
                  child: const Icon(Icons.logout_rounded),
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

          // 3. 左下角 (Bottom-Left) – 篩選 & 定位
          Positioned(
            bottom: 40,
            left: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 篩選按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'filter',
                  mini: false,
                  child: Icon(
                    _showCategoryFilter
                        ? Icons.close_rounded
                        : Icons.tune_rounded,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () {
                    setState(() {
                      _showCategoryFilter = !_showCategoryFilter;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // 定位按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'location',
                  mini: false,
                  child: const Icon(Icons.my_location_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: _findAndRecenter,
                ),
              ],
            ),
          ),

          // 4. 右下角 (Bottom-Right) – Player 專用功能
          Positioned(
            bottom: 40,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 我的應徵清單
                FloatingActionButton(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  heroTag: 'applications',
                  mini: false,
                  child: const Icon(Icons.assignment_turned_in_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: _openMyApplications,
                ),
              ],
            ),
          ),

          // 我的應徵清單底部彈窗
          if (_currentBottomSheet == BottomSheetType.myApplications)
            Positioned.fill(
              child: FullScreenPopup(
                title: '我的應徵清單',
                onClose: _closeMyApplications,
                child: MyApplicationsBottomSheet(
                  applications: _myApplications,
                  onCancelApplication: _cancelApplication,
                  onViewDetails: (application) {
                    // 新增这个回调函数
                    // 关闭当前弹窗
                    _closeMyApplications();

                    // 移動地圖到任務位置並显示新的任务详情彈窗
                    _moveMapToLocation(
                      LatLng(application['lat'], application['lng']),
                    );

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      enableDrag: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => TaskDetailSheet(
                        taskData: application,
                        isParentView: false,
                        currentLocation: _myLocation,
                        onTaskUpdated: () {
                          // 重新載入任務列表和更新標記
                          if (mounted) {
                            setState(() {
                              // 可能需要重新載入 _allPosts
                            });
                            _updateMarkers();
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

          // 個人資料檢視底部彈窗
          if (_currentBottomSheet == BottomSheetType.profileView)
            Positioned.fill(
              child: FullScreenPopup(
                title: '個人資料',
                onClose: () =>
                    setState(() => _currentBottomSheet = BottomSheetType.none),
                child: ProfileViewBottomSheet(
                  profile: _profile,
                  isParentView: false,
                  isUploadingAvatar: _isUploadingAvatar, // 傳遞loading狀態
                  onEditSection: (section) {
                    // 根據區塊顯示對應的編輯頁面
                    _profileForm = Map<String, dynamic>.from(_profile);
                    switch (section) {
                      case 'basic':
                        setState(
                          () => _currentBottomSheet =
                              BottomSheetType.basicInfoEdit,
                        );
                        break;
                      case 'contact':
                        setState(
                          () => _currentBottomSheet =
                              BottomSheetType.contactInfoEdit,
                        );
                        break;
                      case 'resume':
                        setState(
                          () =>
                              _currentBottomSheet = BottomSheetType.resumeEdit,
                        );
                        break;
                    }
                  },
                  onEditAvatar: () {
                    // 直接上傳頭像
                    _pickAndUploadAvatar();
                  },
                ),
              ),
            ),

          // 編輯個人資料底部彈窗
          if (_currentBottomSheet == BottomSheetType.profileEditor)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯個人資料',
                onClose: _closeProfileEditor,
                child: EditProfileBottomSheet(
                  profileForm: _profileForm,
                  isParentView: false,
                  userId: FirebaseAuth.instance.currentUser?.uid,
                  onSave: _saveProfile,
                  onCancel: _closeProfileEditor,
                ),
              ),
            ),

          // 基本資料編輯底部彈窗
          if (_currentBottomSheet == BottomSheetType.basicInfoEdit)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯基本資料',
                onClose: () => setState(
                  () => _currentBottomSheet = BottomSheetType.profileView,
                ),
                child: BasicInfoEditBottomSheet(
                  profileForm: _profileForm,
                  onSave: _saveProfile,
                  onCancel: () => setState(
                    () => _currentBottomSheet = BottomSheetType.profileView,
                  ),
                ),
              ),
            ),

          // 聯絡資訊編輯底部彈窗
          if (_currentBottomSheet == BottomSheetType.contactInfoEdit)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯聯絡資訊',
                onClose: () => setState(
                  () => _currentBottomSheet = BottomSheetType.profileView,
                ),
                child: ContactInfoEditBottomSheet(
                  profileForm: _profileForm,
                  onSave: _saveProfile,
                  onCancel: () => setState(
                    () => _currentBottomSheet = BottomSheetType.profileView,
                  ),
                ),
              ),
            ),

          // 簡介編輯底部彈窗
          if (_currentBottomSheet == BottomSheetType.resumeEdit)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯簡介',
                onClose: () => setState(
                  () => _currentBottomSheet = BottomSheetType.profileView,
                ),
                child: ResumeEditBottomSheet(
                  profileForm: _profileForm,
                  isParentView: false,
                  onSave: _saveProfile,
                  onCancel: () => setState(
                    () => _currentBottomSheet = BottomSheetType.profileView,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 打开通知面板
  void _openNotificationPanel() {
    setState(() {
      _unreadCount = 0; // 清除红点
    });
    _showNotificationsList();
  }

  /// 关闭通知面板
  void _closeNotificationPanel() {
    setState(() {
      _currentBottomSheet = BottomSheetType.none;
    });
  }

  /// 查看案件详情
  void _viewPostDetails(Map<String, dynamic> post) async {
    // 標記通知為已讀
    await _markNotificationAsRead(post['id']);

    setState(() {
      _currentBottomSheet = BottomSheetType.none;
    });

    // 移動地圖到任務位置並显示新的任务详情彈窗
    _moveMapToLocation(LatLng(post['lat'], post['lng']));

    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: post,
        isParentView: false,
        currentLocation: _myLocation,
        onTaskUpdated: () {
          // 重新載入任務列表和更新標記
          if (mounted) {
            setState(() {
              // 可能需要重新載入 _allPosts
            });
            _updateMarkers();
          }
        },
      ),
    );

    // 从新案件列表中移除已查看的案件
    _newPosts.removeWhere((p) => p['id'] == post['id']);
  }

  /// 清除所有通知
  void _clearAllNotifications() async {
    // 標記所有通知為已讀
    for (final post in _newPosts) {
      await _markNotificationAsRead(post['id']);
    }

    setState(() {
      _newPosts.clear();
      _unreadCount = 0;
    });
  }
}
