// lib/screens/auth_view.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthView extends StatefulWidget {
  const AuthView({Key? key}) : super(key: key);

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _auth = AuthService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;

  // 角色選擇欄位
  String _selectedRole = 'parent';
  final _roles = <String, Map<String, dynamic>>{
    'parent': {
      'name': '家長',
      'icon': Icons.family_restroom,
      'color': Colors.blue,
      'description': '發布任務，找到合適的玩家',
    },
    'player': {
      'name': '玩家',
      'icon': Icons.sports_esports,
      'color': Colors.green,
      'description': '接受任務，獲得獎勵',
    },
    'group': {
      'name': '團體',
      'icon': Icons.groups,
      'color': Colors.purple,
      'description': '組織活動，管理團隊',
    },
  };

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
    _loadSavedCredentials(); // 加载保存的登录信息
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  // 加载保存的登录信息
  void _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    final savedRole = prefs.getString('saved_role');
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (rememberMe && savedEmail != null && savedPassword != null) {
      setState(() {
        _emailCtrl.text = savedEmail;
        _pwdCtrl.text = savedPassword;
        _selectedRole = savedRole ?? 'parent';
        _rememberMe = true;
      });
    }
  }

  // 保存登录信息
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailCtrl.text.trim());
      await prefs.setString('saved_password', _pwdCtrl.text);
      await prefs.setString('saved_role', _selectedRole);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.remove('saved_role');
      await prefs.setBool('remember_me', false);
    }
  }

  // 忘记密码
  void _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = '請先輸入您的 Email 地址');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      // 直接使用 Firebase Auth 的重置密码方法
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );
      _showSuccessDialog('重置密碼郵件已發送', '請檢查您的信箱並按照指示重置密碼');
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = '找不到此 Email 對應的用戶';
          break;
        case 'invalid-email':
          errorMessage = 'Email 格式不正確';
          break;
        case 'too-many-requests':
          errorMessage = '請求過於頻繁，請稍後再試';
          break;
        default:
          errorMessage = '發送重置郵件失敗：${e.message}';
      }
      setState(() => _error = errorMessage);
    } catch (e) {
      setState(() => _error = '發送重置郵件失敗，請檢查網路連接');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 显示成功对话框
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600]),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _onSubmit() async {
    if (_emailCtrl.text.trim().isEmpty || _pwdCtrl.text.trim().isEmpty) {
      setState(() => _error = '請填寫完整的 Email 和密碼');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final user = _isLogin
          ? await _auth.signIn(
              email: _emailCtrl.text.trim(),
              password: _pwdCtrl.text,
            )
          : await _auth.register(
              email: _emailCtrl.text.trim(),
              password: _pwdCtrl.text,
            );
      if (user != null) {
        // 保存登录信息（如果勾选了记住我）
        await _saveCredentials();
        Navigator.pushReplacementNamed(context, '/$_selectedRole');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onGoogleSignIn() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final user = await _auth.signInWithGoogle();
      if (user != null) {
        Navigator.pushReplacementNamed(context, '/$_selectedRole');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleSelector() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '選擇您的身份',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tab 样式的角色选择器
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: _roles.entries.map((entry) {
                final role = entry.key;
                final roleData = entry.value;
                final isSelected = _selectedRole == role;
                final isFirst = _roles.keys.first == role;
                final isLast = _roles.keys.last == role;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRole = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? roleData['color']
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.horizontal(
                              left: isFirst
                                  ? const Radius.circular(8)
                                  : Radius.zero,
                              right: isLast
                                  ? const Radius.circular(8)
                                  : Radius.zero,
                            ).copyWith(
                              topLeft: isFirst
                                  ? const Radius.circular(8)
                                  : const Radius.circular(8),
                              topRight: isLast
                                  ? const Radius.circular(8)
                                  : const Radius.circular(8),
                              bottomLeft: isFirst
                                  ? const Radius.circular(8)
                                  : const Radius.circular(8),
                              bottomRight: isLast
                                  ? const Radius.circular(8)
                                  : const Radius.circular(8),
                            ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: roleData['color'].withOpacity(0.3),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            roleData['icon'],
                            color: isSelected
                                ? Colors.white
                                : roleData['color'],
                            size: 20,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            roleData['name'],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : roleData['color'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // 選中角色的描述
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(_selectedRole),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _roles[_selectedRole]!['color'].withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _roles[_selectedRole]!['color'].withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: _roles[_selectedRole]!['color'],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _roles[_selectedRole]!['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: _roles[_selectedRole]!['color'].withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // 標題區域
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 160,
                        height: 80,
                        child: Image.asset('assets/logo.png'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isLogin ? '歡迎回來' : '建立帳戶',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? '登入您的帳戶以繼續使用' : '註冊新帳戶開始使用服務',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // 角色選擇器
                _buildRoleSelector(),

                const SizedBox(height: 24),

                // Email / Password 輸入欄位
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
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
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

                      // 记住我和忘记密码
                      if (_isLogin) ...[
                        Row(
                          children: [
                            // 记住我复选框
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (value) => setState(
                                  () => _rememberMe = value ?? false,
                                ),
                                activeColor: Colors.blue[600],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '記住我',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Spacer(),
                            // 忘记密码
                            TextButton(
                              onPressed: _isLoading ? null : _forgotPassword,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                '忘記密碼？',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pwdCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: '密碼',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
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

                // 登入/註冊按鈕
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onSubmit,
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
                            _isLogin ? '登入' : '註冊',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // 切換登入/註冊
                Center(
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _isLogin = !_isLogin),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        children: [
                          TextSpan(text: _isLogin ? '還沒有帳戶？' : '已經有帳戶？'),
                          TextSpan(
                            text: _isLogin ? ' 立即註冊' : ' 立即登入',
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 分隔線
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '或',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),

                const SizedBox(height: 24),

                // Google 登入按鈕
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _onGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Image.asset('assets/google_logo.png', height: 24),
                    label: Text(
                      '使用 Google 登入',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
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
