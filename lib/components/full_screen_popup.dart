// lib/components/full_screen_popup.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class FullScreenPopup extends StatelessWidget {
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onBack;
  final String? title;
  final Widget? titleWidget;

  const FullScreenPopup({
    Key? key,
    required this.child,
    this.onClose,
    this.onBack,
    this.title,
    this.titleWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        leading: onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: onBack,
              )
            : null,
        elevation: 0,
        backgroundColor: Colors.white,
        title:
            titleWidget ??
            Text(
              title ?? '',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: onClose ?? () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: child, // 直接使用 child，不包装在 SingleChildScrollView 中
      ),
    );
  }
}

// 2. 應徵者列表彈窗
class ApplicantsListBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> applicants;
  final Function(Map<String, dynamic>) onApplicantTap;

  const ApplicantsListBottomSheet({
    Key? key,
    required this.applicants,
    required this.onApplicantTap,
  }) : super(key: key);

  // 在 ApplicantsListBottomSheet 中修改 build 方法：
  @override
  Widget build(BuildContext context) {
    if (applicants.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '目前沒有應徵者',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: applicants.length,
      itemBuilder: (context, index) {
        final applicant = applicants[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.person, color: Colors.blue[600], size: 24),
            ),
            title: Text(
              applicant['name'] ?? '未設定名稱', // ✅ 改用 name 欄位
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (applicant['applicantResume']?.toString().isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 8),
                  Text(
                    applicant['applicantResume'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => onApplicantTap(applicant),
          ),
        );
      },
    );
  }
}

// 3. 應徵者詳情彈窗
class ApplicantProfileBottomSheet extends StatelessWidget {
  final Map<String, dynamic> applicant;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onBack;

  const ApplicantProfileBottomSheet({
    Key? key,
    required this.applicant,
    required this.onAccept,
    required this.onReject,
    required this.onBack,
  }) : super(key: key);

  @override
  // 在 ApplicantProfileBottomSheet 中修改顯示邏輯：
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.blue[100],
                backgroundImage:
                    applicant['avatarUrl']?.toString().isNotEmpty == true
                    ? NetworkImage(applicant['avatarUrl'])
                    : null,
                child: applicant['avatarUrl']?.toString().isNotEmpty != true
                    ? Icon(Icons.person, color: Colors.blue[600], size: 40)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      applicant['name'] ?? '未設定名稱', // ✅ 改用 name 欄位
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 聯絡資訊
          if (applicant['phoneNumber']?.toString().isNotEmpty == true)
            _buildInfoCard('聯絡電話', applicant['phoneNumber'], Icons.phone),
          if (applicant['email']?.toString().isNotEmpty == true)
            _buildInfoCard('Email', applicant['email'], Icons.email),
          if (applicant['lineId']?.toString().isNotEmpty == true)
            _buildInfoCard('Line ID', applicant['lineId'], Icons.chat),
          if (applicant['applicantResume']?.toString().isNotEmpty ==
              true) // ✅ 改用 applicantResume
            _buildInfoCard(
              '個人履歷',
              applicant['applicantResume'],
              Icons.description,
            ),

          // 其餘按鈕保持不變...
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String content, IconData icon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 16, height: 1.4)),
        ],
      ),
    );
  }
}

// 5. 編輯個人資料彈窗
class EditProfileBottomSheet extends StatefulWidget {
  final Map<String, dynamic> profileForm;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool isParentView;

  const EditProfileBottomSheet({
    Key? key,
    required this.profileForm,
    required this.onSave,
    required this.onCancel,
    this.isParentView = true,
    // 加入這個參數來獲取當前用戶 ID
  }) : super(key: key);

  @override
  State<EditProfileBottomSheet> createState() => _EditProfileBottomSheetState();
}

