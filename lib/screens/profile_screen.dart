import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/custom_snackbar.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_date_time_field.dart';
import '../widgets/custom_dropdown_field.dart';
import '../services/auth_service.dart';

/// 個人資料頁面
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic> _profile = {};
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String _userRole = 'parent'; // parent 或 player

  // 表單控制器
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _lineIdController = TextEditingController();
  final _socialLinksController = TextEditingController();
  final _resumeController = TextEditingController();

  DateTime? _selectedBirthday;
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _lineIdController.dispose();
    _socialLinksController.dispose();
    _resumeController.dispose();
    super.dispose();
  }

  /// 載入個人資料
  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _profile = data;
          _userRole = data['preferredRole'] ?? 'parent';

          // 初始化表單控制器
          _nameController.text = data['name'] ?? '';
          _emailController.text = data['email'] ?? '';
          _lineIdController.text = data['lineId'] ?? '';

          final socialLinks =
              data['socialLinks'] as Map<String, dynamic>? ?? {};
          _socialLinksController.text = socialLinks['other']?.toString() ?? '';

          final resumeField = _userRole == 'parent'
              ? 'publisherResume'
              : 'applicantResume';
          _resumeController.text = data[resumeField]?.toString() ?? '';

          // 初始化生日
          final birthday = data['birthday'];
          if (birthday != null) {
            try {
              if (birthday is Timestamp) {
                _selectedBirthday = birthday.toDate();
              } else if (birthday is String) {
                _selectedBirthday = DateTime.parse(birthday);
              }
            } catch (e) {
              _selectedBirthday = null;
            }
          }

          // 初始化性別
          _selectedGender = _convertGenderToDisplayValue(
            data['gender']?.toString(),
          );

          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _profile = {
            'name': '未設定',
            'email': '',
            'lineId': '',
            'socialLinks': {},
            'publisherResume': '',
            'applicantResume': '',
            'avatarUrl': '',
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      print('載入個人資料失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 保存個人資料
  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'lineId': _lineIdController.text.trim(),
        'birthday': _selectedBirthday,
        'gender': _convertGenderToStorageValue(_selectedGender),
        'socialLinks': {'other': _socialLinksController.text.trim()},
      };

      // 根據角色更新對應的履歷欄位
      final resumeField = _userRole == 'parent'
          ? 'publisherResume'
          : 'applicantResume';
      updateData[resumeField] = _resumeController.text.trim();

      await _firestore.collection('user').doc(user.uid).update(updateData);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '個人資料更新成功');
        setState(() {
          _isEditing = false;
        });
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '儲存失敗：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 上傳頭像
  Future<void> _uploadAvatar() async {
    try {
      setState(() {
        _isUploadingAvatar = true;
      });

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        final imageBytes = await image.readAsBytes();

        // 上傳到 Firebase Storage
        final storageRef = FirebaseStorage.instance.ref().child(
          'avatars/${user.uid}.jpg',
        );
        await storageRef.putData(imageBytes);
        final avatarUrl = await storageRef.getDownloadURL();

        // 更新 Firestore 中的頭像 URL
        await _firestore.collection('user').doc(user.uid).update({
          'avatarUrl': avatarUrl,
        });

        if (mounted) {
          CustomSnackBar.showSuccess(context, '頭像更新成功！');
          await _loadProfile();
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '頭像上傳失敗：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  /// 登出
  Future<void> _logout() async {
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('登出'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    // 保存context引用以避免在異步操作中出現問題
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 顯示載入指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在登出...'),
          ],
        ),
      ),
    );

    try {
      // 使用 AuthService 登出
      final authService = AuthService();
      await authService.signOut();

      // 關閉載入對話框並導航到首頁
      if (mounted) {
        navigator.pop(); // 關閉載入對話框
        navigator.pushReplacementNamed('/');
      }
    } catch (e) {
      // 關閉載入對話框並顯示錯誤
      if (mounted) {
        navigator.pop(); // 關閉載入對話框
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('登出失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 選擇生日
  void _selectBirthday() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (selectedDate != null && mounted) {
      setState(() {
        _selectedBirthday = selectedDate;
      });
    }
  }

  /// 性別轉換方法
  String? _convertGenderToDisplayValue(String? genderValue) {
    if (genderValue == null || genderValue.isEmpty) return null;

    switch (genderValue.toLowerCase()) {
      case 'male':
        return '男';
      case 'female':
        return '女';
      case 'other':
        return '其他';
      default:
        return genderValue;
    }
  }

  String? _convertGenderToStorageValue(String? displayValue) {
    if (displayValue == null || displayValue.isEmpty) return null;

    switch (displayValue) {
      case '男':
        return 'male';
      case '女':
        return 'female';
      case '其他':
        return 'other';
      default:
        return displayValue;
    }
  }

  /// 格式化加入時間
  String _calculateJoinTime() {
    final createdAt = _profile['createdAt'];
    if (createdAt == null) return '加入時間未知';

    try {
      DateTime date;
      if (createdAt is Timestamp) {
        date = createdAt.toDate();
      } else if (createdAt is String) {
        date = DateTime.parse(createdAt);
      } else {
        return '加入時間未知';
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays < 30) {
        return '加入 ${difference.inDays} 天';
      } else if (difference.inDays < 365) {
        final months = difference.inDays ~/ 30;
        return '加入 $months 個月';
      } else {
        final years = difference.inDays ~/ 365;
        return '加入 $years 年';
      }
    } catch (e) {
      return '加入時間未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '個人資料',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (!_isEditing)
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              child: const Text('編輯'),
            ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(bottom: 140), // 為導覽列預留空間
              child: _isEditing
                  ? _buildEditForm()
                  : _buildProfileView(),
            ),
    );
  }

  Widget _buildProfileView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頭像區域
          _buildAvatarSection(),
          const SizedBox(height: 32),

          // 基本資料
          _buildInfoSection(
            title: '基本資料',
            children: [
              _buildInfoRow('姓名', _profile['name'] ?? '未設定', Icons.person),
              _buildInfoRow('生日', _formatBirthday(), Icons.cake),
              _buildInfoRow('性別', _formatGender(), Icons.wc),
            ],
          ),

          const SizedBox(height: 24),

          // 聯絡資訊
          _buildInfoSection(
            title: '聯絡資訊',
            children: [
              _buildInfoRow('Email', _profile['email'] ?? '未設定', Icons.email),
              _buildInfoRow('Line ID', _profile['lineId'] ?? '未設定', Icons.chat),
              _buildInfoRow('社群連結', _formatSocialLinks(), Icons.link),
            ],
          ),

          const SizedBox(height: 24),

          // 簡介/履歷
          _buildResumeSection(),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 姓名
          CustomTextField(
            controller: _nameController,
            label: '姓名',
            hintText: '請輸入您的姓名',
          ),
          const SizedBox(height: 20),

          // 生日
          CustomDateTimeField(
            label: '生日',
            icon: Icons.calendar_today,
            selectedDate: _selectedBirthday,
            onDateTap: _selectBirthday,
          ),
          const SizedBox(height: 20),

          // 性別
          CustomDropdownField<String>(
            label: '性別',
            value: _selectedGender,
            icon: Icons.wc,
            hintText: '請選擇性別',
            items: const [
              DropdownMenuItem(value: '男', child: Text('男')),
              DropdownMenuItem(value: '女', child: Text('女')),
              DropdownMenuItem(value: '其他', child: Text('其他')),
            ],
            onChanged: (String? newValue) {
              setState(() {
                _selectedGender = newValue;
              });
            },
          ),
          const SizedBox(height: 20),

          // Email
          CustomTextField(
            controller: _emailController,
            label: 'Email',
            hintText: '請輸入您的 Email',
          ),
          const SizedBox(height: 20),

          // Line ID
          CustomTextField(
            controller: _lineIdController,
            label: 'Line ID',
            hintText: '請輸入您的 Line ID',
          ),
          const SizedBox(height: 20),

          // 社群連結
          CustomTextField(
            controller: _socialLinksController,
            label: '社群連結',
            hintText: '請輸入您的社群媒體連結',
          ),
          const SizedBox(height: 20),

          // 簡介/履歷
          CustomTextField(
            controller: _resumeController,
            label: _userRole == 'parent' ? '發布者簡介' : '應徵者履歷',
            hintText: _userRole == 'parent'
                ? '簡單介紹一下自己，讓應徵者更了解你...'
                : '描述您的技能、經驗和專長...',
            maxLines: 5,
          ),
          const SizedBox(height: 32),

          // 按鈕
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isEditing = false;
                    });
                    _loadProfile(); // 重新載入資料
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          '儲存',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _uploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[300]!, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 58,
                    backgroundColor: Colors.grey[100],
                    backgroundImage:
                        _profile['avatarUrl']?.toString().isNotEmpty == true
                        ? NetworkImage(_profile['avatarUrl'])
                        : null,
                    child: _profile['avatarUrl']?.toString().isNotEmpty != true
                        ? Icon(Icons.person, size: 60, color: Colors.grey[400])
                        : null,
                  ),
                ),
                // 載入遮罩
                if (_isUploadingAvatar)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),
                // 編輯圖標
                if (!_isUploadingAvatar)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: Colors.blue[600],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _profile['name']?.toString().isNotEmpty == true
                ? _profile['name']
                : '未設定名稱',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _calculateJoinTime(),
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (_profile['isVerified'] == true)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user, size: 16, color: Colors.green[600]),
                const SizedBox(width: 6),
                Text(
                  '已認證',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            '$label：',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeSection() {
    final resumeField = _userRole == 'parent'
        ? 'publisherResume'
        : 'applicantResume';
    final resumeContent = _profile[resumeField]?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _userRole == 'parent' ? '發布者簡介' : '應徵者履歷',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Text(
            resumeContent?.isNotEmpty == true
                ? resumeContent!
                : '尚未填寫${_userRole == 'parent' ? "簡介" : "履歷"}',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: resumeContent?.isNotEmpty == true
                  ? Colors.black
                  : Colors.grey[500],
              fontStyle: resumeContent?.isNotEmpty == true
                  ? FontStyle.normal
                  : FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  String _formatBirthday() {
    if (_selectedBirthday == null) return '未設定';
    return '${_selectedBirthday!.year}年${_selectedBirthday!.month}月${_selectedBirthday!.day}日';
  }

  String _formatGender() {
    return _selectedGender ?? '未設定';
  }

  String _formatSocialLinks() {
    final socialLinks = _profile['socialLinks'] as Map<String, dynamic>? ?? {};
    final otherLink = socialLinks['other']?.toString();
    return otherLink?.isNotEmpty == true ? otherLink! : '未設定';
  }
}
