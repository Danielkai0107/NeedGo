import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../components/online_avatar.dart';
import 'chat_detail_screen.dart';
import '../styles/app_colors.dart';
import '../utils/custom_snackbar.dart';

/// 聊天室列表頁面
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final currentUser = FirebaseAuth.instance.currentUser;
  late TabController _tabController;
  DateTime? _lastCleanupCheck;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    // 進入聊天分頁時自動檢查清理過期聊天室
    _checkAndCleanupExpiredChatRooms();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 每次頁面依賴變化時檢查清理（包括從其他頁面切換回來）
    _checkAndCleanupExpiredChatRoomsWithDebounce();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 當應用從後台回到前台時檢查清理
    if (state == AppLifecycleState.resumed) {
      _checkAndCleanupExpiredChatRoomsWithDebounce();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  /// 刷新聊天室列表
  Future<void> _refreshChatRooms() async {
    try {
      // 立即清理所有過期任務的聊天室
      await ChatService.triggerImmediateCleanupForExpiredTasks();
      // 強制刷新狀態
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('刷新聊天室列表失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '聊天室',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.grey[300],
        actions: [
          // 手動觸發聊天室清理（調試用）
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '立即清理過期聊天室',
            onPressed: _triggerImmediateCleanup,
          ),
        ],

        bottom: TabBar(
          controller: _tabController,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 2.0, color: Colors.black),
            insets: const EdgeInsets.symmetric(horizontal: 48.0),
          ),
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
          ),
          tabs: [
            // Parent 角色 Tab（我是發布者）
            StreamBuilder<List<ChatRoom>>(
              stream: ChatService.getUserChatRooms(),
              builder: (context, snapshot) {
                final parentUnreadCount = _getUnreadCountForRole(
                  snapshot.data,
                  true,
                );
                return Tab(
                  child: _buildTabContent(
                    icon: Icons.business_rounded,
                    text: '我是發布者',
                    itemCount: _getChatRoomCountForRole(snapshot.data, true),
                    unreadCount: parentUnreadCount,
                  ),
                );
              },
            ),
            // Player 角色 Tab（我是陪伴者）
            StreamBuilder<List<ChatRoom>>(
              stream: ChatService.getUserChatRooms(),
              builder: (context, snapshot) {
                final playerUnreadCount = _getUnreadCountForRole(
                  snapshot.data,
                  false,
                );
                return Tab(
                  child: _buildTabContent(
                    icon: Icons.person_rounded,
                    text: '我是陪伴者',
                    itemCount: _getChatRoomCountForRole(snapshot.data, false),
                    unreadCount: playerUnreadCount,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.only(bottom: 140), // 為導覽列預留空間
        child: TabBarView(
          controller: _tabController,
          children: [
            // Parent 角色的聊天室（我是發布者）
            _buildChatRoomList(isParentView: true),
            // Player 角色的聊天室（我是陪伴者）
            _buildChatRoomList(isParentView: false),
          ],
        ),
      ),
    );
  }

  /// 計算指定角色的未讀消息數量
  int _getUnreadCountForRole(List<ChatRoom>? chatRooms, bool isParentRole) {
    if (chatRooms == null) return 0;

    int totalUnread = 0;
    for (final chatRoom in chatRooms) {
      final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;

      // 如果是當前需要計算的角色，且聊天室未關閉，累加未讀數量
      if (isParentRole == isCurrentUserParent && !chatRoom.isConnectionLost) {
        totalUnread += chatRoom.unreadCount[currentUser?.uid] ?? 0;
      }
    }

    return totalUnread;
  }

  /// 計算指定角色的聊天室數量
  int _getChatRoomCountForRole(List<ChatRoom>? chatRooms, bool isParentRole) {
    if (chatRooms == null) return 0;

    int count = 0;
    for (final chatRoom in chatRooms) {
      final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;

      // 如果是當前需要計算的角色，計數
      if (isParentRole == isCurrentUserParent) {
        count++;
      }
    }

    return count;
  }

  /// 建立 Tab 內容（包含圖標、文字和項目數量）
  Widget _buildTabContent({
    required IconData icon,
    required String text,
    required int itemCount,
    int unreadCount = 0,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 18),
            if (unreadCount > 0)
              Positioned(
                right: -3,
                top: -1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 6),
        Text(itemCount > 0 ? '$text ($itemCount)' : text),
      ],
    );
  }

  /// 建立聊天室列表
  Widget _buildChatRoomList({required bool isParentView}) {
    return RefreshIndicator(
      onRefresh: _refreshChatRooms,
      child: StreamBuilder<List<ChatRoom>>(
        stream: ChatService.getUserChatRooms(),
        builder: (context, snapshot) {
          print('聊天室列表狀態: ${snapshot.connectionState}');
          print('是否有錯誤: ${snapshot.hasError}');
          print('錯誤信息: ${snapshot.error}');
          print('數據: ${snapshot.data?.length ?? 0} 個聊天室');

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            print('聊天室載入錯誤詳情: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '載入聊天室時發生錯誤',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('重新載入'),
                  ),
                ],
              ),
            );
          }

          final allChatRooms = snapshot.data ?? [];

          // 根據當前用戶的角色篩選聊天室
          final roleChatRooms = allChatRooms.where((chatRoom) {
            final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;
            return isParentView ? isCurrentUserParent : !isCurrentUserParent;
          }).toList();

          if (roleChatRooms.isEmpty) {
            return _buildEmptyState(isParentView);
          }

          // 將聊天室分為進行中和已關閉兩組，然後合併（進行中在前，已關閉在後）
          final activeChatRooms = roleChatRooms
              .where((chatRoom) => !chatRoom.isConnectionLost)
              .toList();
          final closedChatRooms = roleChatRooms
              .where((chatRoom) => chatRoom.isConnectionLost)
              .toList();

          final sortedChatRooms = [...activeChatRooms, ...closedChatRooms];

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedChatRooms.length,
            itemBuilder: (context, index) {
              final chatRoom = sortedChatRooms[index];
              return _buildChatRoomItem(chatRoom);
            },
          );
        },
      ),
    );
  }

  /// 建立聊天室項目
  Widget _buildChatRoomItem(ChatRoom chatRoom) {
    final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;
    final otherUserId = isCurrentUserParent
        ? chatRoom.playerId
        : chatRoom.parentId;
    final unreadCount = chatRoom.unreadCount[currentUser?.uid] ?? 0;
    final isClosed = chatRoom.isConnectionLost;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isClosed ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isClosed ? 0.02 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: isClosed ? null : () => _enterChatRoom(chatRoom),
          onLongPress: () => _showLongPressOptions(chatRoom),
          child: Opacity(
            opacity: isClosed ? 0.6 : 1.0,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: _buildChatRoomAvatar(otherUserId, isClosed),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      chatRoom.taskTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isClosed ? Colors.grey[500] : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '已關閉',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Text(
                      _formatTime(chatRoom.updatedAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatLastMessage(chatRoom),
                        style: TextStyle(
                          fontSize: 14,
                          color: isClosed
                              ? Colors.grey[500]
                              : (unreadCount > 0
                                    ? Colors.black87
                                    : Colors.grey[600]),
                          fontWeight: isClosed
                              ? FontWeight.normal
                              : (unreadCount > 0
                                    ? FontWeight.w500
                                    : FontWeight.normal),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unreadCount > 0 && !isClosed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建立聊天室頭像（帶在線狀態）
  Widget _buildChatRoomAvatar(String otherUserId, bool isClosed) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: ChatService.getUserInfo(otherUserId),
      builder: (context, snapshot) {
        String? avatarUrl;

        if (snapshot.hasData && snapshot.data != null) {
          avatarUrl = snapshot.data!['avatarUrl']?.toString();
        }

        return OnlineAvatar(
          userId: otherUserId,
          avatarUrl: avatarUrl,
          radius: 25,
          showOnlineStatus: !isClosed,
          onlineIndicatorSize: 12,
        );
      },
    );
  }

  /// 格式化時間顯示
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return '昨天';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}天前';
      } else {
        return '${time.month}/${time.day}';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小時前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分鐘前';
    } else {
      return '剛剛';
    }
  }

  /// 格式化最後訊息顯示
  String _formatLastMessage(ChatRoom chatRoom) {
    // 如果聊天室已失去聯繫，顯示失去聯繫狀態
    if (chatRoom.isConnectionLost) {
      return '系統已關閉聊天室';
    }

    if (chatRoom.lastMessageSender == 'system') {
      return chatRoom.lastMessage;
    }

    final isCurrentUserSender = chatRoom.lastMessageSender == currentUser?.uid;
    final prefix = isCurrentUserSender ? '你: ' : '';
    return '$prefix${chatRoom.lastMessage}';
  }

  /// 建立空狀態
  Widget _buildEmptyState(bool isParentView) {
    String title = isParentView ? '還沒有聊天室' : '還沒有聊天室';
    String subtitle = isParentView ? '發布任務後等待陪伴者申請就會有聊天室了' : '申請任務後就可以開始聊天了';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 進入聊天室
  void _enterChatRoom(ChatRoom chatRoom) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(chatRoom: chatRoom),
      ),
    );
  }

  /// 顯示長按選項
  void _showLongPressOptions(ChatRoom chatRoom) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示器
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

              // 聊天室標題
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  chatRoom.taskTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // 確認文案
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '確定刪除「${chatRoom.taskTitle}」的聊天室嗎？',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),

              // 左右按鈕
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // 左邊取消按鈕
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 右邊刪除按鈕
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _deleteChatRoom(chatRoom);
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

  /// 顯示刪除確認對話框
  Future<bool?> _showDeleteConfirmDialog(ChatRoom chatRoom) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                Text(
                  '刪除聊天室',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                // 內容
                Text(
                  '確定要刪除與「${chatRoom.taskTitle}」相關的聊天室嗎？',
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
                    '此操作不可復原。',
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
        );
      },
    );
  }

  /// 刪除聊天室
  Future<void> _deleteChatRoom(ChatRoom chatRoom) async {
    try {
      await ChatService.deleteChatRoom(chatRoom.id);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '聊天室「${chatRoom.taskTitle}」已刪除');
        // 注意：恢復功能現在需要通過長按選單來使用
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '刪除聊天室失敗：$e');
      }
    }
  }

  /// 恢復聊天室
  Future<void> _restoreChatRoom(ChatRoom chatRoom) async {
    try {
      final success = await ChatService.smartRestoreChatRoom(chatRoom.id);

      if (mounted) {
        if (success) {
          CustomSnackBar.showSuccess(context, '聊天室「${chatRoom.taskTitle}」已恢復');
        } else {
          CustomSnackBar.showWarning(
            context,
            '聊天室「${chatRoom.taskTitle}」無法恢復\n任務可能已完成或過期',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '恢復聊天室失敗：$e');
      }
    }
  }

  /// 自動檢查並清理過期聊天室
  Future<void> _checkAndCleanupExpiredChatRooms() async {
    try {
      // 靜默執行立即清理，不顯示任何UI反饋
      await ChatService.triggerImmediateCleanupForExpiredTasks();
      _lastCleanupCheck = DateTime.now();
      print('✅ 聊天分頁：自動立即清理過期聊天室完成');
    } catch (e) {
      print(' 聊天分頁：自動立即清理過期聊天室失敗: $e');
      // 靜默失敗，不影響用戶體驗
    }
  }

  /// 帶防抖的聊天室清理檢查（避免頻繁調用）
  Future<void> _checkAndCleanupExpiredChatRoomsWithDebounce() async {
    final now = DateTime.now();

    // 如果上次檢查在30秒內，跳過本次檢查
    if (_lastCleanupCheck != null &&
        now.difference(_lastCleanupCheck!).inSeconds < 30) {
      print('⏭️ 聊天分頁：距離上次清理檢查未超過30秒，跳過本次檢查');
      return;
    }

    await _checkAndCleanupExpiredChatRooms();
  }

  /// 手動觸發聊天室清理（調試用）
  void _triggerImmediateCleanup() async {
    try {
      // 使用立即清理方法，不等待配置時間
      await ChatService.triggerImmediateCleanupForExpiredTasks();
      _lastCleanupCheck = DateTime.now(); // 更新時間以避免再次跳過
      print('✅ 聊天分頁：手動觸發立即清理完成');
      if (mounted) {
        CustomSnackBar.showSuccess(context, '✅ 已立即清理所有過期任務的聊天室');
      }
    } catch (e) {
      print(' 聊天分頁：手動觸發立即清理失敗: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '手動清理失敗：$e');
      }
    }
  }
}
