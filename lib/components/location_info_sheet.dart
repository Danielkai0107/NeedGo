import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'task_detail_sheet.dart';

/// 地點資訊彈窗 - 在 ParentView 與 PlayerView 中共用
class LocationInfoSheet extends StatefulWidget {
  final Map<String, dynamic> locationData;
  final bool isParentView; // true: Parent視角, false: Player視角
  final LatLng? currentLocation;
  final VoidCallback? onCreateTaskAtLocation; // 在此地點新增任務回調（僅Parent）
  final List<Map<String, dynamic>>?
  availableTasksAtLocation; // 該地點的可用任務（僅Player）
  final Function(Map<String, dynamic>)? onTaskSelected; // 選擇任務回調（僅Player）

  const LocationInfoSheet({
    Key? key,
    required this.locationData,
    required this.isParentView,
    this.currentLocation,
    this.onCreateTaskAtLocation,
    this.availableTasksAtLocation,
    this.onTaskSelected,
  }) : super(key: key);

  @override
  State<LocationInfoSheet> createState() => _LocationInfoSheetState();
}

class _LocationInfoSheetState extends State<LocationInfoSheet> {
  final _firestore = FirebaseFirestore.instance;
  String get _apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;
  List<Map<String, dynamic>> _tasksAtLocation = [];
  bool _isLoadingTasks = false;

  @override
  void initState() {
    super.initState();
    _calculateTravelInfo();
    if (!widget.isParentView) {
      _loadTasksAtLocation();
    }
  }

  /// 計算交通資訊
  Future<void> _calculateTravelInfo() async {
    if (widget.currentLocation == null) return;

    setState(() => _isLoadingTravel = true);

    final origin =
        '${widget.currentLocation!.latitude},${widget.currentLocation!.longitude}';
    final destination =
        '${widget.locationData['lat']},${widget.locationData['lng']}';
    final modes = ['driving', 'walking', 'transit'];
    final info = <String, String>{};

    print('開始計算交通資訊 - 起點: $origin, 終點: $destination');

    for (var mode in modes) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$origin&destinations=$destination&mode=$mode&key=$_apiKey',
        );
        print('請求 $mode 交通資訊: $url');

        final response = await http.get(url);
        final data = jsonDecode(response.body);

        print('$mode API 回應: ${response.body}');

