import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

/// 任務詳情彈窗 - 在 ParentView 與 PlayerView 中共用
class TaskDetailSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final bool isParentView; // true: Parent視角, false: Player視角
  final LatLng? currentLocation;
  final VoidCallback? onTaskUpdated; // 任務更新回調
  final VoidCallback? onEditTask; // 編輯任務回調（僅Parent）
  final VoidCallback? onDeleteTask; // 刪除任務回調（僅Parent）

  const TaskDetailSheet({
    Key? key,
    required this.taskData,
    required this.isParentView,
    this.currentLocation,
    this.onTaskUpdated,
    this.onEditTask,
    this.onDeleteTask,
  }) : super(key: key);

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  final _firestore = FirebaseFirestore.instance;
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;
  bool _isApplying = false;

  // 任務申請者列表
  List<Map<String, dynamic>> _applicants = [];
  bool _isLoadingApplicants = false;

  @override
  void initState() {
    super.initState();
    _calculateTravelInfo();
    if (widget.isParentView) {
      _loadApplicants();
    }
  }

  /// 計算交通資訊
  Future<void> _calculateTravelInfo() async {
    if (widget.currentLocation == null) return;

    setState(() => _isLoadingTravel = true);

    final origin =
        '${widget.currentLocation!.latitude},${widget.currentLocation!.longitude}';
    final destination = '${widget.taskData['lat']},${widget.taskData['lng']}';
    final modes = ['driving', 'walking', 'transit'];
    final info = <String, String>{};

    for (var mode in modes) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$origin&destinations=$destination&mode=$mode&key=$_apiKey',
        );
        final response = await http.get(url);
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final element = data['rows'][0]['elements'][0];
          if (element['status'] == 'OK') {
            info[mode] =
                '${element['duration']['text']} (${element['distance']['text']})';
          } else {
            info[mode] = '無法計算';
          }
        } else {
          info[mode] = '無法計算';
        }
      } catch (e) {
        info[mode] = '無法計算';
      }
    }

    setState(() {
      _travelInfo = info;
      _isLoadingTravel = false;
    });
  }

  /// 載入申請者列表（僅Parent視角）
  Future<void> _loadApplicants() async {
    if (!widget.isParentView) return;

    setState(() => _isLoadingApplicants = true);

    try {
      final applicantIds = List<String>.from(
        widget.taskData['applicants'] ?? [],
      );
      final applicants = <Map<String, dynamic>>[];

      for (String uid in applicantIds) {
        final userDoc = await _firestore.doc('user/$uid').get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          userData['uid'] = uid;
          applicants.add(userData);
        }
      }

      setState(() {
        _applicants = applicants;
        _isLoadingApplicants = false;
      });
    } catch (e) {
      print('載入申請者失敗: $e');
      setState(() => _isLoadingApplicants = false);
    }
  }

  /// 申請任務（僅Player視角）
  Future<void> _applyForTask() async {
    if (widget.isParentView) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isApplying = true);

    try {
      final taskRef = _firestore.doc('posts/${widget.taskData['id']}');
      await taskRef.update({
        'applicants': FieldValue.arrayUnion([user.uid]),
      });

      if (mounted) {
        // 更新本地狀態
        final currentApplicants = List<String>.from(
          widget.taskData['applicants'] ?? [],
        );
        currentApplicants.add(user.uid);
        widget.taskData['applicants'] = currentApplicants;

        widget.onTaskUpdated?.call();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('申請成功！')));

        setState(() {}); // 刷新UI狀態
      }
    } catch (e) {
      print('申請失敗: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('申請失敗：$e')));
    } finally {
      setState(() => _isApplying = false);
    }
  }

  /// 取消申請（僅Player視角）
  Future<void> _cancelApplication() async {
    if (widget.isParentView) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isApplying = true);

    try {
      final taskRef = _firestore.doc('posts/${widget.taskData['id']}');
      await taskRef.update({
        'applicants': FieldValue.arrayRemove([user.uid]),
      });

      if (mounted) {
        // 更新本地狀態
        final currentApplicants = List<String>.from(
          widget.taskData['applicants'] ?? [],
        );
        currentApplicants.remove(user.uid);
        widget.taskData['applicants'] = currentApplicants;

        widget.onTaskUpdated?.call();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已取消申請')));

        setState(() {}); // 刷新UI狀態
      }
    } catch (e) {
      print('取消申請失敗: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取消申請失敗：$e')));
    } finally {
      setState(() => _isApplying = false);
    }
  }

  /// 檢查當前用戶是否已申請
  bool get _hasApplied {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final applicantIds = List<String>.from(widget.taskData['applicants'] ?? []);
    return applicantIds.contains(user.uid);
  }

  /// 檢查是否為自己發布的任務
  bool get _isMyTask {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    return widget.taskData['userId'] == user.uid;
  }

  /// 顯示圖片全屏預覽
  void _showImagePreview(
    BuildContext context,
    List<dynamic> images,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImagePreviewWidget(
              images: images.map((img) => img.toString()).toList(),
              initialIndex: initialIndex,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
        opaque: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
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
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 任務標題
                      _buildTitleSection(),
                      const SizedBox(height: 16),

                      // 執行時間
                      if (widget.taskData['date'] != null ||
                          widget.taskData['time'] != null)
                        _buildTimeSection(),

                      // 任務報酬
                      if (widget.taskData['price'] != null &&
                          widget.taskData['price'] > 0)
                        _buildPriceSection(),

                      // 任務圖片
                      if (widget.taskData['images'] != null &&
                          (widget.taskData['images'] as List).isNotEmpty)
                        _buildImagesSection(),

                      // 地點資訊
                      _buildLocationSection(),

                      // 交通資訊
                      _buildTravelSection(),

                      // 任務內容
                      _buildContentSection(),

                      // 申請者列表（僅Parent視角）
                      if (widget.isParentView) _buildApplicantsSection(),

                      const SizedBox(height: 100), // 為按鈕留出空間
                    ],
                  ),
                ),
              ),

              // 底部操作按鈕
              _buildActionButtons(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitleSection() {
    // 優先顯示 title，向下兼容 name
    final title =
        widget.taskData['title']?.toString().trim() ??
        widget.taskData['name']?.toString().trim() ??
        '未命名任務';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isParentView ? '我發布的任務' : '任務詳情',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSection() {
    String timeText = '';

    // 處理日期
    if (widget.taskData['date'] != null) {
      try {
        final date = DateTime.parse(widget.taskData['date']);
        timeText =
            '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      } catch (e) {
        timeText = widget.taskData['date'].toString();
      }
    }

    // 處理時間
    if (widget.taskData['time'] != null) {
      final timeData = widget.taskData['time'];
      if (timeData is Map) {
        final hour = timeData['hour']?.toString().padLeft(2, '0') ?? '00';
        final minute = timeData['minute']?.toString().padLeft(2, '0') ?? '00';
        timeText += timeText.isEmpty ? '$hour:$minute' : ' $hour:$minute';
      }
    }

    if (timeText.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Colors.green[700], size: 20),
          const SizedBox(width: 8),
          Text(
            '執行時間：$timeText',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    final price = widget.taskData['price'];
    if (price == null || price == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_money, color: Colors.orange[700], size: 20),
          const SizedBox(width: 8),
          Text(
            '任務報酬：NT\$ $price',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesSection() {
    final images = widget.taskData['images'] as List? ?? [];
    if (images.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '任務圖片',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () => _showImagePreview(context, images, index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        images[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    final address = widget.taskData['address']?.toString() ?? '地址未設定';
    final lat = widget.taskData['lat'];
    final lng = widget.taskData['lng'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, color: Colors.red[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openGoogleMaps(lat, lng, address),
                  child: Text(
                    address,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue[700],
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!widget.isParentView && lat != null && lng != null) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _openGoogleMapsNavigation(lat, lng),
              icon: const Icon(Icons.navigation, size: 16),
              label: const Text('開始導航'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 打開Google Maps查看地址
  void _openGoogleMaps(double? lat, double? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    } else {
      final encodedAddress = Uri.encodeComponent(address);
      uri = Uri.parse('https://maps.google.com/?q=$encodedAddress');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 打開Google Maps導航
  void _openGoogleMapsNavigation(double lat, double lng) async {
    final uri = Uri.parse(
      'https://maps.google.com/maps?saddr=&daddr=$lat,$lng',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildTravelSection() {
    if (_isLoadingTravel) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('計算交通時間中...'),
          ],
        ),
      );
    }

    if (_travelInfo == null || _travelInfo!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '交通資訊',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._travelInfo!.entries.map((entry) {
            IconData icon;
            Color color;
            String label;

            switch (entry.key) {
              case 'driving':
                icon = Icons.directions_car;
                color = Colors.blue;
                label = '開車';
                break;
              case 'walking':
                icon = Icons.directions_walk;
                color = Colors.green;
                label = '步行';
                break;
              case 'transit':
                icon = Icons.directions_transit;
                color = Colors.orange;
                label = '大眾運輸';
                break;
              default:
                icon = Icons.directions;
                color = Colors.grey;
                label = entry.key;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '$label：${entry.value}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildContentSection() {
    final content = widget.taskData['content']?.toString().trim() ?? '';
    if (content.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '任務內容',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
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
              content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicantsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '申請者 (${_applicants.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_isLoadingApplicants)
            const Center(child: CircularProgressIndicator())
          else if (_applicants.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Icon(Icons.person_off, color: Colors.grey[400], size: 32),
                  const SizedBox(height: 8),
                  Text(
                    '目前還沒有人申請這個任務',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ...(_applicants.map((applicant) {
              return GestureDetector(
                onTap: () => _showApplicantDetail(applicant),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[100]!),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            applicant['avatarUrl']?.isNotEmpty == true
                            ? NetworkImage(applicant['avatarUrl'])
                            : null,
                        child: applicant['avatarUrl']?.isEmpty != false
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              applicant['name'] ?? '未設定姓名',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (applicant['applicantResume']?.isNotEmpty ==
                                true)
                              Text(
                                applicant['applicantResume'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                    ],
                  ),
                ),
              );
            }).toList()),
        ],
      ),
    );
  }

  /// 顯示申請者詳情彈窗
  void _showApplicantDetail(Map<String, dynamic> applicant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ApplicantDetailSheet(
        applicantData: applicant,
        taskData: widget.taskData,
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 關閉按鈕
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('關閉'),
              ),
            ),

            const SizedBox(width: 12),

            // 主要操作按鈕
            Expanded(flex: 2, child: _buildMainActionButton()),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActionButton() {
    if (widget.isParentView) {
      // Parent 視角：編輯/刪除按鈕
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: widget.onEditTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('編輯'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: widget.onDeleteTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('刪除'),
            ),
          ),
        ],
      );
    } else {
      // Player 視角：申請/取消申請按鈕
      if (_isMyTask) {
        return ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[400]),
          child: const Text('這是我的任務'),
        );
      } else if (_hasApplied) {
        return ElevatedButton(
          onPressed: _isApplying ? null : _cancelApplication,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[600],
            foregroundColor: Colors.white,
          ),
          child: _isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('取消申請'),
        );
      } else {
        return ElevatedButton(
          onPressed: _isApplying ? null : _applyForTask,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('申請任務'),
        );
      }
    }
  }
}

/// 圖片預覽組件
class ImagePreviewWidget extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImagePreviewWidget({
    Key? key,
    required this.images,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<ImagePreviewWidget> createState() => _ImagePreviewWidgetState();
}

class _ImagePreviewWidgetState extends State<ImagePreviewWidget> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 圖片顯示區域
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: Image.network(
                    widget.images[index],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, color: Colors.white, size: 64),
                      );
                    },
                  ),
                ),
              );
            },
          ),

          // 關閉按鈕
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),

          // 頁面指示器
          if (widget.images.length > 1)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 申請者詳情彈窗
