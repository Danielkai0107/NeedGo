import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// 載入該地點的任務列表（僅Player視角）
  Future<void> _loadTasksAtLocation() async {
    if (widget.isParentView) return;

    setState(() => _isLoadingTasks = true);

    try {
      // 使用提供的任務列表或從資料庫查詢
      if (widget.availableTasksAtLocation != null) {
        setState(() {
          _tasksAtLocation = widget.availableTasksAtLocation!;
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

      setState(() {
        _tasksAtLocation = tasksAtLocation;
        _isLoadingTasks = false;
      });
    } catch (e) {
      print('載入地點任務失敗: $e');
      setState(() => _isLoadingTasks = false);
    }
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
                      // 地點標題
                      _buildLocationHeader(),
                      const SizedBox(height: 16),

                      // 地點描述
                      if (widget.locationData['description'] != null)
                        _buildDescriptionSection(),

                      // 地址資訊
                      _buildAddressSection(),

                      // 交通資訊
                      _buildTravelSection(),

                      // 地點設施資訊
                      if (widget.locationData['facilities'] != null)
                        _buildFacilitiesSection(),

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
    final name = widget.locationData['name']?.toString() ?? '未命名地點';
    final category = widget.locationData['category']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 系統道館標題
          Text(
            '系統道館',
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (category.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    final description = widget.locationData['description']?.toString() ?? '';
    if (description.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '地點介紹',
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
              description,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    final address =
        widget.locationData['address']?.toString() ??
        widget.locationData['name']?.toString() ??
        '地址未設定';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on, color: Colors.red[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _openGoogleMaps(),
              child: Text(
                address,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildFacilitiesSection() {
    final facilities = widget.locationData['facilities'];
    if (facilities == null) return const SizedBox.shrink();

    List<String> facilityList = [];

    if (facilities is List) {
      facilityList = facilities.map((f) => f.toString()).toList();
    } else if (facilities is String) {
      facilityList = [facilities];
    }

    if (facilityList.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '設施資訊',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: facilityList.map((facility) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Text(
                  facility,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '該地點任務 (${_tasksAtLocation.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          if (_isLoadingTasks)
            const Center(child: CircularProgressIndicator())
          else if (_tasksAtLocation.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: const Center(
                child: Text(
                  '此地點目前沒有可用任務',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          else
            ...(_tasksAtLocation.map((task) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ListTile(
                  title: Text(
                    task['title']?.toString() ??
                        task['name']?.toString() ??
                        '未命名任務',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task['price'] != null && task['price'] > 0)
                        Text(
                          'NT\$ ${task['price']}',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      if (task['content'] != null &&
                          task['content'].toString().isNotEmpty)
                        Text(
                          task['content'].toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => widget.onTaskSelected?.call(task),
                ),
              );
            }).toList()),
        ],
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
      // Parent 視角：以此地點新增任務
      return ElevatedButton(
        onPressed: widget.onCreateTaskAtLocation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
        child: const Text('以此地點新增任務'),
      );
    } else {
      // Player 視角：查看所有任務或導航
      return Row(
        children: [
          if (_tasksAtLocation.isNotEmpty) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  // 滾動到任務列表區域
                  // 這裡可以實現滾動到任務區域的邏輯
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('查看任務'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // 開啟地圖導航
                _openNavigation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('導航'),
            ),
          ),
        ],
      );
    }
  }

  /// 開啟 Google Maps 查看地址
  Future<void> _openGoogleMaps() async {
    final lat = widget.locationData['lat'];
    final lng = widget.locationData['lng'];
    final name = widget.locationData['name']?.toString() ?? '';

    // 建構 Google Maps URL
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟地圖')));
      }
    }
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
