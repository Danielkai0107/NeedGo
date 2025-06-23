// lib/screens/player_view.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../styles/map_styles.dart';
import '../services/auth_service.dart';
import '../components/full_screen_popup.dart';

enum BottomSheetType {
  none,
  locationDetail,
  newPostNotification,
  myApplications,
  notificationPanel,
  profileEditor,
}

class PlayerView extends StatefulWidget {
  const PlayerView({Key? key}) : super(key: key);

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  late GoogleMapController _mapCtrl;
  LatLng _center = const LatLng(25.0479, 121.5171);
  double _zoom = 14;
  LatLng? _myLocation;

  final _firestore = FirebaseFirestore.instance;
  final _authService = AuthService();

  StreamSubscription<QuerySnapshot>? _postsSub;
  List<Map<String, dynamic>> _allPosts = [];
  Timestamp? _listenerAttachedTs;

  // 被选中的，无论是静态公园还是某条贴文
  Map<String, dynamic>? _selectedLocation;
  bool _isLoadingTravel = false;
  Map<String, String>? _travelInfo;

  // 將多個布林變數替換為單一的枚舉狀態
  BottomSheetType _currentBottomSheet = BottomSheetType.none;

  // 在 _PlayerViewState 類別中添加：
  List<Map<String, dynamic>> _systemLocations = [];
  Set<String> _availableCategories = {};
  Set<String> _selectedCategories = {};
  bool _showCategoryFilter = false;

  // 添加缺失的變數
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _profileForm = {};
  String? _profileStatusType;
  String? _profileStatusMessage;
  Map<String, dynamic>? _newPostToShow;
  bool _isApplying = false;
  static const String _apiKey = 'AIzaSyCne1CQNTGm_a3DFxcN59lYhKGlj5McqqE';

  List<Map<String, dynamic>> get _myApplications {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    return _allPosts.where((p) {
      final apps = List<String>.from(p['applicants'] ?? []);
      return apps.contains(user.uid);
    }).toList();
  }

  // 新增通知相关变量
  List<Map<String, dynamic>> _newPosts = [];
  int _unreadCount = 0;
  Timer? _notificationTimer;
  DateTime? _lastCheckTime;

