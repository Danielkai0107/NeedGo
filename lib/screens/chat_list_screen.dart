import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../components/online_avatar.dart';
import 'chat_detail_screen.dart';

/// 聊天室列表頁面
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  final currentUser = FirebaseAuth.instance.currentUser;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '聊天室',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 2.0, color: Colors.blue[600]!),
            insets: const EdgeInsets.symmetric(horizontal: 48.0),
          ),
          labelColor: Colors.blue[600],
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
        padding: const EdgeInsets.only(top: 16),
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

      // 如果是當前需要計算的角色，累加未讀數量
      if (isParentRole == isCurrentUserParent) {
        totalUnread += chatRoom.unreadCount[currentUser?.uid] ?? 0;
      }
    }

    return totalUnread;
  }

  /// 建立 Tab 內容（包含圖標、文字和未讀角標）
  Widget _buildTabContent({
    required IconData icon,
    required String text,
    required int unreadCount,
  }) {
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
        if (unreadCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 建立聊天室列表
  Widget _buildChatRoomList({required bool isParentView}) {
    return StreamBuilder<List<ChatRoom>>(
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
        final filteredChatRooms = allChatRooms.where((chatRoom) {
          final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;
          return isParentView ? isCurrentUserParent : !isCurrentUserParent;
        }).toList();

        if (filteredChatRooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  isParentView ? '還沒有發布者聊天室' : '還沒有陪伴者聊天室',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isParentView ? '發布任務後等待陪伴者申請就會有聊天室了' : '申請任務後就可以開始聊天了',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredChatRooms.length,
          itemBuilder: (context, index) {
            final chatRoom = filteredChatRooms[index];
            return _buildChatRoomItem(chatRoom);
          },
        );
      },
    );
  }

  /// 建立聊天室項目
  Widget _buildChatRoomItem(ChatRoom chatRoom) {
    final isCurrentUserParent = currentUser?.uid == chatRoom.parentId;
    final otherUserId = isCurrentUserParent
        ? chatRoom.playerId
        : chatRoom.parentId;
    final unreadCount = chatRoom.unreadCount[currentUser?.uid] ?? 0;

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
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () => _enterChatRoom(chatRoom),
          onLongPress: () => _showLongPressOptions(chatRoom),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: _buildChatRoomAvatar(otherUserId),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    chatRoom.taskTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                        color: unreadCount > 0
                            ? Colors.black87
                            : Colors.grey[600],
                        fontWeight: unreadCount > 0
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unreadCount > 0)
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
    );
  }

  /// 建立聊天室頭像（帶在線狀態）
  Widget _buildChatRoomAvatar(String otherUserId) {
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
          showOnlineStatus: true,
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
    if (chatRoom.lastMessageSender == 'system') {
      return chatRoom.lastMessage;
    }

    final isCurrentUserSender = chatRoom.lastMessageSender == currentUser?.uid;
    final prefix = isCurrentUserSender ? '你: ' : '';
    return '$prefix${chatRoom.lastMessage}';
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
        return AlertDialog(
          title: const Text('刪除聊天室'),
          content: Text('確定要刪除與「${chatRoom.taskTitle}」相關的聊天室嗎？\n此操作不可復原。'),
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

  /// 刪除聊天室
  Future<void> _deleteChatRoom(ChatRoom chatRoom) async {
    try {
      await ChatService.deleteChatRoom(chatRoom.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('聊天室「${chatRoom.taskTitle}」已刪除'),
            action: SnackBarAction(
              label: '恢復',
              onPressed: () => _restoreChatRoom(chatRoom),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除聊天室失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 恢復聊天室
  Future<void> _restoreChatRoom(ChatRoom chatRoom) async {
    try {
      await ChatService.restoreChatRoom(chatRoom.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('聊天室「${chatRoom.taskTitle}」已恢復'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢復聊天室失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
