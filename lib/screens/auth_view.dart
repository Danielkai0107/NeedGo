// lib/screens/auth_view.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../styles/app_colors.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    print('🚀 開始 Google 登入流程...');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('📞 調用 AuthService.signInWithGoogle()');
      final user = await _authService.signInWithGoogle();

      if (user != null) {
        // 登入成功，AuthGate 會自動處理導航
        print('✅ Google 登入成功: ${user.email}');
        print('🔍 用戶資料: uid=${user.uid}, displayName=${user.displayName}');
        print('📧 用戶信箱: ${user.email}');
        print('📱 電話號碼: ${user.phoneNumber ?? "無"}');

        // 手動觸發狀態檢查（以防萬一）
        print('🔄 登入成功，等待 AuthGate 處理...');
      } else {
        // 用戶取消登入，這是正常行為，不需要顯示錯誤
        print('⏹️ 用戶取消 Google 登入');
      }
    } catch (e) {
      print('❌ Google 登入失敗: $e');
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        print('🏁 登入流程結束，更新 UI 狀態');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 應用程式 Logo
                SizedBox(
                  width: 160,
                  height: 80,
                  child: Image.asset(
                    'assets/logo.png',
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 160,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryShade(50),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.app_registration,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // 歡迎標題
                const Text(
                  '歡迎使用',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  '使用 Google 帳號登入以開始使用',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 48),

                // Google 登入按鈕
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/google_logo.png',
                                width: 20,
                                height: 20,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.login, size: 20);
                                },
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                '使用 Google 帳號登入',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // 錯誤訊息
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // 登入提示
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '首次使用需要完成註冊',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '登入後我們會引導您填寫基本資料和上傳頭像',
                              style: TextStyle(
                                color: Colors.blue.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const SizedBox(height: 32),

                // 免責聲明
                Text(
                  '登入即表示您同意我們的服務條款和隱私政策',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