  @override
  void initState() {
    super.initState();
    _loadSystemLocations();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _loadProfile(user.uid);
        _initializeNotificationSystem(); // 先初始化時間
        _attachPostsListener(); // 再檢查歷史通知並設置監聽器
      } else {
        _postsSub?.cancel();
        _notificationTimer?.cancel();
        setState(() {
          _allPosts = [];
          _newPosts.clear(); // 清空通知
          _unreadCount = 0;
        });
      }
    });
    _findAndRecenter();
  }

  Future<void> _loadSystemLocations() async {
    try {
      final snapshot = await _firestore.collection('systemLocations').get();
      final locations = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // 提取所有類別
      final categories = locations
          .map((loc) => loc['category']?.toString() ?? '')
          .where((cat) => cat.isNotEmpty)
          .toSet();

      setState(() {
        _systemLocations = locations;
        _availableCategories = categories;
        _selectedCategories = Set.from(categories); // 預設全選
      });

      print('載入了 ${locations.length} 個系統地點，${categories.length} 個類別');
    } catch (e) {
      print('載入系統地點失敗: $e');
    }
  }

  Future<void> _loadProfile(String uid) async {
    final doc = await _firestore.doc('players/$uid').get();
    if (doc.exists) setState(() => _profile = doc.data()!);
  }

  /// 檢查歷史通知（登入時檢查登入前的新貼文）
  Future<void> _checkHistoricalNotifications() async {
    if (_lastCheckTime == null) return;

    try {
      print('檢查歷史通知，從 $_lastCheckTime 開始');

      final snapshot = await _firestore
          .collection('posts')
          .where(
            'createdAt',
            isGreaterThan: Timestamp.fromDate(_lastCheckTime!),
          )
          .orderBy('createdAt', descending: true)
          .get();

      print('找到 ${snapshot.docs.length} 個歷史新貼文');

      if (snapshot.docs.isNotEmpty) {
        final historicalPosts = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).toList();

        setState(() {
          _newPosts.addAll(historicalPosts);
          _unreadCount = _newPosts.length;
        });

        print('已添加 ${historicalPosts.length} 個歷史通知');
      }
    } catch (e) {
      print('檢查歷史通知失敗: $e');
    }
  }

  void _attachPostsListener() {
    // 先檢查歷史通知
    _checkHistoricalNotifications();

    // 設定監聽器附加時間（用於後續新貼文檢測）
    _listenerAttachedTs = Timestamp.now();

    _postsSub = _firestore.collection('posts').snapshots().listen((snap) {
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data() as Map);
        m['id'] = d.id;
        return m;
      }).toList();

      list.sort((a, b) {
        final ta = a['createdAt'] as Timestamp?;
        final tb = b['createdAt'] as Timestamp?;
        return (tb?.seconds ?? 0).compareTo(ta?.seconds ?? 0);
      });

      setState(() => _allPosts = list);

      // 處理即時新增的貼文（登入後新發布的）
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.added &&
            _listenerAttachedTs != null &&
            (change.doc['createdAt'] as Timestamp).compareTo(
                  _listenerAttachedTs!,
                ) >
                0) {
          final newPost = {
            'id': change.doc.id,
            ...Map<String, dynamic>.from(change.doc.data() as Map),
          };

          // 添加到通知列表
          setState(() {
            _newPosts.insert(0, newPost);
            _unreadCount = _newPosts.length;
          });

          // 如果當前沒有彈窗，顯示即時通知
          if (_currentBottomSheet == BottomSheetType.none &&
              _selectedLocation == null) {
            setState(() {
              _newPostToShow = newPost;
              _currentBottomSheet = BottomSheetType.newPostNotification;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  /// 初始化通知系统
  void _initializeNotificationSystem() {
    // 只需要初始化時間記錄
    _lastCheckTime = DateTime.now().subtract(const Duration(hours: 24));
    print('初始化通知系統，最後檢查時間: $_lastCheckTime');
  }

  /// 获取并更新当前位置
  Future<void> _findAndRecenter() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請在系統設定允許定位權限')));
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      final coord = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = coord);
      _mapCtrl.animateCamera(CameraUpdate.newLatLngZoom(coord, 16));
    } catch (_) {}
  }

  /// 点击任意 Marker（静态或动态）都会调用它
  void _selectLocationMarker(
    Map<String, dynamic> loc, {
    bool isStatic = false,
  }) {
    // 新增 isStatic 參數
    // 調試信息：檢查傳遞給 LocationDetailBottomSheet 的數據
    print('選中的位置數據: $loc');
    print('地址字段: ${loc['address']}');
    print('地址字段類型: ${loc['address'].runtimeType}');

    setState(() {
      _selectedLocation = {...loc, 'isStatic': isStatic}; // 添加 isStatic 標記
      _travelInfo = null;
      _currentBottomSheet = BottomSheetType.locationDetail;
    });
    _calculateTravelInfo(LatLng(loc['lat'], loc['lng']));
  }

  void _closePopup() {
    setState(() {
      _selectedLocation = null;
      _travelInfo = null;
      _currentBottomSheet = BottomSheetType.none;
    });
  }

  /// 计算路程信息
  Future<void> _calculateTravelInfo(LatLng dest) async {
    if (_myLocation == null) return;
    setState(() => _isLoadingTravel = true);
    final o = '${_myLocation!.latitude},${_myLocation!.longitude}';
    final d = '${dest.latitude},${dest.longitude}';
    final modes = ['driving', 'walking', 'transit'];
    final info = <String, String>{};
    for (var m in modes) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$o&destinations=$d&mode=$m&key=$_apiKey',
        );
        final resp = await http.get(url);
        final row = jsonDecode(resp.body)['rows'][0]['elements'][0];
        info[m] = '${row['duration']['text']} (${row['distance']['text']})';
      } catch (_) {
        info[m] = '無法計算';
      }
    }
    setState(() {
      _travelInfo = info;
      _isLoadingTravel = false;
    });
  }

  Future<void> _applyToPost(String postId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || _isApplying) return;
    setState(() => _isApplying = true);
    await _firestore.doc('posts/$postId').update({
      'applicants': FieldValue.arrayUnion([u.uid]),
    });
    setState(() {
      _isApplying = false;
      _closePopup();
    });
  }

  Future<void> _cancelApplication(String postId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    await _firestore.doc('posts/$postId').update({
      'applicants': FieldValue.arrayRemove([u.uid]),
    });
    _closePopup();
  }

  void _openProfileEditor() {
    _profileForm = Map<String, dynamic>.from(_profile);
    _profileStatusType = null;
    _profileStatusMessage = null;
    setState(() {
      _currentBottomSheet = BottomSheetType.profileEditor;
    });
  }

  void _closeProfileEditor() =>
      setState(() => _currentBottomSheet = BottomSheetType.none);

  Future<void> _saveProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ref = _firestore.doc('players/${u.uid}');
    try {
      await ref.set(_profileForm, SetOptions(merge: true));
      setState(() {
        _profile = Map.from(_profileForm);
        _profileStatusType = 'success';
        _profileStatusMessage = '履歷更新成功';
      });
      Future.delayed(const Duration(seconds: 1), _closeProfileEditor);
    } catch (_) {
      setState(() {
        _profileStatusType = 'error';
        _profileStatusMessage = '儲存失敗';
      });
    }
  }

  void _acceptNewPost() {
    if (_newPostToShow != null) {
      _selectLocationMarker(_newPostToShow!, isStatic: false); // 新增參數
      setState(() {
        _currentBottomSheet = BottomSheetType.none;
        _newPostToShow = null;
      });
    }
  }

  void _closeNewPostNotification() {
    setState(() {
      _currentBottomSheet = BottomSheetType.none;
      _newPostToShow = null;
    });
  }

  void _openMyApplications() =>
      setState(() => _currentBottomSheet = BottomSheetType.myApplications);
  void _closeMyApplications() =>
      setState(() => _currentBottomSheet = BottomSheetType.none);

  bool get _hasApplied {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || _selectedLocation == null) return false;
    final apps = List<String>.from(_selectedLocation!['applicants'] ?? []);
    return apps.contains(u.uid);
  }

  Set<Marker> _buildStaticParkMarkers() {
    return {
      for (var location in _systemLocations)
        if (_selectedCategories.contains(location['category']))
          Marker(
            markerId: MarkerId('system_${location['id']}'),
            position: LatLng(location['lat'], location['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            onTap: () => _selectLocationMarker({
              'name': location['name'],
              'lat': location['lat'],
              'lng': location['lng'],
              'address': location['address'],
              'category': location['category'],
              'content': null,
              'applicants': <String>[],
              'userId': null,
              'id': null,
            }, isStatic: true), // 移除重複的註解，保持這個參數
          ),
    };
  }

  Set<Marker> _buildPostMarkers() {
    return {
      for (var post in _allPosts)
        Marker(
          markerId: MarkerId(post['id']),
          position: LatLng(post['lat'], post['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          onTap: () => _selectLocationMarker(post, isStatic: false), // 明確指定為非靜態
        ),
    };
  }

  // 新增方法：
  Widget _buildCategoryFilter() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showCategoryFilter ? null : 0,
      child: _showCategoryFilter
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一個按鈕：全選/取消按鈕（加陰影）

                  // 類別按鈕區域 - 每個按鈕都加陰影
                  ..._availableCategories.map((category) {
                    final isSelected = _selectedCategories.contains(category);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        // 新增 Container 包裝
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(60),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: FilterChip(
                          label: Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey[800],
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategories.add(category);
                              } else {
                                _selectedCategories.remove(category);
                              }
                            });
                          },
                          selectedColor: Colors.orange[600],
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: isSelected
                                ? Colors.orange[600]!
                                : Colors.grey[300]!,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(60),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: FilterChip(
                      label: Text(
                        _selectedCategories.length ==
                                _availableCategories.length
                            ? '全部取消'
                            : '全部選取',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      selected: false,
                      onSelected: (_) {
                        setState(() {
                          if (_selectedCategories.length ==
                              _availableCategories.length) {
                            _selectedCategories.clear();
                          } else {
                            _selectedCategories = Set.from(
                              _availableCategories,
                            );
                          }
                        });
                      },
                      backgroundColor: Colors.blue[50],
                      side: BorderSide(color: Colors.blue[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(60),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// 构建通知按钮（带红点）
  Widget _buildNotificationButton() {
    return Stack(
      children: [
        FloatingActionButton(
          backgroundColor: _unreadCount > 0 ? Colors.orange[600] : Colors.white,
          foregroundColor: _unreadCount > 0 ? Colors.white : Colors.blueGrey,
          heroTag: 'notifications',
          mini: false,
          child: Icon(Icons.notifications),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(56),
          ),
          onPressed: _openNotificationPanel,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  /// 构建通知面板
  Widget _buildNotificationPanel() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeNotificationPanel,
        child: Container(
          color: Colors.black38,
          child: Center(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: Colors.orange[600],
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '最新案件通知',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_newPosts.isNotEmpty)
                          TextButton(
                            onPressed: _clearAllNotifications,
                            child: Text(
                              '清除全部',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(),

                    // 案件列表
                    Expanded(
                      child: _newPosts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '目前沒有新案件',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '我們會即時通知您最新的工作機會',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _newPosts.length,
                              itemBuilder: (context, index) {
                                final post = _newPosts[index];
                                final createdAt =
                                    (post['createdAt'] as Timestamp?)?.toDate();
                                final timeAgo = createdAt != null
                                    ? _getTimeAgo(createdAt)
                                    : '剛剛';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 2,
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.orange[300]!,
                                            Colors.orange[500]!,
                                          ],
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (post['content']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true)
                                          Text(
                                            post['content'],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                        const SizedBox(height: 4),
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
                                    onTap: () => _viewPostDetails(post),
                                  ),
                                );
                              },
                            ),
                    ),

                    const SizedBox(height: 16),

                    // 底部按钮
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _closeNotificationPanel,
                            icon: const Icon(Icons.close),
                            label: const Text('關閉'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _closeNotificationPanel();
                              // 可以跳转到所有案件列表页面
                            },
                            icon: const Icon(Icons.list),
                            label: const Text('查看全部'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
        ),
      ),
    );
  }

  /// 计算时间差
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

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      if (_myLocation != null)
        Marker(
          markerId: const MarkerId('me'),
          position: _myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      ..._buildStaticParkMarkers(),
      ..._buildPostMarkers(),
    };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            onMapCreated: (c) => _mapCtrl = c..setMapStyle(mapStyleJson),
            markers: markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            zoomGesturesEnabled: true,
          ),

          Positioned(
            bottom: 100,
            left: 0, // 從左邊 20px 開始
            width: 320, // 固定寬度 300px
            child: _buildCategoryFilter(),
          ),

          // 篩選選單按鈕
          Positioned(
            bottom: 40, // 動態調整位置
            left: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 新增：篩選切換按鈕
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'filter',
                  mini: false,
                  child: Icon(
                    _showCategoryFilter
                        ? Icons
                              .close // 選單打開時顯示 X
                        : Icons.filter_list,
                  ), // 選單關閉時顯示篩選圖標
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56),
                  ),
                  onPressed: () {
                    setState(() {
                      _showCategoryFilter = !_showCategoryFilter;
                    });
                  },
                ),
              ],
            ),
          ),

          // 右下角工具栏（添加通知按钮）
          Positioned(
            bottom: 40, // 動態調整位置
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.white, // 背景色
                  foregroundColor: Colors.blueGrey, // icon 顏色
                  heroTag: 'loc',
                  mini: false,
                  child: const Icon(Icons.my_location),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: _findAndRecenter,
                ),
                const SizedBox(height: 16),

                // 新增通知按钮
                _buildNotificationButton(),
                const SizedBox(height: 16),

                FloatingActionButton(
                  backgroundColor: Colors.white, // 背景色
                  foregroundColor: Colors.blueGrey, // icon 顏色
                  heroTag: 'profile',
                  mini: false,
                  child: const Icon(Icons.person),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: _openProfileEditor,
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'apps',
                  mini: false,
                  child: const Icon(Icons.note),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: _openMyApplications,
                ),
                const SizedBox(height: 16),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey,
                  heroTag: 'logout',
                  mini: false,
                  child: const Icon(Icons.logout),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(56), // 半徑 12
                  ),
                  onPressed: () async {
                    await _authService.signOut();
                    Navigator.pushReplacementNamed(context, '/');
                  },
                ),
              ],
            ),
          ),

          // 通用弹窗：静态公园 or 动态任务
          if (_selectedLocation != null)
            Positioned.fill(
              child: FullScreenPopup(
                title: _selectedLocation!['name'] ?? '地點',
                onClose: _closePopup,
                child: LocationDetailBottomSheet(
                  location: _selectedLocation!,
                  travelInfo: _travelInfo,
                  isLoadingTravel: _isLoadingTravel,
                  hasApplied: _hasApplied,
                  isApplying: _isApplying,
                  onApply:
                      _selectedLocation!['userId'] != null &&
                          FirebaseAuth.instance.currentUser!.uid !=
                              _selectedLocation!['userId']
                      ? () => _applyToPost(_selectedLocation!['id'])
                      : null,
                  onCancelApplication: _hasApplied
                      ? () => _cancelApplication(_selectedLocation!['id'])
                      : null,
                  publisherInfo: _selectedLocation!['userId'] != null
                      ? FutureBuilder<DocumentSnapshot>(
                          future: _firestore
                              .doc('parents/${_selectedLocation!['userId']}')
                              .get(),
                          builder: (ctx, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snap.hasData || !snap.data!.exists) {
                              return const Text('無法取得發佈者資料');
                            }
                            final data =
                                snap.data!.data() as Map<String, dynamic>;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('👤 名稱：${data['displayName'] ?? '—'}'),
                                if (data['contact'] != null)
                                  Text('📞 聯絡：${data['contact']}'),
                                if (data['bio'] != null)
                                  Text('📝 關於他：${data['bio']}'),
                              ],
                            );
                          },
                        )
                      : null,
                ),
              ),
            ),

          // 新貼文通知彈窗
          if (_currentBottomSheet == BottomSheetType.newPostNotification &&
              _newPostToShow != null)
            Positioned.fill(
              child: FullScreenPopup(
                title: '✨ 有新的案件！',
                onClose: _closeNewPostNotification,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '標題：${_newPostToShow!['name'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            if (_newPostToShow!['content'] != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '內容：${_newPostToShow!['content']}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _closeNewPostNotification,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey[300]!),
                                ),
                              ),
                              child: const Text('稍後再說'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _acceptNewPost,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('立即接洽'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 我的應徵清單底部彈窗
          if (_currentBottomSheet == BottomSheetType.myApplications)
            Positioned.fill(
              child: FullScreenPopup(
                title: '我的應徵清單',
                onClose: _closeMyApplications,
                child: MyApplicationsBottomSheet(
                  applications: _myApplications,
                  onCancelApplication: _cancelApplication,
                  onViewDetails: (application) {
                    // 新增这个回调函数
                    // 关闭当前弹窗
                    _closeMyApplications();
                    // 显示应用详情
                    _selectLocationMarker(application, isStatic: false); // 新增參數
                  },
                ),
              ),
            ),

          // 通知面板
          if (_currentBottomSheet == BottomSheetType.notificationPanel)
            Positioned.fill(
              child: FullScreenPopup(
                title: '最新案件通知',
                onClose: _closeNotificationPanel,
                child: NotificationPanelBottomSheet(
                  newPosts: _newPosts,
                  onViewPost: _viewPostDetails,
                  onClearAll: _clearAllNotifications,
                ),
              ),
            ),

          // 編輯個人資料底部彈窗
          if (_currentBottomSheet == BottomSheetType.profileEditor)
            Positioned.fill(
              child: FullScreenPopup(
                title: '編輯個人資料',
                onClose: _closeProfileEditor,
                child: EditProfileBottomSheet(
                  profileForm: _profileForm,
                  onSave: _saveProfile,
                  onCancel: _closeProfileEditor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 打开通知面板
  void _openNotificationPanel() {
    setState(() {
      _currentBottomSheet = BottomSheetType.notificationPanel;
      _unreadCount = 0; // 清除红点
    });
  }

  /// 关闭通知面板
  void _closeNotificationPanel() {
    setState(() {
      _currentBottomSheet = BottomSheetType.none;
    });
  }

  /// 查看案件详情
  void _viewPostDetails(Map<String, dynamic> post) {
    setState(() {
      _currentBottomSheet = BottomSheetType.none;
    });
    _selectLocationMarker(post, isStatic: false); // 新增參數

    // 从新案件列表中移除已查看的案件
    _newPosts.removeWhere((p) => p['id'] == post['id']);
  }

  /// 清除所有通知
  void _clearAllNotifications() {
    setState(() {
      _newPosts.clear();
      _unreadCount = 0;
    });
  }
}
