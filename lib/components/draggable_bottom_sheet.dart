// 首先創建一個可拖拽的底部彈窗組件
// lib/components/draggable_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 添加這行

class DraggableBottomSheet extends StatefulWidget {
  final Widget child;
  final VoidCallback? onClose;
  final double initialHeight;
  final double maxHeight;
  final String? title;
  final Widget? titleWidget;

  const DraggableBottomSheet({
    Key? key,
    required this.child,
    this.onClose,
    this.initialHeight = 0.5,
    this.maxHeight = 0.5,
    this.title,
    this.titleWidget,
  }) : super(key: key);

  @override
  State<DraggableBottomSheet> createState() => _DraggableBottomSheetState();
}

class _DraggableBottomSheetState extends State<DraggableBottomSheet>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _heightAnimation;

  double _currentHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _currentHeight = widget.initialHeight;
    _heightAnimation = Tween<double>(begin: 0.0, end: widget.initialHeight)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );

    // 啟動進入動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _close() {
    _animateToHeight(0.0).then((_) {
      if (widget.onClose != null) {
        widget.onClose!();
      }
    });
  }

  Future<void> _animateToHeight(double height) async {
    _heightAnimation = Tween<double>(begin: _currentHeight, end: height)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );

    _animationController.reset();
    await _animationController.forward();

    setState(() {
      _currentHeight = height;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // 獲取鍵盤高度
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _heightAnimation,
      builder: (context, child) {
        // 簡化的高度計算
        final adjustedHeight = keyboardHeight > 0
            ? (0.5 * screenHeight) + keyboardHeight
            : (0.5 * screenHeight);

        return Stack(
          children: [
            // 底部彈窗
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: adjustedHeight,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 標題區域
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            children: [
                              // 拖拽指示條
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),

                              // 標題區域
                              if (widget.title != null ||
                                  widget.titleWidget != null) ...[
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child:
                                            widget.titleWidget ??
                                            Text(
                                              widget.title!,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                      ),
                                      IconButton(
                                        onPressed: _close,
                                        icon: const Icon(Icons.close),
                                        iconSize: 20,
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(color: Colors.grey[200]),
                              ],
                            ],
                          ),
                        ),

                        // 內容區域
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 針對不同類型的彈窗內容組件

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

  @override
  Widget build(BuildContext context) {
    final isStatic = task['isStatic'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 地址資訊
          if (task['address']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務地址',
              icon: Icons.location_city,
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 任務內容
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

          // 應徵者狀況
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

          // 操作按鈕
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

          // 交通資訊
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

          // 底部安全區域
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
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
          // 頭像和基本資訊
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

          // 詳細資訊
          if (applicant['contact']?.toString().isNotEmpty == true)
            _buildInfoCard('聯絡方式', applicant['contact'], Icons.contact_phone),

          if (applicant['email']?.toString().isNotEmpty == true)
            _buildInfoCard('Email', applicant['email'], Icons.email),

          if (applicant['bio']?.toString().isNotEmpty == true)
            _buildInfoCard('自我介紹', applicant['bio'], Icons.description),

          const SizedBox(height: 24),

          // 操作按鈕
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

          // 返回按鈕
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
        // 增加底部間距，確保鍵盤彈出時內容不會被擠壓
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      // 防止滾動時鍵盤消失
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 任務名稱
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

          // 任務內容
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

          // 地點搜尋
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

                // 地點建議列表
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

          // 操作按鈕
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

          // 底部安全區域
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
        // 增加底部間距，確保鍵盤彈出時內容不會被擠壓
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      // 防止滾動時鍵盤消失
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頭像區域
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
                    // TODO: 實現頭像更換功能
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

          // 顯示名稱
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

          // 聯絡方式
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

          // 自我介紹
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

          // 操作按鈕
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

          // 底部安全區域
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

  @override
  Widget build(BuildContext context) {
    final bool isTask = location['userId'] != null;

    // 調試信息
    print('LocationDetailBottomSheet 接收到的數據: $location');
    print('地址字段: ${location['address']}');
    print('地址字段是否為空: ${location['address']?.toString().isEmpty}');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 地址資訊
          if (location['address']?.toString().isNotEmpty == true) ...[
            _buildSection(
              title: '任務地址',
              icon: Icons.location_city,
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 任務內容
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

          // 交通資訊
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

          // 發布者資訊
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

          // 應徵按鈕
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

          // 底部安全區域
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

  const MyApplicationsBottomSheet({
    Key? key,
    required this.applications,
    required this.onCancelApplication,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.work_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                '目前沒有任何應徵記錄',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '快去地圖上尋找適合的工作機會吧！',
                style: TextStyle(fontSize: 14, color: Colors.grey),
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
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.work,
                        color: Colors.blue[600],
                        size: 20,
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
                          if (application['content']?.toString().isNotEmpty ==
                              true)
                            Text(
                              application['content'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          if (application['address']?.toString().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.orange[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    application['address'],
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
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '已應徵',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => onCancelApplication(application['id']),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[600],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('取消應徵'),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                '目前沒有新案件',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '我們會即時通知您最新的工作機會',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 標題列
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

        // 案件列表
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
