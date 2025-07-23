// lib/screens/registration_view.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mvp_app/styles/app_colors.dart';

import 'dart:ui' as ui;
import 'dart:math' as math;
import '../widgets/custom_text_field.dart';
import '../widgets/custom_dropdown_field.dart';
import '../widgets/custom_date_time_field.dart';
import '../services/rekognition_service.dart';
import '../services/auth_service.dart';
import '../utils/custom_snackbar.dart';

class RegistrationView extends StatefulWidget {
  final String uid;
  final String phoneNumber;

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
  final AuthService _authService = AuthService();

  // 添加鍵盤高度跟蹤變量
  double _previousKeyboardHeight = 0.0;

  // 添加一個空的FocusNode作為默認焦點，避免輸入框自動聚焦
  late FocusNode _defaultFocusNode;

  // 添加標記變量，用於控制何時需要強制移除焦點
  bool _shouldForceClearFocus = false;

  // Step 1: 基本資訊
  final _formKey1 = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _gender;
  DateTime? _birthDate;
  String? _nameError;
  String? _genderError;
  String? _birthDateError;

  // Step 2: 大頭貼裁切
  Uint8List? _croppedImage;
  bool _isProcessingImage = false;

  // Step 3: 真人驗證
  Uint8List? _verificationImage;
  bool _isVerifying = false;
  bool _isVerified = false;
  double? _verificationScore;
  String? _verificationError;

  // Step 4: 聯絡方式
  final _formKey4 = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _lineCtrl = TextEditingController();
  final TextEditingController _socialLinksCtrl = TextEditingController();
  String? _emailError;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    print('📝 RegistrationView initState 被調用');
    print('📝 傳入參數: uid=${widget.uid}, phoneNumber=${widget.phoneNumber}');

