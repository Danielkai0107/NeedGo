import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../components/task_detail_sheet.dart';
import '../utils/custom_snackbar.dart';

/// 通知頁面
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _myPosts = [];
  bool _isLoading = true;
  String _userRole = 'parent'; // parent 或 player
  Set<String> _readNotificationIds = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  /// 初始化通知
  Future<void> _initializeNotifications() async {
    await _determineUserRole();
    await _loadReadNotificationIds();

    if (_userRole == 'parent') {
      await _loadParentNotifications();
    } else {
      await _loadPlayerNotifications();
    }
  }

  /// 判斷用戶角色
  Future<void> _determineUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc.data()?['preferredRole'] ?? 'parent';
        });
      }
    } catch (e) {
      print('判斷用戶角色失敗: $e');
    }
  }

  /// 載入已讀通知 ID
  Future<void> _loadReadNotificationIds() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = '${_userRole}_read_notifications_${user.uid}';
      final readIds = prefs.getStringList(key) ?? [];

      setState(() {
        _readNotificationIds = readIds.toSet();
      });
    } catch (e) {
      print('載入已讀通知 ID 失敗: $e');
    }
  }

  /// 保存已讀通知 ID
  Future<void> _saveReadNotificationIds() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = '${_userRole}_read_notifications_${user.uid}';
      await prefs.setStringList(key, _readNotificationIds.toList());
    } catch (e) {
      print('保存已讀通知 ID 失敗: $e');
    }
  }

  /// 載入 Parent 通知（應徵者通知）
  Future<void> _loadParentNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 載入我的任務
      final tasksSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      _myPosts = tasksSnapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // 生成應徵者通知
      final notifications = <Map<String, dynamic>>[];

      for (var task in _myPosts) {
        final applicants = task['applicants'] as List? ?? [];

        for (var applicantId in applicants) {
          final notificationId = '${task['id']}_$applicantId';
          if (!_readNotificationIds.contains(notificationId)) {
            notifications.add({
              'id': notificationId,
              'type': 'new_applicant',
              'taskId': task['id'],
              'taskName': task['title'] ?? task['name'] ?? '未命名任務',
              'applicantId': applicantId,
              'message': '「${task['title'] ?? task['name']}」有新的應徵者！',
              'timestamp':
                  (task['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              'isRead': false,
            });
          }
        }
      }

      // 按時間排序，最新的在前
      notifications.sort(
        (a, b) =>
            (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('載入 Parent 通知失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 載入 Player 通知（新任務通知）
  Future<void> _loadPlayerNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 嘗試使用複合索引查詢
      final tasksSnapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      await _processTasksForNotifications(tasksSnapshot, user);
    } catch (e) {
      print('載入 Player 通知失敗: $e');

      // 如果是索引問題，嘗試替代查詢方法
      if (e.toString().contains('FAILED_PRECONDITION') ||
          e.toString().contains('index')) {
        print('🔄 索引缺失，嘗試替代查詢方法...');
        await _loadPlayerNotificationsAlternative();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  /// 替代的 Player 通知載入方法
  Future<void> _loadPlayerNotificationsAlternative() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 先只按 isActive 篩選
      final tasksSnapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .get();

      await _processTasksForNotifications(tasksSnapshot, user);
      print('✅ 使用替代方法成功載入通知');
    } catch (e) {
      print('❌ 替代通知查詢也失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 處理任務數據生成通知
  Future<void> _processTasksForNotifications(
    QuerySnapshot tasksSnapshot,
    User user,
  ) async {
    final notifications = <Map<String, dynamic>>[];

    // 轉換並排序任務
    final tasks = tasksSnapshot.docs.map((doc) {
      final task = doc.data() as Map<String, dynamic>;
      task['id'] = doc.id;
      return task;
    }).toList();

    // 在客戶端按 createdAt 排序，只取前 50 個
    tasks.sort((a, b) {
      final aTime = a['createdAt'];
      final bTime = b['createdAt'];
      if (aTime is Timestamp && bTime is Timestamp) {
        return bTime.compareTo(aTime); // 降序排序
      }
      return 0;
    });

    final limitedTasks = tasks.take(50).toList();

    for (var task in limitedTasks) {
      // 跳過自己發布的任務
      if (task['userId'] == user.uid) continue;

      final notificationId = 'task_${task['id']}';
      if (!_readNotificationIds.contains(notificationId)) {
        notifications.add({
          'id': notificationId,
          'type': 'new_task',
          'taskId': task['id'],
          'taskName': task['title'] ?? task['name'] ?? '未命名任務',
          'taskData': task,
          'message': '新任務：${task['title'] ?? task['name']}',
          'timestamp':
              (task['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'isRead': false,
        });
      }
    }

    // 按時間排序，最新的在前
    notifications.sort(
      (a, b) =>
          (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime),
    );

    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  /// 標記通知為已讀
  Future<void> _markNotificationAsRead(String notificationId) async {
    if (_readNotificationIds.add(notificationId)) {
      await _saveReadNotificationIds();

      setState(() {
        final index = _notifications.indexWhere(
          (n) => n['id'] == notificationId,
        );
        if (index != -1) {
          _notifications[index]['isRead'] = true;
        }
      });
    }
  }

  /// 清除所有通知
  Future<void> _clearAllNotifications() async {
    for (final notification in _notifications) {
      await _markNotificationAsRead(notification['id']);
    }

    setState(() {
      _notifications.clear();
    });

    if (mounted) {
      CustomSnackBar.showSuccess(context, '所有通知已清除');
    }
  }

  /// 顯示任務詳情（從通知）
  void _showTaskFromNotification(Map<String, dynamic> notification) async {
    // 標記通知為已讀
    await _markNotificationAsRead(notification['id']);

    if (_userRole == 'parent') {
      // Parent 視角：顯示我的任務詳情
      final taskId = notification['taskId'];
      final task = _myPosts.firstWhere(
        (t) => t['id'] == taskId,
        orElse: () => {},
      );

      if (task.isEmpty) {
        CustomSnackBar.showError(context, '找不到對應的任務');
        return;
      }

      _showTaskDetail(task, isMyTask: true);
    } else {
      // Player 視角：顯示新任務詳情
      final taskData = notification['taskData'];
      if (taskData != null) {
        _showTaskDetail(taskData, isMyTask: false);
      }
    }
  }

  /// 顯示任務詳情彈窗
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
        isParentView: _userRole == 'parent',
        currentLocation: null,
        onTaskUpdated: () {
          // 重新載入通知
          _initializeNotifications();
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => n['isRead'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '通知中心',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.grey[300],
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAllNotifications,
              child: const Text('全部清除'),
            ),
        ],
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(bottom: 140), // 為導覽列預留空間
              child: RefreshIndicator(
                onRefresh: _initializeNotifications,
                child: _buildBody(),
              ),
            ),
    );
  }

  Widget _buildBody() {
    final unreadNotifications = _notifications
        .where((n) => n['isRead'] != true)
        .toList();

    if (unreadNotifications.isEmpty) {
      return Center(
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
              _userRole == 'parent' ? '有新的應徵者時會在這裡顯示通知' : '有新的任務時會在這裡顯示通知',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: unreadNotifications.length,
      itemBuilder: (context, index) {
        final notification =
            unreadNotifications[unreadNotifications.length - 1 - index]; // 反向顯示
        return _buildNotificationItem(notification);
      },
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isParentNotification = notification['type'] == 'new_applicant';
    final isRead = notification['isRead'] == true;

    return GestureDetector(
      onTap: () => _showTaskFromNotification(notification),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.grey[50]
              : (isParentNotification ? Colors.blue[50] : Colors.orange[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRead
                ? Colors.grey[200]!
                : (isParentNotification
                      ? Colors.blue[200]!
                      : Colors.orange[200]!),
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
                color: isParentNotification
                    ? Colors.blue[600]
                    : Colors.orange[600],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isParentNotification
                    ? Icons.person_add_rounded
                    : Icons.work_rounded,
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
                        isParentNotification ? '新的應徵者' : '新任務',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
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
                      const SizedBox(width: 8),
                      Text(
                        '點擊查看詳情',
                        style: TextStyle(
                          fontSize: 11,
                          color: isParentNotification
                              ? Colors.blue[600]
                              : Colors.orange[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 刪除按鈕
            IconButton(
              onPressed: () async {
                await _markNotificationAsRead(notification['id']);
                setState(() {
                  _notifications.removeWhere(
                    (n) => n['id'] == notification['id'],
                  );
                });
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
}
