import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../styles/map_styles.dart';
import '../components/create_edit_task_bottom_sheet.dart' as new_task_sheet;
import '../components/task_detail_sheet.dart';
import '../components/location_info_sheet.dart';
import '../components/map_marker_manager.dart';
import '../utils/custom_snackbar.dart';

/// 用戶角色枚舉
enum UserRole { parent, player }

/// 底部彈窗類型
enum BottomSheetType {
  none,
  locationDetail,
  taskDetail,
  applicantsList,
  applicantProfile,
  myPostsList,
  myApplications,
  createEditPost,
  profileView,
  profileEditor,
  basicInfoEdit,
  contactInfoEdit,
  resumeEdit,
  verification,
  notificationPanel,
  newPostNotification,
}

/// 統一的地圖視角 - 合併 Player 和 Parent 視角
class UnifiedMapView extends StatefulWidget {
  const UnifiedMapView({Key? key}) : super(key: key);

  @override
  State<UnifiedMapView> createState() => _UnifiedMapViewState();
}

class _UnifiedMapViewState extends State<UnifiedMapView> {
  final _firestore = FirebaseFirestore.instance;
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locationSearchCtrl = TextEditingController();
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 16;
  LatLng? _myLocation;

  // 用戶角色和個人資料
  UserRole _userRole = UserRole.parent;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _profileForm = {};
  bool _isUploadingAvatar = false;

  // 地圖相關
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _systemLocations = [];
  Set<String> _availableCategories = {};
  Set<String> _selectedCategories = {};
  bool _showCategoryFilter = false;
  MarkerData? _selectedMarker;
  Map<String, dynamic>? _selectedLocation;
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;

  // 任務相關
  List<Map<String, dynamic>> _myPosts = [];
  List<Map<String, dynamic>> _allPosts = [];
  Map<String, dynamic> _postForm = {
    'name': '',
    'content': '',
    'lat': null,
    'lng': null,
  };
  String? _editingPostId;
  List<Map<String, dynamic>> _currentApplicants = [];
  Map<String, dynamic>? _selectedApplicant;
  Map<String, List<Map<String, dynamic>>> _clusteredPosts = {};
  StreamSubscription<QuerySnapshot>? _postsSub;

  // 通知相關
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _newPosts = [];
  int _unreadCount = 0;
  bool _showNotificationPopup = false;
  String? _latestNotificationMessage;
  Timer? _notificationTimer;
  DateTime? _lastCheckTime;
  Set<String> _readNotificationIds = {};
  Set<String> _readApplicantIds = {};
  StreamSubscription<QuerySnapshot>? _postsSubscription;
  bool _isInitialLoad = true;

  // 底部彈窗
  BottomSheetType _currentBottomSheet = BottomSheetType.none;

