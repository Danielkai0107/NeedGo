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
  final bool isConnectionLost;
  final List<String> hiddenBy; // 記錄隱藏此聊天室的用戶ID列表
  final List<String> visibleTo; // 記錄可以看到此聊天室的用戶ID列表

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
    this.isConnectionLost = false,
    this.hiddenBy = const [], // 默認沒有被任何用戶隱藏
    this.visibleTo = const [], // 默認沒有對任何用戶可見（需要在創建時指定）
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
        isConnectionLost: data['isConnectionLost'] ?? false,
        hiddenBy: data['hiddenBy'] != null
            ? List<String>.from(data['hiddenBy'])
            : [],
        visibleTo: data['visibleTo'] != null
            ? List<String>.from(data['visibleTo'])
            : [
                data['parentId']?.toString() ?? '',
                data['playerId']?.toString() ?? '',
              ].where((id) => id.isNotEmpty).toList(),
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
      'hiddenBy': hiddenBy, // 記錄隱藏此聊天室的用戶ID列表
      'visibleTo': visibleTo, // 記錄可以看到此聊天室的用戶ID列表
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
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('用戶未登入');

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
        visibleTo: [currentUser.uid], // 只對創建者可見
      );

      await chatRef.set(chatRoom.toFirestore());

      // 創建時就發送系統歡迎訊息
      await _sendSystemWelcomeMessage(chatId, taskTitle);

      print('✅ 聊天室創建成功: $chatId (只對創建者 ${currentUser.uid} 可見)');
    } else {
      // 聊天室已存在，檢查是否被當前用戶隱藏
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final chatData = doc.data()!;
        final hiddenBy = List<String>.from(chatData['hiddenBy'] ?? []);

        print('📋 聊天室 $chatId 已存在');
        print('🔍 被隱藏的用戶列表: $hiddenBy');
        print('👤 當前用戶: ${currentUser.uid}');

        // 如果當前用戶隱藏了此聊天室，嘗試智能恢復
        if (hiddenBy.contains(currentUser.uid)) {
          print('🔄 檢測到聊天室被當前用戶隱藏，嘗試恢復...');
          final restored = await smartRestoreChatRoom(chatId);
          if (restored) {
            print('✅ 聊天室已自動恢復: $chatId（任務進行中）');

            // 為了確保 Stream 更新，觸發聊天室數據的輕微更新
            await _firestore.collection('chats').doc(chatId).update({
              'updatedAt': Timestamp.now(),
            });
            print('🔄 已觸發聊天室列表更新');
          } else {
            print('⚠️ 聊天室無法恢復: $chatId（任務可能已完成或過期）');
          }
        } else {
          print('ℹ️ 聊天室未被當前用戶隱藏，無需恢復');
        }
      }
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

    // 檢查是否是第一則真實訊息，如果是則讓聊天室對所有人可見
    await _checkAndUpdateChatRoomVisibility(chatId);

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

  /// 檢查並更新聊天室可見性（在發送第一則真實訊息時）
  static Future<void> _checkAndUpdateChatRoomVisibility(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return;

      final chatData = chatDoc.data()!;
      final visibleTo = List<String>.from(chatData['visibleTo'] ?? []);
      final parentId = chatData['parentId'] as String?;
      final playerId = chatData['playerId'] as String?;
      final taskTitle = chatData['taskTitle'] as String?;

      if (parentId == null || playerId == null) return;

      // 檢查是否只有一個用戶可見（創建者可見）
      if (visibleTo.length == 1) {
        print('🔍 檢測到聊天室只對創建者可見，準備讓所有參與者可見: $chatId');

        // 更新聊天室為所有參與者可見
        await _firestore.collection('chats').doc(chatId).update({
          'visibleTo': [parentId, playerId],
          'updatedAt': Timestamp.now(),
        });

        print('✅ 聊天室已設置為對所有參與者可見: $chatId');
      }
    } catch (e) {
      print('❌ 更新聊天室可見性失敗: $e');
    }
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
      final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);
      final taskId = data['taskId'] as String?;

      // 更新對方的未讀數量
      for (String userId in unreadCount.keys) {
        if (userId != senderId) {
          unreadCount[userId] = (unreadCount[userId] ?? 0) + 1;
        }
      }

      // 檢查是否有用戶隱藏了此聊天室，如果有新訊息且任務仍在進行中，自動恢復聊天室
      List<String> updatedHiddenBy = List.from(hiddenBy);
      if (hiddenBy.isNotEmpty && taskId != null) {
        print('🔍 檢測到聊天室 $chatId 被 ${hiddenBy.length} 個用戶隱藏，檢查是否需要恢復...');

        // 檢查任務是否仍在進行中
        final isActive = await isTaskActive(taskId);
        print('📊 任務 $taskId 活躍狀態: $isActive');

        if (isActive) {
          // 任務仍在進行中，將所有隱藏用戶從列表中移除（恢復聊天室）
          for (String hiddenUserId in hiddenBy) {
            if (hiddenUserId != senderId) {
              // 不是發送者的用戶才需要恢復
              updatedHiddenBy.remove(hiddenUserId);
              print('🔄 自動恢復聊天室給用戶: $hiddenUserId');
            }
          }
        } else {
          print('⚠️ 任務已完成或過期，不恢復聊天室');
        }
      }

      // 更新聊天室資訊
      await chatRef.update({
        'lastMessage': lastMessage,
        'lastMessageSender': senderId,
        'updatedAt': Timestamp.now(),
        'unreadCount': unreadCount,
        'hiddenBy': updatedHiddenBy,
      });

      // 如果有聊天室被恢復，記錄日誌
      if (hiddenBy.length > updatedHiddenBy.length) {
        final restoredCount = hiddenBy.length - updatedHiddenBy.length;
        print('✅ 因新訊息自動恢復 $restoredCount 個用戶的聊天室: $chatId');
      }
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
                // 在應用層過濾活躍的聊天室，並且沒有被當前用戶隱藏，且對當前用戶可見
                if (chatRoom.isActive &&
                    !chatRoom.hiddenBy.contains(currentUser.uid) &&
                    chatRoom.visibleTo.contains(currentUser.uid)) {
                  chatRooms.add(chatRoom);
                }
              } catch (e) {
                print('跳過無效的聊天室數據: ${doc.id}, 錯誤: $e');
              }
            }
            // 在應用層排序：已失去聯繫的聊天室排在最後
            chatRooms.sort((a, b) {
              // 首先按是否失去聯繫分組
              if (a.isConnectionLost && !b.isConnectionLost) {
                return 1; // a排在後面
              } else if (!a.isConnectionLost && b.isConnectionLost) {
                return -1; // a排在前面
              } else {
                // 同組內按更新時間排序（最新的在前）
                return b.updatedAt.compareTo(a.updatedAt);
              }
            });
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
                  final isConnectionLost = data['isConnectionLost'] ?? false;
                  final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);

                  // 跳過不活躍、失去聯繫或被當前用戶隱藏的聊天室
                  if (!isActive ||
                      isConnectionLost ||
                      hiddenBy.contains(currentUser.uid))
                    continue;

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
                  final isConnectionLost = data['isConnectionLost'] ?? false;
                  final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);

                  // 跳過不活躍、失去聯繫或被當前用戶隱藏的聊天室
                  if (!isActive ||
                      isConnectionLost ||
                      hiddenBy.contains(currentUser.uid))
                    continue;

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
                  final isConnectionLost = data['isConnectionLost'] ?? false;
                  final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);

                  // 跳過不活躍、失去聯繫或被當前用戶隱藏的聊天室
                  if (!isActive ||
                      isConnectionLost ||
                      hiddenBy.contains(currentUser.uid))
                    continue;

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

  /// 個人化隱藏聊天室
  static Future<void> deleteChatRoom(String chatId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('用戶未登入');

      // 個人化隱藏：將當前用戶加入到 hiddenBy 列表中
      await _firestore.collection('chats').doc(chatId).update({
        'hiddenBy': FieldValue.arrayUnion([currentUser.uid]),
      });

      print('✅ 聊天室已隱藏: $chatId（僅對用戶 ${currentUser.uid} 隱藏）');
    } catch (e) {
      print('隱藏聊天室失敗: $e');
      throw Exception('隱藏聊天室失敗: $e');
    }
  }

  /// 恢復聊天室（從個人隱藏列表中移除）
  static Future<void> restoreChatRoom(String chatId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('用戶未登入');

      // 從 hiddenBy 列表中移除當前用戶
      await _firestore.collection('chats').doc(chatId).update({
        'hiddenBy': FieldValue.arrayRemove([currentUser.uid]),
      });

      print('✅ 聊天室已恢復: $chatId（對用戶 ${currentUser.uid} 恢復顯示）');
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
        final isConnectionLost = chatData['isConnectionLost'] ?? false;
        final isCleanedUp = chatData['isCleanedUp'] ?? false;

        // 跳過已經失去聯繫或已清理的聊天室，避免重複處理
        if (isConnectionLost || isCleanedUp) {
          continue;
        }

        if (taskId == null || parentId == null || playerId == null) {
          continue;
        }

        // 檢查任務是否已完成超過配置的時間
        final shouldCleanup = await isTaskCompletedForConfiguredTime(taskId);

        if (shouldCleanup) {
          print('🧹 清理過期聊天室: $chatId');

          try {
            // 使用事務確保原子性操作
            await _firestore.runTransaction((transaction) async {
              // 重新讀取聊天室狀態
              final chatRef = _firestore.collection('chats').doc(chatId);
              final currentChatDoc = await transaction.get(chatRef);

              if (!currentChatDoc.exists) {
                print('⚠️ 聊天室已被刪除: $chatId');
                return;
              }

              final currentChatData = currentChatDoc.data()!;
              final currentIsConnectionLost =
                  currentChatData['isConnectionLost'] ?? false;
              final currentIsCleanedUp =
                  currentChatData['isCleanedUp'] ?? false;

              // 再次確認聊天室未被處理
              if (currentIsConnectionLost || currentIsCleanedUp) {
                print('⚠️ 聊天室已被其他進程處理: $chatId');
                return;
              }

              // 先標記為正在清理
              transaction.update(chatRef, {
                'isCleanedUp': true,
                'cleanedUpAt': Timestamp.now(),
              });
            });

            // 清空聊天室訊息
            await clearChatRoomMessages(chatId);

            // 發送失去聯繫訊息
            await _sendConnectionLostMessage(chatId);

            // 最終標記聊天室為已失去聯繫
            await _firestore.collection('chats').doc(chatId).update({
              'isConnectionLost': true,
              'lastMessage': '任務已結束，聊天室已關閉。',
              'lastMessageSender': 'system',
              'updatedAt': Timestamp.now(),
            });

            cleanedCount++;
            print('✅ 聊天室清理完成: $chatId');
          } catch (e) {
            print('❌ 清理聊天室 $chatId 失敗: $e');
            // 如果清理失敗，回滾 isCleanedUp 標記
            try {
              await _firestore.collection('chats').doc(chatId).update({
                'isCleanedUp': false,
              });
            } catch (rollbackError) {
              print('❌ 回滾清理標記失敗: $rollbackError');
            }
          }
        }
      }

      print('✅ 聊天室清理完成，共清理 $cleanedCount 個聊天室');
    } catch (e) {
      print('❌ 清理過期聊天室失敗: $e');
    }
  }

  /// 發送失去聯繫訊息（簡化版本，避免重複）
  static Future<void> _sendConnectionLostMessage(String chatId) async {
    try {
      // 檢查最近的訊息，避免重複發送相同的系統訊息
      final recentMessagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(3) // 檢查最近3條訊息
          .get();

      final targetContent = '任務已結束，聊天室已關閉。';

      // 檢查是否已有相同的系統訊息
      for (var doc in recentMessagesSnapshot.docs) {
        final messageData = doc.data();
        final senderId = messageData['senderId'] as String?;
        final content = messageData['content'] as String?;

        if (senderId == 'system' && content == targetContent) {
          print('⚠️ 聊天室 $chatId 已存在相同的系統訊息，跳過發送');
          return;
        }
      }

      final systemMessage = ChatMessage(
        id: '',
        senderId: 'system',
        senderName: '系統',
        senderAvatar: '',
        content: targetContent,
        timestamp: DateTime.now(),
        type: 'system',
        isRead: true,
      );

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(systemMessage.toFirestore());

      print('✅ 失去聯繫訊息發送成功: $chatId');
    } catch (e) {
      print('發送失去聯繫訊息失敗: $e');
      throw Exception('發送失去聯繫訊息失敗: $e');
    }
  }

  /// 啟動聊天室清理定時器
  static Timer? _cleanupTimer;

  static void startChatRoomCleanupTimer() {
    // 每5分鐘檢查一次，確保及時清理過期聊天室
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      checkAndCleanupExpiredChatRooms();
    });

    // 立即執行一次
    checkAndCleanupExpiredChatRooms();

    print('✅ 聊天室清理定時器已啟動（每5分鐘檢查一次）');
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

  /// 測試聊天室恢復功能（用於調試）
  static Future<Map<String, dynamic>> testChatRoomRestore(
    String taskId,
    String otherUserId,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return {'success': false, 'message': '用戶未登入'};
    }

    try {
      print('🧪 開始測試聊天室恢復功能');
      print('📋 測試參數:');
      print('   - 任務ID: $taskId');
      print('   - 對方用戶ID: $otherUserId');
      print('   - 當前用戶ID: ${currentUser.uid}');

      // 確定 parent 和 player 角色
      final isCurrentUserParent = true; // 假設當前用戶是發布者
      final parentId = isCurrentUserParent ? currentUser.uid : otherUserId;
      final playerId = isCurrentUserParent ? otherUserId : currentUser.uid;

      final chatId = "${parentId}_${playerId}_$taskId";
      print('🔍 生成的聊天室ID: $chatId');

      // 檢查聊天室是否存在
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        return {'success': false, 'message': '聊天室不存在: $chatId'};
      }

      final chatData = chatDoc.data()!;
      final hiddenBy = List<String>.from(chatData['hiddenBy'] ?? []);

      print('📊 聊天室當前狀態:');
      print('   - 是否活躍: ${chatData['isActive']}');
      print('   - 被隱藏用戶: $hiddenBy');
      print('   - 是否被當前用戶隱藏: ${hiddenBy.contains(currentUser.uid)}');

      // 檢查任務狀態
      final taskActive = await isTaskActive(taskId);
      print('📊 任務狀態: ${taskActive ? "活躍" : "非活躍"}');

      // 嘗試創建或恢復聊天室
      final resultChatId = await createOrGetChatRoom(
        parentId: parentId,
        playerId: playerId,
        taskId: taskId,
        taskTitle: '測試任務',
      );

      print('✅ 測試完成，聊天室ID: $resultChatId');

      return {
        'success': true,
        'message': '測試完成',
        'chatId': resultChatId,
        'wasHidden': hiddenBy.contains(currentUser.uid),
        'taskActive': taskActive,
      };
    } catch (e) {
      print('❌ 測試聊天室恢復功能失敗: $e');
      return {'success': false, 'message': '測試失敗: $e'};
    }
  }

  /// 檢查任務是否還在進行中（未完成且未過期）
  static Future<bool> isTaskActive(String taskId) async {
    try {
      print('🔍 檢查任務是否活躍: $taskId');

      final taskDoc = await _firestore.collection('posts').doc(taskId).get();
      if (!taskDoc.exists) {
        print('❌ 任務不存在: $taskId');
        return false;
      }

      final taskData = taskDoc.data()!;
      final rawStatus = taskData['status'] ?? 'open';
      final acceptedApplicant = taskData['acceptedApplicant'];
      final status = _getTaskStatus(taskData);

      print('📊 任務詳細信息:');
      print('   - 原始狀態: $rawStatus');
      print('   - 已接受申請者: $acceptedApplicant');
      print('   - 計算後狀態: $status');
      print('   - 是否過期: ${_isTaskExpiredNow(taskData)}');

      // 如果任務狀態為 open 或 accepted，則認為任務還在進行中
      final isActive = status == 'open' || status == 'accepted';
      print('✅ 任務活躍狀態結果: $isActive');

      return isActive;
    } catch (e) {
      print('❌ 檢查任務狀態失敗: $e');
      return false;
    }
  }

  /// 獲取任務狀態（包含過期檢查）
  static String _getTaskStatus(Map<String, dynamic> task) {
    if (task['status'] == 'completed') return 'completed';
    if (task['acceptedApplicant'] != null) return 'accepted';
    if (_isTaskExpiredNow(task)) return 'expired';
    return task['status'] ?? 'open';
  }

  /// 檢查任務是否已過期
  static bool _isTaskExpiredNow(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDateTime;
      final date = task['date'];
      final time = task['time'];

      // 解析日期
      if (date is String) {
        taskDateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDateTime = date;
      } else if (date is Timestamp) {
        taskDateTime = (date as Timestamp).toDate();
      } else {
        return false;
      }

      // 如果有時間資訊，使用精確時間
      if (time != null && time is Map) {
        final hour = time['hour'] ?? 0;
        final minute = time['minute'] ?? 0;
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          hour,
          minute,
        );
      } else {
        // 如果沒有時間資訊，設定為當天 23:59
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          23,
          59,
        );
      }

      final now = DateTime.now();
      return now.isAfter(taskDateTime);
    } catch (e) {
      print('檢查任務過期時間失敗: $e');
      return false;
    }
  }

  /// 智能恢復聊天室（根據任務狀態決定是否可以恢復）
  static Future<bool> smartRestoreChatRoom(String chatId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('用戶未登入');

      print('🔍 開始智能恢復聊天室: $chatId');

      // 獲取聊天室資訊
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        print('❌ 聊天室不存在: $chatId');
        return false;
      }

      final chatData = chatDoc.data()!;
      final taskId = chatData['taskId'] as String?;
      final hiddenBy = List<String>.from(chatData['hiddenBy'] ?? []);

      print('📋 聊天室信息:');
      print('   - 任務ID: $taskId');
      print('   - 被隱藏用戶: $hiddenBy');
      print('   - 當前用戶: ${currentUser.uid}');

      // 檢查該用戶是否確實隱藏了此聊天室
      if (!hiddenBy.contains(currentUser.uid)) {
        print('⚠️ 用戶未隱藏此聊天室: $chatId');
        return false;
      }

      if (taskId == null) {
        print('❌ 聊天室缺少任務ID: $chatId');
        return false;
      }

      // 檢查任務是否還在進行中
      print('🔍 檢查任務狀態: $taskId');
      final isActive = await isTaskActive(taskId);
      print('📊 任務活躍狀態: $isActive');

      if (!isActive) {
        print('❌ 任務已完成或過期，無法恢復聊天室: $chatId, 任務ID: $taskId');
        return false;
      }

      // 從 hiddenBy 列表中移除當前用戶
      print('🔄 從隱藏列表中移除用戶...');
      await _firestore.collection('chats').doc(chatId).update({
        'hiddenBy': FieldValue.arrayRemove([currentUser.uid]),
      });

      print('✅ 聊天室已智能恢復: $chatId（任務進行中，對用戶 ${currentUser.uid} 恢復顯示）');
      return true;
    } catch (e) {
      print('❌ 智能恢復聊天室失敗: $e');
      return false;
    }
  }
}
