// lib/screens/auth_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/auth_service.dart';
import '../services/system_service.dart';
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
  bool _hasAgreed = false;

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
        // 登入成功，記錄用戶同意聲明
        print('✅ Google 登入成功: ${user.email}');
        print('🔍 用戶資料: uid=${user.uid}, displayName=${user.displayName}');
        print('📧 用戶信箱: ${user.email}');
        print('📱 電話號碼: ${user.phoneNumber ?? "無"}');

        // 記錄同意聲明
        try {
          print('📝 記錄用戶同意聲明...');
          await _authService.recordUserConsent();
          print('✅ 同意聲明記錄成功');
        } catch (e) {
          print('⚠️ 記錄同意聲明失敗: $e');
          // 不阻止登入流程，但記錄錯誤
        }

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

  /// 顯示服務條款
  Future<void> _showTermsOfService() async {
    final content = await SystemService.getTermsOfService();
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildPolicySheet('服務條款', content),
      );
    }
  }

  /// 顯示隱私政策
  Future<void> _showPrivacyPolicy() async {
    final content = await SystemService.getPrivacyPolicy();
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildPolicySheet('隱私政策', content),
      );
    }
  }

  /// 建構政策顯示組件
  Widget _buildPolicySheet(String title, String content) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // 頂部標題欄
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.greyShade(200), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          // 內容區域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          // 底部按鈕 - 修正高度和 padding
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), // 增加底部 padding
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.greyShade(200), width: 1),
              ),
            ),
            child: SafeArea(
              // 確保按鈕不會被底部安全區域遮擋
              child: SizedBox(
                width: double.infinity,
                height: 54, // 增加按鈕高度
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    '我已閱讀',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

                const SizedBox(height: 12),

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
                    onPressed: (_isLoading || !_hasAgreed)
                        ? null
                        : _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey[700],
                      elevation: 0, // 移除陰影
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

                const SizedBox(height: 32),

                // 同意聲明 checkbox
                Container(
                  alignment: Alignment.center, // 整個區域置中
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, // 內容水平置中
                    crossAxisAlignment: CrossAxisAlignment.center, // 垂直置中對齊
                    mainAxisSize: MainAxisSize.min, // 最小化 Row 寬度以實現置中
                    children: [
                      Transform.scale(
                        scale: 1.2,
                        child: Checkbox(
                          value: _hasAgreed,
                          onChanged: (value) {
                            setState(() {
                              _hasAgreed = value ?? false;
                            });
                          },
                          activeColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          side: MaterialStateBorderSide.resolveWith((states) {
                            if (states.contains(MaterialState.selected)) {
                              return BorderSide.none; // 選中時不顯示邊框
                            }
                            return BorderSide(
                              color: AppColors.greyShade(400), // 更淡的灰色
                              width: 1.0, // 更細的線條
                            );
                          }),
                        ),
                      ),
                      const SizedBox(width: 0),
                      Flexible(
                        // 改用 Flexible 以允許文字換行
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: '我已閱讀並同意 '),
                              TextSpan(
                                text: '服務條款',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _showTermsOfService,
                              ),
                              const TextSpan(text: ' 和 '),
                              TextSpan(
                                text: '隱私政策',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _showPrivacyPolicy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
