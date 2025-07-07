import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../components/task_detail_sheet.dart';
import '../components/create_edit_task_bottom_sheet.dart' as new_task_sheet;
import '../utils/custom_snackbar.dart';

/// 我的活動頁面
class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({Key? key}) : super(key: key);

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  List<Map<String, dynamic>> _myCreatedTasks = [];
  List<Map<String, dynamic>> _myAppliedTasks = [];
  bool _isLoading = true;
  String? _editingTaskId;

  // 篩選選項
  String _createdTasksFilter = '全部';
  String _appliedTasksFilter = '全部';

  final List<String> _filterOptions = ['全部', '進行中', '過去發布'];
  final List<String> _appliedFilterOptions = ['全部', '進行中', '過去應徵'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadAllTasks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 當應用程式重新進入前台時自動載入資料
    if (state == AppLifecycleState.resumed) {
      print('應用程式重新進入前台，自動載入最新資料');
      _loadAllTasks();
    }
  }

  /// 載入所有任務（我發布的和我應徵的）
  Future<void> _loadAllTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('用戶未登入');
      return;
    }

    print('開始載入任務，用戶 ID: ${user.uid}');

    // 如果不是初次載入，不顯示載入指示器
    if (_myCreatedTasks.isNotEmpty || _myAppliedTasks.isNotEmpty) {
      // 背景載入，不顯示載入指示器
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
    }

    try {
      // 載入我發布的任務
      print('開始查詢我發布的任務...');
      final createdSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .get();

      final createdTasks = createdSnapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // 手動排序我發布的任務
      createdTasks.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime); // 降序排序
        }
        return 0;
      });

      print('找到 ${createdTasks.length} 個我發布的任務');

      // 載入我應徵的任務
      print('開始查詢我應徵的任務...');
      final appliedSnapshot = await _firestore
          .collection('posts')
          .where('applicants', arrayContains: user.uid)
          .get();

      final appliedTasks = appliedSnapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // 手動排序我應徵的任務
      appliedTasks.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime); // 降序排序
        }
        return 0;
      });

      print('找到 ${appliedTasks.length} 個我應徵的任務');

      if (mounted) {
        setState(() {
          _myCreatedTasks = createdTasks;
          _myAppliedTasks = appliedTasks;
          _isLoading = false;
        });

        print('狀態更新完成');
        print('進行中的任務: ${_activeCreatedTasks.length}');
        print('過去的任務: ${_pastCreatedTasks.length}');
      }
    } catch (e) {
      print('載入任務失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  /// 獲取我發布的任務中的進行中任務
  List<Map<String, dynamic>> get _activeCreatedTasks {
    return _myCreatedTasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'open' || status == 'accepted';
    }).toList();
  }

  /// 獲取我發布的任務中的過去任務
  List<Map<String, dynamic>> get _pastCreatedTasks {
    return _myCreatedTasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'completed' || status == 'expired';
    }).toList();
  }

  /// 獲取我應徵的任務中的進行中任務
  List<Map<String, dynamic>> get _activeAppliedTasks {
    return _myAppliedTasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'open' || status == 'accepted';
    }).toList();
  }

  /// 獲取我應徵的任務中的過去任務
  List<Map<String, dynamic>> get _pastAppliedTasks {
    return _myAppliedTasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'completed' || status == 'expired';
    }).toList();
  }

  /// 根據篩選條件獲取我發布的任務
  List<Map<String, dynamic>> get _filteredCreatedTasks {
    switch (_createdTasksFilter) {
      case '進行中':
        return _activeCreatedTasks;
      case '過去發布':
        return _pastCreatedTasks;
      case '全部':
      default:
        return _myCreatedTasks;
    }
  }

  /// 根據篩選條件獲取我應徵的任務
  List<Map<String, dynamic>> get _filteredAppliedTasks {
    switch (_appliedTasksFilter) {
      case '進行中':
        return _activeAppliedTasks;
      case '過去應徵':
        return _pastAppliedTasks;
      case '全部':
      default:
        return _myAppliedTasks;
    }
  }

  /// 顯示任務詳情
  void _showTaskDetail(
    Map<String, dynamic> task, {
    bool isCreatedByMe = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: task,
        isParentView: isCreatedByMe,
        currentLocation: null,
        onTaskUpdated: _loadAllTasks,
        onEditTask: isCreatedByMe
            ? () {
                Navigator.of(context).pop();
                _editTask(task);
              }
            : null,
        onDeleteTask: isCreatedByMe
            ? () async {
                Navigator.of(context).pop();
                await _deleteTask(task['id']);
              }
            : null,
      ),
    );
  }

  /// 編輯任務
  void _editTask(Map<String, dynamic> task) {
    _editingTaskId = task['id'];
    _showEditTaskSheet(task);
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
    if (_editingTaskId == null) return;

    try {
      await _firestore.collection('posts').doc(_editingTaskId).update({
        ...taskData,
        'updatedAt': Timestamp.now(),
      });

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務更新成功！');
        await _loadAllTasks();
        _editingTaskId = null;
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
        await _loadAllTasks();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '刪除任務失敗：$e');
      }
    }
  }

  /// 顯示刪除確認對話框
  Future<bool?> _showDeleteConfirmDialog(Map<String, dynamic> task) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('刪除任務'),
          content: Text('確定要刪除「${task['title'] ?? task['name']}」嗎？此操作不可復原。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );
  }

  /// 創建新任務
  void _createNewTask() {
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
        await _loadAllTasks();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '創建任務失敗：$e');
      }
    }
  }

  /// 解析任務日期
  DateTime? _parseTaskDate(dynamic date) {
    if (date == null) return null;
    try {
      if (date is String) {
        return DateTime.parse(date);
      } else if (date is DateTime) {
        return date;
      } else if (date is Timestamp) {
        return (date as Timestamp).toDate();
      }
    } catch (e) {
      print('解析日期失敗: $e, 日期類型: ${date.runtimeType}');
    }
    return null;
  }

  /// 獲取狀態顏色
  List<Color> _getStatusColors(String status) {
    switch (status) {
      case 'open':
        return [Colors.blue[400]!, Colors.blue[600]!];
      case 'accepted':
        return [Colors.orange[400]!, Colors.orange[600]!];
      case 'completed':
        return [Colors.green[400]!, Colors.green[600]!];
      case 'expired':
        return [Colors.grey[400]!, Colors.grey[600]!];
      default:
        return [Colors.blue[400]!, Colors.blue[600]!];
    }
  }

  /// 獲取狀態圖標
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.schedule;
      case 'accepted':
        return Icons.person;
      case 'completed':
        return Icons.check_circle;
      case 'expired':
        return Icons.access_time_filled;
      default:
        return Icons.schedule;
    }
  }

  /// 建立狀態標籤
  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case 'open':
        backgroundColor = Colors.blue[50]!;
        textColor = Colors.blue[700]!;
        text = '進行中';
        break;
      case 'accepted':
        backgroundColor = Colors.orange[50]!;
        textColor = Colors.orange[700]!;
        text = '已接受';
        break;
      case 'completed':
        backgroundColor = Colors.green[50]!;
        textColor = Colors.green[700]!;
        text = '已完成';
        break;
      case 'expired':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[600]!;
        text = '已過期';
        break;
      default:
        backgroundColor = Colors.blue[50]!;
        textColor = Colors.blue[700]!;
        text = '進行中';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '我的活動',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.assignment_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text('我的任務 (${_myCreatedTasks.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_search_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text('我的應徵 (${_myAppliedTasks.length})'),
                ],
              ),
            ),
          ],
          labelColor: Colors.orange[600],
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.orange[600],
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildMyTasksTab(), _buildMyApplicationsTab()],
            ),
    );
  }

  /// 建立我的任務分頁
  Widget _buildMyTasksTab() {
    if (_myCreatedTasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.assignment_outlined,
        title: '還沒有發布任何任務',
        subtitle: '開始創建你的第一個任務，\n讓更多人看到你的需求！',
        buttonText: '創建第一個任務',
        onButtonPressed: _createNewTask,
      );
    }

    final filteredTasks = _filteredCreatedTasks;

    return Column(
      children: [
        // 篩選下拉選單
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _createdTasksFilter,
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              iconSize: 24,
              elevation: 0,
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _createdTasksFilter = newValue;
                  });
                }
              },
              items: _filterOptions.map<DropdownMenuItem<String>>((
                String value,
              ) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    children: [
                      Icon(
                        value == '全部'
                            ? Icons.list_alt
                            : value == '進行中'
                            ? Icons.schedule_rounded
                            : Icons.history_rounded,
                        size: 20,
                        color: Colors.blue[600],
                      ),
                      const SizedBox(width: 8),
                      Text(value),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // 任務列表
        Expanded(
          child: filteredTasks.isEmpty
              ? _buildEmptyFilterResult()
              : RefreshIndicator(
                  onRefresh: _loadAllTasks,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      return _buildTaskCard(task, isCreatedByMe: true);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 建立我的應徵分頁
  Widget _buildMyApplicationsTab() {
    if (_myAppliedTasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search_outlined,
        title: '還沒有應徵任何任務',
        subtitle: '前往地圖頁面尋找感興趣的任務，\n開始你的第一次應徵吧！',
        buttonText: '前往地圖',
        onButtonPressed: () {
          // 簡單的反饋，用戶可以手動切換到地圖
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('請點擊底部導覽列的「地圖」標籤來尋找任務'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      );
    }

    final filteredTasks = _filteredAppliedTasks;

    return Column(
      children: [
        // 篩選下拉選單
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _appliedTasksFilter,
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              iconSize: 24,
              elevation: 0,
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _appliedTasksFilter = newValue;
                  });
                }
              },
              items: _appliedFilterOptions.map<DropdownMenuItem<String>>((
                String value,
              ) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    children: [
                      Icon(
                        value == '全部'
                            ? Icons.list_alt
                            : value == '進行中'
                            ? Icons.schedule_rounded
                            : Icons.history_rounded,
                        size: 20,
                        color: Colors.green[600],
                      ),
                      const SizedBox(width: 8),
                      Text(value),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // 任務列表
        Expanded(
          child: filteredTasks.isEmpty
              ? _buildEmptyFilterResult()
              : RefreshIndicator(
                  onRefresh: _loadAllTasks,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      return _buildTaskCard(task, isCreatedByMe: false);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 建立空狀態
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onButtonPressed,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 64, color: Colors.orange[300]),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.add_task_rounded, size: 20),
              label: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建立任務列表
  Widget _buildTaskList(
    List<Map<String, dynamic>> tasks, {
    required bool isCreatedByMe,
  }) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '目前沒有任務',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllTasks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _buildTaskCard(task, isCreatedByMe: isCreatedByMe);
        },
      ),
    );
  }

  /// 建立任務卡片
  Widget _buildTaskCard(
    Map<String, dynamic> task, {
    required bool isCreatedByMe,
  }) {
    final status = _getTaskStatus(task);
    final taskDate = _parseTaskDate(task['date']);
    final price = task['price'] ?? 0;
    final applicantCount = (task['applicants'] as List?)?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: isCreatedByMe
          ? Dismissible(
              key: Key('task_${task['id']}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Colors.red[600],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_rounded, color: Colors.white, size: 24),
                    SizedBox(height: 4),
                    Text(
                      '刪除',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              confirmDismiss: (direction) => _showDeleteConfirmDialog(task),
              onDismissed: (direction) => _deleteTask(task['id']),
              child: _buildTaskCardContent(task, isCreatedByMe: isCreatedByMe),
            )
          : _buildTaskCardContent(task, isCreatedByMe: isCreatedByMe),
    );
  }

  /// 建立任務卡片內容
  Widget _buildTaskCardContent(
    Map<String, dynamic> task, {
    required bool isCreatedByMe,
  }) {
    final status = _getTaskStatus(task);
    final taskDate = _parseTaskDate(task['date']);
    final price = task['price'] ?? 0;
    final applicantCount = (task['applicants'] as List?)?.length ?? 0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTaskDetail(task, isCreatedByMe: isCreatedByMe),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // 左側圓形圖標
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _getStatusColors(status),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: _getStatusColors(status)[0].withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _getStatusIcon(status),
                  color: Colors.white,
                  size: 28,
                ),
              ),

              const SizedBox(width: 16),

              // 右側資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：任務標題 + 狀態標籤
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task['title']?.toString() ??
                                task['name']?.toString() ??
                                '未命名任務',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(status),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 第二行：日期 + 價格
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          taskDate != null
                              ? '${taskDate.month}月${taskDate.day}日'
                              : '日期未設定',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '\$${price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 第三行：任務描述
                    if (task['content']?.toString().isNotEmpty == true)
                      Text(
                        task['content'],
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    const SizedBox(height: 12),

                    // 第四行：應徵者數量 + 編輯按鈕（只有我發布的任務才有編輯按鈕）
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: applicantCount > 0
                                ? Colors.blue[50]
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: applicantCount > 0
                                  ? Colors.blue[200]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_rounded,
                                size: 14,
                                color: applicantCount > 0
                                    ? Colors.blue[600]
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$applicantCount 位應徵者',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: applicantCount > 0
                                      ? Colors.blue[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (isCreatedByMe)
                          TextButton.icon(
                            onPressed: () => _editTask(task),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('編輯'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.orange[600],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 14,
                                  color: Colors.green[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '已應徵',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[600],
                                  ),
                                ),
                              ],
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

  /// 建立空白區塊
  Widget _buildEmptySection({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onButtonPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onButtonPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// 建立篩選結果為空的提示
  Widget _buildEmptyFilterResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            '沒有找到相關任務',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '試試選擇其他篩選條件',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
