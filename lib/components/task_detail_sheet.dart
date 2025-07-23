import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/custom_snackbar.dart';
import '../services/chat_service.dart';
import '../screens/chat_detail_screen.dart';
import '../styles/app_colors.dart';

/// 可重複使用的頭像組件，支援認證圖標
class VerifiedAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final bool isVerified;
  final IconData? defaultIcon;
  final double? badgeSize; // 認證徽章大小參數（可選）
  final bool showWhiteBorder; // 是否顯示白色邊框

  const VerifiedAvatar({
    Key? key,
    this.avatarUrl,
    required this.radius,
    this.isVerified = false,
    this.defaultIcon,
    this.badgeSize, // 可選參數，控制認證徽章大小
    this.showWhiteBorder = false, // 預設不顯示白色邊框
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 計算認證圖標大小：使用提供的參數，否則默認為頭像半徑的0.28倍
    final verifiedBadgeSize = badgeSize ?? (radius * 0.28).clamp(16.0, 32.0);
    // 認證圖標內的icon大小（badge大小的0.6倍）
    final badgeIconSize = (verifiedBadgeSize * 0.6).clamp(10.0, 20.0);
    // 頭像內圖標大小（默認為半徑的1.2倍）
    final avatarIconSize = radius * 1.2;

    return Stack(
      children: [
        // 頭像容器（包含白色邊框）
        Container(
          width: (radius + (showWhiteBorder ? 2 : 0)) * 2,
          height: (radius + (showWhiteBorder ? 2 : 0)) * 2,
          decoration: showWhiteBorder
              ? BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                )
              : null,
          child: Center(
            child: CircleAvatar(
              radius: radius,
              backgroundImage: (avatarUrl?.isNotEmpty == true)
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: (avatarUrl?.isEmpty != false)
                  ? Icon(
                      defaultIcon ?? Icons.person_rounded,
                      size: avatarIconSize,
                    )
                  : null,
            ),
          ),
        ),
        if (isVerified)
          Positioned(
            bottom: showWhiteBorder ? 2 : 0,
            right: showWhiteBorder ? 2 : 0,
            child: Container(
              width: verifiedBadgeSize,
              height: verifiedBadgeSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: showWhiteBorder
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.verified,
                color: Colors.white,
                size: badgeIconSize,
              ),
            ),
          ),
      ],
    );
  }
}

