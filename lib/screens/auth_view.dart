// lib/screens/auth_view.dart
import 'dart:async'; // 加入這行
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isLoading = false;
  bool _isOtpSent = false;
  String? _error;
  String? _verificationId;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _animationController.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // 格式化手機號碼
  String _formatPhoneNumber(String phone) {
    // 移除所有非數字字符
    phone = phone.replaceAll(RegExp(r'[^\d]'), '');

    // 檢查是否為測試號碼格式
    if (phone == '0912341234') {
      return '+1 0912341234'; // Firebase 測試號碼格式
    }

    if (phone == '0912345678') {
      return '+1 0912345678'; // Firebase 測試號碼格式
    }

    if (phone == '0911111111') {
      return '+1 0911111111'; // Firebase 測試號碼格式
    }

    // 台灣手機號碼格式
    // if (phone.startsWith('0')) {
    //   phone = '+886${phone.substring(1)}';
    // } else if (!phone.startsWith('+886')) {
    //   phone = '+886$phone';
    // }

    return phone;
  }

  // 驗證手機號碼格式
  bool _isValidPhoneNumber(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

    // 允許測試號碼
    if (cleanPhone == '0912341234') {
      return true;
    }
    if (cleanPhone == '0912345678') {
      return true;
    }
    if (cleanPhone == '0911111111') {
      return true;
    }

    // 台灣手機號碼驗證
    return cleanPhone.length == 10 && cleanPhone.startsWith('09');
  }

  // 發送 OTP
  void _sendOtp() async {
    if (!_isValidPhoneNumber(_phoneCtrl.text)) {
      setState(() => _error = '請輸入正確的手機號碼格式（09xxxxxxxx 或測試號碼 0912345678）');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final formattedPhone = _formatPhoneNumber(_phoneCtrl.text.trim());

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential = await FirebaseAuth.instance
                .signInWithCredential(credential);
            if (userCredential.user != null && mounted) {
              _navigateToRegistration(userCredential.user!, formattedPhone);
            }
          } catch (e) {
            if (mounted) {
              setState(() => _error = '自動驗證失敗：${e.toString()}');
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              switch (e.code) {
                case 'invalid-phone-number':
                  _error = '手機號碼格式不正確';
                  break;
                case 'too-many-requests':
                  _error = '請求過於頻繁，請稍後再試';
                  break;
                case 'quota-exceeded':
                  _error = '今日驗證次數已達上限，請明日再試';
                  break;
                case 'operation-not-allowed':
                  _error = '手機驗證功能未啟用，請檢查 Firebase 設定';
                  break;
                default:
                  _error = '發送驗證碼失敗：${e.message}';
              }
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isOtpSent = true;
              _isLoading = false;
            });
            _startResendTimer();
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() => _verificationId = verificationId);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '發送驗證碼失敗，請檢查網路連接：${e.toString()}';
        });
      }
    }
  }

  // 重新發送倒數計時
  void _startResendTimer() {
    _resendTimer?.cancel();

    setState(() => _resendSeconds = 60);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _resendSeconds--);

      if (_resendSeconds <= 0) {
        timer.cancel();
      }
    });
  }

  // 驗證 OTP
  void _verifyOtp() async {
    if (_otpCtrl.text.trim().length != 6) {
      setState(() => _error = '請輸入 6 位數驗證碼');
      return;
    }

    if (_verificationId == null) {
      setState(() => _error = '驗證流程異常，請重新發送驗證碼');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      if (userCredential.user != null) {
        final formattedPhone = _formatPhoneNumber(_phoneCtrl.text.trim());
        _navigateToRegistration(userCredential.user!, formattedPhone);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        switch (e.code) {
          case 'invalid-verification-code':
            _error = '驗證碼錯誤，請重新輸入';
            break;
          case 'code-expired':
            _error = '驗證碼已過期，請重新發送';
            break;
          default:
            _error = '驗證失敗：${e.message}';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '驗證失敗，請檢查網路連接：${e.toString()}';
      });
    }
  }

  // 導向註冊頁面或主頁面
  void _navigateToRegistration(User user, String phoneNumber) async {
    try {
      // 檢查用戶是否已註冊 - 統一使用 user 集合
      final userDoc = await FirebaseFirestore.instance
          .collection('user')
          .doc(user.uid)
          .get();

      if (mounted) {
        if (userDoc.exists) {
          // 已註冊用戶，直接進入主頁面
          Navigator.of(context).pushReplacementNamed('/parent');
        } else {
          // 新用戶，進入註冊流程 - 使用命名路由並傳遞參數
          Navigator.of(context).pushReplacementNamed(
            '/registration',
            arguments: {'uid': user.uid, 'phoneNumber': phoneNumber},
          );
        }
      }
    } catch (e) {
      print('檢查用戶註冊狀態失敗: $e');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/registration',
          arguments: {'uid': user.uid, 'phoneNumber': phoneNumber},
        );
      }
    }
  }

  // 重新發送驗證碼
  void _resendOtp() {
    if (_resendSeconds == 0) {
      _resendTimer?.cancel(); // 取消現有計時器
      setState(() {
        _isOtpSent = false;
        _otpCtrl.clear();
        _error = null;
      });
      _sendOtp();
    }
  }

  // 返回輸入手機號碼步驟
  void _goBack() {
    _resendTimer?.cancel(); // 先取消計時器
    setState(() {
      _isOtpSent = false;
      _otpCtrl.clear();
      _error = null;
      _verificationId = null;
      _resendSeconds = 0; // ✅ 修復：使用 _resendSeconds 而不是 _resendTimer
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // 標題區域
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 160,
                        height: 80,
                        child: Image.asset('assets/logo.png'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isOtpSent ? '驗證手機號碼' : '手機登入',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isOtpSent
                            ? '請輸入發送到 ${_phoneCtrl.text} 的驗證碼'
                            : '輸入手機號碼以接收驗證碼',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 輸入欄位
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (!_isOtpSent) ...[
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: InputDecoration(
                            labelText: '手機號碼',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            hintText: '0912345678 (測試) 或 09xxxxxxxx',
                            helperText: '請輸入台灣手機號碼或測試號碼',
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.blue[400]!),
                            ),
                          ),
                        ),
                      ] else ...[
                        // OTP 輸入
                        TextField(
                          controller: _otpCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 8,
                          ),
                          decoration: InputDecoration(
                            labelText: '驗證碼',
                            prefixIcon: const Icon(Icons.sms_outlined),
                            hintText: '',
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.blue[400]!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 重新發送按鈕
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '沒收到驗證碼？',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            TextButton(
                              onPressed: _resendSeconds == 0
                                  ? _resendOtp
                                  : null,
                              child: Text(
                                _resendSeconds > 0
                                    ? '重新發送 ($_resendSeconds)'
                                    : '重新發送',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _resendSeconds > 0
                                      ? Colors.grey[400]
                                      : Colors.blue[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 錯誤訊息
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[600],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_error != null) const SizedBox(height: 16),

                // 主要按鈕
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (_isOtpSent ? _verifyOtp : _sendOtp),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            _isOtpSent ? '驗證' : '發送驗證碼',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // 返回按鈕
                if (_isOtpSent)
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : _goBack,
                      child: Text(
                        '返回修改手機號碼',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                  ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