class ApplicantDetailSheet extends StatelessWidget {
  final Map<String, dynamic> applicantData;
  final Map<String, dynamic> taskData;

  const ApplicantDetailSheet({
    Key? key,
    required this.applicantData,
    required this.taskData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
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
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 申請者頭像和基本資訊
                      _buildApplicantHeader(),
                      const SizedBox(height: 20),

                      // 聯絡資訊
                      _buildContactInfo(),
                      const SizedBox(height: 20),

                      // 個人簡介
                      _buildResumeSection(),
                      const SizedBox(height: 20),

                      // 申請任務資訊
                      _buildTaskInfo(),

                      const SizedBox(height: 100), // 為按鈕留出空間
                    ],
                  ),
                ),
              ),

              // 底部操作按鈕
              _buildActionButtons(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApplicantHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: applicantData['avatarUrl']?.isNotEmpty == true
                ? NetworkImage(applicantData['avatarUrl'])
                : null,
            child: applicantData['avatarUrl']?.isEmpty != false
                ? const Icon(Icons.person, size: 35)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  applicantData['name'] ?? '未設定姓名',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '申請者詳情',
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo() {
    final contacts = <Widget>[];

    if (applicantData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.phone,
          '電話',
          applicantData['phoneNumber'],
          Colors.green,
        ),
      );
    }

    if (applicantData['email']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.email,
          '電子郵件',
          applicantData['email'],
          Colors.orange,
        ),
      );
    }

    if (applicantData['lineId']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.chat,
          'Line ID',
          applicantData['lineId'],
          Colors.green,
        ),
      );
    }

    if (contacts.isEmpty) {
      contacts.add(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Text('申請者尚未提供聯絡資訊', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '聯絡資訊',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...contacts,
      ],
    );
  }

  Widget _buildContactItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumeSection() {
    final resume = applicantData['applicantResume']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '個人簡介',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
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
            resume.isNotEmpty ? resume : '申請者尚未填寫個人簡介',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: resume.isNotEmpty ? Colors.black87 : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskInfo() {
    final taskTitle = taskData['title'] ?? taskData['name'] ?? '未命名任務';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '申請的任務',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                taskTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (taskData['price'] != null && taskData['price'] > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '報酬：NT\$ ${taskData['price']}',
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 返回按鈕
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(width: 12),
            // 聯絡申請者按鈕
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => _contactApplicant(context),
                icon: const Icon(Icons.chat),
                label: const Text('聯絡申請者'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _contactApplicant(BuildContext context) {
    final contacts = <String>[];

    if (applicantData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add('電話: ${applicantData['phoneNumber']}');
    }
    if (applicantData['email']?.toString().isNotEmpty == true) {
      contacts.add('Email: ${applicantData['email']}');
    }
    if (applicantData['lineId']?.toString().isNotEmpty == true) {
      contacts.add('Line: ${applicantData['lineId']}');
    }

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('申請者尚未提供聯絡資訊')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('聯絡申請者'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可透過以下方式聯絡申請者：'),
            const SizedBox(height: 12),
            ...contacts.map(
              (contact) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $contact', style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