/// 任務詳情彈窗 - 在 ParentView 與 PlayerView 中共用
class TaskDetailSheet extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final bool isParentView; // true: Parent視角, false: Player視角
  final LatLng? currentLocation;
  final VoidCallback? onTaskUpdated; // 任務更新回調
  final VoidCallback? onEditTask; // 編輯任務回調（僅Parent）
  final VoidCallback? onDeleteTask; // 刪除任務回調（僅Parent）
  final bool showBackButton; // 是否顯示返回按鈕
  final VoidCallback? onBack; // 返回按鈕回調
  final bool hideBottomActions; // 是否隱藏底部操作按鈕
  final bool hideApplicantsList; // 是否隱藏申請者清單

  const TaskDetailSheet({
    Key? key,
    required this.taskData,
    required this.isParentView,
    this.currentLocation,
    this.onTaskUpdated,
    this.onEditTask,
    this.onDeleteTask,
    this.showBackButton = false,
    this.onBack,
    this.hideBottomActions = false,
    this.hideApplicantsList = false,
  }) : super(key: key);

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet>
    with TickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;
  bool _isApplying = false;

  // 任務申請者列表
  List<Map<String, dynamic>> _applicants = [];
  bool _isLoadingApplicants = false;

  // 發布者資訊
  Map<String, dynamic>? _publisherData;
  bool _isLoadingPublisher = false;
  int _publisherTaskCount = 0;

  // 倒數計時器相關
  Timer? _countdownTimer;
  String _countdownText = '';
  late AnimationController _countdownAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  /// 顯示成功訊息
  void _showSuccessMessage(String message) {
    CustomSnackBar.showSuccess(context, message);
  }

  /// 顯示錯誤訊息
  void _showErrorMessage(String message) {
    CustomSnackBar.showError(context, message);
  }

  /// 顯示警告訊息
  void _showWarningMessage(String message) {
    CustomSnackBar.showWarning(context, message);
  }

  @override
  void initState() {
    super.initState();

    // 初始化動畫控制器（保留用於其他可能的動畫需求）
    _countdownAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 創建縮放動畫
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _countdownAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    // 創建淡入動畫
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _countdownAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // 第一個動作：檢查任務是否過期
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTaskExpiredOnOpen();
    });

    _calculateTravelInfo();
    if (widget.isParentView) {
      _loadApplicants();
    }
    _loadPublisherInfo();

    // 啟動倒數計時器
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownAnimationController.dispose();
    super.dispose();
  }

  /// 計算交通資訊
  Future<void> _calculateTravelInfo() async {
    if (widget.currentLocation == null) return;

    if (mounted) {
      setState(() => _isLoadingTravel = true);
    }

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

    if (mounted) {
      setState(() {
        _travelInfo = info;
        _isLoadingTravel = false;
      });
    }
  }

  /// 載入申請者列表（僅Parent視角）
  Future<void> _loadApplicants() async {
    if (!widget.isParentView) return;

    if (mounted) {
      setState(() => _isLoadingApplicants = true);
    }

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

      if (mounted) {
        setState(() {
          _applicants = applicants;
          _isLoadingApplicants = false;
        });
      }
    } catch (e) {
      print('載入申請者失敗: $e');
      if (mounted) {
        setState(() => _isLoadingApplicants = false);
      }
    }
  }

  /// 載入發布者資訊
  Future<void> _loadPublisherInfo() async {
    if (mounted) {
      setState(() => _isLoadingPublisher = true);
    }

    try {
      final publisherId = widget.taskData['userId'];
      if (publisherId != null) {
        // 獲取發布者資訊
        final userDoc = await _firestore.doc('user/$publisherId').get();
        if (userDoc.exists) {
          _publisherData = userDoc.data()!;
          _publisherData!['uid'] = publisherId;
        }

        // 計算發布者的任務數量
        final tasksQuery = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: publisherId)
            .get();
        _publisherTaskCount = tasksQuery.docs.length;
      }

      if (mounted) {
        setState(() => _isLoadingPublisher = false);
      }
    } catch (e) {
      print('載入發布者資訊失敗: $e');
      if (mounted) {
        setState(() => _isLoadingPublisher = false);
      }
    }
  }

  /// 啟動倒數計時器
  void _startCountdownTimer() {
    // 先更新一次倒數文字
    _updateCountdownText();

    // 每秒更新一次
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCountdownText();
      } else {
        timer.cancel();
      }
    });
  }

  /// 更新倒數計時文字
  void _updateCountdownText() {
    final status = _getTaskStatus();

    // 只有進行中的任務才顯示倒數計時
    if (status != 'open') {
      if (_countdownTimer != null && _countdownTimer!.isActive) {
        _countdownTimer!.cancel();
      }
      return;
    }

    final remainingTime = _calculateRemainingTime();

    // 檢查是否倒數結束，需要更新任務狀態
    if (remainingTime == null || remainingTime.isNegative) {
      // 倒數結束，自動更新任務狀態為過期
      _handleTaskExpired();
      return;
    }

    final newText = _formatRemainingTime(remainingTime);

    // 只有當文字改變時才更新，不觸發動畫（避免閃爍）
    if (_countdownText != newText) {
      setState(() {
        _countdownText = newText;
      });
    }
  }

  /// 處理任務過期邏輯（倒數結束時自動觸發）
  Future<void> _handleTaskExpired() async {
    print(
      '⏰ 倒數計時結束，任務即將過期: ${widget.taskData['title'] ?? widget.taskData['name']}',
    );

    // 停止計時器
    if (_countdownTimer != null && _countdownTimer!.isActive) {
      _countdownTimer!.cancel();
    }

    try {
      // 更新資料庫狀態
      await _markTaskAsExpired(widget.taskData['id']);

      // 更新本地數據
      if (mounted) {
        setState(() {
          widget.taskData['status'] = 'expired';
          widget.taskData['isActive'] = false;
          widget.taskData['expiredAt'] = Timestamp.now();
          _countdownText = '已過期'; // 設定最終顯示文字
        });
      }

      // 通知父組件更新
      widget.onTaskUpdated?.call();

      print('任務狀態已自動更新為過期');

      // 顯示過期通知（不阻塞）
      if (mounted) {
        _showTaskExpiredMessage();
      }
    } catch (e) {
      print(' 自動更新任務過期狀態失敗: $e');
      // 如果更新失敗，仍然停止計時器並更新本地狀態
      if (mounted) {
        setState(() {
          _countdownText = '已過期';
        });
      }
    }
  }

  /// 顯示任務過期通知訊息（非阻塞式）
  void _showTaskExpiredMessage() {
    final taskTitle =
        widget.taskData['title'] ?? widget.taskData['name'] ?? '任務';

    _showWarningMessage('「$taskTitle」已結束，任務狀態已自動更新');
  }

  /// 計算任務剩餘時間
  Duration? _calculateRemainingTime() {
    if (widget.taskData['date'] == null) return null;

    try {
      DateTime taskDateTime;
      final date = widget.taskData['date'];
      final time = widget.taskData['time'];

      // 解析日期
      if (date is String) {
        taskDateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDateTime = date;
      } else {
        return null;
      }

      // 如果有時間資訊，使用精確時間
      if (time != null && time is Map) {
        final hour = time['hour'] ?? 0;
        final minute = time['minute'] ?? 0;
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          hour,
          minute,
        );
      } else {
        // 如果沒有時間資訊，設定為當天 23:59
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          23,
          59,
        );
      }

      final now = DateTime.now();
      final remaining = taskDateTime.difference(now);

      // 如果已經過期，返回 null
      if (remaining.isNegative) {
        return null;
      }

      return remaining;
    } catch (e) {
      print('計算剩餘時間失敗: $e');
      return null;
    }
  }

  /// 格式化剩餘時間顯示
  String _formatRemainingTime(Duration remaining) {
    if (remaining.inDays > 0) {
      final days = remaining.inDays;
      final hours = remaining.inHours % 24;
      return '${days}天${hours}小時';
    } else if (remaining.inHours > 0) {
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes % 60;
      return '${hours}小時${minutes}分';
    } else if (remaining.inMinutes > 0) {
      final minutes = remaining.inMinutes;
      final seconds = remaining.inSeconds % 60;
      return '${minutes}分${seconds.toString().padLeft(2, '0')}秒';
    } else {
      final seconds = remaining.inSeconds;
      return '${seconds.toString().padLeft(2, '0')}秒';
    }
  }

  /// 檢查任務是否過期（打開詳情時檢查）
  Future<void> _checkTaskExpiredOnOpen() async {
    if (!mounted) return;

    print(
      '🔍 檢查任務詳情時是否過期: ${widget.taskData['title'] ?? widget.taskData['name']}',
    );

    try {
      // 檢查任務是否已過期
      if (_isTaskExpiredNow(widget.taskData)) {
        final currentStatus = widget.taskData['status'] ?? 'open';

        // 如果任務已過期但狀態還不是 expired，需要更新
        if (currentStatus != 'expired') {
          print('⏰ 發現過期任務，正在更新狀態...');

          // 更新資料庫狀態
          await _markTaskAsExpired(widget.taskData['id']);

          // 更新本地數據並刷新UI
          if (mounted) {
            setState(() {
              widget.taskData['status'] = 'expired';
              widget.taskData['isActive'] = false;
              widget.taskData['expiredAt'] = Timestamp.now();
            });
          }

          // 通知父組件更新
          widget.onTaskUpdated?.call();

          // 顯示過期提示框（只在狀態剛變更時顯示一次）
          if (mounted) {
            _showTaskExpiredDialog();
          }
        } else {
          // 任務已經是過期狀態，不需要再次顯示提示
          print('ℹ️ 任務已經是過期狀態，跳過提示顯示');
        }
      }
    } catch (e) {
      print(' 檢查任務過期狀態失敗: $e');
    }
  }

  /// 檢查任務是否已過期（基於精確時間）
  bool _isTaskExpiredNow(Map<String, dynamic> task) {
    if (task['date'] == null) return false;

    try {
      DateTime taskDateTime;
      final date = task['date'];
      final time = task['time'];

      // 解析日期
      if (date is String) {
        taskDateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDateTime = date;
      } else {
        return false;
      }

      // 如果有時間資訊，使用精確時間
      if (time != null && time is Map) {
        final hour = time['hour'] ?? 0;
        final minute = time['minute'] ?? 0;
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          hour,
          minute,
        );
      } else {
        // 如果沒有時間資訊，設定為當天 23:59
        taskDateTime = DateTime(
          taskDateTime.year,
          taskDateTime.month,
          taskDateTime.day,
          23,
          59,
        );
      }

      final now = DateTime.now();
      return now.isAfter(taskDateTime);
    } catch (e) {
      print('檢查任務過期時間失敗: $e');
      return false;
    }
  }

  /// 將任務標記為過期
  Future<void> _markTaskAsExpired(String taskId) async {
    try {
      print('⏰ 正在標記任務為過期: $taskId');

      await _firestore.doc('posts/$taskId').update({
        'status': 'expired',
        'isActive': false, // 從地圖上隱藏
        'updatedAt': Timestamp.now(),
        'expiredAt': Timestamp.now(),
      });

      // 發送聊天室關閉提醒訊息
      await ChatService.sendTaskExpiredChatCloseReminder(taskId);

      print('任務狀態已更新為過期，聊天室關閉提醒已發送');
    } catch (e) {
      print(' 更新任務過期狀態失敗: $e');
    }
  }

  /// 顯示任務過期提示框
  void _showTaskExpiredDialog() {
    final taskTitle =
        widget.taskData['title'] ?? widget.taskData['name'] ?? '任務';

    showDialog(
      context: context,
      barrierDismissible: false, // 不能點擊外部關閉
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
                  '任務已結束',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                // 內容
                Text(
                  '「$taskTitle」已超過執行時間，系統已自動結束此任務。',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // 資訊容器
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange[700],
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '任務結束後：',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isParentView
                            ? '• 任務已從地圖上移除\n• 應徵者無法再申請\n• 可在「我的發佈清單」中查看'
                            : '• 任務已從地圖上移除\n• 無法申請或取消申請\n• 可在「我的應徵清單」中查看',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 按鈕組
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 關閉對話框
                      Navigator.of(context).pop(); // 關閉任務詳情頁
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '我知道了',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 申請任務（僅Player視角）
  Future<void> _applyForTask() async {
    if (widget.isParentView) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      setState(() => _isApplying = true);
    }

    try {
      final taskRef = _firestore.doc('posts/${widget.taskData['id']}');
      await taskRef.update({
        'applicants': FieldValue.arrayUnion([user.uid]),
        'updatedAt': Timestamp.now(), // 更新時間戳以觸發通知
      });

      if (mounted) {
        // 更新本地狀態
        final currentApplicants = List<String>.from(
          widget.taskData['applicants'] ?? [],
        );
        currentApplicants.add(user.uid);
        widget.taskData['applicants'] = currentApplicants;
        widget.taskData['updatedAt'] = Timestamp.now(); // 同步更新本地狀態

        widget.onTaskUpdated?.call();

        CustomSnackBar.showSuccess(context, '申請成功！');

        setState(() {}); // 刷新UI狀態
      }
    } catch (e) {
      print('申請失敗: $e');
      CustomSnackBar.showError(context, '申請失敗：$e');
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  /// 取消申請（僅Player視角）
  Future<void> _cancelApplication() async {
    if (widget.isParentView) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      setState(() => _isApplying = true);
    }

    try {
      final taskRef = _firestore.doc('posts/${widget.taskData['id']}');
      await taskRef.update({
        'applicants': FieldValue.arrayRemove([user.uid]),
        'updatedAt': Timestamp.now(), // 更新時間戳以觸發通知
      });

      if (mounted) {
        // 更新本地狀態
        final currentApplicants = List<String>.from(
          widget.taskData['applicants'] ?? [],
        );
        currentApplicants.remove(user.uid);
        widget.taskData['applicants'] = currentApplicants;
        widget.taskData['updatedAt'] = Timestamp.now(); // 同步更新本地狀態

        widget.onTaskUpdated?.call();

        CustomSnackBar.showSuccess(context, '已取消申請');

        setState(() {}); // 刷新UI狀態
      }
    } catch (e) {
      print('取消申請失敗: $e');
      CustomSnackBar.showError(context, '取消申請失敗：$e');
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
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

  /// 開始與發布者聊天（僅Player視角）
  Future<void> _startChatWithPublisher() async {
    if (widget.isParentView) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showErrorMessage('請先登入');
      return;
    }

    final publisherId = widget.taskData['userId'];
    if (publisherId == null) {
      _showErrorMessage('無法獲取發布者資訊');
      return;
    }

    try {
      // 創建或獲取聊天室
      final chatId = await ChatService.createOrGetChatRoom(
        parentId: publisherId,
        playerId: currentUser.uid,
        taskId: widget.taskData['id'],
        taskTitle:
            widget.taskData['title'] ?? widget.taskData['name'] ?? '未命名任務',
      );

      // 獲取聊天室資訊
      final chatRoom = await ChatService.getChatRoomInfo(chatId);
      if (chatRoom == null) {
        _showErrorMessage('無法創建聊天室');
        return;
      }

      // 導航到聊天室
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(chatRoom: chatRoom),
          ),
        );
      }
    } catch (e) {
      print('開始聊天失敗: $e');
      _showErrorMessage('開始聊天失敗: $e');
    }
  }

  /// 開始與特定應徵者聊天（僅Parent視角）
  Future<void> _startChatWithApplicant(Map<String, dynamic> applicant) async {
    if (!widget.isParentView) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showErrorMessage('請先登入');
      return;
    }

    final applicantId = applicant['uid'];
    if (applicantId == null) {
      _showErrorMessage('無法獲取應徵者資訊');
      return;
    }

    try {
      // 創建或獲取聊天室
      final chatId = await ChatService.createOrGetChatRoom(
        parentId: currentUser.uid,
        playerId: applicantId,
        taskId: widget.taskData['id'],
        taskTitle:
            widget.taskData['title'] ?? widget.taskData['name'] ?? '未命名任務',
      );

      // 獲取聊天室資訊
      final chatRoom = await ChatService.getChatRoomInfo(chatId);
      if (chatRoom == null) {
        _showErrorMessage('無法創建聊天室');
        return;
      }

      // 導航到聊天室
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(chatRoom: chatRoom),
          ),
        );
      }
    } catch (e) {
      print('開始與應徵者聊天失敗: $e');
      _showErrorMessage('開始與應徵者聊天失敗: $e');
    }
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
                      const SizedBox(height: 20),
                      // 執行時間
                      if (widget.taskData['date'] != null ||
                          widget.taskData['time'] != null)
                        _buildTimeSection(),

                      // 任務報酬
                      _buildPriceSection(),

                      // 任務內容
                      _buildContentSection(),

                      // 地點資訊
                      _buildLocationSection(),

                      // 交通資訊
                      _buildTravelSection(),

                      // 任務圖片
                      if (widget.taskData['images'] != null &&
                          (widget.taskData['images'] as List).isNotEmpty)
                        _buildImagesSection(),

                      // 申請者列表（僅Parent視角且未隱藏，且非過去任務）
                      if (widget.isParentView &&
                          !widget.hideApplicantsList &&
                          !_isPastTask())
                        _buildApplicantsSection(),

                      // 任務結束按鈕（僅Parent視角且任務進行中時）
                      if (widget.isParentView && !_isPastTask())
                        _buildTaskCompleteButton(),

                      // 取消申請按鈕（僅Player視角且已申請時）
                      if (!widget.isParentView && _hasApplied && !_isPastTask())
                        _buildCancelApplicationButton(),

                      const SizedBox(height: 100), // 為按鈕留出空間
                    ],
                  ),
                ),
              ),

              // 底部操作按鈕
              if (!widget.hideBottomActions) _buildActionButtons(),
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
          Row(
            children: [
              Text(
                '任務詳情',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const Spacer(),
              _buildTaskStatusChip(),
            ],
          ),
          _buildPublisherSection(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskStatusChip() {
    final status = _getTaskStatus();
    final colors = _getStatusColors(status);
    final statusText = _getStatusText(status);
    final icon = _getStatusIcon(status);

    // 統一使用無動畫的樣式，避免閃爍
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _getTaskStatus() {
    final status = widget.taskData['status'] ?? 'open';
    final acceptedApplicant = widget.taskData['acceptedApplicant'];

    if (status == 'completed') return 'completed';
    if (acceptedApplicant != null) return 'accepted';
    // 使用精確時間檢查來判斷是否過期
    if (_isTaskExpiredNow(widget.taskData)) return 'expired';
    return status;
  }

  bool _isTaskExpired() {
    if (widget.taskData['date'] == null) return false;

    try {
      DateTime taskDate;
      final date = widget.taskData['date'];
      if (date is String) {
        taskDate = DateTime.parse(date);
      } else if (date is DateTime) {
        taskDate = date;
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

  List<Color> _getStatusColors(String status) {
    switch (status) {
      case 'completed':
        return [Colors.green[500]!, Colors.green[700]!];
      case 'accepted':
        return [AppColors.primaryShade(400), AppColors.primaryShade(600)];
      case 'expired':
        return [Colors.grey[500]!, Colors.grey[700]!];
      default:
        return [AppColors.primaryShade(400), AppColors.primaryShade(600)];
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'accepted':
        return '已接受';
      case 'expired':
        return '已過期';
      default:
        // 進行中的任務顯示倒數計時，如果沒有則顯示進行中
        return _countdownText.isNotEmpty ? _countdownText : '進行中';
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
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: Colors.black, size: 24),
          const SizedBox(width: 8),
          Text(
            '時間 ：$timeText',
            style: TextStyle(fontSize: 15, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    final price = widget.taskData['price'];

    String priceText;
    if (price == null || price == 0) {
      priceText = '任務報酬 ： 免費';
    } else {
      priceText = '任務報酬 ： NT\$ $price';
    }

    return Container(
      child: Row(
        children: [
          Icon(Icons.paid_rounded, color: Colors.black, size: 24),
          const SizedBox(width: 8),
          Text(priceText, style: TextStyle(fontSize: 15, color: Colors.black)),
        ],
      ),
    );
  }

  Widget _buildPublisherSection() {
    if (_isLoadingPublisher) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16, top: 20),
        padding: const EdgeInsets.all(16),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('載入發布者資訊中...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    if (_publisherData == null) {
      return const SizedBox.shrink();
    }

    final publisherName = _publisherData!['name'] ?? '未設定姓名';
    final avatarUrl = _publisherData!['avatarUrl']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 20),
      child: GestureDetector(
        onTap: () => _showPublisherDetail(),
        child: Container(
          // padding: const EdgeInsets.all(16),
          // decoration: BoxDecoration(
          //   color: Colors.white,
          //   borderRadius: BorderRadius.circular(16),
          //   border: Border.all(color: Colors.grey[100]!),
          // ),
          child: Row(
            children: [
              VerifiedAvatar(
                avatarUrl: avatarUrl,
                radius: 30,
                isVerified: _publisherData!['isVerified'] == true,
                defaultIcon: Icons.person_2_rounded,
                badgeSize: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$publisherName',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 認證狀態
                    _publisherData!['isVerified'] == true
                        ? Row(
                            children: [
                              Icon(
                                Icons.how_to_reg_rounded,
                                size: 16,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '真人用戶',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '尚未認證用戶',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220), // 線條顏色
            thickness: 1.0, // 線條粗細
            height: 50, // 線條本身佔據的高度（含上下間距）
          ),
          const Text(
            '任務圖片',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 20),
                  width: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[100]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GestureDetector(
                    onTap: () => _showImagePreview(context, images, index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        images[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.image_not_supported_rounded,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220), // 線條顏色
            thickness: 1.0, // 線條粗細
            height: 50, // 線條本身佔據的高度（含上下間距）
          ),
          const Text(
            '任務地點',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_rounded, color: Colors.black, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openGoogleMaps(lat, lng, address),
                  child: Text(
                    address,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // if (!widget.isParentView && lat != null && lng != null) ...[
          //   const SizedBox(height: 8),
          //   ElevatedButton.icon(
          //     onPressed: () => _openGoogleMapsNavigation(lat, lng),
          //     icon: const Icon(Icons.navigation, size: 16),
          //     label: const Text('開始導航'),
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: Colors.blue[700],
          //       foregroundColor: Colors.white,
          //       padding: const EdgeInsets.symmetric(
          //         horizontal: 16,
          //         vertical: 8,
          //       ),
          //       minimumSize: const Size(0, 36),
          //     ),
          //   ),
          // ],
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                backgroundColor: Colors.black,
              ),
            ),
            SizedBox(width: 8),
            Text(
              '計算交通時間中...',
              style: TextStyle(fontSize: 15, color: Colors.black),
            ),
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
          const SizedBox(height: 20),
          const Text(
            '交通資訊',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ..._travelInfo!.entries.map((entry) {
            IconData icon;
            Color color;
            String label;

            switch (entry.key) {
              case 'driving':
                icon = Icons.directions_car_rounded;
                color = Colors.black;
                label = '開車';
                break;
              case 'walking':
                icon = Icons.directions_walk_rounded;
                color = Colors.black;
                label = '步行';
                break;
              case 'transit':
                icon = Icons.directions_transit_rounded;
                color = Colors.black;
                label = '大眾運輸';
                break;
              default:
                icon = Icons.directions_bike_rounded;
                color = Colors.black;
                label = entry.key;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '$label：${entry.value}',
                    style: const TextStyle(fontSize: 15),
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
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220), // 線條顏色
            thickness: 1.0, // 線條粗細
            height: 50, // 線條本身佔據的高度（含上下間距）
          ),
          const Text(
            '任務內容',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Container(
            child: Text(
              content,
              style: const TextStyle(fontSize: 15, height: 1.6),
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
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220),
            thickness: 1.0,
            height: 50,
          ),
          Text(
            '申請者列表 (${_applicants.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (_isLoadingApplicants)
            const Center(child: CircularProgressIndicator())
          else if (_applicants.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Icon(
                    Icons.person_off_rounded,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '目前還沒有人申請這個任務',
                    style: TextStyle(color: Colors.grey[500], fontSize: 15),
                  ),
                ],
              ),
            )
          else
            // 垂直排列的申請者列表
            Column(
              children: _applicants.asMap().entries.map((entry) {
                final index = entry.key;
                final applicant = entry.value;
                return _buildApplicantCard(applicant, index);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildApplicantCard(Map<String, dynamic> applicant, int index) {
    final applicantName = applicant['name'] ?? '未設定姓名';
    final avatarUrl = applicant['avatarUrl']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 左側：頭像（點擊進入詳情頁）
            GestureDetector(
              onTap: () => _showApplicantDetail(applicant),
              child: VerifiedAvatar(
                avatarUrl: avatarUrl,
                radius: 30,
                isVerified: applicant['isVerified'] == true,
                badgeSize: 20,
              ),
            ),
            const SizedBox(width: 16),

            // 中間：基本資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 姓名
                  Text(
                    applicantName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // 認證狀態
                  applicant['isVerified'] == true
                      ? Row(
                          children: [
                            Icon(
                              Icons.how_to_reg_rounded,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '真人用戶',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '尚未認證用戶',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ],
              ),
            ),

            // 右側：聊天按鈕
            ElevatedButton.icon(
              onPressed: () => _startChatWithApplicant(applicant),
              icon: const Icon(Icons.chat_rounded, size: 16),
              label: const Text('聊天'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                minimumSize: const Size(80, 36),
              ),
            ),
          ],
        ),
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
    // 如果是過去的任務，不顯示操作按鈕
    if (_isPastTask()) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(child: _buildMainActionButton()),
    );
  }

  // 檢查是否是過去的任務（已完成或過期）
  bool _isPastTask() {
    final status = _getTaskStatus();
    return status == 'completed' || status == 'expired';
  }

  // 完成任務
  Future<void> _completeTask() async {
    final confirmed = await _showCompleteTaskDialog();
    if (!confirmed) return;

    try {
      // 更新任務狀態為已完成
      await FirebaseFirestore.instance
          .doc('posts/${widget.taskData['id']}')
          .update({
            'status': 'completed',
            'updatedAt': Timestamp.now(),
            'completedAt': Timestamp.now(),
          });

      // 發送聊天室關閉提醒訊息
      await ChatService.sendChatRoomCloseReminder(widget.taskData['id']);

      if (mounted) {
        // 通知父組件任務已更新
        widget.onTaskUpdated?.call();

        // 關閉詳情頁
        Navigator.of(context).pop();

        // 顯示成功訊息
        CustomSnackBar.showSuccess(context, '任務已完成，已通知相關聊天室');
      }
    } catch (e) {
      print('完成任務時發生錯誤: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '完成任務失敗: $e');
      }
    }
  }

  // 顯示任務完成確認對話框
  Future<bool> _showCompleteTaskDialog() async {
    return await showDialog<bool>(
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
                      '確認任務完成',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 內容
                    Text(
                      '您確定要將此任務標記為完成嗎？',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // 任務資訊容器
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '任務：${widget.taskData['title'] ?? widget.taskData['name'] ?? '未命名任務'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '✓ 任務將被標記為已完成',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                            ),
                          ),
                          Text(
                            '✓ 任務將從地圖上移除',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                            ),
                          ),
                          Text(
                            '✓ 任務將移至"過去發布"區域',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '完成後此操作無法復原。',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // 按鈕組
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text(
                              '取消',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              '確認完成',
                              style: TextStyle(fontSize: 16),
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
        ) ??
        false;
  }

  Widget _buildMainActionButton() {
    if (widget.isParentView) {
      // Parent 視角：顯示關閉和編輯任務按鈕
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[500],
                side: BorderSide(color: Colors.grey[400]!),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('關閉'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => widget.onEditTask?.call(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('編輯任務'),
            ),
          ),
        ],
      );
    } else {
      // Player 視角：申請/取消申請按鈕（可能包含返回按鈕）
      Widget actionButton;
      final status = _getTaskStatus();

      if (_isMyTask) {
        actionButton = ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[400],
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('這是我的任務'),
        );
      } else if (status == 'completed' || status == 'expired') {
        // 已完成或過期的任務
        actionButton = ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[400],
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(status == 'completed' ? '任務已完成' : '任務已過期'),
        );
      } else if (_hasApplied) {
        // 已申請的任務，顯示聊天按鈕
        actionButton = ElevatedButton.icon(
          onPressed: () => _startChatWithPublisher(),
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: const Text('聊天'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else {
        actionButton = ElevatedButton(
          onPressed: _isApplying ? null : _applyForTask,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
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

      // 陪伴者視角總是顯示返回按鈕 + 主要操作按鈕
      return Row(
        children: [
          // 返回按鈕
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onBack ?? (() => Navigator.of(context).pop()),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[600],
                side: BorderSide(color: Colors.grey[400]!),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('返回'),
            ),
          ),
          const SizedBox(width: 12),
          // 主要操作按鈕
          Expanded(flex: 2, child: actionButton),
        ],
      );
    }
  }

  /// 顯示發布者詳情彈窗
  void _showPublisherDetail() {
    if (_publisherData == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PublisherDetailSheet(
        publisherData: _publisherData!,
        taskCount: _publisherTaskCount,
        currentTaskData: widget.taskData,
      ),
    );
  }

  Widget _buildTaskCompleteButton() {
    final status = _getTaskStatus();

    // 只有在任務進行中時才顯示完成按鈕
    if (status != 'open' && status != 'accepted') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220),
            thickness: 1.0,
            height: 50,
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _completeTask(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green[600],
                side: BorderSide(color: Colors.green[600]!),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
              child: const Text('完成任務'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelApplicationButton() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 水平分隔線
          const Divider(
            color: Color.fromARGB(255, 220, 220, 220),
            thickness: 1.0,
            height: 50,
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isApplying ? null : _cancelApplication,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[600],
                side: BorderSide(color: Colors.red[400]!),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    )
                  : const Text('取消申請'),
            ),
          ),
        ],
      ),
    );
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
                        child: Icon(
                          Icons.error_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
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
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 24,
                ),
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
class ApplicantDetailSheet extends StatefulWidget {
  final Map<String, dynamic> applicantData;
  final Map<String, dynamic> taskData;

  const ApplicantDetailSheet({
    Key? key,
    required this.applicantData,
    required this.taskData,
  }) : super(key: key);

  @override
  State<ApplicantDetailSheet> createState() => _ApplicantDetailSheetState();
}

class _ApplicantDetailSheetState extends State<ApplicantDetailSheet> {
  final _firestore = FirebaseFirestore.instance;

  // 動態統計資料
  int _applicationCount = 0;
  double _rating = 4.8;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadApplicantStats();
  }

  /// 載入申請者統計資料
  Future<void> _loadApplicantStats() async {
    if (!mounted) return;

    setState(() => _isLoadingStats = true);

    try {
      final applicantId = widget.applicantData['uid'];
      if (applicantId != null) {
        // 查詢申請次數
        final applicationsQuery = await _firestore
            .collection('posts')
            .where('applicants', arrayContains: applicantId)
            .get();

        _applicationCount = applicationsQuery.docs.length;

        // 這裡可以加入評分計算邏輯
        // 暫時使用用戶資料中的評分，如果沒有則用預設值
        _rating = (widget.applicantData['rating']?.toDouble()) ?? 4.8;
      }

      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    } catch (e) {
      print('載入申請者統計資料失敗: $e');
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  /// 顯示成功訊息
  void _showSuccessMessage(String message) {
    CustomSnackBar.showSuccess(context, message);
  }

  /// 顯示錯誤訊息
  void _showErrorMessage(String message) {
    CustomSnackBar.showError(context, message);
  }

  /// 顯示警告訊息
  void _showWarningMessage(String message) {
    CustomSnackBar.showWarning(context, message);
  }

  /// 顯示檢舉對話框
  void _showReportDialog() async {
    final reportReasons = ['不當行為或騷擾', '提供虛假資訊', '違反服務條款', '垃圾訊息或廣告', '其他不當內容'];

    String? selectedReason;
    String additionalDetails = '';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 標題
                        Row(
                          children: [
                            Icon(
                              Icons.report_problem_rounded,
                              color: Colors.red[600],
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '檢舉用戶',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 說明文字
                        Text(
                          '請選擇檢舉原因，我們會盡快處理您的回報。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 檢舉原因選擇
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: reportReasons.asMap().entries.map((
                              entry,
                            ) {
                              final reason = entry.value;
                              return RadioListTile<String>(
                                title: Text(
                                  reason,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                value: reason,
                                groupValue: selectedReason,
                                onChanged: (value) {
                                  setState(() {
                                    selectedReason = value;
                                  });
                                },
                                activeColor: Colors.red[600],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 詳細描述（可選）
                        TextField(
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: '詳細描述（可選）',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red[400]!),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onChanged: (value) {
                            additionalDetails = value;
                          },
                        ),
                        const SizedBox(height: 24),

                        // 按鈕組
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text(
                                  '取消',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: selectedReason != null
                                    ? () {
                                        Navigator.of(context).pop({
                                          'reason': selectedReason!,
                                          'details': additionalDetails,
                                        });
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  '提交檢舉',
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
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      _submitReport('applicant', result['reason']!, result['details'] ?? '');
    }
  }

  /// 提交檢舉報告
  Future<void> _submitReport(String type, String reason, String details) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showErrorMessage('請先登入');
        return;
      }

      final reportData = {
        'reporterId': currentUser.uid,
        'reportedUserId': widget.applicantData['uid'],
        'reportedUserName': widget.applicantData['name'] ?? '未設定姓名',
        'reportType': type, // 'applicant'
        'reason': reason,
        'details': details,
        'taskId': widget.taskData['id'],
        'taskTitle':
            widget.taskData['title'] ?? widget.taskData['name'] ?? '未命名任務',
        'status': 'pending', // pending, reviewed, resolved
        'createdAt': Timestamp.now(),
      };

      await _firestore.collection('reports').add(reportData);

      if (mounted) {
        Navigator.of(context).pop(); // 關閉詳情頁
        _showSuccessMessage('檢舉已提交，感謝您的回報。我們會盡快處理。');
      }
    } catch (e) {
      print('提交檢舉失敗: $e');
      if (mounted) {
        _showErrorMessage('提交檢舉失敗，請稍後再試');
      }
    }
  }

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
                      const SizedBox(height: 20),

                      // 申請者頭像和基本資訊
                      _buildApplicantHeader(),
                      const SizedBox(height: 20),

                      // 聯絡資訊
                      _buildContactInfo(),
                      const SizedBox(height: 20),

                      // 個人簡介
                      _buildResumeSection(),

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
    final applicantName = widget.applicantData['name'] ?? '未設定姓名';
    final avatarUrl = widget.applicantData['avatarUrl']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.grey[100]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左側：申請者資訊
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  VerifiedAvatar(
                    avatarUrl: avatarUrl,
                    radius: 50,
                    isVerified: widget.applicantData['isVerified'] == true,
                    badgeSize: 28,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    applicantName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  // 認證狀態
                  widget.applicantData['isVerified'] == true
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.how_to_reg_rounded,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '真人用戶',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '尚未認證用戶',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // 右側：申請統計
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '申請次數',
                        style: TextStyle(fontSize: 13, color: Colors.black),
                      ),
                      const SizedBox(height: 4),
                      _isLoadingStats
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '$_applicationCount',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                    ],
                  ),
                  const Divider(
                    color: Color.fromARGB(255, 220, 220, 220),
                    thickness: 1.0,
                    height: 44,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '評分',
                        style: TextStyle(fontSize: 13, color: Colors.black),
                      ),
                      const SizedBox(height: 4),
                      _isLoadingStats
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _rating.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfo() {
    final contacts = <Widget>[];

    if (widget.applicantData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.call_rounded,
          '電話',
          widget.applicantData['phoneNumber'],
          Colors.black,
          onTap: () => _makePhoneCall(widget.applicantData['phoneNumber']),
        ),
      );
    }

    if (widget.applicantData['email']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.email_rounded,
          '電子郵件',
          widget.applicantData['email'],
          Colors.black,
          onTap: () => _sendEmail(widget.applicantData['email']),
        ),
      );
    }

    if (widget.applicantData['lineId']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.chat_rounded,
          'Line ID',
          widget.applicantData['lineId'],
          Colors.black,
          onTap: () => _openLine(widget.applicantData['lineId']),
        ),
      );
    }

    if (contacts.isEmpty) {
      contacts.add(
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_rounded, color: Colors.grey[400], size: 32),
              const SizedBox(height: 12),
              Text(
                '申請者尚未提供聯絡資訊',
                style: TextStyle(color: Colors.grey[500], fontSize: 15),
              ),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        ...contacts,
      ],
    );
  }

  Widget _buildContactItem(
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 24),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? color : Colors.black,
                      decoration: onTap != null ? TextDecoration.none : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumeSection() {
    final education = widget.applicantData['education']?.toString() ?? '';
    final hasCarLicense = widget.applicantData['hasCarLicense'] ?? false;
    final hasMotorcycleLicense =
        widget.applicantData['hasMotorcycleLicense'] ?? false;
    final resumePdfName =
        widget.applicantData['resumePdfName']?.toString() ?? '';
    final resumePdfUrl = widget.applicantData['resumePdfUrl']?.toString() ?? '';
    final selfIntro = widget.applicantData['selfIntro']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 水平分隔線
        const Divider(
          color: Color.fromARGB(255, 220, 220, 220),
          thickness: 1.0,
          height: 50,
        ),
        const Text(
          '應徵簡歷',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 32),

        // 學歷
        _buildResumeItem(
          Icons.school_rounded,
          '學歷',
          education.isNotEmpty ? education : '未設定',
          education.isEmpty,
        ),
        const SizedBox(height: 26),

        // 駕照資訊
        _buildResumeItem(
          Icons.directions_car_rounded,
          '汽車駕照',
          hasCarLicense ? '有' : '無',
          false,
          color: hasCarLicense ? Colors.green[600] : Colors.grey[500],
        ),
        const SizedBox(height: 26),

        _buildResumeItem(
          Icons.two_wheeler_rounded,
          '機車駕照',
          hasMotorcycleLicense ? '有' : '無',
          false,
          color: hasMotorcycleLicense ? Colors.green[600] : Colors.grey[500],
        ),
        const SizedBox(height: 26),

        // 自我介紹
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_rounded, color: Colors.black, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '自我介紹 ：',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(),
          child: Text(
            selfIntro.isNotEmpty ? selfIntro : '申請者尚未填寫自我介紹',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: selfIntro.isNotEmpty ? Colors.black : Colors.grey[500],
              fontStyle: selfIntro.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResumeItem(
    IconData icon,
    String label,
    String value,
    bool isEmpty, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.black, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 16, color: Colors.black),
              children: [
                TextSpan(
                  text: '$label ：',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: isEmpty ? Colors.grey[500] : (color ?? Colors.black),
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 開啟PDF履歷
  void _openPdfResume(String pdfUrl) async {
    try {
      final uri = Uri.parse(pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showErrorMessage('無法開啟PDF履歷');
        }
      }
    } catch (e) {
      print('開啟PDF履歷失敗: $e');
      if (mounted) {
        _showErrorMessage('開啟PDF履歷失敗: $e');
      }
    }
  }

  /// 撥打電話
  void _makePhoneCall(String phoneNumber) async {
    try {
      print('嘗試撥打電話: $phoneNumber');
      final uri = Uri.parse('tel:$phoneNumber');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以撥打電話: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(uri);
        print('撥打電話結果: $result');
      } else {
        if (mounted) {
          _showErrorMessage('無法撥打電話，請檢查設備是否支援通話功能');
        }
      }
    } catch (e) {
      print('撥打電話錯誤: $e');
      if (mounted) {
        _showErrorMessage('撥打電話失敗: $e');
      }
    }
  }

  /// 發送郵件
  void _sendEmail(String email) async {
    try {
      print('嘗試發送郵件至: $email');
      final uri = Uri.parse('mailto:$email');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以發送郵件: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(uri);
        print('發送郵件結果: $result');
      } else {
        if (mounted) {
          _showErrorMessage('無法開啟郵件應用程式，請檢查設備是否已安裝郵件應用程式');
        }
      }
    } catch (e) {
      print('發送郵件錯誤: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '開啟郵件應用程式失敗: $e');
      }
    }
  }

  /// 開啟 Line
  void _openLine(String lineId) async {
    try {
      print('嘗試開啟 Line: $lineId');
      final uri = Uri.parse('https://line.me/ti/p/$lineId');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以開啟 Line: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('開啟 Line 結果: $result');
      } else {
        if (mounted) {
          _showErrorMessage('無法開啟 Line，請檢查設備是否已安裝 Line 應用程式');
        }
      }
    } catch (e) {
      print('開啟 Line 錯誤: $e');
      if (mounted) {
        _showErrorMessage('開啟 Line 失敗: $e');
      }
    }
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[100]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 關閉按鈕
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[500],
                  side: BorderSide(color: Colors.grey[400]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('關閉'),
              ),
            ),
            const SizedBox(width: 12),

            // 檢舉按鈕
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showReportDialog,
                label: const Text('我要檢舉'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[600],
                  side: BorderSide(color: Colors.red[400]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
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

    if (widget.applicantData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add('電話: ${widget.applicantData['phoneNumber']}');
    }
    if (widget.applicantData['email']?.toString().isNotEmpty == true) {
      contacts.add('Email: ${widget.applicantData['email']}');
    }
    if (widget.applicantData['lineId']?.toString().isNotEmpty == true) {
      contacts.add('Line: ${widget.applicantData['lineId']}');
    }

    if (contacts.isEmpty) {
      CustomSnackBar.showWarning(context, '申請者尚未提供聯絡資訊');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題
              Text(
                '聯絡申請者',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              // 內容
              Text(
                '可透過以下方式聯絡申請者：',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 聯絡方式容器
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...contacts.map(
                      (contact) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• $contact',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 確認按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('知道了', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 發布者詳情彈窗
class PublisherDetailSheet extends StatefulWidget {
  final Map<String, dynamic> publisherData;
  final int taskCount;
  final Map<String, dynamic> currentTaskData;

  const PublisherDetailSheet({
    Key? key,
    required this.publisherData,
    required this.taskCount,
    required this.currentTaskData,
  }) : super(key: key);

  @override
  State<PublisherDetailSheet> createState() => _PublisherDetailSheetState();
}

class _PublisherDetailSheetState extends State<PublisherDetailSheet> {
  final _firestore = FirebaseFirestore.instance;

  // 動態統計資料
  int _taskCount = 0;
  double _rating = 4.8;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _taskCount = widget.taskCount; // 先使用傳入的值
    _loadPublisherStats();
  }

  /// 載入發布者統計資料
  Future<void> _loadPublisherStats() async {
    if (!mounted) return;

    setState(() => _isLoadingStats = true);

    try {
      final publisherId = widget.publisherData['uid'];
      if (publisherId != null) {
        // 查詢最新的任務數量
        final tasksQuery = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: publisherId)
            .get();

        _taskCount = tasksQuery.docs.length;

        // 這裡可以加入評分計算邏輯
        // 暫時使用用戶資料中的評分，如果沒有則用預設值
        _rating = (widget.publisherData['rating']?.toDouble()) ?? 4.8;
      }

      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    } catch (e) {
      print('載入發布者統計資料失敗: $e');
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  /// 顯示檢舉對話框
  void _showReportDialog() async {
    final reportReasons = ['不當行為或騷擾', '提供虛假資訊', '違反服務條款', '垃圾訊息或廣告', '其他不當內容'];

    String? selectedReason;
    String additionalDetails = '';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 標題
                        Row(
                          children: [
                            Icon(
                              Icons.report_problem_rounded,
                              color: Colors.red[600],
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '檢舉用戶',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 說明文字
                        Text(
                          '請選擇檢舉原因，我們會盡快處理您的回報。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 檢舉原因選擇
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: reportReasons.asMap().entries.map((
                              entry,
                            ) {
                              final reason = entry.value;
                              return RadioListTile<String>(
                                title: Text(
                                  reason,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                value: reason,
                                groupValue: selectedReason,
                                onChanged: (value) {
                                  setState(() {
                                    selectedReason = value;
                                  });
                                },
                                activeColor: Colors.red[600],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 詳細描述（可選）
                        TextField(
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: '詳細描述（可選）',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.red[400]!),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onChanged: (value) {
                            additionalDetails = value;
                          },
                        ),
                        const SizedBox(height: 24),

                        // 按鈕組
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text(
                                  '取消',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: selectedReason != null
                                    ? () {
                                        Navigator.of(context).pop({
                                          'reason': selectedReason!,
                                          'details': additionalDetails,
                                        });
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  '提交檢舉',
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
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      _submitReport('publisher', result['reason']!, result['details'] ?? '');
    }
  }

  /// 提交檢舉報告
  Future<void> _submitReport(String type, String reason, String details) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        CustomSnackBar.showError(context, '請先登入');
        return;
      }

      final reportData = {
        'reporterId': currentUser.uid,
        'reportedUserId': widget.publisherData['uid'],
        'reportedUserName': widget.publisherData['name'] ?? '未設定姓名',
        'reportType': type, // 'publisher'
        'reason': reason,
        'details': details,
        'taskId': widget.currentTaskData['id'],
        'taskTitle':
            widget.currentTaskData['title'] ??
            widget.currentTaskData['name'] ??
            '未命名任務',
        'status': 'pending', // pending, reviewed, resolved
        'createdAt': Timestamp.now(),
      };

      await _firestore.collection('reports').add(reportData);

      if (mounted) {
        Navigator.of(context).pop(); // 關閉詳情頁
        CustomSnackBar.showSuccess(context, '檢舉已提交，感謝您的回報。我們會盡快處理。');
      }
    } catch (e) {
      print('提交檢舉失敗: $e');
      if (mounted) {
        CustomSnackBar.showError(context, '提交檢舉失敗，請稍後再試');
      }
    }
  }

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
                      const SizedBox(height: 20),

                      // 發布者頭像和基本資訊
                      _buildPublisherHeader(),
                      const SizedBox(height: 20),

                      // 聯絡資訊
                      _buildContactInfo(context),
                      const SizedBox(height: 20),

                      // 個人簡介
                      _buildResumeSection(),

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

  Widget _buildPublisherHeader() {
    final publisherName = widget.publisherData['name'] ?? '未設定姓名';
    final avatarUrl = widget.publisherData['avatarUrl']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.grey[100]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左側：發布者資訊
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  VerifiedAvatar(
                    avatarUrl: avatarUrl,
                    radius: 50,
                    isVerified: widget.publisherData['isVerified'] == true,
                    badgeSize: 28,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$publisherName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  widget.publisherData['isVerified'] == true
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.how_to_reg_rounded,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '真人用戶',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '尚未認證用戶',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // 右側：任務統計
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已發布任務',
                        style: TextStyle(fontSize: 13, color: Colors.black),
                      ),
                      const SizedBox(height: 4),
                      _isLoadingStats
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '$_taskCount',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                    ],
                  ),
                  const Divider(
                    color: Color.fromARGB(255, 220, 220, 220),
                    thickness: 1.0,
                    height: 44,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '評分',
                        style: TextStyle(fontSize: 13, color: Colors.black),
                      ),
                      const SizedBox(height: 4),
                      _isLoadingStats
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _rating.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfo(BuildContext context) {
    final contacts = <Widget>[];

    if (widget.publisherData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.phone_rounded,
          '電話',
          widget.publisherData['phoneNumber'],
          Colors.black,
          onTap: () =>
              _makePhoneCall(widget.publisherData['phoneNumber'], context),
        ),
      );
    }

    if (widget.publisherData['email']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.email_rounded,
          '電子郵件',
          widget.publisherData['email'],
          Colors.black,
          onTap: () => _sendEmail(widget.publisherData['email'], context),
        ),
      );
    }

    if (widget.publisherData['lineId']?.toString().isNotEmpty == true) {
      contacts.add(
        _buildContactItem(
          Icons.chat_rounded,
          'Line ID',
          widget.publisherData['lineId'],
          Colors.black,
          onTap: () => _openLine(widget.publisherData['lineId'], context),
        ),
      );
    }

    if (contacts.isEmpty) {
      contacts.add(
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_rounded, color: Colors.grey[400], size: 32),
              const SizedBox(height: 12),
              Text(
                '發布者尚未提供聯絡資訊',
                style: TextStyle(color: Colors.grey[500], fontSize: 15),
              ),
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
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        ...contacts,
      ],
    );
  }

  Widget _buildContactItem(
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 24),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? color : Colors.black,
                      decoration: onTap != null ? TextDecoration.none : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 撥打電話
  void _makePhoneCall(String phoneNumber, BuildContext context) async {
    try {
      print('嘗試撥打電話: $phoneNumber');
      final uri = Uri.parse('tel:$phoneNumber');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以撥打電話: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(uri);
        print('撥打電話結果: $result');
      } else {
        CustomSnackBar.showError(context, '無法撥打電話，請檢查設備是否支援通話功能');
      }
    } catch (e) {
      print('撥打電話錯誤: $e');
      CustomSnackBar.showError(context, '撥打電話失敗: $e');
    }
  }

  /// 發送郵件
  void _sendEmail(String email, BuildContext context) async {
    try {
      print('嘗試發送郵件至: $email');
      final uri = Uri.parse('mailto:$email');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以發送郵件: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(uri);
        print('發送郵件結果: $result');
      } else {
        CustomSnackBar.showError(context, '無法開啟郵件應用程式，請檢查設備是否已安裝郵件應用程式');
      }
    } catch (e) {
      print('發送郵件錯誤: $e');
      CustomSnackBar.showError(context, '開啟郵件應用程式失敗: $e');
    }
  }

  /// 開啟 Line
  void _openLine(String lineId, BuildContext context) async {
    try {
      print('嘗試開啟 Line: $lineId');
      final uri = Uri.parse('https://line.me/ti/p/$lineId');

      final canLaunch = await canLaunchUrl(uri);
      print('是否可以開啟 Line: $canLaunch');

      if (canLaunch) {
        final result = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('開啟 Line 結果: $result');
      } else {
        CustomSnackBar.showError(context, '無法開啟 Line，請檢查設備是否已安裝 Line 應用程式');
      }
    } catch (e) {
      print('開啟 Line 錯誤: $e');
      CustomSnackBar.showError(context, '開啟 Line 失敗: $e');
    }
  }

  Widget _buildResumeSection() {
    final publisherIntro =
        widget.publisherData['publisherResume']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 水平分隔線
        const Divider(
          color: Color.fromARGB(255, 220, 220, 220),
          thickness: 1.0,
          height: 50,
        ),
        const Text(
          '個人介紹',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Text(
            publisherIntro.isNotEmpty ? publisherIntro : '發布者尚未填寫個人介紹',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: publisherIntro.isNotEmpty
                  ? Colors.black
                  : Colors.grey[500],
              fontStyle: publisherIntro.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
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
        border: Border(top: BorderSide(color: Colors.grey[100]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 關閉按鈕
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[500],
                  side: BorderSide(color: Colors.grey[400]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('關閉'),
              ),
            ),
            const SizedBox(width: 12),

            // 檢舉按鈕
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showReportDialog,
                label: const Text('我要檢舉'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[600],
                  side: BorderSide(color: Colors.red[400]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _contactPublisher(BuildContext context) {
    final contacts = <String>[];

    if (widget.publisherData['phoneNumber']?.toString().isNotEmpty == true) {
      contacts.add('電話: ${widget.publisherData['phoneNumber']}');
    }
    if (widget.publisherData['email']?.toString().isNotEmpty == true) {
      contacts.add('Email: ${widget.publisherData['email']}');
    }
    if (widget.publisherData['lineId']?.toString().isNotEmpty == true) {
      contacts.add('Line: ${widget.publisherData['lineId']}');
    }

    if (contacts.isEmpty) {
      CustomSnackBar.showWarning(context, '發布者尚未提供聯絡資訊');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題
              Text(
                '聯絡發布者',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              // 內容
              Text(
                '可透過以下方式聯絡發布者：',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 聯絡方式容器
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...contacts.map(
                      (contact) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• $contact',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 確認按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('知道了', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
