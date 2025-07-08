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

  // 系統配置緩存
  static int? _cachedChatCloseTimer;
  static DateTime? _cacheExpiry;

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

  /// 發送系統訊息
  static Future<void> sendSystemMessage({
    required String chatId,
    required String content,
  }) async {
    try {
      final systemMessage = ChatMessage(
        id: '',
        senderId: 'system',
        senderName: '系統',
        senderAvatar: '',
        content: content,
        timestamp: DateTime.now(),
        type: 'system',
        isRead: true,
      );

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(systemMessage.toFirestore());

      // 更新聊天室最後訊息資訊
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': content,
        'lastMessageSender': 'system',
        'updatedAt': Timestamp.now(),
      });

      print('✅ 系統訊息發送成功: $chatId');
    } catch (e) {
      print('發送系統訊息失敗: $e');
      throw Exception('發送系統訊息失敗: $e');
    }
  }

  /// 發送聊天室關閉提醒訊息
  static Future<void> sendChatRoomCloseReminder(String taskId) async {
    try {
      // 獲取聊天室關閉時間配置
      final closeTimeMinutes = await _getChatCloseTimer();

      // 查找與此任務相關的所有聊天室
      final chatRoomsSnapshot = await _firestore
          .collection('chats')
          .where('taskId', isEqualTo: taskId)
          .where('isActive', isEqualTo: true)
          .get();

      if (chatRoomsSnapshot.docs.isEmpty) {
        print('📭 任務 $taskId 沒有找到相關的聊天室');
        return;
      }

      final reminderMessage = '活動已結束，聊天室將在 $closeTimeMinutes 分鐘後關閉。';

      // 為每個聊天室發送提醒訊息
      for (var chatDoc in chatRoomsSnapshot.docs) {
        final chatId = chatDoc.id;

        await sendSystemMessage(chatId: chatId, content: reminderMessage);

        print('📢 已發送聊天室關閉提醒: $chatId');
      }

      print('✅ 任務 $taskId 的所有聊天室關閉提醒已發送完成');
    } catch (e) {
      print('❌ 發送聊天室關閉提醒失敗: $e');
    }
  }

  /// 發送任務過期聊天室關閉提醒
  static Future<void> sendTaskExpiredChatCloseReminder(String taskId) async {
    try {
      // 獲取聊天室關閉時間配置
      final closeTimeMinutes = await _getChatCloseTimer();

      // 查找與此任務相關的所有聊天室
      final chatRoomsSnapshot = await _firestore
          .collection('chats')
          .where('taskId', isEqualTo: taskId)
          .where('isActive', isEqualTo: true)
          .get();

      if (chatRoomsSnapshot.docs.isEmpty) {
        print('📭 過期任務 $taskId 沒有找到相關的聊天室');
        return;
      }

      final reminderMessage = '任務已過期，聊天室將在 $closeTimeMinutes 分鐘後關閉。';

      // 為每個聊天室發送提醒訊息
      for (var chatDoc in chatRoomsSnapshot.docs) {
        final chatId = chatDoc.id;

        await sendSystemMessage(chatId: chatId, content: reminderMessage);

        print('📢 已發送過期任務聊天室關閉提醒: $chatId');
      }

      print('✅ 過期任務 $taskId 的所有聊天室關閉提醒已發送完成');
    } catch (e) {
      print('❌ 發送過期任務聊天室關閉提醒失敗: $e');
    }
  }

  /// 發送個人化的系統訊息
  static Future<void> _sendPersonalizedSystemMessage({
    required String chatId,
    required String parentId,
    required String playerId,
    required String parentName,
    required String playerName,
  }) async {
    try {
      // 為發布者發送一條個人化訊息
      final parentMessage = ChatMessage(
        id: '',
        senderId: 'system',
        senderName: '系統',
        senderAvatar: '',
        content: '你和 $playerName 已失去聯繫，他可能取消了配對或刪除帳號。',
        timestamp: DateTime.now(),
        type: 'system',
        isRead: true,
      );

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(parentMessage.toFirestore());

      // 延遲一秒後發送陪伴者的訊息
      await Future.delayed(const Duration(seconds: 1));

      final playerMessage = ChatMessage(
        id: '',
        senderId: 'system',
        senderName: '系統',
        senderAvatar: '',
        content: '你和 $parentName 已失去聯繫，他可能取消了配對或刪除帳號。',
        timestamp: DateTime.now(),
        type: 'system',
        isRead: true,
      );

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(playerMessage.toFirestore());

      // 更新聊天室最後訊息資訊
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': '聯繫已失去',
        'lastMessageSender': 'system',
        'updatedAt': Timestamp.now(),
      });

      print('✅ 個人化系統訊息發送成功: $chatId');
    } catch (e) {
      print('發送個人化系統訊息失敗: $e');
      throw Exception('發送個人化系統訊息失敗: $e');
    }
  }

  /// 清空聊天室訊息
  static Future<void> clearChatRoomMessages(String chatId) async {
    try {
      // 獲取聊天室的所有訊息
      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      // 批量刪除所有訊息
      final batch = _firestore.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      print('✅ 聊天室訊息已清空: $chatId');
    } catch (e) {
      print('清空聊天室訊息失敗: $e');
      throw Exception('清空聊天室訊息失敗: $e');
    }
  }

  /// 從系統配置獲取聊天室關閉時間（分鐘）
  static Future<int> _getChatCloseTimer() async {
    try {
      // 檢查緩存是否有效（緩存5分鐘）
      final now = DateTime.now();
      if (_cachedChatCloseTimer != null &&
          _cacheExpiry != null &&
          now.isBefore(_cacheExpiry!)) {
        print('✅ 使用緩存的聊天室關閉時間: ${_cachedChatCloseTimer}分鐘');
        return _cachedChatCloseTimer!;
      }

      final systemDoc = await _firestore
          .collection('system')
          .doc('DtLX3K2FgJEGWvguqplh')
          .get();

      if (systemDoc.exists) {
        final systemData = systemDoc.data()!;
        final chatCloseTimer = systemData['chatCloseTimer'] as int?;

        if (chatCloseTimer != null && chatCloseTimer > 0) {
          // 更新緩存
          _cachedChatCloseTimer = chatCloseTimer;
          _cacheExpiry = now.add(const Duration(minutes: 5));

          print('✅ 從資料庫獲取聊天室關閉時間: ${chatCloseTimer}分鐘 (已緩存)');
          return chatCloseTimer;
        }
      }

      // 如果無法獲取配置，使用預設值 1440 分鐘（24小時），但不緩存
      print('⚠️ 無法獲取聊天室關閉時間配置，使用預設值: 1440分鐘');
      return 1440;
    } catch (e) {
      print('❌ 獲取系統配置失敗: $e，使用預設值: 1440分鐘');
      return 1440;
    }
  }

  /// 檢查任務是否已完成超過指定時間
  static Future<bool> isTaskCompletedForConfiguredTime(String taskId) async {
    try {
      // 獲取系統配置的關閉時間
      final closeTimeMinutes = await _getChatCloseTimer();

      final taskDoc = await _firestore.collection('posts').doc(taskId).get();

      if (!taskDoc.exists) {
        return false;
      }

      final taskData = taskDoc.data()!;
      final status = taskData['status'] ?? '';
      final completedAt = taskData['completedAt'] as Timestamp?;
      final expiredAt = taskData['expiredAt'] as Timestamp?;

      // 檢查任務是否已完成超過配置的時間
      if (status == 'completed' && completedAt != null) {
        final completedTime = completedAt.toDate();
        final now = DateTime.now();
        final difference = now.difference(completedTime);
        final isExpired = difference.inMinutes >= closeTimeMinutes;
        print(
          '📅 任務完成於: $completedTime, 已過 ${difference.inMinutes} 分鐘, 配置: ${closeTimeMinutes}分鐘, 需清理: $isExpired',
        );
        return isExpired;
      }

      // 檢查任務是否已過期超過配置的時間
      if (status == 'expired' && expiredAt != null) {
        final expiredTime = expiredAt.toDate();
        final now = DateTime.now();
        final difference = now.difference(expiredTime);
        final isExpired = difference.inMinutes >= closeTimeMinutes;
        print(
          '📅 任務過期於: $expiredTime, 已過 ${difference.inMinutes} 分鐘, 配置: ${closeTimeMinutes}分鐘, 需清理: $isExpired',
        );
        return isExpired;
      }

      // 如果任務狀態不是 completed 或 expired，則不應該清理聊天室
      // 即使任務日期已過，但任務可能仍在進行中
      print('📅 任務狀態: $status，不需要清理聊天室（任務未完成或過期）');
      return false;
    } catch (e) {
      print('檢查任務完成狀態失敗: $e');
      return false;
    }
  }

  /// 檢查並清理過期的聊天室
  static Future<void> checkAndCleanupExpiredChatRooms() async {
    try {
      print('🧹 開始檢查過期的聊天室...');

      // 獲取所有活躍的聊天室
      final chatRoomsSnapshot = await _firestore
          .collection('chats')
          .where('isActive', isEqualTo: true)
          .get();

      int cleanedCount = 0;

      for (var chatDoc in chatRoomsSnapshot.docs) {
        final chatData = chatDoc.data();
        final chatId = chatDoc.id;
        final taskId = chatData['taskId'] as String?;
        final parentId = chatData['parentId'] as String?;
        final playerId = chatData['playerId'] as String?;

        if (taskId == null || parentId == null || playerId == null) {
          continue;
        }

        // 檢查任務是否已完成超過配置的時間
        final shouldCleanup = await isTaskCompletedForConfiguredTime(taskId);

        if (shouldCleanup) {
          print('🧹 清理過期聊天室: $chatId');

          // 清空聊天室訊息
          await clearChatRoomMessages(chatId);

          // 獲取用戶名稱
          final parentInfo = await getUserInfo(parentId);
          final playerInfo = await getUserInfo(playerId);

          final parentName = parentInfo?['name'] ?? '用戶';
          final playerName = playerInfo?['name'] ?? '用戶';

          // 為每個用戶發送個人化的系統訊息
          await _sendPersonalizedSystemMessage(
            chatId: chatId,
            parentId: parentId,
            playerId: playerId,
            parentName: parentName,
            playerName: playerName,
          );

          // 標記聊天室為已清理
          await _firestore.collection('chats').doc(chatId).update({
            'isCleanedUp': true,
            'cleanedUpAt': Timestamp.now(),
          });

          cleanedCount++;
        }
      }

      print('✅ 聊天室清理完成，共清理 $cleanedCount 個聊天室');
    } catch (e) {
      print('❌ 清理過期聊天室失敗: $e');
    }
  }

  /// 啟動聊天室清理定時器
  static Timer? _cleanupTimer;

  static void startChatRoomCleanupTimer() {
    // 每小時檢查一次
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      checkAndCleanupExpiredChatRooms();
    });

    // 立即執行一次
    checkAndCleanupExpiredChatRooms();

    print('✅ 聊天室清理定時器已啟動');
  }

  static void stopChatRoomCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    print('✅ 聊天室清理定時器已停止');
  }

  /// 立即觸發聊天室清理（用於測試）
  static Future<void> triggerChatRoomCleanupNow() async {
    print('🧹 手動觸發聊天室清理...');
    // 清除緩存以獲取最新配置
    _cachedChatCloseTimer = null;
    _cacheExpiry = null;
    await checkAndCleanupExpiredChatRooms();
  }

  /// 清除系統配置緩存
  static void clearSystemConfigCache() {
    _cachedChatCloseTimer = null;
    _cacheExpiry = null;
    print('🧹 系統配置緩存已清除');
  }

  /// 獲取當前緩存的聊天室關閉時間（用於調試）
  static int? getCachedChatCloseTimer() {
    if (_cachedChatCloseTimer != null &&
        _cacheExpiry != null &&
        DateTime.now().isBefore(_cacheExpiry!)) {
      return _cachedChatCloseTimer;
    }
    return null;
  }

  /// 檢查指定聊天室是否需要清理（用於測試）
  static Future<bool> shouldCleanupChatRoom(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return false;

      final chatData = chatDoc.data()!;
      final taskId = chatData['taskId'] as String?;

      if (taskId == null) return false;

      return await isTaskCompletedForConfiguredTime(taskId);
    } catch (e) {
      print('檢查聊天室清理狀態失敗: $e');
      return false;
    }
  }
}
