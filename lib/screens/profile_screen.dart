import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

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
  bool _isUploadingAvatar = false;

  // 獨立編輯狀態
  bool _isEditingBasicInfo = false;
  bool _isEditingContactInfo = false;
  bool _isEditingPublisherIntro = false;
  bool _isEditingApplicantResume = false;

  // 保存狀態
  bool _isSavingBasicInfo = false;
  bool _isSavingContactInfo = false;
  bool _isSavingPublisherIntro = false;
  bool _isSavingApplicantResume = false;

  // 表單控制器
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _lineIdController = TextEditingController();
  final _socialLinksController = TextEditingController();
  final _publisherIntroController = TextEditingController();

  // 應徵簡歷相關控制器
  final _educationController = TextEditingController();
  final _selfIntroController = TextEditingController();

  // 駕照狀態
  bool _hasCarLicense = false;
  bool _hasMotorcycleLicense = false;

  // 履歷PDF相關
  String? _resumePdfUrl;
  String? _resumePdfName;
  bool _isUploadingPdf = false;

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
    _publisherIntroController.dispose();
    _educationController.dispose();
    _selfIntroController.dispose();
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

          // 初始化基本資料控制器
          _nameController.text = data['name'] ?? '';
          _emailController.text = data['email'] ?? '';
          _lineIdController.text = data['lineId'] ?? '';

          final socialLinks =
              data['socialLinks'] as Map<String, dynamic>? ?? {};
          _socialLinksController.text = socialLinks['other']?.toString() ?? '';

          // 初始化發布者簡介控制器
          _publisherIntroController.text =
              data['publisherResume']?.toString() ?? '';

          // 初始化應徵簡歷相關控制器
          _educationController.text = data['education']?.toString() ?? '';
          _selfIntroController.text = data['selfIntro']?.toString() ?? '';

          // 初始化駕照狀態
          _hasCarLicense = data['hasCarLicense'] ?? false;
          _hasMotorcycleLicense = data['hasMotorcycleLicense'] ?? false;

          // 初始化履歷PDF
          _resumePdfUrl = data['resumePdfUrl']?.toString();
          _resumePdfName = data['resumePdfName']?.toString();

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
            'education': '',
            'selfIntro': '',
            'hasCarLicense': false,
            'hasMotorcycleLicense': false,
            'resumePdfUrl': '',
            'resumePdfName': '',
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

  /// 保存基本資料
  Future<void> _saveBasicInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSavingBasicInfo = true;
    });

    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'birthday': _selectedBirthday,
        'gender': _convertGenderToStorageValue(_selectedGender),
      };

      await _firestore.collection('user').doc(user.uid).update(updateData);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '基本資料更新成功');
        setState(() {
          _isEditingBasicInfo = false;
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
          _isSavingBasicInfo = false;
        });
      }
    }
  }

  /// 保存聯絡資訊
  Future<void> _saveContactInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSavingContactInfo = true;
    });

    try {
      final updateData = <String, dynamic>{
        'email': _emailController.text.trim(),
        'lineId': _lineIdController.text.trim(),
        'socialLinks': {'other': _socialLinksController.text.trim()},
      };

      await _firestore.collection('user').doc(user.uid).update(updateData);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '聯絡資訊更新成功');
        setState(() {
          _isEditingContactInfo = false;
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
          _isSavingContactInfo = false;
        });
      }
    }
  }

  /// 保存發布者簡介
  Future<void> _savePublisherIntro() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSavingPublisherIntro = true;
    });

    try {
      final updateData = <String, dynamic>{
        'publisherResume': _publisherIntroController.text.trim(),
      };

      await _firestore.collection('user').doc(user.uid).update(updateData);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '個人介紹更新成功');
        setState(() {
          _isEditingPublisherIntro = false;
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
          _isSavingPublisherIntro = false;
        });
      }
    }
  }

  /// 保存應徵簡歷
  Future<void> _saveApplicantResume() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSavingApplicantResume = true;
    });

    try {
      final updateData = <String, dynamic>{
        'education': _educationController.text.trim(),
        'selfIntro': _selfIntroController.text.trim(),
        'hasCarLicense': _hasCarLicense,
        'hasMotorcycleLicense': _hasMotorcycleLicense,
        'resumePdfUrl': _resumePdfUrl,
        'resumePdfName': _resumePdfName,
      };

      await _firestore.collection('user').doc(user.uid).update(updateData);

      if (mounted) {
        CustomSnackBar.showSuccess(context, '應徵簡歷更新成功');
        setState(() {
          _isEditingApplicantResume = false;
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
          _isSavingApplicantResume = false;
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

  /// 上傳PDF履歷
  Future<void> _uploadResumePdf() async {
    try {
      setState(() {
        _isUploadingPdf = true;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // 檢查文件大小 (10MB = 10 * 1024 * 1024 bytes)
        if (file.size > 10 * 1024 * 1024) {
          if (mounted) {
            CustomSnackBar.showError(context, 'PDF文件大小不能超過10MB');
          }
          return;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        final fileBytes = file.bytes;
        if (fileBytes == null) return;

        // 上傳到 Firebase Storage
        final storageRef = FirebaseStorage.instance.ref().child(
          'resumes/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );

        await storageRef.putData(fileBytes);
        final downloadUrl = await storageRef.getDownloadURL();

        setState(() {
          _resumePdfUrl = downloadUrl;
          _resumePdfName = file.name;
        });

        if (mounted) {
          CustomSnackBar.showSuccess(context, '履歷PDF上傳成功！');
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, 'PDF上傳失敗：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPdf = false;
        });
      }
    }
  }

  /// 刪除PDF履歷
  void _deleteResumePdf() {
    setState(() {
      _resumePdfUrl = null;
      _resumePdfName = null;
    });
    CustomSnackBar.showSuccess(context, '已移除履歷PDF');
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
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(bottom: 140), // 為導覽列預留空間
              child: _isEditingBasicInfo
                  ? _buildEditBasicInfoForm()
                  : _isEditingContactInfo
                  ? _buildEditContactInfoForm()
                  : _isEditingPublisherIntro
                  ? _buildEditPublisherIntroForm()
                  : _isEditingApplicantResume
                  ? _buildEditApplicantResumeForm()
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
            onEdit: () {
              setState(() {
                _isEditingBasicInfo = true;
              });
            },
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
            onEdit: () {
              setState(() {
                _isEditingContactInfo = true;
              });
            },
            children: [
              _buildInfoRow('Email', _profile['email'] ?? '未設定', Icons.email),
              _buildInfoRow('Line ID', _profile['lineId'] ?? '未設定', Icons.chat),
              _buildInfoRow('社群連結', _formatSocialLinks(), Icons.link),
            ],
          ),

          const SizedBox(height: 24),

          // 個人介紹 (發布用)
          _buildPublisherIntroSection(),

          const SizedBox(height: 24),

          // 應徵簡歷 (應徵用)
          _buildApplicantResumeSection(),
        ],
      ),
    );
  }

  Widget _buildEditBasicInfoForm() {
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
          const SizedBox(height: 32),

          // 按鈕
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isEditingBasicInfo = false;
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
                  onPressed: _isSavingBasicInfo ? null : _saveBasicInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSavingBasicInfo
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

  Widget _buildEditContactInfoForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 32),

          // 按鈕
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isEditingContactInfo = false;
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
                  onPressed: _isSavingContactInfo ? null : _saveContactInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSavingContactInfo
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

  Widget _buildEditPublisherIntroForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 個人介紹
          CustomTextField(
            controller: _publisherIntroController,
            label: '個人介紹 (發布用)',
            hintText: '簡單介紹一下自己，讓應徵者更了解你...',
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
                      _isEditingPublisherIntro = false;
                    });
                    _loadProfile();
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
                  onPressed: _isSavingPublisherIntro
                      ? null
                      : _savePublisherIntro,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSavingPublisherIntro
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

  Widget _buildEditApplicantResumeForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '應徵簡歷 (應徵用)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),

          // 學歷
          CustomTextField(
            controller: _educationController,
            label: '學歷',
            hintText: '請輸入您的最高學歷...',
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          // 駕照資訊
          Text(
            '駕照',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('汽車駕照'),
            value: _hasCarLicense,
            onChanged: (bool? value) {
              setState(() {
                _hasCarLicense = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            title: const Text('機車駕照'),
            value: _hasMotorcycleLicense,
            onChanged: (bool? value) {
              setState(() {
                _hasMotorcycleLicense = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 20),

          // PDF履歷上傳
          Text(
            '履歷PDF (< 10MB)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (_resumePdfUrl != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resumePdfName ?? '履歷.pdf',
                      style: TextStyle(color: Colors.green[800]),
                    ),
                  ),
                  IconButton(
                    onPressed: _deleteResumePdf,
                    icon: Icon(Icons.delete, color: Colors.red[600]),
                    iconSize: 20,
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _isUploadingPdf ? null : _uploadResumePdf,
              icon: _isUploadingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isUploadingPdf ? '上傳中...' : '上傳履歷PDF'),
            ),
          const SizedBox(height: 20),

          // 自我介紹
          CustomTextField(
            controller: _selfIntroController,
            label: '自我介紹',
            hintText: '描述您的技能、經驗和專長，讓雇主更了解您...',
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
                      _isEditingApplicantResume = false;
                    });
                    _loadProfile();
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
                  onPressed: _isSavingApplicantResume
                      ? null
                      : _saveApplicantResume,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSavingApplicantResume
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
    VoidCallback? onEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            if (onEdit != null)
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),
          ],
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

  Widget _buildPublisherIntroSection() {
    final publisherIntro = _profile['publisherResume']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '個人介紹 (發布用)',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isEditingPublisherIntro = true;
                });
              },
              icon: const Icon(Icons.edit, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 20,
            ),
          ],
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
            publisherIntro?.isNotEmpty == true ? publisherIntro! : '尚未填寫個人介紹',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: publisherIntro?.isNotEmpty == true
                  ? Colors.black
                  : Colors.grey[500],
              fontStyle: publisherIntro?.isNotEmpty == true
                  ? FontStyle.normal
                  : FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApplicantResumeSection() {
    final education = _profile['education']?.toString();
    final selfIntro = _profile['selfIntro']?.toString();
    final hasCarLicense = _profile['hasCarLicense'] ?? false;
    final hasMotorcycleLicense = _profile['hasMotorcycleLicense'] ?? false;
    final resumePdfName = _profile['resumePdfName']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '應徵簡歷 (應徵用)',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isEditingApplicantResume = true;
                });
              },
              icon: const Icon(Icons.edit, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 20,
            ),
          ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('學歷', education ?? '未設定', Icons.school),
              _buildInfoRow(
                '汽車駕照',
                hasCarLicense ? '有' : '無',
                Icons.directions_car,
              ),
              _buildInfoRow(
                '機車駕照',
                hasMotorcycleLicense ? '有' : '無',
                Icons.two_wheeler,
              ),
              _buildInfoRow(
                '履歷PDF',
                resumePdfName ?? '未上傳',
                Icons.picture_as_pdf,
              ),
              const Divider(),
              const Text(
                '自我介紹：',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                selfIntro?.isNotEmpty == true ? selfIntro! : '尚未填寫自我介紹',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: selfIntro?.isNotEmpty == true
                      ? Colors.black
                      : Colors.grey[500],
                  fontStyle: selfIntro?.isNotEmpty == true
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              ),
            ],
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
