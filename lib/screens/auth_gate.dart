import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_view.dart';
import 'main_tab_view.dart';
import 'registration_view.dart';

/// AuthGate - 登入狀態判斷的主入口元件
/// 自動偵測使用者登入狀態，決定顯示登入頁面或主畫面
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  int _rebuildTrigger = 0; // 添加重建觸發器

  @override
  void initState() {
    super.initState();
    print('🚪 AuthGate initState 被調用');
  }

  @override
  Widget build(BuildContext context) {
    print('🚪 AuthGate build() 被調用 (trigger: $_rebuildTrigger)');

    return StreamBuilder<User?>(
      // 監聽 Firebase Auth 狀態變化
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('🔍 AuthGate StreamBuilder 狀態: ${snapshot.connectionState}');
        print('🔍 AuthGate 用戶狀態: ${snapshot.hasData ? "已登入" : "未登入"}');
        if (snapshot.hasData) {
          print(
            '🔍 用戶資料: uid=${snapshot.data?.uid}, email=${snapshot.data?.email}',
          );
        }

        // 載入中
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ AuthGate 正在等待連接...');
          return _buildLoadingScreen();
        }

        // 檢查連接錯誤
        if (snapshot.hasError) {
          print('❌ AuthGate 認證狀態錯誤: ${snapshot.error}');
          return _buildErrorScreen(context, '認證狀態檢查失敗，請重試');
        }

        // 檢查登入狀態
        final user = snapshot.data;
        if (user == null) {
          print('📱 用戶未登入，顯示登入頁面');
          // 未登入，顯示登入頁面
          return const AuthView();
        }

        print('✅ 用戶已登入，檢查註冊狀態...');
        // 已登入，檢查是否已註冊
        return FutureBuilder<bool>(
          key: ValueKey('${user.uid}_$_rebuildTrigger'), // 使用重建觸發器強制重新檢查
          future: _checkUserRegistration(user.uid),
          builder: (context, registrationSnapshot) {
            print('📋 註冊檢查狀態: ${registrationSnapshot.connectionState}');
            print('📋 註冊檢查結果: ${registrationSnapshot.data}');
            print('📋 註冊檢查錯誤: ${registrationSnapshot.error}');

            if (registrationSnapshot.connectionState ==
                ConnectionState.waiting) {
              print('⏳ 正在檢查用戶註冊狀態...');
              return _buildLoadingScreen();
            }

            // 處理註冊檢查錯誤
            if (registrationSnapshot.hasError) {
              print('❌ 檢查用戶註冊狀態錯誤: ${registrationSnapshot.error}');
              return _buildErrorScreen(
                context,
                '無法檢查用戶資料，請檢查網路連接後重試',
                onRetry: () {
                  print('🔄 用戶點擊重試按鈕');
                  // 觸發重建以重新檢查
                  setState(() {
                    _rebuildTrigger++;
                  });
                },
              );
            }

            // 檢查是否已完成註冊
            final isRegistered = registrationSnapshot.data ?? false;
            print('📊 最終註冊狀態判斷: $isRegistered');

            if (isRegistered) {
              print('🏠 用戶已註冊，進入主畫面');
              // 已註冊，進入主畫面
              return const MainTabView();
            } else {
              print('📝 用戶未註冊，進入註冊頁面');
              print(
                '📝 傳遞參數: uid=${user.uid}, phoneNumber=${user.phoneNumber}',
              );
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

  /// 檢查用戶是否已註冊，帶有重試機制
  Future<bool> _checkUserRegistration(String uid) async {
    print('🔍 開始檢查用戶註冊狀態: $uid');

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        print('🔄 第 ${retryCount + 1} 次檢查用戶文檔...');

        final doc = await FirebaseFirestore.instance
            .collection('user')
            .doc(uid)
            .get();

        final exists = doc.exists;
        print('📄 用戶文檔存在狀態: $exists');

        if (exists) {
          final data = doc.data();
          print('📊 用戶文檔資料: ${data?.keys.toList()}');
        }

        return exists;
      } catch (e) {
        retryCount++;
        print('❌ 檢查用戶註冊狀態失敗 (第 $retryCount 次): $e');

        if (retryCount >= maxRetries) {
          print('💥 達到最大重試次數，拋出異常');
          throw Exception('多次嘗試後仍無法檢查用戶註冊狀態: $e');
        }

        // 等待後重試
        final waitSeconds = retryCount;
        print('⏳ 等待 $waitSeconds 秒後重試...');
        await Future.delayed(Duration(seconds: waitSeconds));
      }
    }

    print('⚠️ 預設返回未註冊狀態');
    return false; // 預設為未註冊
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

  /// 建立錯誤畫面
  Widget _buildErrorScreen(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 錯誤圖標
              Icon(Icons.error_outline, size: 80, color: Colors.red[400]),

              const SizedBox(height: 24),

              // 錯誤標題
              const Text(
                '發生問題',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 16),

              // 錯誤訊息
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // 重試按鈕
              if (onRetry != null)
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    '重試',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),

              const SizedBox(height: 16),

              // 回到登入頁面按鈕
              TextButton(
                onPressed: () {
                  print('🔄 用戶點擊重新檢查，觸發重建');
                  // 觸發重建，讓 AuthGate 重新檢查狀態
                  setState(() {
                    _rebuildTrigger++;
                  });
                },
                child: Text(
                  '重新檢查',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
