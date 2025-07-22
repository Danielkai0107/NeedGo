import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../components/task_detail_sheet.dart';
import '../components/create_edit_task_bottom_sheet.dart';
import '../utils/custom_snackbar.dart';
import '../styles/app_colors.dart';

/// 通知頁面
class NotificationScreen extends StatefulWidget {
  final Function(int)? onNotificationCountChanged;

  const NotificationScreen({Key? key, this.onNotificationCountChanged})
    : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _userRole = 'parent';
  Set<String> _readNotificationIds = {};
  StreamSubscription<QuerySnapshot>? _notificationListener;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  @override
  void dispose() {
    _notificationListener?.cancel();
    super.dispose();
  }

  /// 通知數量更新回調
  void _updateNotificationCount() {
    final unreadCount = _notifications.where((n) => n['isRead'] != true).length;
    widget.onNotificationCountChanged?.call(unreadCount);
  }

  /// 初始化通知系統
  Future<void> _initializeNotifications() async {
    print('🚀 開始初始化通知系統...');

    await _determineUserRole();
    await _loadReadNotificationIds();
    _setupNotificationListener();

    print('通知系統初始化完成');
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
      print(' 判斷用戶角色失敗: $e');
    }
  }

  /// 載入已讀通知ID
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
      print(' 載入已讀通知ID失敗: $e');
    }
  }

  /// 保存已讀通知ID
  Future<void> _saveReadNotificationIds() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = '${_userRole}_read_notifications_${user.uid}';
      await prefs.setStringList(key, _readNotificationIds.toList());
    } catch (e) {
      print(' 保存已讀通知ID失敗: $e');
    }
  }

  /// 設置實時監聽器
  void _setupNotificationListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('🔔 設置通知監聽器...');

    _notificationListener?.cancel();

    if (_userRole == 'parent') {
      _notificationListener = _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
            print('📢 檢測到任務變化，重新載入通知...');
            _loadParentNotifications();
          });
    } else {
      _notificationListener = _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
            print('📢 檢測到新任務，重新載入通知...');
            _loadPlayerNotifications();
          });
    }

    print('通知監聽器設置完成');
  }

  /// 載入父級通知（應徵者通知）
  Future<void> _loadParentNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      print('🔄 開始載入父級通知...');

      final tasksSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .get();

      final notifications = <Map<String, dynamic>>[];
      final existingNotificationIds = <String>{};

      print('📋 找到 ${tasksSnapshot.docs.length} 個我的任務');

      for (var doc in tasksSnapshot.docs) {
        final task = doc.data();
        task['id'] = doc.id;
        final applicants = task['applicants'] as List? ?? [];
        final taskTitle = task['title'] ?? task['name'] ?? '未命名任務';

        print('📝 任務: $taskTitle');
        print('   應徵者: ${applicants.length} 個');
        print('   應徵者ID: $applicants');

        for (var applicantId in applicants) {
          // 保持原有的通知ID格式以維持已讀狀態兼容性
          final notificationId = '${task['id']}_$applicantId';

          print('   🔔 檢查通知: $notificationId');

          // 避免重複添加相同的通知
          if (existingNotificationIds.contains(notificationId)) {
            print('    通知已存在，跳過');
            continue;
          }
          existingNotificationIds.add(notificationId);

          // 使用更新時間作為通知時間，如果沒有則使用創建時間
          final timestamp =
              (task['updatedAt'] as Timestamp?)?.toDate() ??
              (task['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          final isRead = _readNotificationIds.contains(notificationId);

          print('   📖 是否已讀: $isRead');
          print('   ⏰ 通知時間: $timestamp');

          notifications.add({
            'id': notificationId,
            'type': 'new_applicant',
            'taskId': task['id'],
            'taskName': taskTitle,
            'applicantId': applicantId,
            'message': '「$taskTitle」有新的應徵者！',
            'timestamp': timestamp,
            'isRead': isRead,
            'taskData': task,
          });

          print('   通知已添加');
        }
      }

      print('📊 總共生成 ${notifications.length} 個通知');
      print('🔐 已讀通知ID: ${_readNotificationIds.length} 個');

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
        _updateNotificationCount();

        print('🎯 UI更新完成');
        print('📋 總通知數: ${_notifications.length}');
        print(
          '🔔 未讀通知數: ${_notifications.where((n) => n['isRead'] != true).length}',
        );
      }
    } catch (e) {
      print(' 載入父級通知失敗: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 載入子級通知（新任務通知）
  Future<void> _loadPlayerNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      print('🔄 開始載入子級通知...');

      final tasksSnapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final notifications = <Map<String, dynamic>>[];
      final existingNotificationIds = <String>{};

      print('📋 找到 ${tasksSnapshot.docs.length} 個活躍任務');

      for (var doc in tasksSnapshot.docs) {
        final task = doc.data();
        task['id'] = doc.id;

        if (task['userId'] == user.uid) continue;

        final notificationId = 'new_task_${task['id']}';

        // 避免重複添加相同的通知
        if (existingNotificationIds.contains(notificationId)) {
          continue;
        }
        existingNotificationIds.add(notificationId);

        final timestamp =
            (task['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final isRead = _readNotificationIds.contains(notificationId);

        notifications.add({
          'id': notificationId,
          'type': 'new_task',
          'taskId': task['id'],
          'taskName': task['title'] ?? task['name'] ?? '未命名任務',
          'message': '有新的任務：${task['title'] ?? task['name']}',
          'timestamp': timestamp,
          'isRead': isRead,
          'taskData': task,
        });
      }

      print('📊 總共生成 ${notifications.length} 個通知');

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
        _updateNotificationCount();

        print('🎯 UI更新完成');
        print('📋 總通知數: ${_notifications.length}');
        print(
          '🔔 未讀通知數: ${_notifications.where((n) => n['isRead'] != true).length}',
        );
      }
    } catch (e) {
      print(' 載入子級通知失敗: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 標記通知為已讀
  Future<void> _markAsRead(String notificationId) async {
    if (_readNotificationIds.contains(notificationId)) return;

    setState(() {
      _readNotificationIds.add(notificationId);
    });

    final notificationIndex = _notifications.indexWhere(
      (n) => n['id'] == notificationId,
    );
    if (notificationIndex != -1) {
      _notifications[notificationIndex]['isRead'] = true;
    }

    _updateNotificationCount();
    await _saveReadNotificationIds();
  }

  /// 標記所有通知為已讀
  Future<void> _markAllAsRead() async {
    for (var notification in _notifications) {
      _readNotificationIds.add(notification['id']);
      notification['isRead'] = true;
    }

    setState(() {});
    _updateNotificationCount();
    await _saveReadNotificationIds();
  }

  /// 刪除通知
  Future<void> _deleteNotification(String notificationId) async {
    setState(() {
      _notifications.removeWhere((n) => n['id'] == notificationId);
      _readNotificationIds.add(notificationId);
    });

    _updateNotificationCount();
    await _saveReadNotificationIds();
  }

  /// 清除所有通知
  Future<void> _clearAllNotifications() async {
    await _markAllAsRead();
    setState(() {
      _notifications.clear();
    });
    _updateNotificationCount();
  }

  /// 測試通知生成（調試用）
  void _testNotificationGeneration() async {
    print('🧪 開始測試通知生成...');

    // 清除已讀狀態以便測試
    setState(() {
      _readNotificationIds.clear();
    });

    // 重新載入通知
    if (_userRole == 'parent') {
      await _loadParentNotifications();
    } else {
      await _loadPlayerNotifications();
    }

    print('🧪 測試完成');
  }

  /// 顯示任務詳情
  void _showTaskDetail(Map<String, dynamic> notification) {
    _markAsRead(notification['id']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: notification['taskData'],
        isParentView: _userRole == 'parent',
        onTaskUpdated: () {
          if (_userRole == 'parent') {
            _loadParentNotifications();
          } else {
            _loadPlayerNotifications();
          }
        },
        // 提供編輯任務回調（僅對自己的任務有效）
        onEditTask:
            _userRole == 'parent' &&
                notification['taskData']['userId'] ==
                    FirebaseAuth.instance.currentUser?.uid
            ? () {
                Navigator.of(context).pop(); // 關閉任務詳情頁
                _showEditTaskSheet(notification['taskData']);
              }
            : null,
        // 提供刪除任務回調（僅對自己的任務有效）
        onDeleteTask:
            _userRole == 'parent' &&
                notification['taskData']['userId'] ==
                    FirebaseAuth.instance.currentUser?.uid
            ? () async {
                Navigator.of(context).pop(); // 關閉任務詳情頁
                await _deleteTask(notification['taskData']['id']);
              }
            : null,
      ),
    );
  }

  /// 顯示編輯任務彈窗
  void _showEditTaskSheet(Map<String, dynamic> taskData) {
    CreateEditTaskBottomSheet.show(
      context,
      existingTask: taskData,
      onSubmit: (updatedTaskData) async {
        await _updateTask(updatedTaskData, taskData['id']);
      },
    );
  }

  /// 更新任務
  Future<void> _updateTask(TaskData taskData, String taskId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 如果有新圖片需要上傳，獲取包含圖片 URL 的數據
      Map<String, dynamic> updateData;
      if (taskData.images.isNotEmpty) {
        updateData = await taskData.toJsonWithUploadedImages(taskId: taskId);
      } else {
        updateData = taskData.toJson();
      }

      // 移除不需要的字段（Firestore 會自動處理）
      updateData.remove('id');

      // 加入必要的更新字段
      updateData['updatedAt'] = Timestamp.now();
      updateData['userId'] = user.uid; // 確保用戶 ID 正確

      // 更新到 Firestore
      await _firestore.collection('posts').doc(taskId).update(updateData);

      print('任務更新成功，ID: $taskId');

      // 重新載入通知
      if (_userRole == 'parent') {
        await _loadParentNotifications();
      } else {
        await _loadPlayerNotifications();
      }

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務更新成功！');
      }
    } catch (e) {
      print('❌ 更新任務失敗: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '更新任務失敗：$e');
      }
    }
  }

  /// 刪除任務
  Future<void> _deleteTask(String taskId) async {
    // 顯示確認對話框
    final confirmed = await showDialog<bool>(
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
                '刪除任務',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              // 內容
              Text(
                '確定要刪除這個任務嗎？',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 警告容器
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  '此操作無法復原。',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.red[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              // 按鈕組
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('刪除', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // 從 Firestore 刪除任務
      await _firestore.collection('posts').doc(taskId).delete();

      print('任務刪除成功');

      // 重新載入通知
      if (_userRole == 'parent') {
        await _loadParentNotifications();
      } else {
        await _loadPlayerNotifications();
      }

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務已刪除');
      }
    } catch (e) {
      print('❌ 刪除任務失敗: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '刪除任務失敗：$e');
      }
    }
  }

  /// 顯示長按選單
  void _showLongPressOptions(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  notification['taskName'] ?? '未命名任務',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          if (isRead) {
                            // 標記為未讀
                            setState(() {
                              _readNotificationIds.remove(notification['id']);
                              notification['isRead'] = false;
                            });
                            _updateNotificationCount();
                            _saveReadNotificationIds();
                          } else {
                            // 標記為已讀
                            _markAsRead(notification['id']);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: AppColors.primary),
                        ),
                        child: Text(
                          isRead ? '標記為未讀' : '標記為已讀',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _deleteNotification(notification['id']);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.red[400]!),
                        ),
                        child: Text(
                          '刪除',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.red[600],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// 建立狀態標籤
  Widget _buildStatusChip(String type, bool isRead) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (type) {
      case 'new_applicant':
        backgroundColor = isRead ? Colors.blue[50]! : Colors.blue[100]!;
        textColor = isRead ? Colors.blue[600]! : Colors.blue[700]!;
        text = '新應徵者';
        break;
      case 'new_task':
        backgroundColor = isRead ? Colors.orange[50]! : Colors.orange[100]!;
        textColor = isRead ? Colors.orange[600]! : Colors.orange[700]!;
        text = '新任務';
        break;
      default:
        backgroundColor = Colors.grey[50]!;
        textColor = Colors.grey[600]!;
        text = '通知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  /// 建立通知卡片
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] ?? false;
    final type = notification['type'] ?? '';
    final timestamp = notification['timestamp'] as DateTime;
    final taskName = notification['taskName'] ?? '未命名任務';

    String timeText = '${timestamp.month}/${timestamp.day}';
    if (timestamp.hour != 0 || timestamp.minute != 0) {
      timeText +=
          ' ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showTaskDetail(notification),
          onLongPress: () => _showLongPressOptions(notification),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        taskName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: isRead
                              ? FontWeight.w500
                              : FontWeight.w600,
                          color: isRead ? Colors.grey[700] : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStatusChip(type, isRead),
                  ],
                ),
                const SizedBox(height: 8),

                Text(
                  notification['message'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    color: isRead ? Colors.grey[600] : Colors.grey[700],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeText,
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const Spacer(),
                    if (!isRead) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: type == 'new_applicant'
                              ? Colors.blue
                              : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '點擊查看詳情',
                      style: TextStyle(
                        fontSize: 12,
                        color: type == 'new_applicant'
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '通知',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.grey[400],
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAllNotifications,
              child: const Text('全部清除'),
            ),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(bottom: 140),
              child: RefreshIndicator(
                onRefresh: _initializeNotifications,
                child: _notifications.isEmpty
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
                              _userRole == 'parent'
                                  ? '有新的應徵者時會在這裡顯示通知'
                                  : '有新的任務時會在這裡顯示通知',
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
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return _buildNotificationCard(notification);
                        },
                      ),
              ),
            ),
    );
  }
}
