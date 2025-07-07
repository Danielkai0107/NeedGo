import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../components/task_detail_sheet.dart';
import '../components/location_info_sheet.dart';
import '../components/create_edit_task_bottom_sheet.dart' as new_task_sheet;
import '../styles/map_styles.dart';
import '../utils/custom_snackbar.dart';

/// 首頁地圖視角
class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({Key? key}) : super(key: key);

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  final _firestore = FirebaseFirestore.instance;
  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 16;
  LatLng? _myLocation;

  // 數據
  List<Map<String, dynamic>> _allPosts = [];
  List<Map<String, dynamic>> _myPosts = [];
  List<Map<String, dynamic>> _systemLocations = [];
  Map<String, dynamic> _profile = {};
  String _userRole = 'parent'; // parent 或 player

  // 地圖相關
  Set<Marker> _markers = {};
  Set<String> _availableCategories = {};
  Set<String> _selectedCategories = {};
  bool _showCategoryFilter = false;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  /// 初始化地圖數據
  Future<void> _initializeMapData() async {
    if (!mounted) return;

    try {
      await _loadUserProfile();
      await _loadSystemLocations();
      await _findAndRecenter();

      if (_userRole == 'parent') {
        await _loadMyPosts();
      } else {
        await _loadAllPosts();
      }

      _updateMarkers();
    } catch (e) {
      print('初始化地圖數據失敗: $e');
    }
  }

  /// 載入用戶資料
  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _profile = doc.data() ?? {};
          // 從用戶偏好或默認設定判斷角色
          _userRole = _profile['preferredRole'] ?? 'parent';
        });
      }
    } catch (e) {
      print('載入用戶資料失敗: $e');
    }
  }

  /// 載入系統地點
  Future<void> _loadSystemLocations() async {
    try {
      final snapshot = await _firestore.collection('systemLocations').get();
      final locations = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      final categories = locations
          .map((loc) => loc['category']?.toString() ?? '')
          .where((cat) => cat.isNotEmpty)
          .toSet();

      if (mounted) {
        setState(() {
          _systemLocations = locations;
          _availableCategories = categories;
          _selectedCategories = Set.from(categories);
        });
      }
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  /// 載入我的任務（Parent 視角）
  Future<void> _loadMyPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        if (data['lat'] != null) {
          data['lat'] = data['lat'] is String
              ? double.parse(data['lat'])
              : data['lat'].toDouble();
        }
        if (data['lng'] != null) {
          data['lng'] = data['lng'] is String
              ? double.parse(data['lng'])
              : data['lng'].toDouble();
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _myPosts = posts;
        });
      }
    } catch (e) {
      print('載入我的任務失敗: $e');
    }
  }

  /// 載入所有任務（Player 視角）
  Future<void> _loadAllPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        if (data['lat'] != null) {
          data['lat'] = data['lat'] is String
              ? double.parse(data['lat'])
              : data['lat'].toDouble();
        }
        if (data['lng'] != null) {
          data['lng'] = data['lng'] is String
              ? double.parse(data['lng'])
              : data['lng'].toDouble();
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _allPosts = posts;
        });
      }
    } catch (e) {
      print('載入所有任務失敗: $e');
    }
  }

  /// 定位到當前位置
  Future<void> _findAndRecenter() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition();
      final newLocation = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _myLocation = newLocation;
          _center = newLocation;
        });

        _mapCtrl.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newLocation, zoom: _zoom),
          ),
        );
      }
    } catch (e) {
      print('定位失敗: $e');
    }
  }

  /// 更新地圖標記
  void _updateMarkers() {
    if (!mounted) return;

    final allMarkers = <Marker>{};

    // 添加系統地點標記
    allMarkers.addAll(_buildSystemLocationMarkers());

    // 根據角色添加任務標記
    if (_userRole == 'parent') {
      allMarkers.addAll(_buildMyTaskMarkers());
    } else {
      allMarkers.addAll(_buildAllTaskMarkers());
    }

    // 添加我的位置標記
    if (_myLocation != null) {
      allMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: '我的位置'),
        ),
      );
    }

    setState(() {
      _markers = allMarkers;
    });
  }

  /// 建立系統地點標記
  Set<Marker> _buildSystemLocationMarkers() {
    final markers = <Marker>{};

    for (var location in _systemLocations) {
      if (!_selectedCategories.contains(location['category'])) continue;

      markers.add(
        Marker(
          markerId: MarkerId('system_${location['id']}'),
          position: LatLng(location['lat'], location['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () => _showLocationDetail(location),
        ),
      );
    }

    return markers;
  }

  /// 建立我的任務標記（Parent 視角）
  Set<Marker> _buildMyTaskMarkers() {
    final markers = <Marker>{};

    for (var task in _myPosts) {
      if (task['lat'] == null || task['lng'] == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId('my_task_${task['id']}'),
          position: LatLng(task['lat'], task['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          onTap: () => _showTaskDetail(task, isMyTask: true),
        ),
      );
    }

    return markers;
  }

  /// 建立所有任務標記（Player 視角）
  Set<Marker> _buildAllTaskMarkers() {
    final markers = <Marker>{};
    final currentUser = FirebaseAuth.instance.currentUser;

    for (var task in _allPosts) {
      if (task['lat'] == null || task['lng'] == null) continue;
      if (task['userId'] == currentUser?.uid) continue; // 跳過自己的任務

      markers.add(
        Marker(
          markerId: MarkerId('task_${task['id']}'),
          position: LatLng(task['lat'], task['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          onTap: () => _showTaskDetail(task, isMyTask: false),
        ),
      );
    }

    return markers;
  }

  /// 顯示地點詳情
  void _showLocationDetail(Map<String, dynamic> locationData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationInfoSheet(
        locationData: locationData,
        isParentView: _userRole == 'parent',
        currentLocation: _myLocation,
        onCreateTaskAtLocation: () {
          Navigator.of(context).pop();
          if (_userRole == 'parent') {
            _showCreateTaskSheet(locationData);
          }
        },
      ),
    );
  }

  /// 顯示任務詳情
  void _showTaskDetail(
    Map<String, dynamic> taskData, {
    required bool isMyTask,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        taskData: taskData,
        isParentView: _userRole == 'parent',
        currentLocation: _myLocation,
        onTaskUpdated: () {
          if (_userRole == 'parent') {
            _loadMyPosts();
          } else {
            _loadAllPosts();
          }
          _updateMarkers();
        },
        onEditTask: isMyTask
            ? () {
                Navigator.of(context).pop();
                _showEditTaskSheet(taskData);
              }
            : null,
        onDeleteTask: isMyTask
            ? () async {
                Navigator.of(context).pop();
                await _deleteTask(taskData['id']);
              }
            : null,
      ),
    );
  }

  /// 顯示創建任務彈窗
  void _showCreateTaskSheet([Map<String, dynamic>? locationData]) {
    if (_userRole != 'parent') return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        onSubmit: (taskData) async {
          Navigator.of(context).pop();
          await _saveNewTask(taskData.toJson());
        },
      ),
    );
  }

  /// 顯示編輯任務彈窗
  void _showEditTaskSheet(Map<String, dynamic> taskData) {
    if (_userRole != 'parent') return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      builder: (context) => new_task_sheet.CreateEditTaskBottomSheet(
        existingTask: taskData,
        onSubmit: (updatedTaskData) async {
          Navigator.of(context).pop();
          await _saveEditedTask(updatedTaskData.toJson());
        },
      ),
    );
  }

  /// 保存新任務
  Future<void> _saveNewTask(Map<String, dynamic> taskData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firestore.collection('posts').add({
        ...taskData,
        'userId': user.uid,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'isActive': true,
        'applicants': [],
      });

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務創建成功！');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '創建任務失敗：$e');
      }
    }
  }

  /// 保存編輯的任務
  Future<void> _saveEditedTask(Map<String, dynamic> taskData) async {
    try {
      final taskId = taskData['id'];
      await _firestore.collection('posts').doc(taskId).update({
        ...taskData,
        'updatedAt': Timestamp.now(),
      });

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務更新成功！');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '更新任務失敗：$e');
      }
    }
  }

  /// 刪除任務
  Future<void> _deleteTask(String taskId) async {
    try {
      await _firestore.collection('posts').doc(taskId).delete();

      if (mounted) {
        CustomSnackBar.showSuccess(context, '任務已刪除');
        await _loadMyPosts();
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, '刪除任務失敗：$e');
      }
    }
  }

  /// 切換角色
  void _switchRole() {
    setState(() {
      _userRole = _userRole == 'parent' ? 'player' : 'parent';
    });

    // 重新載入數據
    if (_userRole == 'parent') {
      _loadMyPosts();
    } else {
      _loadAllPosts();
    }
    _updateMarkers();
  }

  /// 建立類別篩選器
  Widget _buildCategoryFilter() {
    if (!_showCategoryFilter || _availableCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '篩選類別',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableCategories.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCategories.add(category);
                    } else {
                      _selectedCategories.remove(category);
                    }
                  });
                  _updateMarkers();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 地圖
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            onMapCreated: (GoogleMapController controller) {
              _mapCtrl = controller;
              controller.setMapStyle(MapStyles.customStyle);
            },
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),

          // 類別篩選器
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: _buildCategoryFilter(),
          ),

          // 右上角功能按鈕
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Column(
              children: [
                // 角色切換按鈕
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'role_switch',
                  onPressed: _switchRole,
                  child: Icon(
                    _userRole == 'parent' ? Icons.person : Icons.business,
                  ),
                ),
                const SizedBox(height: 8),
                // 篩選按鈕
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  heroTag: 'filter',
                  onPressed: () {
                    setState(() {
                      _showCategoryFilter = !_showCategoryFilter;
                    });
                  },
                  child: Icon(_showCategoryFilter ? Icons.close : Icons.tune),
                ),
              ],
            ),
          ),

          // 右下角定位按鈕
          Positioned(
            bottom: 160,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              heroTag: 'location',
              onPressed: _findAndRecenter,
              child: const Icon(Icons.my_location),
            ),
          ),

          // 左下角創建任務按鈕（僅 Parent 角色）
          if (_userRole == 'parent')
            Positioned(
              bottom: 160,
              left: 16,
              child: FloatingActionButton(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                heroTag: 'create_task',
                onPressed: () => _showCreateTaskSheet(),
                child: const Icon(Icons.add),
              ),
            ),
        ],
      ),
    );
  }
}
