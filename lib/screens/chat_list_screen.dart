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

class _ChatListScreenState extends State<ChatListScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey[200]),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<List<ChatRoom>>(
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

          final chatRooms = snapshot.data ?? [];

          if (chatRooms.isEmpty) {
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
                    '還沒有聊天室',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '申請任務後就可以開始聊天了',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: chatRooms.length,
            itemBuilder: (context, index) {
              final chatRoom = chatRooms[index];
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildChatRoomAvatar(otherUserId),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  isCurrentUserParent ? Icons.business : Icons.person,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  isCurrentUserParent ? '陪伴者' : '發布者',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
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
                    color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
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
        onTap: () => _enterChatRoom(chatRoom),
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
}
