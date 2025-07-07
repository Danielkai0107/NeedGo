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
        // 載入中
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen();
        }

        // 檢查登入狀態
        final user = snapshot.data;
        if (user == null) {
          // 未登入，顯示登入頁面
          return const AuthView();
        }

        // 已登入，檢查是否已註冊
        return FutureBuilder<bool>(
          future: _checkUserRegistration(user.uid),
          builder: (context, registrationSnapshot) {
            if (registrationSnapshot.connectionState ==
                ConnectionState.waiting) {
              return _buildLoadingScreen();
            }

            // 檢查是否已完成註冊
            final isRegistered = registrationSnapshot.data ?? false;

            if (isRegistered) {
              // 已註冊，進入主畫面
              return const MainTabView();
            } else {
              // 未註冊，進入註冊頁面
              return RegistrationView(
                uid: user.uid,
                phoneNumber: user.phoneNumber ?? '',
              );
            }
          },
        );
      },
    );
  }

  /// 檢查用戶是否已註冊
  Future<bool> _checkUserRegistration(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (e) {
      print('檢查用戶註冊狀態時發生錯誤: $e');
      return false;
    }
  }

  /// 建立載入畫面
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
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
              '載入中...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
