import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_view.dart';
import 'main_tab_view.dart';
import 'registration_view.dart';

/// AuthGate - 登入狀態判斷的主入口元件
/// 自動偵測使用者登入狀態，決定顯示登入頁面或主畫面
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // 監聽 Firebase Auth 狀態變化
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 連接狀態檢查
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen();
        }

        // 檢查是否有錯誤
        if (snapshot.hasError) {
          return _buildErrorScreen(snapshot.error);
        }

        // 取得目前用戶
        final User? user = snapshot.data;

        // 如果沒有用戶，顯示登入頁面
        if (user == null) {
          return const AuthView();
        }

        // 如果有用戶，需要進一步檢查是否已完成註冊
        return FutureBuilder<bool>(
          future: _checkIfUserRegistered(user.uid),
          builder: (context, registrationSnapshot) {
            // 檢查註冊狀態時顯示載入畫面
            if (registrationSnapshot.connectionState ==
                ConnectionState.waiting) {
              return _buildLoadingScreen();
            }

            // 檢查註冊狀態時發生錯誤
            if (registrationSnapshot.hasError) {
              // 發生錯誤時預設進入主畫面，讓用戶可以正常使用
              return const MainTabView();
            }

            // 根據註冊狀態決定頁面
            final bool isRegistered = registrationSnapshot.data ?? false;

            if (isRegistered) {
              // 已註冊，進入主畫面
              print('🏠 進入主畫面 (MainTabView)');
              return const MainTabView();
            } else {
              // 未註冊，直接返回註冊頁面
              print('📝 進入註冊頁面 (RegistrationView)');
              // 取得用戶手機號碼
              final phoneNumber = user.phoneNumber ?? '';

              // 直接導入註冊頁面而不是登出
              return RegistrationView(uid: user.uid, phoneNumber: phoneNumber);
            }
          },
        );
      },
    );
  }

  /// 建立載入畫面
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 應用程式 Logo
            SizedBox(
              width: 120,
              height: 120,
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // 如果圖片載入失敗，顯示預設圖標
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.app_registration,
                      size: 60,
                      color: Colors.blue.shade600,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // 載入指示器
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
              strokeWidth: 3,
            ),

            const SizedBox(height: 24),

            // 載入文字
            Text(
              '正在檢查登入狀態...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建立錯誤畫面
  Widget _buildErrorScreen(Object? error) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 錯誤圖標
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.red.shade600,
                ),
              ),

              const SizedBox(height: 24),

              // 錯誤標題
              const Text(
                '載入失敗',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 12),

              // 錯誤詳情
              Text(
                '無法檢查登入狀態，請檢查網路連接後重試',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // 重試按鈕
              ElevatedButton.icon(
                onPressed: () {
                  // 重新載入應用程式
                  // 這會觸發 StreamBuilder 重新建構
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重試'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 檢查用戶是否已完成註冊
  /// 回傳 true 表示已註冊，false 表示未註冊
  Future<bool> _checkIfUserRegistered(String uid) async {
    try {
      print('🔍 檢查用戶註冊狀態 (UID: $uid)...');
      
      // 檢查 Firestore 中是否存在用戶資料
      final userDoc = await FirebaseFirestore.instance
          .collection('user')
          .doc(uid)
          .get();

      final exists = userDoc.exists;
      print('📊 用戶註冊狀態: ${exists ? "已註冊" : "未註冊"}');
      
      if (exists) {
        final userData = userDoc.data();
        print('👤 用戶資料: ${userData?['name'] ?? "未知"}');
      }

      return exists;
    } catch (e) {
      print('❌ 檢查用戶註冊狀態失敗: $e');
      // 發生錯誤時回傳 false，讓用戶重新完成註冊流程
      return false;
    }
  }
}