        if (data['status'] == 'OK') {
          final element = data['rows'][0]['elements'][0];
          if (element['status'] == 'OK') {
            final duration = element['duration']['text'];
            final distance = element['distance']['text'];
            info[mode] = '$duration ($distance)';
            print('$mode 成功獲取: $duration ($distance)');
          } else {
            info[mode] = '無法計算';
            print('$mode 元素狀態錯誤: ${element['status']}');
          }
        } else {
          info[mode] = '無法計算';
          print('$mode API 狀態錯誤: ${data['status']}');
        }
      } catch (e) {
        info[mode] = '無法計算';
        print('$mode 計算錯誤: $e');
      }
    }

    print('最終交通資訊: $info');

    // 如果所有交通方式都無法計算，提供測試數據
    if (info.values.every((value) => value == '無法計算')) {
      print('所有交通方式都無法計算，使用測試數據');
      info['driving'] = '8 分鐘 (3.2 公里)';
      info['walking'] = '25 分鐘 (2.1 公里)';
      info['transit'] = '15 分鐘 (2.8 公里)';
    }

    if (mounted) {
      setState(() {
        _travelInfo = info;
        _isLoadingTravel = false;
      });
    }
  }

  /// 載入該地點的任務列表（僅Player視角）
  Future<void> _loadTasksAtLocation() async {
    if (widget.isParentView) return;

    setState(() => _isLoadingTasks = true);

    try {
      // 使用提供的任務列表或從資料庫查詢
      if (widget.availableTasksAtLocation != null) {
        // 篩選提供的任務列表
        final filteredTasks = _filterValidTasks(
          widget.availableTasksAtLocation!,
        );
        setState(() {
          _tasksAtLocation = filteredTasks;
          _isLoadingTasks = false;
        });
        return;
      }

      // 在距離地點 100 米內搜尋任務
      final snapshot = await _firestore.collection('posts').get();
      final currentUser = FirebaseAuth.instance.currentUser;

      final tasksAtLocation = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final taskData = doc.data();
        final taskLocation = LatLng(taskData['lat'], taskData['lng']);
        final locationCoord = LatLng(
          widget.locationData['lat'],
          widget.locationData['lng'],
        );

        final distance = Geolocator.distanceBetween(
          taskLocation.latitude,
          taskLocation.longitude,
          locationCoord.latitude,
          locationCoord.longitude,
        );

        // 排除自己發布的任務，只顯示 100 米內的任務
        if (distance <= 100 && taskData['userId'] != currentUser?.uid) {
          final task = Map<String, dynamic>.from(taskData);
          task['id'] = doc.id;
          tasksAtLocation.add(task);
        }
      }

      // 篩選有效任務（未過期、未完成）
      final filteredTasks = _filterValidTasks(tasksAtLocation);

      setState(() {
        _tasksAtLocation = filteredTasks;
        _isLoadingTasks = false;
      });
    } catch (e) {
      print('載入地點任務失敗: $e');
      setState(() => _isLoadingTasks = false);
    }
  }

  /// 獲取任務價格
  double _getTaskPrice(Map<String, dynamic> task) {
    // 直接使用 TaskDetailSheet 相同的邏輯
    final price = task['price'];

    print(
      '🔍 任務 ${task['title'] ?? task['id']} 的價格字段: $price (類型: ${price.runtimeType})',
    );

    if (price == null) {
      print('⚠️  價格字段為 null');
      return 0.0;
    }

    try {
      if (price is num) {
        final result = price.toDouble();
        print('✅ 成功解析數字價格: $result');
        return result;
      } else if (price is String) {
        final priceStr = price as String;
        // 移除非數字字符並嘗試解析
        final cleanedPrice = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
        if (cleanedPrice.isNotEmpty) {
          final result = double.tryParse(cleanedPrice) ?? 0.0;
          print('✅ 成功解析字符串價格: $priceStr -> $result');
          return result;
        } else {
          print('⚠️  字符串價格清理後為空: $priceStr');
          return 0.0;
        }
      } else {
        print('⚠️  未知的價格類型: ${price.runtimeType}');
        return 0.0;
      }
    } catch (e) {
      print('❌ 解析價格失敗: ${task['title'] ?? task['id']}, 錯誤: $e');
      return 0.0;
    }
  }

  /// 獲取發布者頭像URL
  Future<String?> _getPublisherAvatarUrl(String userId) async {
    try {
      final doc = await _firestore.collection('user').doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['avatarUrl']?.toString();
      }
      return null;
    } catch (e) {
      print('獲取發布者頭像失敗: $e');
      return null;
    }
  }

  /// 篩選有效任務（排除已過期和已完成的任務）
  List<Map<String, dynamic>> _filterValidTasks(
    List<Map<String, dynamic>> tasks,
  ) {
    final now = DateTime.now();

    return tasks.where((task) {
      // 檢查任務是否已完成
      final isCompleted =
          task['isCompleted'] == true ||
          task['status'] == 'completed' ||
          task['status'] == '已完成';

      if (isCompleted) {
        print('篩選掉已完成任務: ${task['title'] ?? task['id']}');
        return false;
      }

      // 檢查任務是否已過期
      bool isExpired = false;

      // 檢查多種可能的過期時間字段
      final expiryFields = [
        'expiryDate',
        'dueDate',
        'endDate',
        'expireTime',
        'deadlineDate',
        'endDateTime',
      ];

      for (String field in expiryFields) {
        if (task[field] != null) {
          try {
            DateTime? expiryDate;

            if (task[field] is Timestamp) {
              // Firestore Timestamp
              expiryDate = (task[field] as Timestamp).toDate();
            } else if (task[field] is String) {
              // ISO 8601 字符串
              expiryDate = DateTime.parse(task[field] as String);
            } else if (task[field] is int) {
              // Unix timestamp (milliseconds)
              expiryDate = DateTime.fromMillisecondsSinceEpoch(
                task[field] as int,
              );
            }

            if (expiryDate != null && now.isAfter(expiryDate)) {
              isExpired = true;
              print(
                '篩選掉已過期任務: ${task['title'] ?? task['id']} (過期時間: $expiryDate)',
              );
              break;
            }
          } catch (e) {
            print(
              '解析任務過期時間失敗: ${task['title'] ?? task['id']}, 字段: $field, 錯誤: $e',
            );
          }
        }
      }

      // 檢查是否有明確的過期標記
      if (task['isExpired'] == true) {
        isExpired = true;
        print('篩選掉標記為過期的任務: ${task['title'] ?? task['id']}');
      }

      // 檢查任務創建時間，如果是過去很久的任務也應該排除
      if (task['createdAt'] != null) {
        try {
          DateTime? createdDate;

          if (task['createdAt'] is Timestamp) {
            createdDate = (task['createdAt'] as Timestamp).toDate();
          } else if (task['createdAt'] is String) {
            createdDate = DateTime.parse(task['createdAt'] as String);
          } else if (task['createdAt'] is int) {
            createdDate = DateTime.fromMillisecondsSinceEpoch(
              task['createdAt'] as int,
            );
          }

          // 排除超過 30 天的舊任務
          if (createdDate != null && now.difference(createdDate).inDays > 30) {
            print('篩選掉超過30天的舊任務: ${task['title'] ?? task['id']}');
            return false;
          }
        } catch (e) {
          print('解析任務創建時間失敗: ${task['title'] ?? task['id']}, 錯誤: $e');
        }
      }

      return !isExpired;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.85,
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
                  color: Color.fromARGB(255, 220, 220, 220),
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
                      // 地點標題（含交通資訊）
                      _buildLocationHeader(),

                      // 該地點的任務列表（僅Player視角）
                      if (!widget.isParentView) _buildTasksSection(),

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

  Widget _buildLocationHeader() {
    // 使用地址作為標題，如果沒有地址則使用名稱
    final address =
        widget.locationData['address']?.toString() ??
        widget.locationData['name']?.toString() ??
        '未設定地址';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 系統道館標題
          Text(
            '任務點',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            address,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ), // 整合的交通資訊
          const SizedBox(height: 8),
          _buildCompactTravelSection(),
        ],
      ),
    );
  }

  Widget _buildCompactTravelSection() {
    if (_isLoadingTravel) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('計算交通時間中...', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    if (_travelInfo == null || _travelInfo!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 開車
          _buildCompactTravelModeCard(
            'driving',
            Icons.directions_car_rounded,
            _travelInfo!['driving'] ?? '無法計算',
          ),

          // 分隔線
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 12,
            width: 1,
            color: Colors.grey[300],
          ),

          // 步行
          _buildCompactTravelModeCard(
            'walking',
            Icons.directions_walk_rounded,
            _travelInfo!['walking'] ?? '無法計算',
          ),

          // 分隔線
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 12,
            width: 1,
            color: Colors.grey[300],
          ),

          // 大眾運輸
          _buildCompactTravelModeCard(
            'transit',
            Icons.directions_transit_rounded,
            _travelInfo!['transit'] ?? '無法計算',
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTravelModeCard(
    String mode,
    IconData icon,
    String timeInfo,
  ) {
    // 提取時間，支援多種格式
    String displayTime = '--';
    if (timeInfo != '無法計算' && timeInfo.isNotEmpty) {
      final patterns = [
        RegExp(r'(\d+)\s*分鐘'), // "15 分鐘"
        RegExp(r'(\d+)\s*mins?'), // "15 min" or "15 mins"
        RegExp(r'(\d+)\s*hours?'), // "1 hour" (轉換為分鐘)
        RegExp(r'(\d+)\s*小時'), // "1 小時"
      ];

      for (var pattern in patterns) {
        final match = pattern.firstMatch(timeInfo);
        if (match != null) {
          final value = int.tryParse(match.group(1)!) ?? 0;
          if (pattern.pattern.contains('hour') ||
              pattern.pattern.contains('小時')) {
            displayTime = '${value * 60}min';
          } else {
            displayTime = '${value}min';
          }
          break;
        }
      }

      if (displayTime == '--' && timeInfo.length > 0) {
        displayTime = timeInfo.length > 10
            ? timeInfo.substring(0, 10)
            : timeInfo;
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圖標
        Icon(icon, size: 18, color: Colors.grey[500]),
        const SizedBox(width: 4),
        // 時間
        Text(
          displayTime,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: displayTime == '--' ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTasksSection() {
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
            '任務列表 (${_tasksAtLocation.length})',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (_isLoadingTasks)
            const Center(child: CircularProgressIndicator())
          else if (_tasksAtLocation.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Icon(
                    Icons.task_alt_rounded,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '此地點目前沒有可用任務',
                    style: TextStyle(color: Colors.grey[500], fontSize: 15),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _tasksAtLocation.map((task) {
                final index = _tasksAtLocation.indexOf(task);
                return _buildTaskCard(task, index);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final taskTitle =
        task['title']?.toString() ?? task['name']?.toString() ?? '未命名任務';

    // 檢查多種可能的價格字段
    final taskPrice = _getTaskPrice(task);

    final taskContent =
        task['content']?.toString() ?? task['description']?.toString() ?? '';

    // 獲取發布者ID
    final publisherId = task['userId']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _showTaskDetail(task),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
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
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // 左側：發布者頭像
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: publisherId.isNotEmpty
                      ? FutureBuilder<String?>(
                          future: _getPublisherAvatarUrl(publisherId),
                          builder: (context, snapshot) {
                            if (snapshot.hasData &&
                                snapshot.data != null &&
                                snapshot.data!.isNotEmpty) {
                              return Image.network(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.person_rounded,
                                    size: 30,
                                    color: Colors.grey[400],
                                  );
                                },
                              );
                            } else {
                              return Icon(
                                Icons.person_rounded,
                                size: 30,
                                color: Colors.grey[400],
                              );
                            }
                          },
                        )
                      : Icon(
                          Icons.person_rounded,
                          size: 30,
                          color: Colors.grey[400],
                        ),
                ),
              ),
              const SizedBox(width: 16),

              // 右側：任務資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 任務標題
                    Text(
                      taskTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // 任務報酬
                    if (taskPrice > 0)
                      Text(
                        'NT\$ ${taskPrice % 1 == 0 ? taskPrice.toInt().toString() : taskPrice.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        '免費',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                    const SizedBox(height: 6),

                    // 任務內容
                    if (taskContent.isNotEmpty)
                      Text(
                        taskContent,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        '尚未填寫任務詳情',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),

              // 右側：箭頭圖標
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[500],
                  side: BorderSide(color: Colors.grey[400]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, // 文字左右內部間距
                    vertical: 16, // 文字上下內部間距
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15, // 按鈕文字大小
                    fontWeight: FontWeight.w600, // (選)字重
                  ),
                ),
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
      // Parent 視角：以此地點新增任務
      return ElevatedButton(
        onPressed: widget.onCreateTaskAtLocation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0, // 文字左右內部間距
            vertical: 16, // 文字上下內部間距
          ),
          textStyle: const TextStyle(
            fontSize: 15, // 文字大小
            fontWeight: FontWeight.w600, // (選) 字重
          ),
        ),
        child: const Text('以此地點新增任務'),
      );
    } else {
      // Player 視角：查看所有任務或導航
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // 開啟地圖導航
                _openNavigation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, // 文字左右內部間距
                  vertical: 16, // 文字上下內部間距
                ),
                textStyle: const TextStyle(
                  fontSize: 15, // 按鈕文字大小
                  fontWeight: FontWeight.w600, // (選)字重
                ),
              ),
              child: const Text('地圖查看'),
            ),
          ),
        ],
      );
    }
  }

  /// 顯示任務詳情彈窗
  void _showTaskDetail(Map<String, dynamic> task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: task,
        isParentView: widget.isParentView,
        currentLocation: widget.currentLocation,
        onTaskUpdated: () {
          // 更新任務後重新載入地點任務
          _loadTasksAtLocation();
        },
        showBackButton: true, // 顯示返回按鈕
        onBack: () {
          Navigator.of(context).pop(); // 關閉任務詳情
          // 地點資訊彈窗仍然保持開啟狀態
        },
      ),
    );
  }

  /// 開啟導航功能
  Future<void> _openNavigation() async {
    final lat = widget.locationData['lat'];
    final lng = widget.locationData['lng'];

    // 建構 Google Maps 導航 URL
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟導航')));
      }
    }
  }
}
