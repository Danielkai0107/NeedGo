import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 聊天室數據模型
class ChatRoom {
  final String id;
  final String parentId;
  final String playerId;
  final String taskId;
  final String taskTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMessage;
  final String lastMessageSender;
  final Map<String, int> unreadCount;
  final bool isActive;

  ChatRoom({
    required this.id,
    required this.parentId,
    required this.playerId,
    required this.taskId,
    required this.taskTitle,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessage,
    required this.lastMessageSender,
    required this.unreadCount,
    this.isActive = true,
  });

  factory ChatRoom.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('聊天室數據為空');
      }

      return ChatRoom(
        id: doc.id,
        parentId: data['parentId']?.toString() ?? '',
        playerId: data['playerId']?.toString() ?? '',
        taskId: data['taskId']?.toString() ?? '',
        taskTitle: data['taskTitle']?.toString() ?? '',
        createdAt: data['createdAt'] != null
            ? (data['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
        updatedAt: data['updatedAt'] != null
            ? (data['updatedAt'] as Timestamp).toDate()
            : DateTime.now(),
        lastMessage: data['lastMessage']?.toString() ?? '',
        lastMessageSender: data['lastMessageSender']?.toString() ?? '',
        unreadCount: data['unreadCount'] != null
            ? Map<String, int>.from(data['unreadCount'])
            : {},
        isActive: data['isActive'] ?? true,
      );
    } catch (e) {
      print('解析聊天室數據失敗: $e');
      throw Exception('無法解析聊天室數據: $e');
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'parentId': parentId,
      'playerId': playerId,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessage': lastMessage,
      'lastMessageSender': lastMessageSender,
      'unreadCount': unreadCount,
      'isActive': isActive,
      'participants': [parentId, playerId], // 用於查詢
    };
  }
}

/// 訊息數據模型
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String content;
  final DateTime timestamp;
  final String type;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.content,
    required this.timestamp,
    this.type = 'text',
    this.isRead = false,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('訊息數據為空');
      }

      return ChatMessage(
        id: doc.id,
        senderId: data['senderId']?.toString() ?? '',
        senderName: data['senderName']?.toString() ?? '',
        senderAvatar: data['senderAvatar']?.toString() ?? '',
        content: data['content']?.toString() ?? '',
        timestamp: data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now(),
        type: data['type']?.toString() ?? 'text',
        isRead: data['isRead'] ?? false,
      );
    } catch (e) {
      print('解析訊息數據失敗: $e');
      throw Exception('無法解析訊息數據: $e');
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'isRead': isRead,
    };
  }
}