    _defaultFocusNode = FocusNode();
    // 預先填入 Google 帳號的 email
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.email != null) {
      _emailCtrl.text = currentUser!.email!;
      print('📧 自動填入 Email: ${currentUser.email}');
    }

    print('✅ RegistrationView 初始化完成');
  }

  @override
  void dispose() {
    _defaultFocusNode.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _lineCtrl.dispose();
    _socialLinksCtrl.dispose();
    super.dispose();
  }

  // Email 格式驗證
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // 檢查鍵盤狀態變化
  void _handleKeyboardChange(double currentKeyboardHeight) {
    // 如果鍵盤從顯示狀態變為隱藏狀態，移除焦點
    if (_previousKeyboardHeight > 0 && currentKeyboardHeight == 0) {
      FocusScope.of(context).unfocus();
    }
    _previousKeyboardHeight = currentKeyboardHeight;
  }

  // 重置驗證狀態
  void _resetVerificationState() {
    _verificationImage = null;
    _isVerifying = false;
    _isVerified = false;
    _verificationScore = null;
    _verificationError = null;
  }

  // 提交全部資料：上傳 Storage、寫入 Firestore
  Future<void> _submitAll() async {
    _validateCurrentStep();
    if (!_canProceed() || _croppedImage == null) {
      CustomSnackBar.showWarning(context, '請確認所有欄位填寫與上傳大頭貼');
      return;
    }
    setState(() => _loading = true);

    try {
      print('🚀 開始註冊流程...');

      // 1. 上傳裁切後影像到 Firebase Storage
      print('📤 上傳頭像到 Firebase Storage...');
      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/${widget.uid}.jpg',
      );
      await storageRef.putData(
        _croppedImage!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final avatarUrl = await storageRef.getDownloadURL();
      print('頭像上傳成功: $avatarUrl');

      // 2. 準備社群連結 Map
      Map<String, String> socialLinks = {};
      if (_socialLinksCtrl.text.trim().isNotEmpty) {
        socialLinks['other'] = _socialLinksCtrl.text.trim();
      }

      // 3. 寫入 Firestore user 集合
      print('💾 寫入用戶資料到 Firestore...');
      final userData = {
        'userId': widget.uid,
        'name': _nameCtrl.text.trim(),
        'gender': _gender,
        'birthday': Timestamp.fromDate(_birthDate!),
        'avatarUrl': avatarUrl,
        'isVerified': _isVerified, // 使用實際的驗證狀態
        'phoneNumber': widget.phoneNumber,
        'email': _emailCtrl.text.trim(),
        'lineId': _lineCtrl.text.trim(),
        'socialLinks': socialLinks,
        'publisherResume': '', // 發布者簡介（發布用）
        'applicantResume': '', // 舊的應徵簡歷欄位，保持向後相容
        // 新的應徵簡歷詳細欄位
        'education': '', // 學歷
        'selfIntro': '', // 自我介紹
        'hasCarLicense': false, // 汽車駕照
        'hasMotorcycleLicense': false, // 機車駕照
        'subscriptionStatus': 'free',
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('user')
          .doc(widget.uid)
          .set(userData);
      print('用戶資料寫入成功');

      // 4. 驗證寫入是否成功
      print('🔍 驗證用戶資料是否成功寫入...');
      final doc = await FirebaseFirestore.instance
          .collection('user')
          .doc(widget.uid)
          .get();
      if (doc.exists) {
        print('用戶資料驗證成功');

        // 5. 導向主流程
        if (mounted) {
          print('✅ 註冊完成，重新載入應用讓 AuthGate 檢查狀態');
          // 註冊完成後，重新載入根頁面讓 AuthGate 重新檢查用戶註冊狀態
          // 這次檢查會發現用戶已註冊，自動跳轉到主頁面
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/', // 回到根路由，讓 AuthGate 重新判斷
            (route) => false,
          );
        }
      } else {
        throw Exception('用戶資料寫入失敗，請重試');
      }
    } catch (e) {
      print(' 註冊失敗: $e');

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(34),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 標題
                  Text(
                    '註冊失敗',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 內容
                  Text(
                    '註冊過程中發生錯誤，請重試。',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // 錯誤詳情容器
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      '錯誤詳情：$e',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 確定按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('確定', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // 步驟進度條
  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(4, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
            decoration: BoxDecoration(
              color: isCompleted || isCurrent
                  ? AppColors.primary
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _pickAndCropImage() async {
    if (_isProcessingImage) return;

    // 顯示選擇對話框
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(34),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                Text(
                  '選擇照片來源',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 24),
                // 拍照選項
                InkWell(
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          '拍照',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 相簿選擇選項
                InkWell(
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          '從相簿選擇',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 取消按鈕
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    setState(() => _isProcessingImage = true);

    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) {
        setState(() => _isProcessingImage = false);
        return;
      }

      final bytes = await picked.readAsBytes();

      // 自動裁切
      await _performAutoCrop(bytes);
    } catch (e) {
      setState(() => _isProcessingImage = false);
      CustomSnackBar.showError(context, '選擇圖片失敗：$e');
    }
  }

  // 新增：自動裁切方法
  Future<void> _performAutoCrop(Uint8List imageBytes) async {
    try {
      // 使用 dart:ui 套件計算正方形裁切
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width;
      final height = image.height;
      final size = math.min(width, height);
      final offsetX = (width - size) / 2;
      final offsetY = (height - size) / 2;

      // 創建畫布進行裁切
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final srcRect = Rect.fromLTWH(
        offsetX,
        offsetY,
        size.toDouble(),
        size.toDouble(),
      );
      final destRect = Rect.fromLTWH(0, 0, 300, 300); // 固定輸出尺寸為 300x300

      canvas.drawImageRect(image, srcRect, destRect, Paint());

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(300, 300);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        setState(() {
          _croppedImage = byteData.buffer.asUint8List();
          _isProcessingImage = false;
        });
      } else {
        throw '無法處理圖片';
      }
    } catch (e) {
      setState(() => _isProcessingImage = false);
      CustomSnackBar.showError(context, '自動裁切失敗：$e');
    }
  }

  // 真人驗證拍照
  Future<void> _captureVerificationPhoto() async {
    if (_isVerifying || _croppedImage == null) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 70, // 降低畫質以減少文件大小
        maxWidth: 1024, // 限制最大寬度
        maxHeight: 1024, // 限制最大高度
      );

      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      // 檢查文件大小（AWS Rekognition 限制 5MB）
      if (bytes.length > 5 * 1024 * 1024) {
        print(
          '照片文件過大，請重新拍攝。當前大小: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB',
        );
        setState(() {
          _verificationError = '照片文件過大';
        });
        return;
      }

      setState(() {
        _verificationImage = bytes;
        _verificationError = null;
      });

      // 自動進行驗證
      await _performFaceVerification();
    } catch (e) {
      print('拍照失敗: $e');
      setState(() {
        _verificationError = '拍照失敗';
      });
    }
  }

  // 執行人臉驗證
  Future<void> _performFaceVerification() async {
    if (_croppedImage == null || _verificationImage == null) return;

    setState(() {
      _isVerifying = true;
      _verificationError = null;
    });

    try {
      // 調試：測試 AWS 憑證
      RekognitionService.testCredentials();

      final result = await RekognitionService.compareFaces(
        _croppedImage!,
        _verificationImage!,
      );

      setState(() {
        _verificationScore = result.similarity;
        _isVerifying = false;

        if (!result.isSuccess) {
          // 如果API調用失敗，設定驗證為失敗
          _isVerified = false;
          _verificationError = '驗證失敗';
          print('驗證失敗: ${result.errorMessage}');
        } else {
          // 如果API調用成功，使用返回的驗證結果
          _isVerified = result.isVerified;
          if (!_isVerified) {
            _verificationError = '驗證未通過';
            if (result.similarity != null) {
              print('驗證未通過，相似度: ${result.similarity!.toStringAsFixed(1)}%');
            }
            if (result.errorMessage != null) {
              print('錯誤訊息: ${result.errorMessage}');
            }
          } else {
            // 驗證通過，清除錯誤
            _verificationError = null;
          }
        }
      });

      // 在控制台輸出結果
      if (_isVerified) {
        print('驗證通過！相似度: ${result.similarity!.toStringAsFixed(1)}%');
      } else {
        print('驗證失敗或未通過');
      }
    } catch (e) {
      print('驗證過程中發生錯誤: $e');
      setState(() {
        _isVerifying = false;
        _isVerified = false; // 發生錯誤時設定為驗證失敗
        _verificationError = '驗證錯誤';
      });
    }
  }

  // 處理離開註冊流程
  Future<void> _handleExitRegistration() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 標題
              const Text(
                '確認離開註冊？',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 24),
              // 內容
              Text(
                '離開註冊流程將會登出您的帳號，\n之前填寫的資料將不會被儲存。',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 警告資訊容器
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '離開將會清除所有內容',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 按鈕組
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        '繼續註冊',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[600],
                        side: BorderSide(color: Colors.red[600]!),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        '確認離開',
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
        ),
      ),
    );

    if (shouldExit == true) {
      await _performExitAndSignOut();
    }
  }

  // 執行登出並導航
  Future<void> _performExitAndSignOut() async {
    try {
      setState(() => _loading = true);

      print('🔄 註冊頁面：執行登出...');
      // 先登出用戶
      await _authService.signOut();

      print('✅ 註冊頁面：登出成功，等待 AuthGate 自動處理導航');
      // 不需要手動導航，AuthGate 會自動監聽狀態變化並跳轉
    } catch (e) {
      print('❌ 登出過程發生錯誤: $e');

      // 即使登出失敗，也顯示警告訊息
      if (mounted) {
        CustomSnackBar.showWarning(context, '登出過程中發生問題，請重新嘗試');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 監聽鍵盤高度變化
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleKeyboardChange(keyboardHeight);
      // 只在用戶明確操作後才強制移除焦點
      if (_shouldForceClearFocus) {
        FocusScope.of(context).unfocus();
        _shouldForceClearFocus = false; // 重置標記
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: TextButton(
          onPressed: _loading ? null : _handleExitRegistration,
          child: Text(
            '離開',
            style: TextStyle(
              fontSize: 16,
              color: _loading ? Colors.grey : AppColors.greyDark,
            ),
          ),
        ),
        leadingWidth: 80,
        // 在真人驗證步驟時顯示重置按鈕
        actions: _currentStep == 2 && _verificationImage != null
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _resetVerificationState();
                  }),
                  child: const Text(
                    '重置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              // 點擊空白區域時移除所有焦點
              FocusScope.of(context).unfocus();
            },
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Column(
                  children: [
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

                    // 進度條 + 底部操作按鈕
                    Container(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 步驟進度條移動到這裡
                          _buildStepIndicator(),
                          const SizedBox(height: 16),
                          // 控制按鈕
                          Row(
                            children: [
                              // 上一步按鈕
                              if (_currentStep > 0)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() {
                                      // 如果從驗證步驟返回，重置驗證狀態
                                      if (_currentStep == 2) {
                                        _resetVerificationState();
                                      }
                                      _currentStep--;
                                      _shouldForceClearFocus =
                                          true; // 設置標記確保返回上一步後強制移除焦點
                                    }),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey[500],
                                      side: BorderSide(
                                        color: Colors.grey[400]!,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24.0,
                                        vertical: 16,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('上一步'),
                                  ),
                                ),

                              // 間距
                              if (_currentStep > 0) const SizedBox(width: 12),

                              // 下一步/完成按鈕
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _canProceed() ? _handleNext : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                      vertical: 16,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Text(_getNextButtonText()),
                                ),
                              ),
                            ],
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
        return '真人驗證確保帳號安全';
      case 3:
        return '最後，讓大家聯絡到你';
      default:
        return '';
    }
  }

  String _getNextButtonText() {
    switch (_currentStep) {
      case 0:
      case 1:
        return '下一步';
      case 2:
        // 驗證步驟：成功顯示"下一步"，失敗或尚未驗證顯示"略過"
        return _isVerified ? '下一步' : '略過';
      case 3:
        return '完成';
      default:
        return '下一步';
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
    return Column(
      children: [
        CustomTextField(
          controller: _nameCtrl,
          label: '姓名',
          isRequired: true,
          errorText: _nameError,
          textInputAction: TextInputAction.next,
          onChanged: (value) {
            // 只在有錯誤狀態需要清除時才調用setState，減少不必要的重新構建
            if (_nameError != null && value.isNotEmpty) {
              setState(() {
                _nameError = null;
              });
            }
          },
        ),
        const SizedBox(height: 24),
        CustomDropdownField<String>(
          label: '性別',
          value: _gender,
          isRequired: true,
          errorText: _genderError,
          icon: Icons.wc,
          items: const [
            DropdownMenuItem(value: 'male', child: Text('男')),
            DropdownMenuItem(value: 'female', child: Text('女')),
            DropdownMenuItem(value: 'other', child: Text('其他')),
          ],
          onChanged: (value) {
            // 先移除焦點以避免重新構建後焦點跳回姓名輸入框
            FocusScope.of(context).unfocus();
            setState(() {
              _gender = value;
              if (value != null) _genderError = null;
              _shouldForceClearFocus = true; // 設置標記確保重新構建後強制移除焦點
            });
          },
        ),
        const SizedBox(height: 24),
        CustomDateTimeField(
          label: '生日',
          isRequired: true,
          icon: Icons.calendar_today,
          selectedDate: _birthDate,
          errorText: _birthDateError,
          onDateTap: () async {
            // 先移除焦點以避免重新構建後焦點跳回姓名輸入框
            FocusScope.of(context).unfocus();
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(1990),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (date != null && mounted) {
              setState(() {
                _birthDate = date;
                _birthDateError = null;
                _shouldForceClearFocus = true; // 設置標記確保重新構建後強制移除焦點
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildAvatarStep() {
    return Column(
      children: [
        SizedBox(height: 24),
        // 頭像顯示區域 - 使用固定高度容器
        Center(
          child: GestureDetector(
            onTap: _isProcessingImage ? null : _pickAndCropImage,
            child: Stack(
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _croppedImage != null
                          ? Colors.green[300]!
                          : Colors.grey[300]!,
                      width: 2.8,
                    ),
                  ),
                  child: _croppedImage != null
                      ? ClipOval(
                          child: Image.memory(
                            _croppedImage!,
                            width: 150,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[100],
                          ),
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey[400],
                          ),
                        ),
                ),

                // 處理中的遮罩
                if (_isProcessingImage)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 右下角的相機圖標
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _croppedImage != null
                          ? Colors.green[600]
                          : Colors.grey[400],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.8),
                    ),
                    child: Icon(
                      _croppedImage != null ? Icons.check : Icons.edit,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 狀態文字區域 - 使用固定高度容器避免UI移動
        Container(
          height: 60, // 固定高度
          alignment: Alignment.center,
          child: Text(
            _isProcessingImage
                ? '處理中...'
                : _croppedImage != null
                ? '頭像已設定完成'
                : '點擊拍照或選擇頭像照片',
            style: TextStyle(
              color: _croppedImage != null
                  ? Colors.green[600]
                  : Colors.grey[400],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2, // 限制最大行數
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      children: [
        SizedBox(height: 24),

        // 驗證照片區域 - 使用與頭像上傳相同的乾淨UI
        Center(
          child: GestureDetector(
            onTap: _croppedImage == null || _isVerifying
                ? null
                : _captureVerificationPhoto,
            child: Stack(
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isVerified
                          ? Colors.green[300]!
                          : (_verificationError != null
                                ? Colors.red[300]!
                                : Colors.grey[300]!),
                      width: 2.8,
                    ),
                  ),
                  child: _verificationImage != null
                      ? ClipOval(
                          child: Image.memory(
                            _verificationImage!,
                            width: 150,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[100],
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 60,
                            color: Colors.grey[400],
                          ),
                        ),
                ),

                // 驗證中的遮罩
                if (_isVerifying)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 右下角的狀態圖標
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isVerified
                          ? Colors.green[600]
                          : (_verificationError != null
                                ? Colors.red[600]
                                : Colors.grey[400]),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.8),
                    ),
                    child: Icon(
                      _isVerified
                          ? Icons.verified
                          : (_verificationError != null
                                ? Icons.close
                                : Icons.verified),
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 狀態文字區域 - 使用固定高度容器避免UI移動
        Container(
          height: 60, // 固定高度
          alignment: Alignment.center,
          child: Text(
            _isVerifying
                ? '正在驗證中...'
                : _isVerified
                ? '恭喜你！驗證通過'
                : (_verificationError != null ? '驗證失敗，點擊重新拍照' : '點擊拍照進行真人驗證'),
            style: TextStyle(
              color: _isVerified
                  ? Colors.green[600]
                  : (_verificationError != null
                        ? Colors.red[600]
                        : Colors.grey[400]),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2, // 限制最大行數
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(height: 32),

        // 說明文字
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '溫馨提醒：',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '• 請確保光線充足，避免過亮或過暗',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                '• 正面拍攝，避免側臉或仰頭',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                '• 請勿佩戴口罩、帽子或墨鏡',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '• 保持表情自然，眼睛看向鏡頭',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactStep() {
    return Column(
      children: [
        CustomTextField(
          controller: _emailCtrl,
          label: '聯絡信箱',
          isRequired: true,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (value) {
            // 只在錯誤狀態需要改變時才調用setState
            String? newError;
            if (value.isNotEmpty) {
              if (!_isValidEmail(value)) {
                newError = 'Email格式不正確';
              }
            }

            if (_emailError != newError) {
              setState(() {
                _emailError = newError;
              });
            }
          },
        ),
        const SizedBox(height: 24),
        CustomTextField(
          controller: _lineCtrl,
          label: 'Line ID',
          hintText: '選填',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 24),
        CustomTextField(
          controller: _socialLinksCtrl,
          label: '社群連結',
          hintText: 'Instagram、Facebook 等社群平台連結',
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _nameCtrl.text.isNotEmpty &&
            _gender != null &&
            _birthDate != null;
      case 1:
        return _croppedImage != null && !_isProcessingImage;
      case 2:
        return !_isVerifying; // 只要不在驗證中就可以通過，不管成功或失敗
      case 3:
        return _emailCtrl.text.isNotEmpty &&
            _isValidEmail(_emailCtrl.text) &&
            _emailError == null;
      default:
        return false;
    }
  }

  void _handleNext() {
    if (_currentStep < 3) {
      _validateCurrentStep();
      if (_canProceed()) {
        setState(() {
          _currentStep++;
          _shouldForceClearFocus = true; // 設置標記確保切換步驟後強制移除焦點

          // 進入驗證步驟時，重置驗證狀態
          if (_currentStep == 2) {
            _resetVerificationState();
          }
        });
      }
    } else {
      _submitAll();
    }
  }

  void _validateCurrentStep() {
    // 在驗證之前先移除焦點，避免驗證時焦點跳轉
    FocusScope.of(context).unfocus();

    switch (_currentStep) {
      case 0:
        setState(() {
          _nameError = _nameCtrl.text.isEmpty ? '請輸入姓名' : null;
          _genderError = _gender == null ? '請選擇性別' : null;
          _birthDateError = _birthDate == null ? '請選擇生日' : null;
        });
        break;
      case 3:
        setState(() {
          if (_emailCtrl.text.isEmpty) {
            _emailError = '請輸入信箱';
          } else if (!_isValidEmail(_emailCtrl.text)) {
            _emailError = 'Email格式不正確';
          } else {
            _emailError = null;
          }
        });
        break;
    }
  }
}