class _EditProfileBottomSheetState extends State<EditProfileBottomSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _lineCtrl;
  late TextEditingController _socialLinksCtrl;
  late TextEditingController _bioCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _lineFocus = FocusNode();
  final FocusNode _socialFocus = FocusNode();
  final FocusNode _bioFocus = FocusNode();

  Uint8List? _rawImage;
  Uint8List? _croppedImage;
  final CropController _cropController = CropController();
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingAvatar = false;
  bool _isPickingImage = false; // 新增這個變數

  // 在 _EditProfileBottomSheetState 類中，修改以下方法：

  // 選擇並自動裁切頭像
  Future<void> _pickAndCropAvatar() async {
    // 防止重複調用
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);

    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() => _isPickingImage = false);
        return;
      }

      final bytes = await picked.readAsBytes();

      // 直接進行自動裁切
      await _performAutoCrop(bytes);
    } catch (e) {
      setState(() => _isPickingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('選擇圖片失敗：$e')));
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
          _isPickingImage = false;
        });

        // 直接上傳
        _uploadAvatar();
      } else {
        throw '無法處理圖片';
      }
    } catch (e) {
      setState(() => _isPickingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('自動裁切失敗：$e')));
    }
  }

  // 需要在檔案頂部添加這些 import：
  // import 'dart:ui' as ui;
  // import 'dart:math' as math;
  // 上傳頭像到 Firebase Storage
  Future<void> _uploadAvatar() async {
    if (_croppedImage == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      // 假設需要當前用戶的 uid，這裡需要從外部傳入或獲取
      // 您可能需要在 EditProfileBottomSheet 構造函數中加入 userId 參數
      final userId = widget.profileForm['userId'] ?? 'temp_id';

      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/$userId.jpg',
      );

      await storageRef.putData(
        _croppedImage!,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final avatarUrl = await storageRef.getDownloadURL();

      setState(() {
        widget.profileForm['avatarUrl'] = avatarUrl;
        _isUploadingAvatar = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('頭像更新成功！')));
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('頭像上傳失敗：$e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profileForm['name'] ?? '');
    _phoneCtrl = TextEditingController(
      text: widget.profileForm['phoneNumber'] ?? '',
    );
    _emailCtrl = TextEditingController(text: widget.profileForm['email'] ?? '');
    _lineCtrl = TextEditingController(text: widget.profileForm['lineId'] ?? '');

    // 處理 socialLinks
    final socialLinks =
        widget.profileForm['socialLinks'] as Map<String, dynamic>? ?? {};
    _socialLinksCtrl = TextEditingController(
      text: socialLinks['other']?.toString() ?? '',
    );

    // 根據視角決定使用哪個履歷欄位
    final bioField = widget.isParentView
        ? 'publisherResume'
        : 'applicantResume';
    _bioCtrl = TextEditingController(
      text: widget.profileForm[bioField]?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _lineCtrl.dispose();
    _socialLinksCtrl.dispose();
    _bioCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _lineFocus.dispose();
    _socialFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  void _updateProfileForm() {
    widget.profileForm['name'] = _nameCtrl.text.trim();
    widget.profileForm['phoneNumber'] = _phoneCtrl.text.trim();
    widget.profileForm['email'] = _emailCtrl.text.trim();
    widget.profileForm['lineId'] = _lineCtrl.text.trim();

    // 更新 socialLinks
    final socialLinks = <String, String>{};
    if (_socialLinksCtrl.text.trim().isNotEmpty) {
      socialLinks['other'] = _socialLinksCtrl.text.trim();
    }
    widget.profileForm['socialLinks'] = socialLinks;

    // 根據視角更新對應的履歷欄位
    final bioField = widget.isParentView
        ? 'publisherResume'
        : 'applicantResume';
    widget.profileForm[bioField] = _bioCtrl.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頭像區域
          // 在 _EditProfileBottomSheetState 的 build 方法中，修改頭像區域：

          // 頭像區域
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: (_isUploadingAvatar || _isPickingImage)
                      ? null
                      : _pickAndCropAvatar,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue[100],
                          backgroundImage:
                              widget.profileForm['avatarUrl']
                                      ?.toString()
                                      .isNotEmpty ==
                                  true
                              ? NetworkImage(widget.profileForm['avatarUrl'])
                              : null,
                          child:
                              widget.profileForm['avatarUrl']
                                      ?.toString()
                                      .isNotEmpty !=
                                  true
                              ? Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.blue[600],
                                )
                              : null,
                        ),
                      ),
                      if (_isUploadingAvatar)
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
                          child: Icon(
                            _isPickingImage
                                ? Icons.hourglass_empty
                                : Icons.edit,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 姓名
          _buildInputSection(
            title: '姓名',
            icon: Icons.badge,
            child: TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                hintText: '請輸入您的姓名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),

          // 手機號碼
          _buildInputSection(
            title: '手機號碼',
            icon: Icons.phone,
            child: TextField(
              controller: _phoneCtrl,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '請輸入手機號碼',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _emailFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),

          // Email
          _buildInputSection(
            title: 'Email',
            icon: Icons.email,
            child: TextField(
              controller: _emailCtrl,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: '請輸入 Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _lineFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),

          // Line ID
          _buildInputSection(
            title: 'Line ID',
            icon: Icons.chat,
            child: TextField(
              controller: _lineCtrl,
              focusNode: _lineFocus,
              decoration: InputDecoration(
                hintText: '請輸入 Line ID（選填）',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _socialFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),

          // 社群連結
          _buildInputSection(
            title: '社群連結',
            icon: Icons.link,
            child: TextField(
              controller: _socialLinksCtrl,
              focusNode: _socialFocus,
              decoration: InputDecoration(
                hintText: 'Instagram、Facebook 等連結（選填）',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _bioFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),

          // 個人簡介/履歷
          _buildInputSection(
            title: widget.isParentView ? '發布者簡介' : '應徵者履歷',
            icon: Icons.description,
            child: TextField(
              controller: _bioCtrl,
              focusNode: _bioFocus,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.isParentView
                    ? '簡單介紹一下自己，讓應徵者更了解你...'
                    : '描述您的技能、經驗和專長...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 按鈕
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
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
                  onPressed: () {
                    _updateProfileForm();
                    widget.onSave();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    '儲存資料',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildInputSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// LocationDetailBottomSheet 已刪除 - 沒有被使用

// 7. 我的應徵列表彈窗
class MyApplicationsBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> applications;
  final Function(String) onCancelApplication;
  final Function(Map<String, dynamic>)? onViewDetails; // 新增这个参数

  const MyApplicationsBottomSheet({
    Key? key,
    required this.applications,
    required this.onCancelApplication,
    this.onViewDetails, // 新增这个参数
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 如果 applications 為 null（還在載入），顯示 loading
    if (applications == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (applications.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '目前沒有任何應徵記錄',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '快去地圖上尋找適合的工作機會吧！',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: applications.length,
      itemBuilder: (context, index) {
        final application = applications[index];
        final createdAt = (application['createdAt'] as Timestamp?)?.toDate();
        final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '最近';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部信息
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[300]!, Colors.blue[500]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.work,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            application['name'] ?? '未命名任務',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '應徵時間：$timeAgo',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 状态标签
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '已應徵',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                // 任务内容
                if (application['content']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Text(
                      application['content'],
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],

                // 地址信息
                if (application['address']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.orange[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          application['address'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.orange[600],
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // 底部操作按钮
                const SizedBox(height: 16),
                Row(
                  children: [
                    // 查看详情按钮
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onViewDetails != null
                            ? () => onViewDetails!(application)
                            : null, // 修改这里，调用回调函数
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(color: Colors.blue[300]!),
                        ),
                        icon: Icon(
                          Icons.visibility,
                          size: 16,
                          color: Colors.blue[600],
                        ),
                        label: Text(
                          '查看詳情',
                          style: TextStyle(
                            color: Colors.blue[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 取消应征按钮
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _showCancelConfirmDialog(context, application),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[500],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.cancel, size: 16),
                        label: const Text(
                          '取消應徵',
                          style: TextStyle(
                            fontSize: 14,
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
        );
      },
    );
  }

  // 显示确认取消对话框
  void _showCancelConfirmDialog(
    BuildContext context,
    Map<String, dynamic> application,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[600], size: 24),
              const SizedBox(width: 8),
              const Text('確認取消應徵'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('您確定要取消應徵這個任務嗎？'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '任務：${application['name'] ?? '未命名任務'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '取消後將無法恢復，需要重新應徵。',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                '再想想',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
                onCancelApplication(application['id']); // 执行取消操作
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[500],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '確定取消',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  // 计算时间差的辅助方法
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}週前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}

// 8. 通知面板彈窗
class NotificationPanelBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> newPosts;
  final Function(Map<String, dynamic>) onViewPost;
  final VoidCallback onClearAll;

  const NotificationPanelBottomSheet({
    Key? key,
    required this.newPosts,
    required this.onViewPost,
    required this.onClearAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 如果 newPosts 為 null（還在載入），顯示 loading
    if (newPosts == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (newPosts.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '目前沒有新案件',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text(
                '最新案件通知',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (newPosts.isNotEmpty)
                TextButton(
                  onPressed: onClearAll,
                  child: Text(
                    '清除全部',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: newPosts.length,
            itemBuilder: (context, index) {
              final post = newPosts[index];
              final createdAt = (post['createdAt'] as Timestamp?)?.toDate();
              final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '剛剛';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange[300]!, Colors.orange[500]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.work,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    post['name'] ?? '未命名案件',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post['content']?.toString().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          post['content'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (post['address']?.toString().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.orange[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                post['address'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.orange[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 12,
                            color: Colors.orange[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onTap: () => onViewPost(post),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}

// 在 full_screen_popup.dart 文件中添加这个新组件

class MyTasksListBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  final Function(Map<String, dynamic>) onTaskTap;
  final Function(Map<String, dynamic>) onEditTask;
  final Function(String) onDeleteTask;
  final VoidCallback onCreateNew;

  const MyTasksListBottomSheet({
    Key? key,
    required this.tasks,
    required this.onTaskTap,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onCreateNew,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 如果 tasks 為 null（還在載入），顯示 loading
    if (tasks == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (tasks.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.work_outline, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                '還沒有任何任務',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '開始創建你的第一個任務，\n讓更多人看到你的需求！',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onCreateNew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.add_task, size: 20),
                label: const Text(
                  '創建第一個任務',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 顶部操作栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
          ),
          child: Row(
            children: [
              Icon(Icons.assignment, color: Colors.blue[600], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '管理你的任務',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    Text(
                      '共 ${tasks.length} 個任務',
                      style: TextStyle(fontSize: 14, color: Colors.blue[600]),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: onCreateNew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[500],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 1,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  '新任務',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // 任务列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final createdAt = (task['createdAt'] as Timestamp?)?.toDate();
              final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '最近';
              final applicants = task['applicants'] as List? ?? [];
              final status = task['status'] ?? 'open';
              final acceptedApplicant = task['acceptedApplicant'];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // onTap: () => onTaskTap(task),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 头部：状态和时间
                        Row(
                          children: [
                            _buildStatusChip(status, acceptedApplicant != null),
                            const Spacer(),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // 任务标题
                        Text(
                          task['name'] ?? '未命名任務',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                        // 任务内容
                        if (task['content']?.toString().isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Text(
                              task['content'],
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],

                        // 地址信息
                        if (task['address']?.toString().isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.orange[600],
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  task['address'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.orange[600],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 应徵者信息
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: applicants.isEmpty
                                ? Colors.grey[50]
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: applicants.isEmpty
                                  ? Colors.grey[200]!
                                  : Colors.blue[200]!,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.people,
                                size: 18,
                                color: applicants.isEmpty
                                    ? Colors.grey[500]
                                    : Colors.blue[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  applicants.isEmpty
                                      ? '尚無人應徵'
                                      : '已有 ${applicants.length} 人應徵',
                                  style: TextStyle(
                                    color: applicants.isEmpty
                                        ? Colors.grey[600]
                                        : Colors.blue[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 底部操作按钮
                        Row(
                          children: [
                            // 查看详情按钮
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => onTaskTap(task),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  side: BorderSide(color: Colors.blue[300]!),
                                ),
                                icon: Icon(
                                  Icons.visibility,
                                  size: 16,
                                  color: Colors.blue[600],
                                ),
                                label: Text(
                                  '查看詳情',
                                  style: TextStyle(
                                    color: Colors.blue[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 编辑按钮
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => onEditTask(task),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[500],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 1,
                                ),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text(
                                  '編輯',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 删除按钮
                            IconButton(
                              onPressed: () => _showDeleteConfirmDialog(
                                context,
                                task,
                                onDeleteTask,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.red[50],
                                padding: const EdgeInsets.all(12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Icon(
                                Icons.delete,
                                color: Colors.red[600],
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status, bool hasAcceptedApplicant) {
    MaterialColor chipColor;
    String statusText;
    IconData icon;

    if (hasAcceptedApplicant) {
      chipColor = Colors.green;
      statusText = '已完成';
      icon = Icons.check_circle;
    } else if (status == 'open') {
      chipColor = Colors.blue;
      statusText = '進行中';
      icon = Icons.schedule;
    } else {
      chipColor = Colors.grey;
      statusText = '未知';
      icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor[700]),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: chipColor[700],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // 显示删除确认对话框
  static void _showDeleteConfirmDialog(
    BuildContext context,
    Map<String, dynamic> task,
    Function(String) onDelete,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red[600], size: 24),
              const SizedBox(width: 8),
              const Text('確認刪除'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('您確定要刪除這個任務嗎？'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '任務：${task['name'] ?? '未命名任務'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (task['applicants'] != null &&
                        (task['applicants'] as List).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ 已有 ${(task['applicants'] as List).length} 人應徵',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '此操作無法復原，所有相關的應徵記錄也會被刪除。',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                '取消',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDelete(task['id']);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '確定刪除',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  // 计算时间差的辅助方法
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '剛剛';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}週前';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}

// ClusterPostsListBottomSheet 已刪除 - 沒有被使用
