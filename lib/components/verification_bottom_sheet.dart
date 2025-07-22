import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../utils/custom_snackbar.dart';

// 10. 身份認證彈窗
class VerificationBottomSheet extends StatefulWidget {
  final String userId;
  final String? currentAvatarUrl;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const VerificationBottomSheet({
    Key? key,
    required this.userId,
    this.currentAvatarUrl,
    required this.onComplete,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<VerificationBottomSheet> createState() =>
      _VerificationBottomSheetState();
}

class _VerificationBottomSheetState extends State<VerificationBottomSheet> {
  int _currentStep = 0;
  bool _loading = false;

  // Step 1: 大頭貼
  Uint8List? _croppedImage;
  bool _isProcessingImage = false;

  // Step 2: 真人驗證
  Uint8List? _verificationImage;
  bool _isVerifying = false;
  bool _isVerified = false;
  double? _verificationScore;
  String? _verificationError;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 如果有現有頭像，載入並設置為可進行下一步
    if (widget.currentAvatarUrl?.isNotEmpty == true) {
      _loadExistingAvatar();
    }
  }

  // 載入現有頭像
  Future<void> _loadExistingAvatar() async {
    try {
      // 標記用戶有現有頭像，可以進入下一步
      // 在實際驗證時會需要下載圖片進行比對
    } catch (e) {
      print('載入現有頭像失敗: $e');
    }
  }

  // 重置驗證狀態
  void _resetVerificationState() {
    _verificationImage = null;
    _isVerifying = false;
    _isVerified = false;
    _verificationScore = null;
    _verificationError = null;
  }

  // 選擇並自動裁切頭像
  Future<void> _pickAndCropImage() async {
    if (_isProcessingImage) return;

    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '選擇照片來源',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              InkWell(
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.camera_alt, color: Colors.blue, size: 24),
                      SizedBox(width: 16),
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
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.photo_library, color: Colors.green, size: 24),
                      SizedBox(width: 16),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '取消',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );

    if (source == null) return;

