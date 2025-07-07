// lib/screens/auth_view.dart
import 'dart:async'; // 加入這行
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_text_field.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocusNode = FocusNode(); // 新增：OTP輸入框的FocusNode
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
    _otpFocusNode.dispose(); // 新增：清理FocusNode
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

    if (phone == '0900000000') {
      return '+1 0900000000'; // Firebase 測試號碼格式
    }

    if (phone == '0911111111') {
      return '+1 0911111111'; // Firebase 測試號碼格式
    }

    // 台灣手機號碼格式
    if (phone.startsWith('0')) {
      phone = '+886${phone.substring(1)}';
    } else if (!phone.startsWith('+886')) {
      phone = '+886$phone';
    }

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
    if (cleanPhone == '0900000000') {
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
            // 新增：自動focus到驗證碼輸入框
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _otpFocusNode.requestFocus();
            });
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

  // 導向主頁面（讓 AuthGate 負責狀態判斷）
  void _navigateToRegistration(User user, String phoneNumber) async {
    // 驗證成功後直接回到主頁面，讓 AuthGate 處理狀態判斷
    if (mounted) {
      final navigator = Navigator.of(context);
      navigator.pushReplacementNamed('/');
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

  // 快速填入測試帳號的方法
  void _fillTestAccount(String phoneNumber) {
    setState(() {
      _phoneCtrl.text = phoneNumber;
      _error = null;
    });
  }

  // 新增：獲取測試帳號對應的驗證碼
  String _getTestVerificationCode(String phoneNumber) {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    switch (cleanPhone) {
      case '0912345678':
        return '111111';
      case '0900000000':
        return '000000';
      case '0912341234':
        return '123456';
      case '0911111111':
        return '112233';
      default:
        return '123456'; // 預設驗證碼
    }
  }

  // 新增：快速登入測試帳號的方法
  void _quickLoginTestAccount(String phoneNumber) async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      final testCode = _getTestVerificationCode(phoneNumber);

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
              setState(() {
                _isLoading = false;
                _error = '自動驗證失敗：${e.toString()}';
              });
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _error = '快速登入失敗：${e.message}';
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) async {
          // 對於測試帳號，使用對應的測試驗證碼
          try {
            final credential = PhoneAuthProvider.credential(
              verificationId: verificationId,
              smsCode: testCode,
            );

            final userCredential = await FirebaseAuth.instance
                .signInWithCredential(credential);

            if (userCredential.user != null && mounted) {
              _navigateToRegistration(userCredential.user!, formattedPhone);
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = '快速登入失敗：${e.toString()}';
              });
            }
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // 如果自動檢索失敗，也嘗試使用對應的測試驗證碼
          _verifyTestCode(verificationId, formattedPhone, testCode);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '快速登入失敗，請檢查網路連接：${e.toString()}';
        });
      }
    }
  }

  // 新增：使用測試驗證碼進行驗證
  void _verifyTestCode(
    String verificationId,
    String phoneNumber,
    String testCode,
  ) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: testCode,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      if (userCredential.user != null && mounted) {
        _navigateToRegistration(userCredential.user!, phoneNumber);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '快速登入失敗：${e.toString()}';
        });
      }
    }
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
                        CustomTextField(
                          controller: _phoneCtrl,
                          label: '手機號碼',
                          hintText: '0912345678 (測試) 或 09xxxxxxxx',
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '請輸入台灣手機號碼或測試號碼',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ] else ...[
                        // OTP 輸入 - 保持 TextField 以支援特殊樣式（居中對齊、大字體、字母間距）
                        TextField(
                          controller: _otpCtrl,
                          focusNode: _otpFocusNode,
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
                            hintText: '',
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.blue[600]!,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
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

                // 新增：測試帳號快速登入按鈕（只在手機號碼輸入階段顯示）
                if (!_isOtpSent) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '測試帳號快速登入',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '點擊直接登入，無需輸入驗證碼',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildTestAccountButton('0912341234'),
                            _buildTestAccountButton('0912345678'),
                            _buildTestAccountButton('0911111111'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 新增：建立測試帳號按鈕的方法
  Widget _buildTestAccountButton(String phoneNumber) {
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _quickLoginTestAccount(phoneNumber),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.green[50],
        foregroundColor: Colors.green[700],
        elevation: 0,
        side: BorderSide(color: Colors.green[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flash_on, size: 16, color: Colors.green[600]),
          const SizedBox(width: 4),
          Text(
            phoneNumber,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
