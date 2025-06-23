// lib/components/full_screen_popup.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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

// 1. 任務詳情彈窗
class TaskDetailBottomSheet extends StatelessWidget {
  final Map<String, dynamic> task;
  final Map<String, String>? travelInfo;
  final bool isLoadingTravel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewApplicants;
  final VoidCallback? onCreateFromStatic;

  const TaskDetailBottomSheet({
    Key? key,
    required this.task,
    this.travelInfo,
    this.isLoadingTravel = false,
    this.onEdit,
    this.onDelete,
    this.onViewApplicants,
    this.onCreateFromStatic,
  }) : super(key: key);

  // 開啟Google Maps的方法
  void _openGoogleMaps(String address) async {
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );

    try {
      // 需要在檔案頂部添加 import 'package:url_launcher/url_launcher.dart';
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        throw '無法開啟Google Maps';
      }
    } catch (e) {
      // 如果無法開啟，可以顯示錯誤訊息或使用備用方案
      print('開啟Google Maps失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStatic = task['isStatic'] == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 地址信息 - 修改為可點擊的Google Maps連結
          if (task['address']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務地址',
              icon: Icons.location_city,
              child: InkWell(
                onTap: () => _openGoogleMaps(task['address']),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.orange[600],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          task['address'],
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.orange[600],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!isStatic && task['content']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務內容',
              icon: Icons.description,
              child: Text(
                task['content'],
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!isStatic) ...[
            _buildSection(
              title: '應徵者狀況',
              icon: Icons.people,
              child: InkWell(
                onTap: onViewApplicants,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people, color: Colors.blue[600], size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '查看應徵者',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Builder(
                              builder: (context) {
                                final applicants = task['applicants'] as List?;
                                if (applicants == null || applicants.isEmpty) {
                                  return const Text(
                                    '目前無人應徵',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  );
                                } else {
                                  return Text(
                                    '已有 ${applicants.length} 人應徵',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.blue[600],
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isStatic) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCreateFromStatic,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_task),
                label: const Text(
                  '以此地點新增任務',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.edit),
                    label: const Text('編輯任務'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onDelete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete),
                    label: const Text('刪除任務'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _buildSection(
            title: '交通資訊',
            icon: Icons.directions,
            child: isLoadingTravel
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : travelInfo != null
                ? Column(
                    children: [
                      _buildTravelItem(
                        '🚗',
                        '開車',
                        travelInfo!['driving'] ?? '計算中',
                      ),
                      _buildTravelItem(
                        '🚶',
                        '步行',
                        travelInfo!['walking'] ?? '計算中',
                      ),
                      _buildTravelItem(
                        '🚇',
                        '大眾運輸',
                        travelInfo!['transit'] ?? '計算中',
                      ),
                    ],
                  )
                : const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '請先定位，才能計算交通資訊',
                      style: TextStyle(color: Colors.orange),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildSection({
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

  Widget _buildTravelItem(String emoji, String method, String duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(
            method,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
          ),
          const Spacer(),
          Text(
            duration,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    if (applicants.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '目前沒有應徵者',
                style: TextStyle(fontSize: 18, color: Colors.grey),
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
              backgroundColor: applicant['userType'] == 'player'
                  ? Colors.green[100]
                  : Colors.purple[100],
              child: Icon(
                applicant['userType'] == 'player' ? Icons.person : Icons.groups,
                color: applicant['userType'] == 'player'
                    ? Colors.green[600]
                    : Colors.purple[600],
                size: 24,
              ),
            ),
            title: Text(
              applicant['displayName'] ?? '未設定名稱',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: applicant['userType'] == 'player'
                        ? Colors.green[50]
                        : Colors.purple[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    applicant['userType'] == 'player' ? '玩家' : '團體',
                    style: TextStyle(
                      fontSize: 12,
                      color: applicant['userType'] == 'player'
                          ? Colors.green[700]
                          : Colors.purple[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (applicant['bio']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    applicant['bio'],
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: applicant['userType'] == 'player'
                    ? Colors.green[100]
                    : Colors.purple[100],
                child: Icon(
                  applicant['userType'] == 'player'
                      ? Icons.person
                      : Icons.groups,
                  color: applicant['userType'] == 'player'
                      ? Colors.green[600]
                      : Colors.purple[600],
                  size: 40,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      applicant['displayName'] ?? '未設定名稱',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: applicant['userType'] == 'player'
                            ? Colors.green[50]
                            : Colors.purple[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: applicant['userType'] == 'player'
                              ? Colors.green[200]!
                              : Colors.purple[200]!,
                        ),
                      ),
                      child: Text(
                        applicant['userType'] == 'player' ? '玩家' : '團體',
                        style: TextStyle(
                          fontSize: 14,
                          color: applicant['userType'] == 'player'
                              ? Colors.green[700]
                              : Colors.purple[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (applicant['contact']?.toString().isNotEmpty == true)
            _buildInfoCard('聯絡方式', applicant['contact'], Icons.contact_phone),
          if (applicant['email']?.toString().isNotEmpty == true)
            _buildInfoCard('Email', applicant['email'], Icons.email),
          if (applicant['bio']?.toString().isNotEmpty == true)
            _buildInfoCard('自我介紹', applicant['bio'], Icons.description),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle),
                  label: const Text(
                    '接受',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onReject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.cancel),
                  label: const Text(
                    '拒絕',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onBack,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回應徵者列表'),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
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

// 4. 創建/編輯任務彈窗
class CreateEditTaskBottomSheet extends StatefulWidget {
  final bool isEditing;
  final Map<String, dynamic> taskForm;
  final TextEditingController nameController;
  final TextEditingController contentController;
  final TextEditingController locationSearchController;
  final List<Map<String, dynamic>> locationSuggestions;
  final Function(String) onLocationSearch;
  final Function(Map<String, dynamic>) onLocationSelect;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const CreateEditTaskBottomSheet({
    Key? key,
    required this.isEditing,
    required this.taskForm,
    required this.nameController,
    required this.contentController,
    required this.locationSearchController,
    required this.locationSuggestions,
    required this.onLocationSearch,
    required this.onLocationSelect,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<CreateEditTaskBottomSheet> createState() =>
      _CreateEditTaskBottomSheetState();
}

class _CreateEditTaskBottomSheetState extends State<CreateEditTaskBottomSheet> {
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();

  @override
  void dispose() {
    _nameFocus.dispose();
    _contentFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
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
          _buildInputSection(
            title: '任務名稱',
            icon: Icons.assignment,
            child: TextField(
              controller: widget.nameController,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                hintText: '請輸入任務名稱',
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
              onChanged: (v) => widget.taskForm['name'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _contentFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務內容',
            icon: Icons.description,
            child: TextField(
              controller: widget.contentController,
              focusNode: _contentFocus,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '請詳細描述任務內容...',
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
              onChanged: (v) => widget.taskForm['content'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _locationFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務地點',
            icon: Icons.location_on,
            child: Column(
              children: [
                TextField(
                  controller: widget.locationSearchController,
                  focusNode: _locationFocus,
                  decoration: InputDecoration(
                    hintText: '搜尋地點...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue[500]!,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: widget.onLocationSearch,
                ),
                if (widget.locationSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.locationSuggestions.length,
                      itemBuilder: (context, index) {
                        final place = widget.locationSuggestions[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.location_on,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                          title: Text(
                            place['description'],
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => widget.onLocationSelect(place),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
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
                  onPressed: widget.onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    widget.isEditing ? '儲存修改' : '創建任務',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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

// 5. 編輯個人資料彈窗
class EditProfileBottomSheet extends StatefulWidget {
  final Map<String, dynamic> profileForm;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const EditProfileBottomSheet({
    Key? key,
    required this.profileForm,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<EditProfileBottomSheet> createState() => _EditProfileBottomSheetState();
}

class _EditProfileBottomSheetState extends State<EditProfileBottomSheet> {
  late TextEditingController _displayNameCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _bioCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _contactFocus = FocusNode();
  final FocusNode _bioFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController(
      text: widget.profileForm['displayName'] ?? '',
    );
    _contactCtrl = TextEditingController(
      text: widget.profileForm['contact'] ?? '',
    );
    _bioCtrl = TextEditingController(text: widget.profileForm['bio'] ?? '');
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _contactCtrl.dispose();
    _bioCtrl.dispose();
    _nameFocus.dispose();
    _contactFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
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
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue[100],
                  child: Icon(Icons.person, size: 50, color: Colors.blue[600]),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('頭像更換功能待實現')));
                  },
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('更換頭像'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildInputSection(
            title: '顯示名稱',
            icon: Icons.badge,
            child: TextField(
              controller: _displayNameCtrl,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                hintText: '請輸入您的顯示名稱',
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
              onChanged: (v) => widget.profileForm['displayName'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _contactFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '聯絡方式',
            icon: Icons.contact_phone,
            child: TextField(
              controller: _contactCtrl,
              focusNode: _contactFocus,
              decoration: InputDecoration(
                hintText: '電話、Email 或其他聯絡方式',
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
              onChanged: (v) => widget.profileForm['contact'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _bioFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '自我介紹',
            icon: Icons.description,
            child: TextField(
              controller: _bioCtrl,
              focusNode: _bioFocus,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '簡單介紹一下自己...',
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
              onChanged: (v) => widget.profileForm['bio'] = v,
            ),
          ),
          const SizedBox(height: 32),
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
                  onPressed: widget.onSave,
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

// 6. 任務/地點詳情彈窗 (PlayerView 用)
class LocationDetailBottomSheet extends StatelessWidget {
  final Map<String, dynamic> location;
  final Map<String, String>? travelInfo;
  final bool isLoadingTravel;
  final bool hasApplied;
  final bool isApplying;
  final VoidCallback? onApply;
  final VoidCallback? onCancelApplication;
  final Widget? publisherInfo;

  const LocationDetailBottomSheet({
    Key? key,
    required this.location,
    this.travelInfo,
    this.isLoadingTravel = false,
    this.hasApplied = false,
    this.isApplying = false,
    this.onApply,
    this.onCancelApplication,
    this.publisherInfo,
  }) : super(key: key);

  // 開啟Google Maps的方法
  void _openGoogleMaps(String address) async {
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        throw '無法開啟Google Maps';
      }
    } catch (e) {
      print('開啟Google Maps失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTask = location['userId'] != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (location['address']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務地址',
              icon: Icons.location_city,
              child: InkWell(
                onTap: () => _openGoogleMaps(location['address']),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.orange[600],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          location['address'],
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.orange[600],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isTask && location['content']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務內容',
              icon: Icons.description,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Text(
                  location['content'],
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildSection(
            title: '交通資訊',
            icon: Icons.directions,
            child: isLoadingTravel
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : travelInfo != null
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildTravelItem(
                          '🚗',
                          '開車',
                          travelInfo!['driving'] ?? '計算中',
                        ),
                        _buildTravelItem(
                          '🚶',
                          '步行',
                          travelInfo!['walking'] ?? '計算中',
                        ),
                        _buildTravelItem(
                          '🚇',
                          '大眾運輸',
                          travelInfo!['transit'] ?? '計算中',
                        ),
                      ],
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: const Text(
                      '請先定位，才能計算交通資訊',
                      style: TextStyle(color: Colors.orange),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (publisherInfo != null) ...[
            _buildSection(
              title: '發布者資訊',
              icon: Icons.person,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple[200]!),
                ),
                child: publisherInfo!,
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (isTask) ...[
            SizedBox(
              width: double.infinity,
              child: hasApplied
                  ? ElevatedButton.icon(
                      onPressed: onCancelApplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.cancel),
                      label: const Text(
                        '取消應徵',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: isApplying ? null : onApply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: isApplying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.work),
                      label: Text(
                        isApplying ? '應徵中...' : '應徵此任務',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildSection({
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

  Widget _buildTravelItem(String emoji, String method, String duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(
            method,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
          ),
          const Spacer(),
          Text(
            duration,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

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
                  fontWeight: FontWeight.w500,
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
                            fontWeight: FontWeight.w500,
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
                            fontWeight: FontWeight.w500,
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
                    fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w500,
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
                                  fontWeight: FontWeight.w500,
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
                              fontWeight: FontWeight.w500,
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
                                fontWeight: FontWeight.w500,
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
                                    fontWeight: FontWeight.w500,
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
                                    fontWeight: FontWeight.w500,
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
                                    fontWeight: FontWeight.w500,
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
                          fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w500,
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

// 9. 聚合任務列表彈窗 (新增)
class ClusterPostsListBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final Function(Map<String, dynamic>) onPostTap;
  final VoidCallback onBack;

  const ClusterPostsListBottomSheet({
    Key? key,
    required this.posts,
    required this.onPostTap,
    required this.onBack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 按創建時間排序
    final sortedPosts = List<Map<String, dynamic>>.from(posts);
    sortedPosts.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return Column(
      children: [
        // 頂部信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            border: Border(bottom: BorderSide(color: Colors.orange[100]!)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[600],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '此地點的所有任務',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                    Text(
                      '共 ${posts.length} 個任務等你來應徵',
                      style: TextStyle(fontSize: 14, color: Colors.orange[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 任務列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedPosts.length,
            itemBuilder: (context, index) {
              final post = sortedPosts[index];
              final createdAt = (post['createdAt'] as Timestamp?)?.toDate();
              final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '最近';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onPostTap(post),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 頭部：標題和時間
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post['name'] ?? '未命名任務',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                timeAgo,
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 任務內容
                        if (post['content']?.toString().isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Text(
                              post['content'],
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // 發布者信息
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .doc('parents/${post['userId']}')
                              .get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '👤 發布者：無法取得資料',
                                  style: TextStyle(fontSize: 12),
                                ),
                              );
                            }

                            final publisherData =
                                snapshot.data!.data() as Map<String, dynamic>;
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.purple[200]!),
                              ),
                              child: Text(
                                '👤 發布者：${publisherData['displayName'] ?? '未設定'}',
                                style: TextStyle(
                                  color: Colors.purple[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // 底部：查看詳情按鈕
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => onPostTap(post),
                            icon: const Icon(Icons.visibility, size: 16),
                            label: const Text('查看詳情'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // 底部返回按鈕
        Container(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回地圖'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
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
