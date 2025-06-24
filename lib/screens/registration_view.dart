// lib/screens/registration_view.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';

class RegistrationView extends StatefulWidget {
  final String uid;
  final String phoneNumber; // 新增：從登入時傳入的手機號碼
  const RegistrationView({
    super.key,
    required this.uid,
    required this.phoneNumber,
  });

  @override
  State<RegistrationView> createState() => _RegistrationViewState();
}

class _RegistrationViewState extends State<RegistrationView> {
  int _currentStep = 0;
  bool _loading = false;

  // Step 1: 基本資訊
  final _formKey1 = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _gender;
  DateTime? _birthDate;

  // Step 2: 大頭貼裁切
  Uint8List? _rawImage;
  Uint8List? _croppedImage;
  final CropController _cropController = CropController();

  // Step 3: 真人驗證（跳過）
  // 此步驟暫時跳過，未來實作

  // Step 4: 聯絡方式
  final _formKey4 = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _lineCtrl = TextEditingController();
  final TextEditingController _socialLinksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _lineCtrl.dispose();
    _socialLinksCtrl.dispose();
    super.dispose();
  }

  // 選圖並讀取 bytes
  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _rawImage = bytes);
  }

  // Email 格式驗證
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // 提交全部資料：上傳 Storage、寫入 Firestore
  // 提交全部資料：上傳 Storage、寫入 Firestore
  Future<void> _submitAll() async {
    if (!_formKey4.currentState!.validate() || _croppedImage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請確認所有欄位填寫與上傳大頭貼')));
      return;
    }
    setState(() => _loading = true);

    try {
      // 1. 上傳裁切後影像到 Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/${widget.uid}.jpg',
      );
      await storageRef.putData(
        _croppedImage!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final avatarUrl = await storageRef.getDownloadURL();

      // 2. 準備社群連結 Map
      Map<String, String> socialLinks = {};
      if (_socialLinksCtrl.text.trim().isNotEmpty) {
        socialLinks['other'] = _socialLinksCtrl.text.trim();
      }

      // 3. 寫入 Firestore user 集合
      await FirebaseFirestore.instance.collection('user').doc(widget.uid).set({
        'userId': widget.uid,
        'name': _nameCtrl.text.trim(),
        'gender': _gender,
        'birthday': Timestamp.fromDate(_birthDate!),
        'avatarUrl': avatarUrl,
        'isVerified': true,
        'phoneNumber': widget.phoneNumber,
        'email': _emailCtrl.text.trim(),
        'lineId': _lineCtrl.text.trim(),
        'socialLinks': socialLinks,
        'publisherResume': '', // 空的字串，後續填寫
        'applicantResume': '', // 空的字串，後續填寫
        'subscriptionStatus': 'free',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. 導向主流程
      if (mounted) {
        // 檢查是否已有註冊記錄來決定跳轉到哪個頁面
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/parent', // 或根據用戶類型決定
          (route) => false,
        );
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('上傳失敗'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  // 步驟進度條
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(4, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? Theme.of(context).primaryColor
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        elevation: 0,
        leading: TextButton(
          onPressed: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/auth', (route) => false);
          },
          child: const Text('離開', style: TextStyle(fontSize: 16)),
        ),
        leadingWidth: 80,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 步驟進度條
              _buildStepIndicator(),

              // 主內容區
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 步驟標題
                      Text(
                        _getStepTitle(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 步驟內容
                      _buildStepContent(),
                    ],
                  ),
                ),
              ),

              // 底部操作按鈕
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    // 上一步/跳過按鈕
                    // 上一步/跳過按鈕
                    if (_currentStep > 0)
                      TextButton(
                        onPressed: () => setState(() => _currentStep--),
                        child: const Text('上一步'),
                      ),
                    if (_currentStep == 2) // 真人驗證步驟可跳過
                      TextButton(
                        onPressed: () => setState(() => _currentStep++),
                        child: const Text('跳過'),
                      ),

                    const Spacer(),

                    // 下一步/完成按鈕
                    ElevatedButton(
                      onPressed: _canProceed() ? _handleNext : null,
                      child: Text(_currentStep == 3 ? '完成' : '下一步'),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 載入中遮罩
          if (_loading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return '首先，讓大家認識你';
      case 1:
        return '上傳一張正面照片';
      case 2:
        return '真人驗證提升你的信任形象';
      case 3:
        return '最後，讓大家聯絡到你';
      default:
        return '';
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildBasicInfoStep();
      case 1:
        return _buildAvatarStep();
      case 2:
        return _buildVerificationStep();
      case 3:
        return _buildContactStep();
      default:
        return Container();
    }
  }

  Widget _buildBasicInfoStep() {
    return Form(
      key: _formKey1,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '姓名 *',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.isEmpty ? '必填' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(
              labelText: '性別 *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'male', child: Text('男')),
              DropdownMenuItem(value: 'female', child: Text('女')),
              DropdownMenuItem(value: 'other', child: Text('其他')),
            ],
            onChanged: (v) => setState(() => _gender = v),
            validator: (v) => v == null ? '必選' : null,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() => _birthDate = date);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _birthDate == null
                          ? '生日 *'
                          : '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _birthDate == null
                            ? Colors.grey[600]
                            : Colors.black,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarStep() {
    return Column(
      children: [
        if (_croppedImage != null)
          // 已裁切完成：顯示圓形頭貼
          ClipOval(
            child: Image.memory(
              _croppedImage!,
              width: 150,
              height: 150,
              fit: BoxFit.cover,
            ),
          )
        else if (_rawImage != null)
          // 尚未裁切：顯示 Crop UI
          SizedBox(
            height: 300,
            child: Crop(
              image: _rawImage!,
              controller: _cropController,
              aspectRatio: 1,
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    setState(() => _croppedImage = croppedImage);
                    break;
                  case CropFailure(:final cause):
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('裁切失敗: $cause')));
                    break;
                }
              },
            ),
          )
        else
          // 尚未選擇圖片：顯示圓形佔位符
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: const Icon(Icons.person, size: 80, color: Colors.grey),
          ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _rawImage == null
                ? _pickImage
                : () => _cropController.crop(),
            icon: const Icon(Icons.upload_file),
            label: Text(_rawImage == null ? '上傳大頭照' : '裁切並完成'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.verified_user, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  '自拍驗證',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '通過真人驗證可提升帳號信任度\n讓更多人願意與你合作',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: null, // 功能未實作，暫時 disabled
                    child: const Text('開始驗證'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactStep() {
    return Form(
      key: _formKey4,
      child: Column(
        children: [
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '聯絡信箱 *',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v!.isEmpty) return '必填';
              if (!_isValidEmail(v)) return 'Email格式不正確';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lineCtrl,
            decoration: const InputDecoration(
              labelText: 'Line ID (選填)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _socialLinksCtrl,
            decoration: const InputDecoration(
              labelText: '社群連結 (選填)',
              border: OutlineInputBorder(),
              hintText: 'Instagram、Facebook 等社群平台連結',
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _nameCtrl.text.isNotEmpty &&
            _gender != null &&
            _birthDate != null;
      case 1:
        return _croppedImage != null;
      case 2:
        return true; // 真人驗證可跳過
      case 3:
        return true; // 改為總是返回 true，讓完成按鈕隨時可用
      default:
        return false;
    }
  }

  void _handleNext() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _submitAll();
    }
  }
}
