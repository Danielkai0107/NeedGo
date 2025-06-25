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
class MyApplicationsBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> applications;
  final Function(String) onCancelApplication;
  final Function(Map<String, dynamic>)? onViewDetails;

  const MyApplicationsBottomSheet({
    Key? key,
    required this.applications,
    required this.onCancelApplication,
    this.onViewDetails,
  }) : super(key: key);

  @override
  State<MyApplicationsBottomSheet> createState() =>
      _MyApplicationsBottomSheetState();
}

class _MyApplicationsBottomSheetState extends State<MyApplicationsBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 檢查任務是否過期或已完成（Player 視角）
  bool _isApplicationExpired(Map<String, dynamic> application) {
    // 檢查任務本身的狀態
    final taskStatus = application['status'] ?? 'open';
    if (taskStatus == 'completed') return true;

    // 檢查是否有接受的應徵者且不是自己
    final acceptedApplicant = application['acceptedApplicant'];
    if (acceptedApplicant != null) {
      // 如果有接受的應徵者但不是自己，則視為過期
      // 這裡需要當前用戶ID來判斷，暫時先判斷有接受者就是過期
      return true;
    }

    // 檢查任務日期是否過期
    if (application['date'] == null) return false;

    try {
      DateTime taskDate;
      if (application['date'] is String) {
        taskDate = DateTime.parse(application['date']);
      } else if (application['date'] is DateTime) {
        taskDate = application['date'];
      } else {
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

      return taskDay.isBefore(today);
    } catch (e) {
      return false;
    }
  }

  // 獲取應徵狀態（Player 視角）
  String _getApplicationStatus(Map<String, dynamic> application) {
    final taskStatus = application['status'] ?? 'open';
    final acceptedApplicant = application['acceptedApplicant'];

    if (taskStatus == 'completed') return 'completed';
    if (acceptedApplicant != null) return 'not_selected'; // 有人被選中但不是自己
    if (_isApplicationExpired(application)) return 'expired';
    return 'pending'; // 等待中
  }

  // 分組應徵
  List<Map<String, dynamic>> get _activeApplications {
    return widget.applications.where((app) {
      final status = _getApplicationStatus(app);
      return status == 'pending';
    }).toList();
  }

  List<Map<String, dynamic>> get _pastApplications {
    return widget.applications.where((app) {
      final status = _getApplicationStatus(app);
      return status != 'pending';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.applications.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // 頂部標題區域
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.work_history_rounded,
                  color: Colors.blue[600],
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我的應徵記錄',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '總共 ${widget.applications.length} 個應徵',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 頁籤導航
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.pending_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text('等待回覆 (${_activeApplications.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text('過去應徵 (${_pastApplications.length})'),
                  ],
                ),
              ),
            ],
            labelColor: Colors.blue[600],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.blue[600],
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // 頁籤內容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildApplicationList(_activeApplications, isActive: true),
              _buildApplicationList(_pastApplications, isActive: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.work_history_outlined,
                size: 64,
                color: Colors.blue[300],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '還沒有任何應徵記錄',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '快去地圖上尋找適合的工作機會吧！',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationList(
    List<Map<String, dynamic>> applications, {
    required bool isActive,
  }) {
    if (applications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.pending_outlined : Icons.history_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? '目前沒有等待回覆的應徵' : '沒有過去的應徵記錄',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: applications.length,
      itemBuilder: (context, index) {
        final application = applications[index];
        return _buildApplicationCard(application, isActive);
      },
    );
  }

  Widget _buildApplicationCard(
    Map<String, dynamic> application,
    bool isActive,
  ) {
    final status = _getApplicationStatus(application);
    final createdAt = (application['createdAt'] as Timestamp?)?.toDate();
    final taskDate = _parseTaskDate(application['date']);
    final price = application['price'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key('application_${application['id']}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red[600],
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cancel_rounded, color: Colors.white, size: 24),
              SizedBox(height: 4),
              Text(
                '取消',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (direction) =>
            _showCancelConfirmDialog(context, application),
        onDismissed: (direction) =>
            widget.onCancelApplication(application['id']),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onViewDetails != null
                ? () => widget.onViewDetails!(application)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // 左側圓形圖標
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _getStatusColors(status),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColors(status)[0].withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // 右側資訊
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一行：任務標題 + 狀態標籤
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                application['title']?.toString() ??
                                    application['name']?.toString() ??
                                    '未命名任務',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusChip(status),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // 第二行：日期 + 價格
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              taskDate != null
                                  ? '${taskDate.month}月${taskDate.day}日'
                                  : '日期未設定',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '\$${price.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // 第三行：任務描述
                        if (application['content']?.toString().isNotEmpty ==
                            true)
                          Text(
                            application['content'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                        const SizedBox(height: 12),

                        // 第四行：應徵時間 + 操作按鈕
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    createdAt != null
                                        ? _getTimeAgo(createdAt)
                                        : '最近',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(),

                            // 操作按鈕
                            if (isActive) ...[
                              OutlinedButton(
                                onPressed: () =>
                                    _showCancelConfirmDialog(
                                      context,
                                      application,
                                    ).then((confirmed) {
                                      if (confirmed == true) {
                                        widget.onCancelApplication(
                                          application['id'],
                                        );
                                      }
                                    }),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  side: BorderSide(color: Colors.red[300]!),
                                  minimumSize: Size.zero,
                                ),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else ...[
                              ElevatedButton(
                                onPressed: widget.onViewDetails != null
                                    ? () => widget.onViewDetails!(application)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  '查看詳情',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _parseTaskDate(dynamic date) {
    if (date == null) return null;
    try {
      if (date is String) return DateTime.parse(date);
      if (date is DateTime) return date;
      return null;
    } catch (e) {
      return null;
    }
  }

  List<Color> _getStatusColors(String status) {
    switch (status) {
      case 'completed':
        return [Colors.green[400]!, Colors.green[600]!];
      case 'not_selected':
        return [Colors.grey[400]!, Colors.grey[600]!];
      case 'expired':
        return [Colors.grey[400]!, Colors.grey[600]!];
      default: // pending
        return [Colors.blue[400]!, Colors.blue[600]!];
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'not_selected':
        return Icons.person_off_rounded;
      case 'expired':
        return Icons.schedule_rounded;
      default: // pending
        return Icons.pending_rounded;
    }
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    String statusText;

    switch (status) {
      case 'completed':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[700]!;
        statusText = '已完成';
        break;
      case 'not_selected':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[700]!;
        statusText = '未獲選';
        break;
      case 'expired':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[700]!;
        statusText = '已過期';
        break;
      default: // pending
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[700]!;
        statusText = '已應徵';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Future<bool> _showCancelConfirmDialog(
    BuildContext context,
    Map<String, dynamic> application,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange[600],
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text('確認取消應徵'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('您確定要取消應徵這個任務嗎？'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Text(
                      '任務：${application['title'] ?? application['name'] ?? '未命名任務'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '取消後將無法恢復，需要重新應徵。',
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('再想想', style: TextStyle(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('確定取消'),
                ),
              ],
            );
          },
        ) ??
        false;
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

// ClusterPostsListBottomSheet 已刪除 - 沒有被使用

// 8. 我的任務列表彈窗
class MyTasksListBottomSheet extends StatefulWidget {
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
  State<MyTasksListBottomSheet> createState() => _MyTasksListBottomSheetState();
}

class _MyTasksListBottomSheetState extends State<MyTasksListBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 檢查任務是否過期
  bool _isTaskExpired(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDate;
      if (task['date'] is String) {
        taskDate = DateTime.parse(task['date']);
      } else if (task['date'] is DateTime) {
        taskDate = task['date'];
      } else {
        return false;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);

      return taskDay.isBefore(today);
    } catch (e) {
      return false;
    }
  }

  // 獲取任務狀態
  String _getTaskStatus(Map<String, dynamic> task) {
    if (task['status'] == 'completed') return 'completed';
    if (task['acceptedApplicant'] != null) return 'accepted';
    if (_isTaskExpired(task)) return 'expired';
    return task['status'] ?? 'open';
  }

  // 分組任務
  List<Map<String, dynamic>> get _activeTasks {
    return widget.tasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'open' || status == 'accepted';
    }).toList();
  }

  List<Map<String, dynamic>> get _pastTasks {
    return widget.tasks.where((task) {
      final status = _getTaskStatus(task);
      return status == 'completed' || status == 'expired';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // 頂部標題區域
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment_rounded,
                  color: Colors.orange[600],
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我的任務',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '總共 ${widget.tasks.length} 個任務',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: widget.onCreateNew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  '新增',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // 頁籤導航
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text('正在進行 (${_activeTasks.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text('過去發布 (${_pastTasks.length})'),
                  ],
                ),
              ),
            ],
            labelColor: Colors.orange[600],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.orange[600],
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // 頁籤內容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTaskList(_activeTasks, isActive: true),
              _buildTaskList(_pastTasks, isActive: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.assignment_outlined,
                size: 64,
                color: Colors.orange[300],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '還沒有任何任務',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '開始創建你的第一個任務，\n讓更多人看到你的需求！',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: widget.onCreateNew,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
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
              icon: const Icon(Icons.add_task_rounded, size: 20),
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

  Widget _buildTaskList(
    List<Map<String, dynamic>> tasks, {
    required bool isActive,
  }) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.schedule_outlined : Icons.history_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? '目前沒有進行中的任務' : '沒有過去的任務記錄',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: widget.onCreateNew,
                icon: const Icon(Icons.add_rounded),
                label: const Text('立即創建任務'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange[600],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildTaskCard(task, isActive);
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isActive) {
    final status = _getTaskStatus(task);
    final createdAt = (task['createdAt'] as Timestamp?)?.toDate();
    final taskDate = _parseTaskDate(task['date']);
    final price = task['price'] ?? 0;
    final applicantCount = (task['applicants'] as List?)?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key('task_${task['id']}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red[600],
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_rounded, color: Colors.white, size: 24),
              SizedBox(height: 4),
              Text(
                '刪除',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (direction) => _showDeleteConfirmDialog(context, task),
        onDismissed: (direction) => widget.onDeleteTask(task['id']),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.onTaskTap(task),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // 左側圓形圖標
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _getStatusColors(status),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColors(status)[0].withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // 右側資訊
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一行：任務標題 + 狀態標籤
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task['title']?.toString() ??
                                    task['name']?.toString() ??
                                    '未命名任務',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusChip(status),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // 第二行：日期 + 價格
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              taskDate != null
                                  ? '${taskDate.month}月${taskDate.day}日'
                                  : '日期未設定',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '\$${price.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // 第三行：任務描述
                        if (task['content']?.toString().isNotEmpty == true)
                          Text(
                            task['content'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                        const SizedBox(height: 12),

                        // 第四行：應徵者數量 + 操作按鈕
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: applicantCount > 0
                                    ? Colors.blue[50]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: applicantCount > 0
                                      ? Colors.blue[200]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.people_rounded,
                                    size: 14,
                                    color: applicantCount > 0
                                        ? Colors.blue[600]
                                        : Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    applicantCount > 0
                                        ? '$applicantCount 人應徵'
                                        : '尚無應徵',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: applicantCount > 0
                                          ? Colors.blue[700]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(),

                            // 操作按鈕
                            if (isActive) ...[
                              OutlinedButton(
                                onPressed: () => widget.onEditTask(task),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  side: BorderSide(color: Colors.blue[300]!),
                                  minimumSize: Size.zero,
                                ),
                                child: Text(
                                  '編輯',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else ...[
                              ElevatedButton(
                                onPressed: () => widget.onTaskTap(task),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  '重新發布',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _parseTaskDate(dynamic date) {
    if (date == null) return null;
    try {
      if (date is String) return DateTime.parse(date);
      if (date is DateTime) return date;
      return null;
    } catch (e) {
      return null;
    }
  }

  List<Color> _getStatusColors(String status) {
    switch (status) {
      case 'completed':
        return [Colors.green[400]!, Colors.green[600]!];
      case 'accepted':
        return [Colors.blue[400]!, Colors.blue[600]!];
      case 'expired':
        return [Colors.grey[400]!, Colors.grey[600]!];
      default:
        return [Colors.orange[400]!, Colors.orange[600]!];
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'accepted':
        return Icons.handshake_rounded;
      case 'expired':
        return Icons.schedule_rounded;
      default:
        return Icons.work_rounded;
    }
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    String statusText;

    switch (status) {
      case 'completed':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[700]!;
        statusText = '已完成';
        break;
      case 'accepted':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[700]!;
        statusText = '已接受';
        break;
      case 'expired':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[700]!;
        statusText = '已過期';
        break;
      default:
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[700]!;
        statusText = '進行中';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmDialog(
    BuildContext context,
    Map<String, dynamic> task,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red[600],
                    size: 24,
                  ),
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
                          '任務：${task['title'] ?? task['name'] ?? '未命名任務'}',
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('取消', style: TextStyle(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('確定刪除'),
                ),
              ],
            );
          },
        ) ??
        false;
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

// 9. 通知面板彈窗
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
