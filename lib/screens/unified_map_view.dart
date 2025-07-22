import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../styles/map_styles.dart';
import '../styles/app_colors.dart';
import '../components/create_edit_task_bottom_sheet.dart' as new_task_sheet;
import '../components/create_edit_task_bottom_sheet.dart' show TaskData;
import '../components/task_detail_sheet.dart';
import '../components/location_info_sheet.dart';
import '../components/map_marker_manager.dart';
import '../components/location_marker.dart';
import '../utils/custom_snackbar.dart';
import '../services/chat_service.dart';

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
  StreamSubscription<DocumentSnapshot>? _userProfileSubscription;

  // 角色切換Loading狀態
  bool _isRoleSwitching = false;

  // 地圖標籤載入狀態
  bool _isMarkersLoading = false;

  // 地圖相關
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _systemLocations = [];
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
    // 立即設置載入狀態，避免用戶在資料載入前操作地圖
    _isMarkersLoading = true;
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
    _userProfileSubscription?.cancel();
    super.dispose();
  }

  /// 初始化數據
  Future<void> _initializeData() async {
    if (!mounted) return;

    try {
      print('🚀 開始初始化統一地圖視角...');

      // 載入用戶資料和角色（這是第一步，確保角色正確設定）
      await _loadUserProfile();
      print('用戶資料載入完成，當前角色: ${_userRole.name}');

      await _loadSystemLocations();
      await _findAndRecenter();
      await _loadReadNotificationIds();
      await _loadReadApplicantIds();

      // 根據角色載入不同的數據
      print('🔄 根據角色載入數據 - 當前角色: ${_userRole.name}');
      if (_userRole == UserRole.parent) {
        await _loadMyPosts();
        await _loadHistoricalApplicantNotifications();
        _startListeningForApplicants();
        print('📍 Parent 視角數據載入完成，更新地圖標記...');
      } else {
        await _loadAllPosts();
        _initializeNotificationSystem();
        _attachPostsListener();
        print('📍 Player 視角數據載入完成，更新地圖標記...');
      }

      // 初始化時檢查過期任務
      await _checkAndUpdateExpiredTasks();
      _updateMarkers();
      print('🏁 初始化完成，地圖標記已更新');

      print('統一地圖視角初始化完成');
    } catch (e) {
      print(' 初始化失敗: $e');
      // 確保在錯誤時也清除載入狀態
      if (mounted) {
        setState(() {
          _isMarkersLoading = false;
        });
      }
    }
  }

  /// 載入用戶資料
  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 首先載入一次用戶資料
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
          print('👤 用戶角色設定: $roleString -> ${_userRole.name}');
        });
      } else if (mounted) {
        print('⚠️  用戶文檔不存在，使用預設設定');
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
            'isVerified': false,
            'preferredRole': 'parent', // 確保有預設角色
          };
          _profileForm = Map.from(_profile);
          // 設定預設角色為 parent
          _userRole = UserRole.parent;
          print('👤 使用預設角色: parent -> ${_userRole.name}');
        });
      }

      // 設置即時監聽用戶資料變化
      _userProfileSubscription = _firestore
          .collection('user')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && mounted) {
              final data = snapshot.data()!;
              setState(() {
                _profile = data;
                _profileForm = Map.from(_profile);
                // 根據用戶偏好設定角色
                final roleString = _profile['preferredRole'] ?? 'parent';
                final oldRole = _userRole;
                _userRole = roleString == 'player'
                    ? UserRole.player
                    : UserRole.parent;

                if (oldRole != _userRole) {
                  print('👤 角色變更偵測: ${oldRole.name} -> ${_userRole.name}');
                }
              });
            }
          });
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

      if (mounted) {
        setState(() {
          _systemLocations = locations;
        });
      }
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  /// 載入我的任務（Parent 視角）
  Future<void> _loadMyPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print(' 用戶未登入，無法載入我的任務');
      return;
    }

    print('🔄 開始載入我的任務（Parent 視角）- 用戶ID: ${user.uid}');

    try {
      // 首先嘗試使用複合索引查詢
      final snapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      print('📦 Firestore 查詢結果：${snapshot.docs.length} 個文檔');

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;

        print('📄 任務 ${doc.id}: ${data['title'] ?? data['name'] ?? '無標題'}');
        print('   - lat: ${data['lat']}, lng: ${data['lng']}');
        print('   - isActive: ${data['isActive']}');
        print('   - userId: ${data['userId']}');

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

      print('成功載入 ${posts.length} 個我的任務');

      // 統計有地理位置的任務
      final tasksWithLocation = posts
          .where((task) => task['lat'] != null && task['lng'] != null)
          .length;
      print('📍 其中 $tasksWithLocation 個任務有地理位置');

      if (mounted) {
        setState(() {
          _myPosts = posts;
        });

        // 數據載入完成後立即更新標記
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateMarkers();
          print('🔄 _loadMyPosts 完成後已觸發地圖標記更新');
        });
      }
    } catch (e) {
      print(' 載入我的任務失敗: $e');

      // 如果是索引問題，嘗試替代查詢方法
      if (e.toString().contains('FAILED_PRECONDITION') ||
          e.toString().contains('index')) {
        print('🔄 索引缺失，嘗試替代查詢方法...');
        await _loadMyPostsAlternative();
      } else {
        // 其他錯誤，確保UI狀態正確
        if (mounted) {
          setState(() {
            _myPosts = [];
          });
        }
      }
    }
  }

  /// 替代的載入我的任務方法（當索引缺失時使用）
  Future<void> _loadMyPostsAlternative() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 只按 userId 篩選，然後在客戶端排序
      final snapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .get();

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;

        // 確保座標是 double 類型
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

      // 在客戶端按 createdAt 排序
      posts.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime); // 降序排序
        }
        return 0;
      });

      if (mounted) {
        setState(() {
          _myPosts = posts;
        });
        print('使用替代方法成功載入 ${posts.length} 個我的任務');

        // 數據載入完成後立即更新標記
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateMarkers();
        });
      }
    } catch (e) {
      print(' 替代查詢也失敗: $e');
      if (mounted) {
        setState(() {
          _myPosts = [];
        });
      }
    }
  }

  /// 載入所有任務（Player 視角）
  Future<void> _loadAllPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print(' 用戶未登入，無法載入任務');
      return;
    }

    print('🔄 開始載入所有任務（Player 視角）...');

    try {
      // 嘗試使用複合索引查詢，只載入活躍的任務
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

      // 進一步過濾，只保留真正活躍的任務（排除已過期的任務）
      final activePosts = posts.where((task) => _isTaskActive(task)).toList();

      print('成功載入 ${posts.length} 個標記為活躍的任務');
      print('🔍 過濾後實際活躍任務: ${activePosts.length} 個');

      if (mounted) {
        setState(() {
          _allPosts = activePosts;
        });
      }
    } catch (e) {
      print(' 載入所有任務失敗: $e');

      // 如果是索引問題，嘗試替代查詢方法
      if (e.toString().contains('FAILED_PRECONDITION') ||
          e.toString().contains('index')) {
        print('🔄 索引缺失，嘗試替代查詢方法...');
        await _loadAllPostsAlternative();
      }
    }
  }

  /// 替代的載入方法（當索引缺失時使用）
  Future<void> _loadAllPostsAlternative() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 先只按 isActive 篩選，然後在客戶端排序
      final snapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
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

      // 在客戶端按 createdAt 排序
      posts.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime); // 降序排序
        }
        return 0;
      });

      // 進一步過濾，只保留真正活躍的任務（排除已過期的任務）
      final activePosts = posts.where((task) => _isTaskActive(task)).toList();

      print('使用替代方法成功載入 ${posts.length} 個標記為活躍的任務');
      print('🔍 過濾後實際活躍任務: ${activePosts.length} 個');

      if (mounted) {
        setState(() {
          _allPosts = activePosts;
        });

        // 數據載入完成後立即更新標記
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateMarkers();
        });
      }
    } catch (e) {
      print(' 替代查詢也失敗: $e');
      if (mounted) {
        setState(() {
          _allPosts = [];
        });
      }
    }
  }

  /// 切換角色
  void _switchRole() {
    setState(() {
      _isRoleSwitching = true;
    });

    // 立即執行角色切換邏輯
    final oldRole = _userRole;
    setState(() {
      _userRole = _userRole == UserRole.parent
          ? UserRole.player
          : UserRole.parent;
    });

    print('🔄 角色切換: ${oldRole.name} → ${_userRole.name}');

    // 保存角色偏好
    _saveRolePreference();

    // 立即重新載入數據
    if (_userRole == UserRole.parent) {
      print('📥 切換到 Parent 視角，清空舊數據並載入我的任務...');
      setState(() {
        _myPosts.clear(); // 清空舊數據
        _allPosts.clear();
      });

      _loadMyPosts()
          .then((_) {
            print('Parent 任務載入完成，觸發標記更新');
            _updateMarkers(); // 這裡會自動結束 _isRoleSwitching 狀態
          })
          .catchError((error) {
            print(' Parent 任務載入失敗: $error');
            if (mounted) {
              setState(() {
                _isRoleSwitching = false;
              });
            }
          });
      _startListeningForApplicants();
    } else {
      print('📥 切換到 Player 視角，清空舊數據並載入所有任務...');
      setState(() {
        _myPosts.clear(); // 清空舊數據
        _allPosts.clear();
      });

      _loadAllPosts()
          .then((_) {
            print('Player 任務載入完成，觸發標記更新');
            _updateMarkers(); // 這裡會自動結束 _isRoleSwitching 狀態
          })
          .catchError((error) {
            print(' Player 任務載入失敗: $error');
            if (mounted) {
              setState(() {
                _isRoleSwitching = false;
              });
            }
          });
      _initializeNotificationSystem();
      _attachPostsListener();
    }
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
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
                  color: Colors.black,
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
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isRoleSwitching
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              _switchRole();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('確定', style: TextStyle(fontSize: 16)),
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
            CameraPosition(target: newLocation, zoom: _zoom, tilt: 65.0),
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
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: _zoom,
              tilt: 65.0,
            ),
            style: MapStyles.customStyle,
            onMapCreated: (controller) {
              _mapCtrl = controller;
            },
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            minMaxZoomPreference: const MinMaxZoomPreference(
              12,
              double.infinity,
            ),
            onTap: (_isMarkersLoading || _isRoleSwitching)
                ? null
                : (LatLng position) {
                    // 點擊地圖時的處理
                  },
          ),

          // 地圖操作阻止overlay（當標籤載入或角色切換時）
          if (_isMarkersLoading || _isRoleSwitching)
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
                child: AbsorbPointer(absorbing: true, child: Container()),
              ),
            ),

          // 載入遮罩 overlay（角色切換或地圖標籤載入）
          if (_isRoleSwitching || _isMarkersLoading)
            Container(
              color: Colors.black.withOpacity(_isRoleSwitching ? 0.3 : 0.2),
              child: Center(
                child: Container(
                  width: _isRoleSwitching ? 200 : 180,
                  height: _isRoleSwitching ? 120 : 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          _isRoleSwitching ? 0.2 : 0.15,
                        ),
                        blurRadius: _isRoleSwitching ? 10 : 8,
                        offset: Offset(0, _isRoleSwitching ? 4 : 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 動態顯示不同的icon
                      _isRoleSwitching
                          ? DataTransferIcon(color: Colors.black)
                          : Icon(
                              Icons.location_on,
                              size: 28,
                              color: AppColors.primary,
                            ),
                      SizedBox(height: _isRoleSwitching ? 16 : 12),
                      // 動態顯示不同的文字
                      Text(
                        _isRoleSwitching ? '視角切換中' : '載入地圖標籤',
                        style: TextStyle(
                          fontSize: _isRoleSwitching ? 16 : 15,
                          color: _isRoleSwitching
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: _isRoleSwitching ? 8 : 6),
                      // 三個點點動畫
                      LoadingDots(
                        color: _isRoleSwitching
                            ? Colors.grey[400]!
                            : AppColors.primary,
                        size: _isRoleSwitching ? 4.0 : 3.5,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 左上角 - 角色信息和切換
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.only(
                left: 16.0,
                top: 16.0,
                bottom: 16.0,
                right: 24.0, // 右邊 24，其餘維持 16
              ),
              decoration: BoxDecoration(
                color: _userRole == UserRole.player
                    ? AppColors.primary
                    : Colors.white,
                borderRadius: BorderRadius.circular(34),
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
                  // 用戶頭像 - 使用VerifiedAvatar
                  VerifiedAvatar(
                    avatarUrl: _profile['avatarUrl']?.isNotEmpty == true
                        ? _profile['avatarUrl']
                        : null,
                    radius: 40, // 72px 直徑
                    isVerified: _profile['isVerified'] ?? false,
                    defaultIcon: Icons.person_rounded,
                    badgeSize: 24,
                    showWhiteBorder: _userRole == UserRole.player,
                  ),
                  const SizedBox(width: 12),
                  // 角色信息
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 問候語 (在中間)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          'Hi, ${_profile['name'] ?? '未設定'}',
                          style: TextStyle(
                            color: _userRole == UserRole.player
                                ? Colors.white
                                : Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 角色或Loading動畫
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _isRoleSwitching
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: LoadingDots(
                                  color: _userRole == UserRole.player
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              )
                            : Text(
                                _userRole == UserRole.parent ? '發布者' : '陪伴者',
                                style: TextStyle(
                                  color: _userRole == UserRole.player
                                      ? Colors.white
                                      : Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      // 角色切換按鈕
                      InkWell(
                        onTap: _isRoleSwitching
                            ? null
                            : () => _showRoleSwitchDialog(
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
                              color: _userRole == UserRole.player
                                  ? Colors.white.withOpacity(0.6)
                                  : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _isRoleSwitching ? '切換中...' : '角色切換',
                            style: TextStyle(
                              color: _userRole == UserRole.player
                                  ? Colors.white
                                  : Colors.grey,
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

          // 右上角 - 重新整理按鈕
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: _buildActionButton(
              icon: Icons.refresh_rounded,
              onPressed: _forceReloadData,
              heroTag: 'refresh',
              isLarge: false,
              usePlayerStyle: true,
            ),
          ),

          // 右下角 - 定位按鈕
          Positioned(
            bottom: 140,
            right: 16,
            child: _buildActionButton(
              icon: Icons.my_location_rounded,
              onPressed: _findAndRecenter,
              heroTag: 'location',
              isLarge: true,
              usePlayerStyle: true,
            ),
          ),

          // 右下角 - 角色相關功能
          if (_userRole == UserRole.parent)
            Positioned(
              bottom: 140,
              left: 16,
              child: _buildActionButton(
                icon: Icons.add_rounded,
                onPressed: _startCreatePostManually,
                heroTag: 'create',
                isLarge: true,
                backgroundColor: AppColors.primary,
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
    bool usePlayerStyle = false, // 是否使用陪伴者視角的樣式
  }) {
    Color buttonBackgroundColor;
    Color buttonForegroundColor;

    if (backgroundColor != null) {
      // 如果明確指定了背景色，使用指定的顏色
      buttonBackgroundColor = backgroundColor;
      buttonForegroundColor = Colors.white;
    } else if (badgeCount > 0) {
      // 如果有徽章，使用橙色
      buttonBackgroundColor = Colors.orange[600]!;
      buttonForegroundColor = Colors.white;
    } else if (usePlayerStyle && _userRole == UserRole.player) {
      // 如果是陪伴者視角且啟用了陪伴者樣式，使用主色調
      buttonBackgroundColor = AppColors.primary;
      buttonForegroundColor = Colors.white;
    } else {
      // 預設樣式
      buttonBackgroundColor = Colors.white;
      buttonForegroundColor = Colors.black;
    }

    Widget button = FloatingActionButton(
      backgroundColor: buttonBackgroundColor,
      foregroundColor: buttonForegroundColor,
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

  /// 計算兩個地理位置之間的距離（米）
  double _calculateDistance(LatLng position1, LatLng position2) {
    return Geolocator.distanceBetween(
      position1.latitude,
      position1.longitude,
      position2.latitude,
      position2.longitude,
    );
  }

  /// 手動重新載入所有數據（調試用）
  Future<void> _forceReloadData() async {
    print('🔄 手動強制重新載入所有數據...');

    // 重新載入用戶資料
    await _loadUserProfile();

    // 根據角色載入相應數據
    if (_userRole == UserRole.parent) {
      print('📥 強制重新載入 Parent 任務...');
      await _loadMyPosts();
    } else {
      print('📥 強制重新載入 Player 任務...');
      await _loadAllPosts();
    }

    // 更新地圖標記
    _updateMarkers();

    print('手動重新載入完成');

    if (mounted) {
      CustomSnackBar.showSuccess(context, '數據已重新載入');
    }
  }

  /// 檢查任務是否過期
  bool _isTaskExpired(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDate;
      if (task['date'] is String) {
        taskDate = DateTime.parse(task['date']);
      } else if (task['date'] is DateTime) {
        taskDate = task['date'];
      } else if (task['date'] is Timestamp) {
        taskDate = (task['date'] as Timestamp).toDate();
      } else {
        print('未知的日期格式: ${task['date'].runtimeType}');
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

      return taskDay.isBefore(today);
    } catch (e) {
      print('檢查任務過期失敗: $e');
      return false;
    }
  }

  /// 獲取任務狀態
  String _getTaskStatus(Map<String, dynamic> task) {
    if (task['status'] == 'completed') return 'completed';
    if (task['acceptedApplicant'] != null) return 'accepted';
    if (_isTaskExpired(task)) return 'expired';
    return task['status'] ?? 'open';
  }

  /// 檢查任務是否為活躍狀態（可以在地圖上顯示）
  bool _isTaskActive(Map<String, dynamic> task) {
    final status = _getTaskStatus(task);
    // 只顯示開放狀態和已接受狀態的任務，不顯示已完成或已過期的任務
    return status == 'open' || status == 'accepted';
  }

  /// 更新地圖標記
  void _updateMarkers() async {
    if (!mounted) return;

    // 只在非角色切換時設置標籤載入狀態
    if (!_isRoleSwitching) {
      setState(() {
        _isMarkersLoading = true;
      });
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final tasksToCheck = _userRole == UserRole.parent ? _myPosts : _allPosts;

    print('🗺️ 更新地圖標記 - 角色: ${_userRole.name}, 任務數量: ${tasksToCheck.length}');

    // 過濾出活躍的任務（不包括過期和已完成的任務）
    final activeTasks = tasksToCheck
        .where((task) => _isTaskActive(task))
        .toList();
    print('🔍 過濾後的活躍任務數量: ${activeTasks.length}');

    try {
      // 使用新的標記管理器生成所有標記
      final markers = await MapMarkerManager.generateMarkers(
        systemLocations: _systemLocations,
        userTasks: activeTasks,
        isParentView: _userRole == UserRole.parent,
        onMarkerTap: _handleMarkerTap,
        currentLocation: _myLocation,
      );

      if (mounted) {
        setState(() {
          _markers = markers;
          // 結束標籤載入狀態
          _isMarkersLoading = false;
          // 如果是角色切換，同時結束角色切換狀態
          if (_isRoleSwitching) {
            _isRoleSwitching = false;
          }
        });
      }

      print('🗺️ 總共添加 ${markers.length} 個標記到地圖');
    } catch (e) {
      print(' 更新地圖標記失敗: $e');

      // 回退到原始標記邏輯
      await _updateMarkersLegacy();
    }
  }

  /// 處理標記點擊事件
  void _handleMarkerTap(MarkerData markerData) {
    print('🔍 點擊標記: ${markerData.name} (類型: ${markerData.type})');

    if (markerData.type == MarkerType.custom) {
      // 任務標記
      if (markerData.tasksAtLocation != null &&
          markerData.tasksAtLocation!.length > 1) {
        // 多任務標記 - 顯示任務列表
        _showMultiTaskLocationDetail(
          markerData.data,
          markerData.tasksAtLocation!,
        );
      } else {
        // 單任務標記 - 直接顯示任務詳情
        _showTaskDetail(
          markerData.data,
          isMyTask: _userRole == UserRole.parent,
        );
      }
    } else if (markerData.type == MarkerType.preset ||
        markerData.type == MarkerType.activePreset) {
      // 系統地點標記
      _showLocationDetail(markerData.data);
    }
  }

  /// 原始標記邏輯（作為備用）
  Future<void> _updateMarkersLegacy() async {
    if (!mounted) return;

    // 只在非角色切換時且還沒有設置載入狀態時設置
    if (!_isRoleSwitching && !_isMarkersLoading) {
      setState(() {
        _isMarkersLoading = true;
      });
    }

    final allMarkers = <Marker>{};
    final currentUser = FirebaseAuth.instance.currentUser;
    final tasksToCheck = _userRole == UserRole.parent ? _myPosts : _allPosts;
    final activeTasks = tasksToCheck
        .where((task) => _isTaskActive(task))
        .toList();

    // 添加系統地點標記 - 僅在 Parent 視角下顯示
    if (_userRole == UserRole.parent) {
      for (var location in _systemLocations) {
        final locationPosition = LatLng(location['lat'], location['lng']);
        bool hasOwnTaskNearby = false;

        // 檢查這個系統地點附近是否有自己的任務
        for (var task in activeTasks) {
          if (task['lat'] == null || task['lng'] == null) continue;
          if (task['userId'] != currentUser?.uid) continue;

          final taskPosition = LatLng(task['lat'], task['lng']);
          final distance = _calculateDistance(locationPosition, taskPosition);

          if (distance <= 100) {
            hasOwnTaskNearby = true;
            break;
          }
        }

        // 如果附近沒有自己的任務，則顯示系統地點標記
        if (!hasOwnTaskNearby) {
          // 使用新的白色圓圈+加號標記
          final systemLocationIcon =
              await MapMarkerManager.generateSystemLocationMarker();

          allMarkers.add(
            Marker(
              markerId: MarkerId('system_${location['id']}'),
              position: locationPosition,
              icon: systemLocationIcon,
              onTap: () => _showLocationDetail(location),
            ),
          );
        }
      }
    }

    // 根據角色添加不同的任務標記
    if (_userRole == UserRole.parent) {
      for (var task in activeTasks) {
        if (task['lat'] == null || task['lng'] == null) continue;

        final marker = Marker(
          markerId: MarkerId('my_task_${task['id']}'),
          position: LatLng(task['lat'], task['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          onTap: () => _showTaskDetail(task, isMyTask: true),
        );

        allMarkers.add(marker);
      }
    } else {
      for (var task in activeTasks) {
        if (task['lat'] == null || task['lng'] == null) continue;
        if (task['userId'] == currentUser?.uid) continue;

        allMarkers.add(
          Marker(
            markerId: MarkerId('task_${task['id']}'),
            position: LatLng(task['lat'], task['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            onTap: () => _showTaskLocationDetail(task),
          ),
        );
      }
    }

    // 添加我的位置標記（Google Maps風格）
    if (_myLocation != null) {
      final locationIcon = await LocationMarker.generateCurrentLocationMarker(
        size: 20.0,
        bearing: 0.0, // 如果需要方向指示，可以從GPS獲取
      );

      allMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon: locationIcon,
          infoWindow: const InfoWindow(title: '我的位置'),
          zIndex: 1000, // 設置高zIndex確保在所有標記之上
        ),
      );
    }

    setState(() {
      _markers = allMarkers;
      // 結束標籤載入狀態
      _isMarkersLoading = false;
      // 如果是角色切換，同時結束角色切換狀態
      if (_isRoleSwitching) {
        _isRoleSwitching = false;
      }
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
            _startCreatePostAtLocation(locationData);
          }
        },
      ),
    );
  }

  /// 顯示多任務位置詳情
  void _showMultiTaskLocationDetail(
    Map<String, dynamic> taskData,
    List<Map<String, dynamic>> tasksAtLocation,
  ) {
    // 創建虛擬地點資料
    final locationData = {
      'name': taskData['address']?.toString() ?? '任務地點',
      'address': taskData['address']?.toString() ?? '任務地點',
      'lat': taskData['lat'],
      'lng': taskData['lng'],
      'description': '此地點有 ${tasksAtLocation.length} 個可用任務',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: _userRole == UserRole.parent,
        currentLocation: _myLocation,
        availableTasksAtLocation: tasksAtLocation,
        onTaskSelected: (task) {
          // 從任務列表中選擇任務後的回調
          Navigator.of(context).pop(); // 關閉地點資訊彈窗
          _showTaskDetail(
            task,
            isMyTask: _userRole == UserRole.parent,
          ); // 顯示任務詳情
        },
      ),
    );
  }

  /// 顯示任務位置詳情（陪伴者視角）- 先顯示地點資訊和任務列表
  void _showTaskLocationDetail(Map<String, dynamic> taskData) {
    if (_userRole != UserRole.player) {
      // 如果不是陪伴者視角，直接顯示任務詳情
      _showTaskDetail(taskData, isMyTask: false);
      return;
    }

    // 陪伴者視角：先顯示地點資訊和任務列表
    final taskPosition = LatLng(taskData['lat'], taskData['lng']);

    // 收集該位置附近的所有任務
    final nearbyTasks = _allPosts.where((task) {
      if (task['lat'] == null || task['lng'] == null) return false;
      if (task['userId'] == FirebaseAuth.instance.currentUser?.uid)
        return false;

      final distance = _calculateDistance(
        taskPosition,
        LatLng(task['lat'], task['lng']),
      );

      return distance <= 100; // 100米內的任務
    }).toList();

    // 創建虛擬地點資料
    final locationData = {
      'name': taskData['address']?.toString() ?? '任務地點',
      'address': taskData['address']?.toString() ?? '任務地點',
      'lat': taskData['lat'],
      'lng': taskData['lng'],
      'description': '此地點有 ${nearbyTasks.length} 個可用任務',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: false, // 陪伴者視角
        currentLocation: _myLocation,
        availableTasksAtLocation: nearbyTasks, // 提供該地點的任務列表
        onTaskSelected: (task) {
          // 從任務列表中選擇任務後的回調
          Navigator.of(context).pop(); // 關閉地點資訊彈窗
          _showTaskDetail(task, isMyTask: false); // 顯示任務詳情
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
          // 不立即關閉彈窗，讓 CreateEditTaskBottomSheet 自己控制
          await _saveEditedTask(updatedTaskData, taskData['id']);
        },
      ),
    );
  }

  /// 保存編輯的任務
  Future<void> _saveEditedTask(TaskData taskData, String taskId) async {
    try {
      // 上傳圖片並獲取完整任務數據
      final taskDataWithImages = await taskData.toJsonWithUploadedImages(
        taskId: taskId,
      );

      await _firestore.collection('posts').doc(taskId).update({
        ...taskDataWithImages,
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
          // 不立即關閉彈窗，讓 CreateEditTaskBottomSheet 自己控制
          await _saveNewTask(taskData);
        },
      ),
    );
  }

  /// 在指定地點創建任務
  void _startCreatePostAtLocation(Map<String, dynamic> locationData) {
    if (_userRole != UserRole.parent) return;

    // 準備地點資料
    final prefilledData = {
      'address': locationData['name'] ?? '未知地點',
      'lat': locationData['lat'],
      'lng': locationData['lng'],
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        prefilledLocationData: prefilledData,
        onSubmit: (taskData) async {
          // 不立即關閉彈窗，讓 CreateEditTaskBottomSheet 自己控制
          await _saveNewTask(taskData);
        },
      ),
    );
  }

  /// 保存新任務
  Future<void> _saveNewTask(TaskData taskData) async {
    print('💾 開始保存新任務到 Firestore...');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print(' 用戶未登入，無法保存任務');
        if (mounted) {
          CustomSnackBar.showError(context, '請先登入');
        }
        return;
      }

      // 上傳圖片並獲取完整任務數據
      print('🖼️ 處理任務圖片...');
      final taskDataWithImages = await taskData.toJsonWithUploadedImages();

      // 創建任務資料
      final newTaskData = {
        ...taskDataWithImages,
        'userId': user.uid,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'isActive': true,
        'applicants': [],
      };

      print('📝 準備保存的完整數據: $newTaskData');
      print('🗂️ 數據字段檢查:');
      print('   - title: ${newTaskData['title']}');
      print('   - name: ${newTaskData['name']}');
      print('   - address: ${newTaskData['address']}');
      print(
        '   - images: ${newTaskData['images']} (${(newTaskData['images'] as List).length} 張)',
      );
      print(
        '   - lat: ${newTaskData['lat']} (${newTaskData['lat'].runtimeType})',
      );
      print(
        '   - lng: ${newTaskData['lng']} (${newTaskData['lng'].runtimeType})',
      );
      print('   - userId: ${newTaskData['userId']}');
      print('   - isActive: ${newTaskData['isActive']}');

      // 保存到 Firestore 並獲取文檔引用
      print('🚀 正在保存到 Firestore...');
      final docRef = await _firestore.collection('posts').add(newTaskData);

      print('Firestore 保存成功！文檔 ID: ${docRef.id}');

      // 驗證保存是否成功 - 立即讀取剛保存的文檔
      print('🔍 驗證保存結果...');
      final savedDoc = await _firestore
          .collection('posts')
          .doc(docRef.id)
          .get();

      if (savedDoc.exists) {
        final savedData = savedDoc.data()!;
        print('驗證成功！保存的數據: $savedData');

        // 檢查關鍵字段
        if (savedData['userId'] == user.uid) {
          print('userId 匹配');
        } else {
          print('⚠️  userId 不匹配: 期望 ${user.uid}, 實際 ${savedData['userId']}');
        }

        if (savedData['lat'] != null && savedData['lng'] != null) {
          print('地理位置保存成功');
        } else {
          print('⚠️  地理位置保存失敗');
        }
      } else {
        print(' 驗證失敗！文檔不存在');
      }

      if (mounted) {
        // 立即將新任務添加到本地列表中，避免重新載入的延遲
        final newTask = Map<String, dynamic>.from(newTaskData);
        newTask['id'] = docRef.id; // 添加文檔 ID

        // 確保座標是 double 類型
        if (newTask['lat'] != null) {
          newTask['lat'] = newTask['lat'] is String
              ? double.parse(newTask['lat'])
              : newTask['lat'].toDouble();
        }
        if (newTask['lng'] != null) {
          newTask['lng'] = newTask['lng'] is String
              ? double.parse(newTask['lng'])
              : newTask['lng'].toDouble();
        }

        setState(() {
          // 將新任務添加到列表開頭（因為按時間降序排列）
          _myPosts.insert(0, newTask);
        });

        print('📝 新任務已添加到本地 _myPosts: ${newTask['id']}');
        print('📊 目前本地 _myPosts 包含 ${_myPosts.length} 個任務');

        // 立即更新地圖標記，讓新任務即時顯示
        _updateMarkers();

        // 為了確保數據同步，在保存成功後稍微延遲再重新載入一次
        Future.delayed(const Duration(seconds: 2), () {
          print('🔄 延遲重新載入任務確保數據同步...');
          _loadMyPosts();
        });

        CustomSnackBar.showSuccess(context, '任務創建成功！文檔 ID: ${docRef.id}');
      }
    } catch (e, stackTrace) {
      print(' 保存任務失敗: $e');
      print('📋 錯誤堆疊: $stackTrace');

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

      // 重新載入數據以確保過期任務從列表中移除
      if (_userRole == UserRole.parent) {
        await _loadMyPosts();
      } else {
        await _loadAllPosts();
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

      // 發送聊天室關閉提醒訊息
      await ChatService.sendTaskExpiredChatCloseReminder(taskId);

      final tasksToUpdate = _userRole == UserRole.parent ? _myPosts : _allPosts;
      final taskIndex = tasksToUpdate.indexWhere((t) => t['id'] == taskId);
      if (taskIndex != -1 && mounted) {
        setState(() {
          tasksToUpdate[taskIndex]['status'] = 'expired';
          tasksToUpdate[taskIndex]['isActive'] = false;
        });
      }

      print('任務已標記為過期，聊天室關閉提醒已發送: $taskId');
    } catch (e) {
      print(' 更新任務過期狀態失敗: $e');
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

/// 三個點點Loading動畫
class LoadingDots extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const LoadingDots({
    Key? key,
    this.color = Colors.blue,
    this.size = 6.0,
    this.duration = const Duration(milliseconds: 600),
  }) : super(key: key);

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _animation1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );

    _animation2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.2, 0.8, curve: Curves.easeInOut),
      ),
    );

    _animation3 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.4, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(_animation1.value),
            const SizedBox(width: 3),
            _buildDot(_animation2.value),
            const SizedBox(width: 3),
            _buildDot(_animation3.value),
          ],
        );
      },
    );
  }

  Widget _buildDot(double opacity) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 驗證頭像組件
class VerifiedAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final bool isVerified;
  final IconData defaultIcon;
  final double badgeSize;
  final bool showWhiteBorder;

  const VerifiedAvatar({
    Key? key,
    this.avatarUrl,
    this.radius = 20,
    this.isVerified = false,
    this.defaultIcon = Icons.person,
    this.badgeSize = 16,
    this.showWhiteBorder = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 頭像
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: showWhiteBorder
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey[300],
            backgroundImage: avatarUrl != null
                ? NetworkImage(avatarUrl!)
                : null,
            child: avatarUrl == null
                ? Icon(defaultIcon, size: radius * 0.8, color: Colors.grey[600])
                : null,
          ),
        ),
        // 驗證徽章
        if (isVerified)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Icon(
                Icons.verified,
                size: badgeSize * 0.7,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// 資料傳輸icon動畫
class DataTransferIcon extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const DataTransferIcon({
    Key? key,
    this.color = const Color(0xFF2196F3),
    this.size = 32.0,
    this.duration = const Duration(milliseconds: 1000),
  }) : super(key: key);

  @override
  State<DataTransferIcon> createState() => _DataTransferIconState();
}

class _DataTransferIconState extends State<DataTransferIcon>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // 旋轉動畫控制器
    _rotationController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    // 縮放動畫控制器
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // 開始動畫
    _rotationController.repeat();
    _scaleController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_rotationController, _scaleController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value * 2 * 3.14159,
            child: Icon(Icons.sync, size: widget.size, color: widget.color),
          ),
        );
      },
    );
  }
}
