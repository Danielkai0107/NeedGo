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
import '../utils/custom_snackbar.dart';

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

  // 新增通知相關變數
  StreamSubscription<QuerySnapshot>? _postsSubscription;
  List<Map<String, dynamic>> _notifications = [];
  bool _showNotificationPopup = false;
  String? _latestNotificationMessage;
  bool _isInitialLoad = true; // 標記是否為初始載入
  Set<String> _readApplicantIds = {}; // 已讀的應徵者 ID

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

  // 任務計時器相關
  Timer? _taskTimer;
  static const Duration _checkInterval = Duration(minutes: 1); // 每分鐘檢查一次

  @override
  void initState() {
    super.initState();

    // 延遲初始化，避免在 widget 還沒準備好時就開始載入
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });

    // 啟動任務計時器
    _startTaskTimer();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationSearchCtrl.dispose();
    _contentCtrl.dispose();

    // 停止任務計時器
    _taskTimer?.cancel();

    // 新增：取消訂閱
    _postsSubscription?.cancel();

    super.dispose();
  }

  // 在 _initializeData 中加入錯誤處理
  Future<void> _initializeData() async {
    if (!mounted) return;

    try {
      print('🚀 開始初始化應用程式...');

      // 依序初始化，每步都檢查 mounted
      if (mounted) {
        print('📍 載入系統地點...');
        await _loadSystemLocations();
      }

      if (mounted) {
        print('🌍 取得當前定位...');
        await _findAndRecenter();
      }

      if (mounted) {
        print('👤 載入個人資料...');
        await _loadMyProfile();
      }

      if (mounted) {
        print('📋 載入我的任務...');
        await _loadMyPosts();
      }

      // 延遲再次載入以確保資料完整
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        print('🔄 重新載入任務資料...');
        await _loadMyPosts();
        // 確保初始化完成後更新標記
        _updateMarkers();
        print('✅ 應用程式初始化完成');

        // 在所有資料載入完成後才開始監聽通知
        print('🔔 開始啟動應徵者監聽...');

        // 載入歷史應徵者通知
        await _loadHistoricalApplicantNotifications();

        // 啟動即時監聽
        _startListeningForApplicants();
      }
    } catch (e) {
      print('❌ 初始化失敗: $e');
      // 不要在這裡顯示 SnackBar，可能導致問題
    }
  }

  /// 啟動任務計時器
  void _startTaskTimer() {
    _taskTimer = Timer.periodic(_checkInterval, (timer) {
      if (mounted) {
        _checkAndUpdateExpiredTasks();
      }
    });
    print('🕒 任務計時器已啟動，每 ${_checkInterval.inMinutes} 分鐘檢查一次');
  }

  /// 檢查並更新過期任務
  Future<void> _checkAndUpdateExpiredTasks() async {
    if (_myPosts.isEmpty) return;

    print('🔍 檢查任務是否過期...');

    for (var task in _myPosts) {
      if (_isTaskExpiredNow(task) && task['status'] != 'expired') {
        await _markTaskAsExpired(task['id'], task);
      }
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

  /// 將任務標記為過期
  Future<void> _markTaskAsExpired(
    String taskId,
    Map<String, dynamic> task,
  ) async {
    try {
      print('⏰ 任務過期：${task['title'] ?? task['name']} (ID: $taskId)');

      // 更新資料庫中的任務狀態
      await _firestore.doc('posts/$taskId').update({
        'status': 'expired',
        'isActive': false, // 從地圖上隱藏
        'updatedAt': Timestamp.now(),
        'expiredAt': Timestamp.now(),
      });

      // 更新本地任務狀態
      final taskIndex = _myPosts.indexWhere((t) => t['id'] == taskId);
      if (taskIndex != -1 && mounted) {
        setState(() {
          _myPosts[taskIndex]['status'] = 'expired';
          _myPosts[taskIndex]['isActive'] = false;
        });

        // 更新地圖標記
        _updateMarkers();

        // 顯示過期通知
        if (mounted) {
          _showWarningMessage('任務「${task['title'] ?? task['name']}」已過期');
        }
      }

      print('✅ 任務狀態已更新為過期');
    } catch (e) {
      print('❌ 更新任務過期狀態失敗: $e');
    }
  }

  /// 開始監聽任務的應徵者變化
  void _startListeningForApplicants() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      print('❌ 用戶未登入，無法啟動監聽');
      return;
    }

    print('🔔 開始監聽用戶 ${u.uid} 的任務應徵者變化...');

    _postsSubscription = _firestore
        .collection('posts')
        .where('userId', isEqualTo: u.uid)
        .snapshots(includeMetadataChanges: false) // 只監聽伺服器變化，避免本地變化觸發
        .listen(
          (snapshot) {
            if (!mounted) return;

            print('🔔 收到 Firebase 快照更新，文檔數量: ${snapshot.docs.length}');
            print('🔔 變化數量: ${snapshot.docChanges.length}');

            // 如果不是初始載入，才檢查應徵者變化
            if (!_isInitialLoad) {
              print('🔔 處理非初始載入的變化...');

              // 檢查是否有新的應徵者
              for (var change in snapshot.docChanges) {
                print('🔔 文檔變化類型: ${change.type}, ID: ${change.doc.id}');

                if (change.type == DocumentChangeType.modified) {
                  final newData = change.doc.data() as Map<String, dynamic>;
                  final taskId = change.doc.id;
                  final taskName =
                      newData['title'] ?? newData['name'] ?? '未命名任務';

                  print('🔔 檢查任務「$taskName」的應徵者變化...');

                  // 找到對應的本地任務
                  final existingTaskIndex = _myPosts.indexWhere(
                    (task) => task['id'] == taskId,
                  );

                  if (existingTaskIndex != -1) {
                    final existingTask = _myPosts[existingTaskIndex];
                    final oldApplicants = List<String>.from(
                      existingTask['applicants'] ?? [],
                    );
                    final newApplicants = List<String>.from(
                      newData['applicants'] ?? [],
                    );

                    print('🔔 任務「$taskName」詳細比較:');
                    print('  - 舊應徵者數量: ${oldApplicants.length}');
                    print('  - 新應徵者數量: ${newApplicants.length}');
                    print('  - 舊應徵者 ID: $oldApplicants');
                    print('  - 新應徵者 ID: $newApplicants');

                    // 檢查是否有新的應徵者
                    if (newApplicants.length > oldApplicants.length) {
                      final newApplicantIds = newApplicants
                          .where((id) => !oldApplicants.contains(id))
                          .toList();

                      if (newApplicantIds.isNotEmpty) {
                        print(
                          '🔔 ✅ 確認發現新應徵者：任務「$taskName」有 ${newApplicantIds.length} 位新應徵者',
                        );
                        print('🔔 新應徵者 ID: $newApplicantIds');
                        print('🔔 準備觸發通知...');

                        _showApplicantNotification(
                          taskName,
                          newApplicantIds.length,
                        );
                      } else {
                        print('🔔 ⚠️ 應徵者數量增加但找不到新的 ID');
                      }
                    } else if (newApplicants.length < oldApplicants.length) {
                      print('🔔 應徵者數量減少（可能被移除）');
                    } else {
                      print('🔔 應徵者數量無變化，可能是其他欄位更新');
                    }
                  } else {
                    print('🔔 ⚠️ 在本地任務列表中找不到任務 ID: $taskId');
                    print(
                      '🔔 本地任務 ID 列表: ${_myPosts.map((t) => t['id']).toList()}',
                    );

                    // 嘗試重新載入本地任務
                    print('🔔 嘗試重新載入本地任務...');
                    _loadMyPosts();
                  }
                } else if (change.type == DocumentChangeType.added) {
                  print('🔔 新增任務: ${change.doc.id}');
                } else if (change.type == DocumentChangeType.removed) {
                  print('🔔 刪除任務: ${change.doc.id}');
                }
              }
            } else {
              print('🔔 跳過初始載入的變化檢查');
            }

            // 更新本地任務資料
            _updateLocalTasksFromSnapshot(snapshot);

            // 首次載入後，將標誌設為 false
            if (_isInitialLoad) {
              _isInitialLoad = false;
              print('🔔 ✅ 初始載入完成，現在開始監聽應徵者變化');
            }
          },
          onError: (error) {
            print('❌ 監聽應徵者變化失敗: $error');
            // 嘗試重新啟動監聽
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) {
                print('🔔 嘗試重新啟動監聽...');
                _startListeningForApplicants();
              }
            });
          },
        );

    print('🔔 ✅ Firebase 監聽已啟動');
  }

  /// 從 Firestore 快照更新本地任務資料
  void _updateLocalTasksFromSnapshot(QuerySnapshot snapshot) {
    final updatedTasks = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>,
      );
      data['id'] = doc.id;

      // 確保座標是正確的數字類型
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

    // 手動按創建時間排序
    updatedTasks.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;

      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;

      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        _myPosts = updatedTasks;
      });
      _updateMarkers();
    }
  }

  /// 顯示應徵者通知
  void _showApplicantNotification(String taskName, int applicantCount) {
    print('🔔 [通知函數開始] 準備為任務「$taskName」顯示 $applicantCount 位應徵者的通知');

    if (!mounted) {
      print('🔔 ❌ Widget 未掛載，取消通知');
      return;
    }

    final message = '「$taskName」有 $applicantCount 位新應徵者！';
    final timestamp = DateTime.now();

    print('🔔 通知訊息: $message');
    print('🔔 當前時間: $timestamp');

    // 檢查是否已有相同任務的近期通知（2分鐘內，縮短時間便於測試）
    final recentNotifications = _notifications
        .where(
          (n) =>
              n['taskName'] == taskName &&
              n['type'] == 'new_applicant' &&
              timestamp.difference(n['timestamp']).inMinutes < 2,
        )
        .toList();

    if (recentNotifications.isNotEmpty) {
      print('🔔 ⚠️ 任務「$taskName」在2分鐘內已有通知，跳過重複通知');
      print('🔔 近期通知數量: ${recentNotifications.length}');
      return;
    }

    print('🔔 ✅ 通過重複檢查，開始創建通知');

    // 新增通知到列表中（用於紅點提示）
    final notification = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': 'new_applicant',
      'taskName': taskName,
      'applicantCount': applicantCount,
      'message': message,
      'timestamp': timestamp,
      'isRead': false,
    };

    print('🔔 新增通知到列表，通知 ID: ${notification['id']}');
    print('🔔 呼叫 setState 更新 UI...');

    try {
      setState(() {
        _notifications.add(notification);
        _latestNotificationMessage = message;
        _showNotificationPopup = true;

        // 限制通知數量，保留最新的20個
        if (_notifications.length > 20) {
          _notifications.removeRange(0, _notifications.length - 20);
          print('🔔 通知列表已達上限，保留最新20個通知');
        }
      });

      print('🔔 ✅ setState 完成！');
      print('🔔 當前通知總數: ${_notifications.length}');
      print('🔔 彈窗狀態: $_showNotificationPopup');
      print('🔔 最新通知訊息: $_latestNotificationMessage');
    } catch (e) {
      print('🔔 ❌ setState 失敗: $e');
    }

    // 3秒後自動隱藏通知彈窗（但保留在通知列表中）
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showNotificationPopup = false;
        });
        print('🔔 通知彈窗已自動隱藏');
      }
    });

    // 也顯示 SnackBar 作為備用通知
    print('🔔 顯示 SnackBar 備用通知...');
    try {
      _showCustomSnackBar(
        message,
        iconColor: Colors.blue[600],
        icon: Icons.person_add_rounded,
      );
      print('🔔 ✅ SnackBar 通知已顯示');
    } catch (e) {
      print('🔔 ❌ SnackBar 顯示失敗: $e');
    }

    print('🔔 [通知函數結束] 通知處理完成');
  }

  /// 顯示通知列表
  void _showNotificationsList() {
    print('🔔 打開通知列表，當前通知數量: ${_notifications.length}');

    // 過濾出未讀通知
    final unreadNotifications = _notifications
        .where((n) => n['isRead'] != true)
        .toList();

    print('🔔 未讀通知數量: ${unreadNotifications.length}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // 在 builder 內部重新獲取未讀通知
        final currentUnreadNotifications = _notifications
            .where((n) => n['isRead'] != true)
            .toList();

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
                  color: Colors.blue[50],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_rounded, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Text(
                      '通知中心 (${currentUnreadNotifications.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          // 清除所有未讀通知
                          _notifications.removeWhere(
                            (n) => n['isRead'] != true,
                          );
                        });
                        Navigator.pop(context);
                        _showSuccessMessage('所有通知已清除');
                        print('🔔 所有未讀通知已清除');
                      },
                      child: const Text('全部清除'),
                    ),
                  ],
                ),
              ),
              // 通知列表
              Expanded(
                child: currentUnreadNotifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '目前沒有通知',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '有新的應徵者時會在這裡顯示通知',
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
                        itemCount: currentUnreadNotifications.length,
                        itemBuilder: (context, index) {
                          final notification =
                              currentUnreadNotifications[currentUnreadNotifications
                                      .length -
                                  1 -
                                  index]; // 反向顯示
                          return _buildNotificationItem(notification);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 建立通知項目
  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isHistorical = notification['type'] == 'historical_applicant';
    final isRead = notification['isRead'] == true;

    return GestureDetector(
      onTap: () {
        // 點擊整個通知區域進入任務詳情
        if (isHistorical && notification['taskId'] != null) {
          _showTaskFromNotification(
            notification,
            markAsRead: true,
            removeFromList: true,
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.grey[50]
              : (isHistorical ? Colors.orange[50] : Colors.blue[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead
                ? Colors.grey[200]!
                : (isHistorical ? Colors.orange[200]! : Colors.blue[200]!),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 圖標
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isHistorical ? Colors.orange[600] : Colors.blue[600],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isHistorical ? Icons.history_rounded : Icons.person_add_rounded,
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
                        isHistorical ? '歷史應徵者' : '新的應徵者',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (isHistorical) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '歷史',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      // 點擊提示箭頭
                      if (isHistorical && notification['taskId'] != null)
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.grey[400],
                          size: 12,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['message'],
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _formatNotificationTime(notification['timestamp']),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      if (isHistorical && notification['taskId'] != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '點擊查看詳情',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 操作按鈕（只保留刪除按鈕）
            IconButton(
              onPressed: () {
                setState(() {
                  _notifications.removeWhere(
                    (n) => n['id'] == notification['id'],
                  );
                });
                _showSuccessMessage('通知已刪除');
              },
              icon: Icon(
                Icons.close_rounded,
                color: Colors.grey[400],
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// 從通知中顯示任務詳情
  void _showTaskFromNotification(
    Map<String, dynamic> notification, {
    bool markAsRead = false,
    bool removeFromList = false,
  }) {
    final taskId = notification['taskId'];
    final task = _myPosts.firstWhere(
      (t) => t['id'] == taskId,
      orElse: () => {},
    );

    if (task.isEmpty) {
      _showErrorMessage('找不到對應的任務');
      return;
    }

    // 標記應徵者為已讀
    if (markAsRead && notification['applicantId'] != null) {
      _markApplicantAsRead(notification['applicantId']);
    }

    // 從通知列表中移除（已讀後消失）
    if (removeFromList) {
      setState(() {
        _notifications.removeWhere((n) => n['id'] == notification['id']);
      });
    }

    // 關閉通知列表
    Navigator.of(context).pop();

    // 顯示任務詳情
    _showTaskDetailSheetDirect(task);
  }

  /// 格式化通知時間
  String _formatNotificationTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} 分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} 小時前';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 顯示調試信息
  void _showDebugInfo() async {
    final u = FirebaseAuth.instance.currentUser;
    final allPosts = await _firestore.collection('posts').get();
    final myPosts = await _firestore
        .collection('posts')
        .where('userId', isEqualTo: u?.uid)
        .get();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系統調試信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('👤 當前用戶 UID: ${u?.uid}'),
              Text('📊 Firebase 總任務數量: ${allPosts.docs.length}'),
              Text('📋 我的 Firebase 任務數量: ${myPosts.docs.length}'),
              Text('💾 本地任務數量: ${_myPosts.length}'),
              Text('📍 地圖標記數量: ${_markers.length}'),
              Text('🔔 通知數量: ${_notifications.length}'),
              Text('📚 已讀應徵者: ${_readApplicantIds.length} 位'),
              Text(
                '📡 監聽狀態: ${_postsSubscription != null ? '✅ 已啟動' : '❌ 未啟動'}',
              ),
              Text('🔄 初始載入: ${_isInitialLoad ? '進行中' : '已完成'}'),
              const SizedBox(height: 10),
              const Text(
                '📋 我的任務詳情:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_myPosts.isEmpty)
                const Text('  無任務')
              else
                for (var post in _myPosts.take(3))
                  Text(
                    '  • ${post['title'] ?? post['name']}: ${(post['applicants'] as List?)?.length ?? 0} 位應徵者',
                  ),
              const SizedBox(height: 10),
              const Text(
                '🔔 通知分析:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_notifications.isEmpty)
                const Text('  無通知')
              else ...[
                Text('  • 總通知數: ${_notifications.length}'),
                Text(
                  '  • 歷史通知: ${_notifications.where((n) => n['type'] == 'historical_applicant').length}',
                ),
                Text(
                  '  • 即時通知: ${_notifications.where((n) => n['type'] == 'new_applicant').length}',
                ),
                Text(
                  '  • 未讀通知: ${_notifications.where((n) => n['isRead'] == false).length}',
                ),
                const Text('最近通知:'),
                for (var notification in _notifications.take(2))
                  Text(
                    '  • ${notification['message']} (${notification['type'] == 'historical_applicant' ? '歷史' : '即時'})',
                  ),
              ],
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
  }

  /// 測試通知功能
  void _testNotification() {
    if (_myPosts.isEmpty) {
      _showWarningMessage('請先創建任務才能測試通知');
      return;
    }

    final testTask = _myPosts.first;
    final taskName = testTask['title'] ?? testTask['name'] ?? '測試任務';

    print('🧪 手動觸發測試通知');
    _showApplicantNotification(taskName, 1);

    _showSuccessMessage('測試通知已觸發！');
  }

  /// 載入歷史應徵者通知
  Future<void> _loadHistoricalApplicantNotifications() async {
    print('📚 開始載入歷史應徵者通知...');

    if (_myPosts.isEmpty) {
      print('📚 沒有任務，跳過歷史通知載入');
      return;
    }

    // 載入已讀應徵者 ID（從本地存儲或用戶偏好設定）
    await _loadReadApplicantIds();

    int totalNotifications = 0;
    int filteredNotifications = 0;

    for (var task in _myPosts) {
      // 檢查任務是否過期（使用精確時間判斷）
      if (_isTaskExpiredNow(task)) {
        print('📚 跳過過期任務：${task['title'] ?? task['name']}');
        continue;
      }

      // 檢查任務狀態是否為過期或已完成
      if (task['status'] == 'expired' || task['status'] == 'completed') {
        print(
          '📚 跳過狀態為過期/已完成的任務：${task['title'] ?? task['name']} (狀態: ${task['status']})',
        );
        continue;
      }

      final taskName = task['title'] ?? task['name'] ?? '未命名任務';
      final applicants = List<String>.from(task['applicants'] ?? []);

      if (applicants.isEmpty) {
        continue;
      }

      print('📚 檢查任務「$taskName」，應徵者數量：${applicants.length}');

      // 過濾掉已讀的應徵者
      final unreadApplicants = applicants
          .where((id) => !_readApplicantIds.contains(id))
          .toList();

      if (unreadApplicants.isEmpty) {
        print('📚 任務「$taskName」的所有應徵者都已讀過');
        continue;
      }

      print('📚 任務「$taskName」有 ${unreadApplicants.length} 位未讀應徵者');

      // 為每個未讀應徵者創建通知
      for (String applicantId in unreadApplicants) {
        final notification = {
          'id': 'historical_${task['id']}_$applicantId',
          'type': 'historical_applicant',
          'taskId': task['id'],
          'taskName': taskName,
          'applicantId': applicantId,
          'applicantCount': 1,
          'message': '「$taskName」有新的應徵者',
          'timestamp': task['createdAt']?.toDate() ?? DateTime.now(),
          'isRead': false,
        };

        _notifications.add(notification);
        totalNotifications++;
      }

      filteredNotifications += unreadApplicants.length;
    }

    // 按時間排序（最新的在前）
    _notifications.sort((a, b) {
      final aTime = a['timestamp'] as DateTime;
      final bTime = b['timestamp'] as DateTime;
      return bTime.compareTo(aTime);
    });

    print('📚 ✅ 歷史通知載入完成');
    print('📚 總應徵者數量：$totalNotifications');
    print('📚 未讀通知數量：$filteredNotifications');
    print('📚 已載入通知總數：${_notifications.length}');

    if (filteredNotifications > 0) {
      // 如果有未讀通知，更新 UI
      if (mounted) {
        setState(() {
          // 觸發 UI 更新以顯示紅點
        });
      }

      _showSuccessMessage('載入了 $filteredNotifications 個未讀應徵者通知');
    }
  }

  /// 載入已讀應徵者 ID（從本地存儲）
  Future<void> _loadReadApplicantIds() async {
    // TODO: 這裡可以從 SharedPreferences 或 Firebase 用戶資料中載入
    // 暫時使用空集合，表示所有應徵者都未讀
    print('📚 載入已讀應徵者 ID... (暫時為空)');
    _readApplicantIds = {};
  }

  /// 保存已讀應徵者 ID（到本地存儲）
  Future<void> _saveReadApplicantIds() async {
    // TODO: 這裡可以保存到 SharedPreferences 或 Firebase 用戶資料中
    print('📚 保存已讀應徵者 ID: ${_readApplicantIds.length} 個');
  }

  /// 標記應徵者為已讀
  void _markApplicantAsRead(String applicantId) {
    _readApplicantIds.add(applicantId);
    _saveReadApplicantIds();
    print('📚 標記應徵者 $applicantId 為已讀');
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
      _showErrorMessage('請在系統設定允許定位權限');
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
    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

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

    // 將所有應徵者標記為已讀
    for (String applicantId in List<String>.from(applicants)) {
      _markApplicantAsRead(applicantId);
    }

    // 更新通知狀態
    setState(() {
      // 移除該任務的歷史通知（因為已查看）
      _notifications.removeWhere(
        (notification) =>
            notification['type'] == 'historical_applicant' &&
            notification['taskId'] == _selectedLocation!['id'],
      );
    });

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

        // 檢查任務是否應該在地圖上顯示
        if (!_shouldShowTaskOnMap(post)) {
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
            _getTaskMarkerColor(post),
          ),
          onTap: () {
            _showTaskDetailSheetDirect({
              'id': post['id'],
              'name': post['name'],
              'title': post['title'] ?? post['name'], // 向下兼容
              'content': post['content'],
              'address': post['address'],
              'applicants': post['applicants'],
              'acceptedApplicant': post['acceptedApplicant'],
              'lat': lat.toDouble(),
              'lng': lng.toDouble(),
              'userId': post['userId'],
              'createdAt': post['createdAt'],
              'updatedAt': post['updatedAt'],
              'status': post['status'],
              'date': post['date'],
              'time': post['time'],
              'price': post['price'],
              'images': post['images'],
              'isActive': post['isActive'],
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

  // 檢查任務是否應該在地圖上顯示
  bool _shouldShowTaskOnMap(Map<String, dynamic> task) {
    // 檢查 isActive 欄位
    if (task['isActive'] == false) return false;

    // 檢查任務狀態
    final status = task['status'] ?? 'open';
    if (status == 'completed' || status == 'expired') return false;

    // 檢查是否過期（使用精確時間判斷）
    if (_isTaskExpiredNow(task)) return false;

    return true;
  }

  // 檢查任務是否過期
  bool _isTaskExpired(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDate;
      if (task['date'] is String) {
        taskDate = DateTime.parse(task['date']);
      } else if (task['date'] is DateTime) {
        taskDate = task['date'];
      } else {
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

      return taskDay.isBefore(today);
    } catch (e) {
      return false;
    }
  }

  // 獲取任務標記顏色
  double _getTaskMarkerColor(Map<String, dynamic> task) {
    final status = task['status'] ?? 'open';
    final hasAcceptedApplicant = task['acceptedApplicant'] != null;

    if (hasAcceptedApplicant || status == 'accepted') {
      return BitmapDescriptor.hueBlue; // 藍色：已接受應徵者
    } else if (status == 'open') {
      return BitmapDescriptor.hueYellow; // 黃色：開放中
    } else {
      return BitmapDescriptor.hueRed; // 紅色：其他狀態
    }
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
    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

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
    // 先清除任何現有的 SnackBar，避免與底部彈窗衝突
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

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
        'acceptedApplicant': null, // 被接受的應徵者
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'status': 'open', // open, accepted, completed, expired
        'isActive': true, // 是否在地圖上顯示
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
        _showWarningMessage('正在上傳 ${taskData.images.length} 張圖片...');

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

        _showSuccessMessage(successMessage);

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
        _showErrorMessage('創建任務失敗：${e.toString()}');
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
          _showWarningMessage('正在上傳 ${taskData.images.length} 張圖片...');
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
        'updatedAt': Timestamp.now(),
        // 不更新 userId, applicants, createdAt, status, acceptedApplicant, isActive
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

      _showSuccessMessage(successMessage);
    } catch (e) {
      print('更新任務錯誤詳情: $e');
      _showErrorMessage('更新任務失敗：$e');
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

  /// 顯示自定義樣式的 SnackBar
  void _showCustomSnackBar(String message, {Color? iconColor, IconData? icon}) {
    // 先清除現有的 SnackBar，避免重疊
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon ?? Icons.check_circle_outline,
              color: iconColor ?? Colors.green[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        margin: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 120, // 固定位置，避免與底部彈窗衝突
        ),
        duration: const Duration(seconds: 2), // 縮短顯示時間
      ),
    );
  }

  /// 顯示成功訊息
  void _showSuccessMessage(String message) {
    _showCustomSnackBar(
      message,
      iconColor: Colors.green[600],
      icon: Icons.check_circle_outline,
    );
  }

  /// 顯示錯誤訊息
  void _showErrorMessage(String message) {
    _showCustomSnackBar(
      message,
      iconColor: Colors.red[600],
      icon: Icons.error_outline,
    );
  }

  /// 顯示警告訊息
  void _showWarningMessage(String message) {
    _showCustomSnackBar(
      message,
      iconColor: Colors.orange[600],
      icon: Icons.warning_outlined,
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

          // 調試和測試按鈕
          if (true) // 設為 false 來隱藏調試按鈕
            Positioned(
              top: 140,
              left: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Firebase 監聽狀態按鈕
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: _postsSubscription != null
                        ? Colors.green[100]
                        : Colors.red[100],
                    child: Icon(
                      _postsSubscription != null ? Icons.wifi : Icons.wifi_off,
                      color: _postsSubscription != null
                          ? Colors.green
                          : Colors.red,
                    ),
                    heroTag: 'firebase_status',
                    onPressed: () {
                      _showDebugInfo();
                    },
                  ),
                  const SizedBox(height: 8),
                  // 測試通知按鈕
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.orange[100],
                    child: const Icon(
                      Icons.notifications_active,
                      color: Colors.orange,
                    ),
                    heroTag: 'test_notification',
                    onPressed: () {
                      _testNotification();
                    },
                  ),
                ],
              ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 個人資料設定按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'profile',
                  mini: true,
                  child: const Icon(Icons.person_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => setState(
                    () => _currentBottomSheet = BottomSheetType.profileEditing,
                  ),
                ),
                const SizedBox(width: 12),
                // 角色切換按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'switch',
                  mini: true,
                  child: const Icon(Icons.group_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => _showRoleSwitchDialog(context, '陪伴者'),
                ),
              ],
            ),
          ),

          // 2. 右上角 (Top-Right) – 操作群組
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 通知按鈕（UI預留）
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'notifications',
                  mini: true,
                  child: Stack(
                    children: [
                      const Icon(Icons.notifications_rounded),
                      // 如果有未讀通知，顯示紅點
                      if (_notifications
                          .where((n) => n['isRead'] == false)
                          .isNotEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () {
                    _showNotificationsList();
                  },
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
                  onPressed: () async {
                    var perm = await Geolocator.checkPermission();
                    if (perm == LocationPermission.denied) {
                      perm = await Geolocator.requestPermission();
                    }
                    if (perm == LocationPermission.denied ||
                        perm == LocationPermission.deniedForever) {
                      _showErrorMessage('請在系統設定允許定位權限');
                      return;
                    }

                    final pos = await Geolocator.getCurrentPosition();
                    final newLatLng = LatLng(pos.latitude, pos.longitude);

                    setState(() => _myLocation = newLatLng);
                    _updateMarkers();
                    _mapCtrl.animateCamera(
                      CameraUpdate.newLatLngZoom(newLatLng, 16),
                    );
                  },
                ),
              ],
            ),
          ),

          // 4. 右下角 (Bottom-Right) – 發佈相關
          Positioned(
            bottom: 40,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 我的發佈清單
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'myPosts',
                  mini: false,
                  child: const Icon(Icons.list_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () => setState(
                    () => _currentBottomSheet = BottomSheetType.myPostsList,
                  ),
                ),
                const SizedBox(height: 16),
                // 創建任務
                FloatingActionButton(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                  heroTag: 'create',
                  mini: false,
                  child: const Icon(Icons.add_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: _startCreatePostManually,
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

                      _showSuccessMessage('任務已刪除');

                      // 如果删除后没有任务了，保持在列表页面
                      if (_myPosts.isEmpty) {
                        // 不关闭弹窗，让用户看到空状态
                      }
                    } catch (e) {
                      _showErrorMessage('刪除失敗：$e');
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

          // 應徵者通知彈窗
          if (_showNotificationPopup && _latestNotificationMessage != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                transform: Matrix4.translationValues(
                  0,
                  _showNotificationPopup ? 0 : 200,
                  0,
                ),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue[600]!, Colors.blue[700]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '新的應徵者',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _latestNotificationMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showNotificationPopup = false;
                          });
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
