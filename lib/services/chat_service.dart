import 'dart:async';
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

  // 用於管理活動的監聽器
  static final Map<String, StreamSubscription> _activeListeners = {};
  
  /// 清理所有活動的監聽器
  static Future<void> cancelAllListeners() async {
    print('🧹 開始清理所有聊天服務監聽器...');
    
    final futures = <Future>[];
    for (final subscription in _activeListeners.values) {
      futures.add(subscription.cancel());
    }
    
    await Future.wait(futures);
    _activeListeners.clear();
    
    print('✅ 所有聊天服務監聽器已清理');
  }
  
  /// 添加監聽器到管理器
  static void addListener(String key, StreamSubscription subscription) {
    // 如果已存在同key的監聽器，先取消舊的
    _activeListeners[key]?.cancel();
    _activeListeners[key] = subscription;
  }
  
  /// 移除特定監聽器
  static void removeListener(String key) {
    _activeListeners[key]?.cancel();
    _activeListeners.remove(key);
  }

  /// 更新用戶在線狀態
  static Future<void> updateOnlineStatus(bool isOnline) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final userDocRef = _firestore.collection('user').doc(currentUser.uid);
      final userDoc = await userDocRef.get();

      if (userDoc.exists) {
        // 用戶文檔存在，更新在線狀態
        await userDocRef.update({
          'isOnline': isOnline,
          'lastSeen': Timestamp.now(),
        });
        print('✅ 在線狀態已更新: ${isOnline ? "在線" : "離線"}');
      } else {
        // 用戶文檔不存在，跳過更新（可能正在註冊過程中）
        print('⚠️ 用戶文檔不存在，跳過在線狀態更新');
      }
    } catch (e) {
      print('❌ 更新在線狀態失敗: $e');
    }
  }

  /// 監聽用戶在線狀態
  static Stream<bool> getUserOnlineStatus(String userId) {
    return _firestore.collection('user').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data();
      final isOnline = data?['isOnline'] ?? false;
      final lastSeen = data?['lastSeen'] as Timestamp?;

      // 如果顯示為在線，但最後活動時間超過5分鐘，認為離線
      if (isOnline && lastSeen != null) {
        final lastSeenTime = lastSeen.toDate();
        final now = DateTime.now();
        final difference = now.difference(lastSeenTime);
        return difference.inMinutes < 5;
      }

      return isOnline;
    });
  }

  /// 獲取用戶資訊（包含在線狀態）
  static Future<Map<String, dynamic>?> getUserInfo(String userId) async {
    try {
      final doc = await _firestore.collection('user').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['uid'] = userId;
        return data;
      }
      return null;
    } catch (e) {
      print('獲取用戶資訊失敗: $e');
      return null;
    }
  }

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
      // 暫時使用單一條件查詢，避免索引問題
      return _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots()
          .map((snapshot) {
            final chatRooms = <ChatRoom>[];
            for (var doc in snapshot.docs) {
              try {
                final chatRoom = ChatRoom.fromFirestore(doc);
                // 在應用層過濾活躍的聊天室
                if (chatRoom.isActive) {
                  chatRooms.add(chatRoom);
                }
              } catch (e) {
                print('跳過無效的聊天室數據: ${doc.id}, 錯誤: $e');
              }
            }
            // 在應用層排序
            chatRooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
          .snapshots()
          .map((snapshot) {
            try {
              int totalUnread = 0;
              for (var doc in snapshot.docs) {
                try {
                  final data = doc.data();
                  final isActive = data['isActive'] ?? true;
                  if (!isActive) continue; // 只計算活躍的聊天室

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

  /// 獲取 Parent 角色的未讀訊息數（我作為發布者）
  static Stream<int> getParentUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    try {
      return _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots()
          .map((snapshot) {
            try {
              int totalUnread = 0;
              for (var doc in snapshot.docs) {
                try {
                  final data = doc.data();
                  final isActive = data['isActive'] ?? true;
                  if (!isActive) continue;

                  final parentId = data['parentId']?.toString() ?? '';
                  // 只計算我是 Parent 的聊天室
                  if (parentId == currentUser.uid) {
                    final unreadCount = Map<String, int>.from(
                      data['unreadCount'] ?? {},
                    );
                    totalUnread += unreadCount[currentUser.uid] ?? 0;
                  }
                } catch (e) {
                  print('處理 Parent 未讀數量失敗: ${doc.id}, 錯誤: $e');
                }
              }
              return totalUnread;
            } catch (e) {
              print('計算 Parent 總未讀數量失敗: $e');
              return 0;
            }
          });
    } catch (e) {
      print('獲取 Parent 未讀數量失敗: $e');
      return Stream.value(0);
    }
  }

  /// 獲取 Player 角色的未讀訊息數（我作為陪伴者）
  static Stream<int> getPlayerUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    try {
      return _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots()
          .map((snapshot) {
            try {
              int totalUnread = 0;
              for (var doc in snapshot.docs) {
                try {
                  final data = doc.data();
                  final isActive = data['isActive'] ?? true;
                  if (!isActive) continue;

                  final playerId = data['playerId']?.toString() ?? '';
                  // 只計算我是 Player 的聊天室
                  if (playerId == currentUser.uid) {
                    final unreadCount = Map<String, int>.from(
                      data['unreadCount'] ?? {},
                    );
                    totalUnread += unreadCount[currentUser.uid] ?? 0;
                  }
                } catch (e) {
                  print('處理 Player 未讀數量失敗: ${doc.id}, 錯誤: $e');
                }
              }
              return totalUnread;
            } catch (e) {
              print('計算 Player 總未讀數量失敗: $e');
              return 0;
            }
          });
    } catch (e) {
      print('獲取 Player 未讀數量失敗: $e');
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

  /// 刪除聊天室
  static Future<void> deleteChatRoom(String chatId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('用戶未登入');

      // 軟刪除：將聊天室標記為不活躍
      await _firestore.collection('chats').doc(chatId).update({
        'isActive': false,
        'deletedAt': Timestamp.now(),
        'deletedBy': currentUser.uid,
      });

      print('✅ 聊天室已刪除: $chatId');
    } catch (e) {
      print('刪除聊天室失敗: $e');
      throw Exception('刪除聊天室失敗: $e');
    }
  }

  /// 恢復聊天室
  static Future<void> restoreChatRoom(String chatId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'isActive': true,
        'deletedAt': FieldValue.delete(),
        'deletedBy': FieldValue.delete(),
      });

      print('✅ 聊天室已恢復: $chatId');
    } catch (e) {
      print('恢復聊天室失敗: $e');
      throw Exception('恢復聊天室失敗: $e');
    }
  }
}
