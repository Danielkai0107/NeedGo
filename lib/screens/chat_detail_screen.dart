import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import '../components/online_avatar.dart';
import '../components/task_detail_sheet.dart';

/// 聊天室詳情頁面
class ChatDetailScreen extends StatefulWidget {
  final ChatRoom chatRoom;

  const ChatDetailScreen({Key? key, required this.chatRoom}) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final currentUser = FirebaseAuth.instance.currentUser;

  // 使用 ValueNotifier 來管理輸入狀態，避免不必要的 setState
  final ValueNotifier<bool> _isComposingNotifier = ValueNotifier<bool>(false);
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();

    // 標記訊息為已讀
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ChatService.markMessagesAsRead(widget.chatRoom.id);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _isComposingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentUserParent = currentUser?.uid == widget.chatRoom.parentId;
    final otherUserId = isCurrentUserParent
        ? widget.chatRoom.playerId
        : widget.chatRoom.parentId;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // 對方頭像（帶在線狀態）
            FutureBuilder<Map<String, dynamic>?>(
              future: ChatService.getUserInfo(otherUserId),
              builder: (context, snapshot) {
                String? avatarUrl;
                String? userName;

                if (snapshot.hasData && snapshot.data != null) {
                  avatarUrl = snapshot.data!['avatarUrl']?.toString();
                  userName = snapshot.data!['name']?.toString();
                }

                return OnlineAvatar(
                  userId: otherUserId,
                  avatarUrl: avatarUrl,
                  radius: 20,
                  showOnlineStatus: true,
                  onlineIndicatorSize: 10,
                );
              },
            ),
            const SizedBox(width: 12),

            // 標題和在線狀態文字
            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: ChatService.getUserInfo(otherUserId),
                builder: (context, userSnapshot) {
                  String userName = isCurrentUserParent ? '陪伴者' : '發布者';

                  if (userSnapshot.hasData && userSnapshot.data != null) {
                    userName =
                        userSnapshot.data!['name']?.toString() ?? userName;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      StreamBuilder<bool>(
                        stream: ChatService.getUserOnlineStatus(otherUserId),
                        builder: (context, snapshot) {
                          final isOnline = snapshot.data ?? false;

                          // 組合在線狀態和角色
                          String statusText;
                          Color statusColor;

                          if (isOnline) {
                            statusText =
                                '在線上 • ${isCurrentUserParent ? '陪伴者' : '發布者'}';
                            statusColor = Colors.green[600]!;
                          } else {
                            statusText = isCurrentUserParent ? '陪伴者' : '發布者';
                            statusColor = Colors.grey[600]!;
                          }

                          return Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.normal,
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          // 查看任務詳情按鈕
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showTaskDetails,
            tooltip: '查看任務詳情',
            splashRadius: 24,
          ),
        ],
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey[200]),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // 任務快速預覽卡片
          _buildTaskPreviewCard(),

          // 訊息列表
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: ChatService.getChatMessages(widget.chatRoom.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '載入訊息時發生錯誤',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                // 首次載入時滾動到底部
                if (_isInitialLoad && messages.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToBottom();
                    _isInitialLoad = false;
                  });
                }

                if (messages.isEmpty) {
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
                          '還沒有訊息',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '開始聊天吧！',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // 從底部開始顯示
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isCurrentUserMessage =
                        message.senderId == currentUser?.uid;
                    final showDateSeparator = _shouldShowDateSeparator(
                      messages,
                      index,
                    );

                    return Column(
                      children: [
                        if (showDateSeparator)
                          _buildDateSeparator(message.timestamp),
                        MessageBubble(
                          message: message,
                          isCurrentUser: isCurrentUserMessage,
                          showTime: true,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // 訊息輸入區域
          _buildMessageInput(),
        ],
      ),
    );
  }