/// 聊天服務類
class ChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 創建或獲取聊天室
  static Future<String> createOrGetChatRoom({
    required String parentId,
    required String playerId,
    required String taskId,
    required String taskTitle,
  }) async {
    final chatId = "${parentId}_${playerId}_$taskId";
    final chatRef = _firestore.collection('chats').doc(chatId);

    final doc = await chatRef.get();

    if (!doc.exists) {
      // 創建新聊天室
      final chatRoom = ChatRoom(
        id: chatId,
        parentId: parentId,
        playerId: playerId,
        taskId: taskId,
        taskTitle: taskTitle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessage: '聊天室已建立',
        lastMessageSender: 'system',
        unreadCount: {parentId: 0, playerId: 0},
      );

      await chatRef.set(chatRoom.toFirestore());

      // 發送系統歡迎訊息
      await _sendSystemWelcomeMessage(chatId, taskTitle);

      print('✅ 聊天室創建成功: $chatId');
    }

    return chatId;
  }

  /// 發送系統歡迎訊息
  static Future<void> _sendSystemWelcomeMessage(
    String chatId,
    String taskTitle,
  ) async {
    final welcomeMessage = ChatMessage(
      id: '',
      senderId: 'system',
      senderName: '系統',
      senderAvatar: '',
      content: '歡迎使用聊天室！您可以在這裡討論關於「$taskTitle」的詳細內容。',
      timestamp: DateTime.now(),
      type: 'system',
      isRead: true,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(welcomeMessage.toFirestore());
  }

  /// 發送訊息
  static Future<void> sendMessage({
    required String chatId,
    required String content,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('用戶未登入');

    // 獲取發送者資訊
    final userDoc = await _firestore
        .collection('user')
        .doc(currentUser.uid)
        .get();
    final userData = userDoc.data() ?? {};

    final message = ChatMessage(
      id: '',
      senderId: currentUser.uid,
      senderName: userData['name'] ?? '未知用戶',
      senderAvatar: userData['avatarUrl'] ?? '',
      content: content.trim(),
      timestamp: DateTime.now(),
      type: 'text',
      isRead: false,
    );

    // 添加訊息到子集合
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(message.toFirestore());

    // 更新聊天室最後訊息資訊
    await _updateChatRoomLastMessage(chatId, content, currentUser.uid);

    print('✅ 訊息發送成功');
  }

  /// 更新聊天室最後訊息
  static Future<void> _updateChatRoomLastMessage(
    String chatId,
    String lastMessage,
    String senderId,
  ) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();

    if (chatDoc.exists) {
      final data = chatDoc.data()!;
      final unreadCount = Map<String, int>.from(data['unreadCount'] ?? {});

      // 更新對方的未讀數量
      for (String userId in unreadCount.keys) {
        if (userId != senderId) {
          unreadCount[userId] = (unreadCount[userId] ?? 0) + 1;
        }
      }

      await chatRef.update({
        'lastMessage': lastMessage,
        'lastMessageSender': senderId,
        'updatedAt': Timestamp.now(),
        'unreadCount': unreadCount,
      });
    }
  }

  /// 標記訊息為已讀
  static Future<void> markMessagesAsRead(String chatId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // 重置該用戶的未讀數量
    final chatRef = _firestore.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();

    if (chatDoc.exists) {
      final data = chatDoc.data()!;
      final unreadCount = Map<String, int>.from(data['unreadCount'] ?? {});
      unreadCount[currentUser.uid] = 0;

      await chatRef.update({'unreadCount': unreadCount});
      print('✅ 訊息已標記為已讀');
    }
  }

  /// 獲取用戶的所有聊天室
  static Stream<List<ChatRoom>> getUserChatRooms() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    try {
      return _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .where('isActive', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .map((snapshot) {
            final chatRooms = <ChatRoom>[];
            for (var doc in snapshot.docs) {
              try {
                chatRooms.add(ChatRoom.fromFirestore(doc));
              } catch (e) {
                print('跳過無效的聊天室數據: ${doc.id}, 錯誤: $e');
              }
            }
            return chatRooms;
          });
    } catch (e) {
      print('獲取聊天室失敗: $e');
      return Stream.value([]);
    }
  }

  /// 監聽聊天室訊息
  static Stream<List<ChatMessage>> getChatMessages(String chatId) {
    try {
      return _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(50) // 限制載入數量，後續可實作分頁
          .snapshots()
          .map((snapshot) {
            final messages = <ChatMessage>[];
            for (var doc in snapshot.docs) {
              try {
                messages.add(ChatMessage.fromFirestore(doc));
              } catch (e) {
                print('跳過無效的訊息數據: ${doc.id}, 錯誤: $e');
              }
            }
            return messages;
          });
    } catch (e) {
      print('獲取聊天訊息失敗: $e');
      return Stream.value([]);
    }
  }

  /// 獲取用戶總未讀訊息數
  static Stream<int> getTotalUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    try {
      return _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
            try {
              int totalUnread = 0;
              for (var doc in snapshot.docs) {
                try {
                  final data = doc.data();
                  final unreadCount = Map<String, int>.from(
                    data['unreadCount'] ?? {},
                  );
                  totalUnread += unreadCount[currentUser.uid] ?? 0;
                } catch (e) {
                  print('處理未讀數量失敗: ${doc.id}, 錯誤: $e');
                }
              }
              return totalUnread;
            } catch (e) {
              print('計算總未讀數量失敗: $e');
              return 0;
            }
          });
    } catch (e) {
      print('獲取未讀數量失敗: $e');
      return Stream.value(0);
    }
  }

  /// 檢查是否存在聊天室
  static Future<bool> chatRoomExists({
    required String parentId,
    required String playerId,
    required String taskId,
  }) async {
    final chatId = "${parentId}_${playerId}_$taskId";
    final doc = await _firestore.collection('chats').doc(chatId).get();
    return doc.exists;
  }

  /// 獲取聊天室資訊
  static Future<ChatRoom?> getChatRoomInfo(String chatId) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    if (doc.exists) {
      return ChatRoom.fromFirestore(doc);
    }
    return null;
  }
}
