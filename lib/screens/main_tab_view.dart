import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:badges/badges.dart' as badges;
import 'unified_map_view.dart';
import 'chat_list_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'my_tasks_screen.dart';
import '../services/chat_service.dart';

/// 主要的底部導航欄容器
class MainTabView extends StatefulWidget {
  const MainTabView({Key? key}) : super(key: key);

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _currentIndex = 0;
  final _firestore = FirebaseFirestore.instance;
  Map<String, dynamic> _userProfile = {};
  String _userRole = 'parent'; // 預設為 parent
  int _totalUnreadCount = 0;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _setupChatUnreadListener();
  }

  @override
  void dispose() {
    // 清理監聽器
    ChatService.removeListener('main_tab_unread_count');
    super.dispose();
  }

  /// 載入用戶資料以判斷角色
  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userProfile = doc.data() ?? {};
          // 根據用戶的主要使用模式決定預設角色
          // 如果沒有特別設定，預設為 parent
          _userRole = _userProfile['preferredRole'] ?? 'parent';
        });
      }
    } catch (e) {
      print('載入用戶資料失敗: $e');
    }
  }

  /// 設置聊天未讀訊息監聽器
  void _setupChatUnreadListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final subscription = ChatService.getUserChatRooms().listen((chatRooms) {
      if (mounted) {
        int totalUnread = 0;
        for (final chatRoom in chatRooms) {
          totalUnread += chatRoom.unreadCount[user.uid] ?? 0;
        }
        setState(() {
          _totalUnreadCount = totalUnread;
        });
      }
    });

    // 將監聽器添加到ChatService管理器
    ChatService.addListener('main_tab_unread_count', subscription);
  }

  /// 獲取當前角色的任務頁面
  Widget _getCurrentRoleTasksPage() {
    // Player 和 Parent 角色都使用 MyTasksScreen，但會顯示不同的內容
    return const MyTasksScreen();
  }

  /// 獲取當前角色的任務標題
  String _getCurrentRoleTasksTitle() {
    return '我的活動';
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const UnifiedMapView(), // 使用統一地圖視角
      _getCurrentRoleTasksPage(), // 我的任務/應徵
      const ChatListScreen(), // 訊息
      const NotificationScreen(), // 通知
      const ProfileScreen(), // 個人資料
    ];

    return Scaffold(
      extendBody: true, // 讓 body 延伸到底部導航欄下方
      backgroundColor: Colors.transparent, // 設置背景透明
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          child: SafeArea(
            child: Container(
              height: 90, // 增加導航欄高度給文字更多空間
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  // 首頁地圖
                  Expanded(
                    child: _buildNavItem(
                      icon: Icons.map_outlined,
                      activeIcon: Icons.map,
                      label: '地圖',
                      index: 0,
                      onTap: () => _onNavItemTap(0),
                    ),
                  ),
                  // 我的任務/應徵
                  Expanded(
                    child: _buildNavItem(
                      icon: Icons.assignment_outlined,
                      activeIcon: Icons.assignment,
                      label: _getCurrentRoleTasksTitle(),
                      index: 1,
                      onTap: () => _onNavItemTap(1),
                    ),
                  ),
                  // 訊息分頁
                  Expanded(
                    child: _buildNavItem(
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble,
                      label: '訊息',
                      index: 2,
                      badgeCount: _totalUnreadCount,
                      onTap: () => _onNavItemTap(2),
                    ),
                  ),
                  // 通知分頁
                  Expanded(
                    child: _buildNavItem(
                      icon: Icons.notifications_none,
                      activeIcon: Icons.notifications,
                      label: '通知',
                      index: 3,
                      badgeCount: _notificationCount,
                      onTap: () => _onNavItemTap(3),
                    ),
                  ),
                  // 個人資料分頁
                  Expanded(
                    child: _buildNavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: '個人資料',
                      index: 4,
                      onTap: () => _onNavItemTap(4),
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

  /// 建立導航項目
  Widget _buildNavItem({
    required IconData icon,
    IconData? activeIcon,
    required String label,
    required int index,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final isActive = _currentIndex == index;
    final displayIcon = isActive ? (activeIcon ?? icon) : icon;

    Widget iconWidget = Icon(
      displayIcon,
      size: 26,
      color: isActive ? Colors.blue[600] : Colors.grey[600],
    );

    // 如果有角標，包裝在 badges 中
    if (badgeCount > 0) {
      iconWidget = badges.Badge(
        badgeContent: Text(
          badgeCount > 99 ? '99+' : badgeCount.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        badgeStyle: badges.BadgeStyle(
          badgeColor: Colors.red,
          padding: const EdgeInsets.all(4),
        ),
        child: iconWidget,
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // 讓整個區域都可以點擊
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? Colors.blue[600] : Colors.grey[600],
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 處理導航項目點擊
  void _onNavItemTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }
}