    if (mounted) {
      setState(() => _isProcessingImage = true);
    }

    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) {
        if (mounted) {
          setState(() => _isProcessingImage = false);
        }
        return;
      }

      final bytes = await picked.readAsBytes();
      await _performAutoCrop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingImage = false);
        CustomSnackBar.showError(context, '選擇圖片失敗：$e');
      }
    }
  }

  // 自動裁切方法
  Future<void> _performAutoCrop(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width;
      final height = image.height;
      final size = math.min(width, height);
      final offsetX = (width - size) / 2;
      final offsetY = (height - size) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final srcRect = Rect.fromLTWH(
        offsetX,
        offsetY,
        size.toDouble(),
        size.toDouble(),
      );
      final destRect = Rect.fromLTWH(0, 0, 300, 300);

      canvas.drawImageRect(image, srcRect, destRect, Paint());

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(300, 300);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        if (mounted) {
          setState(() {
            _croppedImage = byteData.buffer.asUint8List();
            _isProcessingImage = false;
          });
        }
      } else {
        throw '無法處理圖片';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingImage = false);
        CustomSnackBar.showError(context, '自動裁切失敗：$e');
      }
    }
  }

  // 真人驗證拍照
  Future<void> _captureVerificationPhoto() async {
    if (_isVerifying || _croppedImage == null) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          setState(() {
            _verificationError = '照片文件過大';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _verificationImage = bytes;
          _verificationError = null;
        });
      }

      await _performFaceVerification();
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationError = '拍照失敗';
        });
      }
    }
  }

  // 執行人臉驗證（模擬版本）
  Future<void> _performFaceVerification() async {
    if (_croppedImage == null || _verificationImage == null) return;

    if (mounted) {
      setState(() {
        _isVerifying = true;
        _verificationError = null;
      });
    }

    try {
      // 模擬驗證過程
      await Future.delayed(const Duration(seconds: 2));

      // 檢查是否仍然 mounted
      if (!mounted) return;

      // 模擬結果
      final random = math.Random();
      final similarity = 75.0 + random.nextDouble() * 20; // 75-95% 相似度
      final isVerified = similarity >= 80.0;

      if (mounted) {
        setState(() {
          _verificationScore = similarity;
          _isVerifying = false;
          _isVerified = isVerified;

          if (!isVerified) {
            _verificationError = '驗證未通過';
          } else {
            _verificationError = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isVerified = false;
          _verificationError = '驗證錯誤';
        });
      }
    }
  }

  // 完成認證並更新資料庫
  Future<void> _completeVerification() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      // 更新 Firestore 中的 isVerified 狀態
      await FirebaseFirestore.instance
          .collection('user')
          .doc(widget.userId)
          .update({'isVerified': _isVerified});

      if (mounted) {
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '更新失敗：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // 步驟進度條
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(2, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: index < 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: index <= _currentStep
                            ? Colors.blue[600]
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 主內容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStepTitle(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildStepContent(),
                  ],
                ),
              ),
            ),

            // 底部按鈕
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[100]!)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            if (_currentStep == 1) {
                              _resetVerificationState();
                            }
                            _currentStep--;
                          }),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('上一步'),
                        ),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canProceed() ? _handleNext : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(_getNextButtonText()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // 載入遮罩
        if (_loading)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return '上傳頭像照片';
      case 1:
        return '真人驗證';
      default:
        return '';
    }
  }

  String _getNextButtonText() {
    switch (_currentStep) {
      case 0:
        return '下一步';
      case 1:
        if (_isVerifying) {
          return '驗證中...';
        } else if (_isVerified) {
          return '完成認證';
        } else {
          return '請完成驗證';
        }
      default:
        return '下一步';
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildAvatarStep();
      case 1:
        return _buildVerificationStep();
      default:
        return Container();
    }
  }

  Widget _buildAvatarStep() {
    return Column(
      children: [
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
                          : Colors.blue[300]!,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_croppedImage != null ? Colors.green : Colors.blue)
                                .withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                      : (widget.currentAvatarUrl?.isNotEmpty == true
                            ? ClipOval(
                                child: Image.network(
                                  widget.currentAvatarUrl!,
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.grey[100],
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.grey[400],
                                      ),
                                    );
                                  },
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
                              )),
                ),

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

                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _croppedImage != null
                          ? Colors.green[600]
                          : Colors.blue[600],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
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

        Container(
          height: 60,
          alignment: Alignment.center,
          child: Text(
            _isProcessingImage
                ? '處理中...'
                : _croppedImage != null
                ? '頭像已設定完成，點擊可重新選擇'
                : (widget.currentAvatarUrl?.isNotEmpty == true
                      ? '使用目前頭像照片進行認證，點擊可重新選擇'
                      : '點擊上方圓圈更新頭像照片'),
            style: TextStyle(
              color:
                  (_croppedImage != null ||
                      widget.currentAvatarUrl?.isNotEmpty == true)
                  ? Colors.green[600]
                  : Colors.blue[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      children: [
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
                                : Colors.blue[300]!),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isVerified
                                    ? Colors.green
                                    : (_verificationError != null
                                          ? Colors.red
                                          : Colors.blue))
                                .withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                                : Colors.blue[600]),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      _isVerified
                          ? Icons.check
                          : (_verificationError != null
                                ? Icons.close
                                : Icons.camera_alt),
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

        Container(
          height: 80,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isVerifying
                    ? '正在驗證中...'
                    : _isVerified
                    ? '驗證通過！'
                    : (_verificationError != null
                          ? '驗證失敗，點擊重新拍照'
                          : '點擊上方圓圈拍照進行真人驗證'),
                style: TextStyle(
                  color: _isVerified
                      ? Colors.green[600]
                      : (_verificationError != null
                            ? Colors.red[600]
                            : Colors.blue[600]),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              if (_verificationScore != null) ...[
                const SizedBox(height: 8),
                Text(
                  '相似度：${_verificationScore!.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '溫馨提醒：',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '• 請確保光線充足，避免過亮或過暗\n'
                '• 正面拍攝，避免側臉或仰頭\n'
                '• 請勿佩戴口罩、帽子或墨鏡\n'
                '• 保持表情自然，眼睛看向鏡頭',
                style: TextStyle(color: Colors.blue[700], fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        // 第一步：有新上傳的圖片或有現有頭像URL都可以進入下一步
        return (_croppedImage != null && !_isProcessingImage) ||
            (widget.currentAvatarUrl?.isNotEmpty == true);
      case 1:
        // 第二步：必須驗證成功才能完成認證
        return !_isVerifying && _isVerified;
      default:
        return false;
    }
  }

  void _handleNext() {
    if (_currentStep < 1) {
      setState(() {
        _currentStep++;
        if (_currentStep == 1) {
          _resetVerificationState();
          // 如果沒有裁切圖片但有現有頭像，需要載入現有頭像進行驗證
          if (_croppedImage == null &&
              widget.currentAvatarUrl?.isNotEmpty == true) {
            _downloadAndSetExistingAvatar();
          }
        }
      });
    } else {
      _completeVerification();
    }
  }

  // 下載並設置現有頭像為驗證用圖片
  Future<void> _downloadAndSetExistingAvatar() async {
    try {
      if (mounted) {
        setState(() => _isProcessingImage = true);
      }

      final response = await http.get(Uri.parse(widget.currentAvatarUrl!));

      // 檢查是否仍然 mounted
      if (!mounted) return;

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await _performAutoCrop(bytes);
      }
    } catch (e) {
      print('下載現有頭像失敗: $e');
      if (mounted) {
        setState(() => _isProcessingImage = false);
      }
    }
  }
}