  /// 建立日期分隔線
  Widget _buildDateSeparator(DateTime timestamp) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatDateSeparator(timestamp),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
        ],
      ),
    );
  }

  /// 判斷是否顯示日期分隔線
  bool _shouldShowDateSeparator(List<ChatMessage> messages, int index) {
    if (index == messages.length - 1) return true; // 最後一則訊息（最舊的）總是顯示

    final currentMessage = messages[index];
    final previousMessage = messages[index + 1];

    final currentDate = DateTime(
      currentMessage.timestamp.year,
      currentMessage.timestamp.month,
      currentMessage.timestamp.day,
    );
    final previousDate = DateTime(
      previousMessage.timestamp.year,
      previousMessage.timestamp.month,
      previousMessage.timestamp.day,
    );

    // 如果日期不同，顯示日期分隔線
    return currentDate != previousDate;
  }

  /// 格式化日期分隔線
  String _formatDateSeparator(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );

    if (messageDate == today) {
      return '今天';
    } else if (messageDate == yesterday) {
      return '昨天';
    } else if (now.difference(messageDate).inDays < 7) {
      // 一週內顯示星期
      const weekdays = ['', '週一', '週二', '週三', '週四', '週五', '週六', '週日'];
      return weekdays[messageDate.weekday];
    } else if (messageDate.year == now.year) {
      // 同年顯示月日
      return '${messageDate.month}月${messageDate.day}日';
    } else {
      // 不同年顯示完整日期
      return '${messageDate.year}年${messageDate.month}月${messageDate.day}日';
    }
  }

  /// 格式化訊息時間（顯示在訊息氣泡旁）
  String _formatMessageTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// 建立訊息輸入區域
  Widget _buildMessageInput() {
    // 如果聊天室已失去聯繫，顯示特殊的UI
    if (widget.chatRoom.isConnectionLost) {
      return _buildConnectionLostInput();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: '輸入訊息...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onChanged: (text) {
                  _isComposingNotifier.value = text.trim().isNotEmpty;
                },
                onSubmitted: (_) => _sendMessage(),
                maxLines: 3,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: _isComposingNotifier,
            builder: (context, isComposing, child) {
              return Container(
                decoration: BoxDecoration(
                  color: isComposing ? Colors.blue : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: isComposing ? _sendMessage : null,
                  icon: const Icon(Icons.send),
                  color: Colors.white,
                  splashRadius: 24,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 建立失去聯繫時的輸入區域
  Widget _buildConnectionLostInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '聊天已結束',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 刪除按鈕
          TextButton.icon(
            onPressed: _showDeleteConnectionLostChatRoom,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('刪除'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// 顯示刪除失去聯繫聊天室的確認對話框
  void _showDeleteConnectionLostChatRoom() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('刪除聊天室'),
          content: Text(
            '確定要刪除「${widget.chatRoom.taskTitle}」的聊天室嗎？',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteConnectionLostChatRoom();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );
  }

  /// 刪除失去聯繫的聊天室
  Future<void> _deleteConnectionLostChatRoom() async {
    try {
      await ChatService.deleteChatRoom(widget.chatRoom.id);

      if (mounted) {
        Navigator.of(context).pop(); // 返回聊天室列表
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('聊天室「${widget.chatRoom.taskTitle}」已刪除'),
            backgroundColor: Colors.green,
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

  /// 發送訊息
  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // 清空輸入框
    _messageController.clear();
    _isComposingNotifier.value = false;

    // 滾動到底部
    _scrollToBottom();

    try {
      await ChatService.sendMessage(chatId: widget.chatRoom.id, content: text);
    } catch (e) {
      print('發送訊息失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送訊息失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 建立任務快速預覽卡片
  Widget _buildTaskPreviewCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.chatRoom.taskId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              height: 80,
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
              child: const Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[600], size: 20),
                  const SizedBox(width: 8),
                  const Text('無法載入任務資訊'),
                ],
              ),
            );
          }

          final taskData = snapshot.data!.data() as Map<String, dynamic>;
          final price = taskData['price'];
          final date = taskData['date'];
          final time = taskData['time'];
          final address = taskData['address']?.toString() ?? '';

          // 格式化時間
          String timeText = '';
          if (date != null) {
            try {
              final dateTime = DateTime.parse(date);
              timeText = '${dateTime.month}/${dateTime.day}';

              if (time != null && time is Map) {
                final hour = time['hour']?.toString().padLeft(2, '0') ?? '00';
                final minute =
                    time['minute']?.toString().padLeft(2, '0') ?? '00';
                timeText += ' $hour:$minute';
              }
            } catch (e) {
              timeText = '時間未設定';
            }
          }

          return GestureDetector(
            onTap: _showTaskDetails,
            child: Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題和查看詳情圖標
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.chatRoom.taskTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[500],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 任務詳細信息
                  Row(
                    children: [
                      // 時間
                      if (timeText.isNotEmpty) ...[
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // 報酬
                      Icon(Icons.payments, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        price == null || price == 0 ? '免費' : 'NT\$ $price',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),

                  // 地址（如果有的話）
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 滾動到底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 顯示任務詳情
  void _showTaskDetails() async {
    try {
      // 顯示載入指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 查詢任務數據
      final taskDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.chatRoom.taskId)
          .get();

      // 關閉載入指示器
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (!taskDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('找不到任務資料'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final taskData = taskDoc.data()!;
      taskData['id'] = taskDoc.id;

      // 判斷當前用戶是否為 Parent
      final isParentView = currentUser?.uid == widget.chatRoom.parentId;

      // 顯示任務詳情頁面
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          enableDrag: true,
          backgroundColor: Colors.transparent,
          builder: (context) => TaskDetailSheet(
            taskData: taskData,
            isParentView: isParentView,
            hideBottomActions: true, // 從聊天室查看時隱藏底部按鈕
            hideApplicantsList: true, // 從聊天室查看時隱藏申請者清單
            onTaskUpdated: () {
              // 任務更新後可以選擇重新載入聊天室數據或其他處理
              print('任務已更新');
            },
          ),
        );
      }
    } catch (e) {
      // 關閉載入指示器（如果還在顯示）
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('載入任務詳情失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入任務詳情失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// 訊息氣泡組件
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isCurrentUser;
  final bool showTime;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isCurrentUser,
    this.showTime = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (message.type == 'system') {
      return _buildSystemMessage();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isCurrentUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[_buildAvatar(), const SizedBox(width: 8)],
          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isCurrentUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: isCurrentUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 自己訊息的時間（顯示在氣泡左側）
                    if (isCurrentUser && showTime)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: Text(
                          _formatMessageTime(),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    // 訊息氣泡
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrentUser ? Colors.blue : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 16,
                          color: isCurrentUser ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    // 對方訊息的時間（顯示在氣泡右側）
                    if (!isCurrentUser && showTime)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text(
                          _formatMessageTime(),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isCurrentUser) ...[const SizedBox(width: 8), _buildAvatar()],
        ],
      ),
    );
  }

  /// 格式化訊息時間
  String _formatMessageTime() {
    return '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
  }

  /// 建立系統訊息
  Widget _buildSystemMessage() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.content,
              style: TextStyle(fontSize: 14, color: Colors.amber[800]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 建立頭像（帶在線狀態）
  Widget _buildAvatar() {
    return SimpleOnlineAvatar(
      userId: message.senderId,
      avatarUrl: message.senderAvatar.isNotEmpty ? message.senderAvatar : null,
      size: 32,
      showOnlineStatus: !isCurrentUser, // 只為對方顯示在線狀態
    );
  }
}