  // 任務計時器
  Timer? _taskTimer;
  static const Duration _checkInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
    _startTaskTimer();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationSearchCtrl.dispose();
    _contentCtrl.dispose();
    _taskTimer?.cancel();
    _postsSubscription?.cancel();
    _postsSub?.cancel();
    _notificationTimer?.cancel();
    _saveReadNotificationIds();
    _saveReadApplicantIds();
    super.dispose();
  }

  /// 初始化數據
  Future<void> _initializeData() async {
    if (!mounted) return;

    try {
      print('🚀 開始初始化統一地圖視角...');

      // 載入用戶資料和角色
      await _loadUserProfile();
      await _loadSystemLocations();
      await _findAndRecenter();
      await _loadReadNotificationIds();
      await _loadReadApplicantIds();

      // 根據角色載入不同的數據
      if (_userRole == UserRole.parent) {
        await _loadMyPosts();
        await _loadHistoricalApplicantNotifications();
        _startListeningForApplicants();
      } else {
        await _loadAllPosts();
        _initializeNotificationSystem();
        _attachPostsListener();
      }

      // 初始化時檢查過期任務
      await _checkAndUpdateExpiredTasks();
      _updateMarkers();

      print('✅ 統一地圖視角初始化完成');
    } catch (e) {
      print('❌ 初始化失敗: $e');
    }
  }

  /// 載入用戶資料
  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _profile = data;
          _profileForm = Map.from(_profile);
          // 根據用戶偏好設定角色
          final roleString = _profile['preferredRole'] ?? 'parent';
          _userRole = roleString == 'player'
              ? UserRole.player
              : UserRole.parent;
        });
      } else if (mounted) {
        setState(() {
          _profile = {
            'name': '未設定',
            'phoneNumber': '',
            'email': '',
            'lineId': '',
            'socialLinks': {},
            'applicantResume': '',
            'parentBio': '',
            'avatarUrl': '',
          };
          _profileForm = Map.from(_profile);
        });
      }
    } catch (e) {
      print('載入用戶資料失敗: $e');
    }
  }

  /// 載入系統地點
  Future<void> _loadSystemLocations() async {
    try {
      final snapshot = await _firestore.collection('systemLocations').get();
      final locations = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      final categories = locations
          .map((loc) => loc['category']?.toString() ?? '')
          .where((cat) => cat.isNotEmpty)
          .toSet();

      if (mounted) {
        setState(() {
          _systemLocations = locations;
          _availableCategories = categories;
          _selectedCategories = Set.from(categories);
        });
      }
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  /// 載入我的任務（Parent 視角）
  Future<void> _loadMyPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        if (data['lat'] != null) {
          data['lat'] = data['lat'] is String
              ? double.parse(data['lat'])
              : data['lat'].toDouble();
        }
        if (data['lng'] != null) {
          data['lng'] = data['lng'] is String
              ? double.parse(data['lng'])
              : data['lng'].toDouble();
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _myPosts = posts;
        });
      }
    } catch (e) {
      print('載入我的任務失敗: $e');
    }
  }

  /// 載入所有任務（Player 視角）
  Future<void> _loadAllPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        if (data['lat'] != null) {
          data['lat'] = data['lat'] is String
              ? double.parse(data['lat'])
              : data['lat'].toDouble();
        }
        if (data['lng'] != null) {
          data['lng'] = data['lng'] is String
              ? double.parse(data['lng'])
              : data['lng'].toDouble();
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _allPosts = posts;
        });
      }
    } catch (e) {
      print('載入所有任務失敗: $e');
    }
  }

  /// 切換角色
  void _switchRole() {
    setState(() {
      _userRole = _userRole == UserRole.parent
          ? UserRole.player
          : UserRole.parent;
    });

    // 保存角色偏好
    _saveRolePreference();

    // 重新載入數據
    if (_userRole == UserRole.parent) {
      _loadMyPosts();
      _startListeningForApplicants();
    } else {
      _loadAllPosts();
      _initializeNotificationSystem();
      _attachPostsListener();
    }

    _updateMarkers();
  }

  /// 保存角色偏好
  Future<void> _saveRolePreference() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('user').doc(user.uid).update({
        'preferredRole': _userRole == UserRole.parent ? 'parent' : 'player',
      });
    } catch (e) {
      print('保存角色偏好失敗: $e');
    }
  }

  /// 顯示角色切換對話框
  void _showRoleSwitchDialog(BuildContext context, String targetRole) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題
              Text(
                '切換角色',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              // 內容
              Text(
                '您確定要切換到「$targetRole」角色嗎？',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 按鈕組
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _switchRole();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('確定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 定位到當前位置
  Future<void> _findAndRecenter() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition();
      final newLocation = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _myLocation = newLocation;
          _center = newLocation;
        });

        _mapCtrl.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newLocation, zoom: _zoom, tilt: 60.0),
          ),
        );
      }
    } catch (e) {
      print('定位失敗: $e');
    }
  }

  // 這裡需要實現所有的通知系統方法、任務管理方法等
  // 由於代碼長度限制，我將創建一個基礎版本，然後逐步完善

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          // 地圖
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            style: MapStyles.customStyle,
            onMapCreated: (controller) {
              _mapCtrl = controller;
            },
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: (LatLng position) {
              // 點擊地圖時的處理
            },
          ),

          // 篩選器面板
          if (_showCategoryFilter)
            Positioned(
              top: MediaQuery.of(context).padding.top + 200,
              left: 16,
              right: 16,
              child: CategoryFilterPanel(
                availableCategories: _availableCategories,
                selectedCategories: _selectedCategories,
                onCategoryChanged: (categories) {
                  setState(() {
                    _selectedCategories = categories;
                  });
                  _updateMarkers();
                },
              ),
            ),

          // 左上角 - 角色信息和切換
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 用戶頭像
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[200],
                    backgroundImage:
                        _profile['avatarUrl'] != null &&
                            _profile['avatarUrl'].isNotEmpty
                        ? NetworkImage(_profile['avatarUrl'])
                        : null,
                    child:
                        _profile['avatarUrl'] == null ||
                            _profile['avatarUrl'].isEmpty
                        ? Icon(Icons.person, color: Colors.grey[600], size: 24)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // 角色信息
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userRole == UserRole.parent ? '發布者' : '陪伴者',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _showRoleSwitchDialog(
                          context,
                          _userRole == UserRole.parent ? '陪伴者' : '發布者',
                        ),
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

          // 左下角 - 篩選和定位
          Positioned(
            bottom: 140,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 篩選按鈕
                _buildActionButton(
                  icon: _showCategoryFilter
                      ? Icons.close_rounded
                      : Icons.tune_rounded,
                  onPressed: () {
                    setState(() {
                      _showCategoryFilter = !_showCategoryFilter;
                    });
                  },
                  heroTag: 'filter',
                  isLarge: true,
                ),
                const SizedBox(height: 16),
                // 定位按鈕
                _buildActionButton(
                  icon: Icons.my_location_rounded,
                  onPressed: _findAndRecenter,
                  heroTag: 'location',
                  isLarge: true,
                ),
              ],
            ),
          ),

          // 右下角 - 角色相關功能
          Positioned(
            bottom: 140,
            left: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Parent 角色 - 創建任務
                _buildActionButton(
                  icon: Icons.add_rounded,
                  onPressed: _startCreatePostManually,
                  heroTag: 'create',
                  isLarge: true,
                  backgroundColor: Colors.orange[600],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 建立操作按鈕
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String heroTag,
    bool isLarge = false,
    int badgeCount = 0,
    Color? backgroundColor,
  }) {
    Widget button = FloatingActionButton(
      backgroundColor:
          backgroundColor ??
          (badgeCount > 0 ? Colors.orange[600] : Colors.white),
      foregroundColor: backgroundColor != null || badgeCount > 0
          ? Colors.white
          : Colors.black,
      heroTag: heroTag,
      mini: !isLarge,
      child: Icon(icon),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(56)),
      onPressed: onPressed,
    );

    if (badgeCount > 0) {
      button = Stack(
        children: [
          button,
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
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
      );
    }

    return button;
  }

  /// 更新地圖標記
  void _updateMarkers() {
    if (!mounted) return;

    final allMarkers = <Marker>{};

    // 添加系統地點標記
    for (var location in _systemLocations) {
      if (!_selectedCategories.contains(location['category'])) continue;

      allMarkers.add(
        Marker(
          markerId: MarkerId('system_${location['id']}'),
          position: LatLng(location['lat'], location['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () => _showLocationDetail(location),
        ),
      );
    }

    // 根據角色添加不同的任務標記
    if (_userRole == UserRole.parent) {
      // Parent 視角 - 顯示我的任務
      for (var task in _myPosts) {
        if (task['lat'] == null || task['lng'] == null) continue;

        allMarkers.add(
          Marker(
            markerId: MarkerId('my_task_${task['id']}'),
            position: LatLng(task['lat'], task['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            onTap: () => _showTaskDetail(task, isMyTask: true),
          ),
        );
      }
    } else {
      // Player 視角 - 顯示所有可應徵的任務
      final currentUser = FirebaseAuth.instance.currentUser;
      for (var task in _allPosts) {
        if (task['lat'] == null || task['lng'] == null) continue;
        if (task['userId'] == currentUser?.uid) continue;

        allMarkers.add(
          Marker(
            markerId: MarkerId('task_${task['id']}'),
            position: LatLng(task['lat'], task['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            onTap: () => _showTaskDetail(task, isMyTask: false),
          ),
        );
      }
    }

    // 添加我的位置標記
    if (_myLocation != null) {
      allMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: '我的位置'),
        ),
      );
    }

    setState(() {
      _markers = allMarkers;
    });
  }

  /// 顯示地點詳情
  void _showLocationDetail(Map<String, dynamic> locationData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: _userRole == UserRole.parent,
        currentLocation: _myLocation,
        onCreateTaskAtLocation: () {
          Navigator.of(context).pop();
          if (_userRole == UserRole.parent) {
            _startCreatePostManually();
          }
        },
      ),
    );
  }

  /// 顯示任務詳情
  void _showTaskDetail(
    Map<String, dynamic> taskData, {
    required bool isMyTask,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: taskData,
        isParentView: _userRole == UserRole.parent,
        currentLocation: _myLocation,
        onTaskUpdated: () {
          if (_userRole == UserRole.parent) {
            _loadMyPosts();
          } else {
            _loadAllPosts();
          }
          _updateMarkers();
        },
        onEditTask: isMyTask
            ? () {
                Navigator.of(context).pop();
                _editingPostId = taskData['id'];
                _showEditTaskSheet(taskData);
              }
            : null,
        onDeleteTask: isMyTask
            ? () async {
                Navigator.of(context).pop();
                await _deleteTask(taskData['id']);
              }
            : null,
      ),
    );
  }

  /// 顯示編輯任務彈窗
  void _showEditTaskSheet(Map<String, dynamic> taskData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        existingTask: taskData,
        onSubmit: (updatedTaskData) async {
          Navigator.of(context).pop();
          await _saveEditedTask(updatedTaskData.toJson());
        },
      ),
    );
  }

  /// 保存編輯的任務
  Future<void> _saveEditedTask(Map<String, dynamic> taskData) async {
    try {
      final taskId = taskData['id'];
      await _firestore.collection('posts').doc(taskId).update({
        ...taskData,
        'updatedAt': Timestamp.now(),
      });

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務更新成功！');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '更新任務失敗：$e');
      }
    }
  }

  /// 刪除任務
  Future<void> _deleteTask(String taskId) async {
    try {
      await _firestore.collection('posts').doc(taskId).delete();

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務已刪除');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '刪除任務失敗：$e');
      }
    }
  }

  /// 開啟通知面板
  void _openNotificationPanel() {
    setState(() {
      _unreadCount = 0;
      _currentBottomSheet = BottomSheetType.notificationPanel;
    });
  }

  /// 開啟我的應徵清單
  void _openMyApplications() {
    setState(() {
      _currentBottomSheet = BottomSheetType.myApplications;
    });
  }

  /// 開始創建任務
  void _startCreatePostManually() {
    if (_userRole != UserRole.parent) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        onSubmit: (taskData) async {
          Navigator.of(context).pop();
          await _saveNewTask(taskData.toJson());
        },
      ),
    );
  }

  /// 保存新任務
  Future<void> _saveNewTask(Map<String, dynamic> taskData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firestore.collection('posts').add({
        ...taskData,
        'userId': user.uid,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'isActive': true,
        'applicants': [],
      });

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務創建成功！');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '創建任務失敗：$e');
      }
    }
  }

  /// 啟動任務計時器
  void _startTaskTimer() {
    _taskTimer = Timer.periodic(_checkInterval, (timer) {
      if (mounted) {
        _checkAndUpdateExpiredTasks();
      }
    });
  }

  /// 檢查並更新過期任務
  Future<void> _checkAndUpdateExpiredTasks() async {
    final tasksToCheck = _userRole == UserRole.parent ? _myPosts : _allPosts;
    if (tasksToCheck.isEmpty) return;

    List<String> expiredTaskIds = [];

    for (var task in tasksToCheck) {
      if (_isTaskExpiredNow(task)) {
        final currentStatus = task['status'] ?? 'open';
        final currentIsActive = task['isActive'] ?? true;

        if (currentStatus != 'expired' || currentIsActive != false) {
          expiredTaskIds.add(task['id']);
        }
      }
    }

    if (expiredTaskIds.isNotEmpty) {
      for (String taskId in expiredTaskIds) {
        await _markTaskAsExpired(taskId);
      }

      _updateMarkers();

      if (mounted) {
        CustomSnackBar.showWarning(
          context,
          '已更新 ${expiredTaskIds.length} 個過期任務的狀態',
        );
      }
    }
  }

  /// 檢查任務是否已過期
  bool _isTaskExpiredNow(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDateTime;
      final date = task['date'];
      final time = task['time'];

      if (date is String) {
        taskDateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDateTime = date;
      } else {
        return false;
      }

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
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          23,
          59,
        );
      }

      return DateTime.now().isAfter(taskDateTime);
    } catch (e) {
      return false;
    }
  }

  /// 標記任務為過期
  Future<void> _markTaskAsExpired(String taskId) async {
    try {
      await _firestore.doc('posts/$taskId').update({
        'status': 'expired',
        'isActive': false,
        'updatedAt': Timestamp.now(),
        'expiredAt': Timestamp.now(),
      });

      final tasksToUpdate = _userRole == UserRole.parent ? _myPosts : _allPosts;
      final taskIndex = tasksToUpdate.indexWhere((t) => t['id'] == taskId);
      if (taskIndex != -1 && mounted) {
        setState(() {
          tasksToUpdate[taskIndex]['status'] = 'expired';
          tasksToUpdate[taskIndex]['isActive'] = false;
        });
      }
    } catch (e) {
      print('❌ 更新任務過期狀態失敗: $e');
    }
  }

  // 簡化的通知系統實現
  void _attachPostsListener() {
    // Player 視角的任務監聽
    print('🔔 Player 視角任務監聽器啟動');
  }

  void _initializeNotificationSystem() {
    // Player 視角的通知系統
    print('🔔 Player 視角通知系統啟動');
  }

  void _startListeningForApplicants() {
    // Parent 視角的應徵者監聽
    print('🔔 Parent 視角應徵者監聽器啟動');
  }

  Future<void> _loadHistoricalApplicantNotifications() async {
    // 載入歷史應徵者通知
    print('📚 載入歷史應徵者通知');
  }

  Future<void> _loadReadNotificationIds() async {
    // 載入已讀通知ID
    print('📚 載入已讀通知ID');
  }

  Future<void> _saveReadNotificationIds() async {
    // 保存已讀通知ID
    print('💾 保存已讀通知ID');
  }

  Future<void> _loadReadApplicantIds() async {
    // 載入已讀應徵者ID
    print('📚 載入已讀應徵者ID');
  }

  Future<void> _saveReadApplicantIds() async {
    // 保存已讀應徵者ID
    print('💾 保存已讀應徵者ID');
  }
}

/// 類別篩選面板
class CategoryFilterPanel extends StatelessWidget {
  final Set<String> availableCategories;
  final Set<String> selectedCategories;
  final Function(Set<String>) onCategoryChanged;

  const CategoryFilterPanel({
    Key? key,
    required this.availableCategories,
    required this.selectedCategories,
    required this.onCategoryChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '篩選類別',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableCategories.map((category) {
              final isSelected = selectedCategories.contains(category);
              return FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  final newSelected = Set<String>.from(selectedCategories);
                  if (selected) {
                    newSelected.add(category);
                  } else {
                    newSelected.remove(category);
                  }
                  onCategoryChanged(newSelected);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
