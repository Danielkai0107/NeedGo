import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'avatar_map_marker.dart';
import 'location_marker.dart';
import 'dart:ui' as ui;

/// Marker 類型枚舉
enum MarkerType {
  preset, // 系統預設地點（藍色）
  custom, // 使用者自訂發佈地點（綠色）
  activePreset, // 系統預設地點 + 已有任務（橙色）
}

/// Marker 資料類
class MarkerData {
  final String id;
  final String name;
  final LatLng position;
  final MarkerType type;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>>?
  tasksAtLocation; // 該地點的任務列表（用於 activePreset）

  const MarkerData({
    required this.id,
    required this.name,
    required this.position,
    required this.type,
    required this.data,
    this.tasksAtLocation,
  });

  /// 從系統地點資料創建 MarkerData
  factory MarkerData.fromSystemLocation(Map<String, dynamic> locationData) {
    return MarkerData(
      id: 'system_${locationData['id']}',
      name: locationData['name'] ?? '未命名地點',
      position: LatLng(locationData['lat'], locationData['lng']),
      type: MarkerType.preset,
      data: locationData,
    );
  }

  /// 從任務資料創建 MarkerData
  factory MarkerData.fromTask(Map<String, dynamic> taskData) {
    return MarkerData(
      id: 'task_${taskData['id']}',
      name: taskData['title'] ?? taskData['name'] ?? '未命名任務',
      position: LatLng(taskData['lat'], taskData['lng']),
      type: MarkerType.custom,
      data: taskData,
    );
  }

  /// 從任務聚合創建 MarkerData
  factory MarkerData.fromTaskCluster(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      throw ArgumentError('任務聚合不能為空');
    }

    final firstTask = tasks.first;
    final taskCount = tasks.length;

    return MarkerData(
      id: 'task_cluster_${tasks.hashCode}',
      name: taskCount > 1
          ? '$taskCount 個任務'
          : (firstTask['title'] ?? firstTask['name'] ?? '未命名任務'),
      position: LatLng(firstTask['lat'], firstTask['lng']),
      type: MarkerType.custom,
      data: firstTask,
      tasksAtLocation: tasks,
    );
  }

  /// 創建有任務的系統地點 MarkerData
  MarkerData copyWithActiveTasks(List<Map<String, dynamic>> tasks) {
    return MarkerData(
      id: id,
      name: name,
      position: position,
      type: MarkerType.activePreset,
      data: data,
      tasksAtLocation: tasks,
    );
  }
}

/// 地圖標記管理器
class MapMarkerManager {
  /// 根據 MarkerType 獲取對應顏色
  static BitmapDescriptor getMarkerIcon(MarkerType type) {
    switch (type) {
      case MarkerType.preset:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      case MarkerType.custom:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case MarkerType.activePreset:
        return BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange,
        );
    }
  }

  /// 獲取 Marker 顏色
  static Color getMarkerColor(MarkerType type) {
    switch (type) {
      case MarkerType.preset:
        return Colors.blue;
      case MarkerType.custom:
        return Colors.green;
      case MarkerType.activePreset:
        return Colors.orange;
    }
  }

  /// 從 MarkerData 創建 Marker
  static Marker createMarker(
    MarkerData markerData, {
    required VoidCallback onTap,
  }) {
    return Marker(
      markerId: MarkerId(markerData.id),
      position: markerData.position,
      icon: getMarkerIcon(markerData.type),
      onTap: onTap,
    );
  }

  /// 獲取 Marker 的描述文字
  static String _getMarkerSnippet(MarkerData markerData) {
    switch (markerData.type) {
      case MarkerType.preset:
        final category = markerData.data['category']?.toString();
        return category != null ? '類別: $category' : '系統預設地點';
      case MarkerType.custom:
        final price = markerData.data['price'];
        if (price != null && price > 0) {
          return 'NT\$ $price';
        }
        return '用戶任務';
      case MarkerType.activePreset:
        final taskCount = markerData.tasksAtLocation?.length ?? 0;
        return '$taskCount 個可用任務';
    }
  }

  /// 生成完整的 Marker 集合
  static Future<Set<Marker>> generateMarkers({
    required List<Map<String, dynamic>> systemLocations,
    required List<Map<String, dynamic>> userTasks,
    required bool isParentView,
    required Function(MarkerData) onMarkerTap,
    LatLng? currentLocation,
  }) async {
    final markers = <Marker>{};
    final currentUser = FirebaseAuth.instance.currentUser;

    // 加入用戶當前位置標記（Google Maps風格）
    if (currentLocation != null) {
      final locationIcon = await LocationMarker.generateCurrentLocationMarker(
        size: 20.0,
        bearing: 0.0, // 如果需要方向指示，可以從GPS獲取
      );

      markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: currentLocation,
          icon: locationIcon,
          zIndex: 1000, // 設置高zIndex確保在所有標記之上
        ),
      );
    }

    // 處理用戶任務 markers - 使用頭像標記
    final taskMarkers = await _generateTaskMarkers(
      userTasks: userTasks,
      isParentView: isParentView,
      onMarkerTap: onMarkerTap,
      currentUser: currentUser,
    );
    markers.addAll(taskMarkers);

    // 處理系統地點 markers
    final systemMarkers = await _processSystemLocations(
      systemLocations: systemLocations,
      userTasks: userTasks,
      isParentView: isParentView,
      onMarkerTap: onMarkerTap,
      currentUser: currentUser,
    );

    markers.addAll(systemMarkers);
    return markers;
  }

  /// 生成任務標記 - 使用頭像標記
  static Future<Set<Marker>> _generateTaskMarkers({
    required List<Map<String, dynamic>> userTasks,
    required bool isParentView,
    required Function(MarkerData) onMarkerTap,
    User? currentUser,
  }) async {
    final markers = <Marker>{};

    // 過濾任務
    final filteredTasks = userTasks.where((task) {
      if (task['lat'] == null || task['lng'] == null) return false;

      // 在 Parent 視角只顯示自己的任務，在 Player 視角排除自己的任務
      if (isParentView) {
        return task['userId'] == currentUser?.uid;
      } else {
        return task['userId'] != currentUser?.uid;
      }
    }).toList();

    // 按位置聚合任務
    final clusteredTasks = _clusterTasksByProximity(filteredTasks);

    // 為每個聚合生成標記
    for (final cluster in clusteredTasks) {
      try {
        final icon = await AvatarMapMarker.generateTasksMarker(
          tasks: cluster,
          size: 40.0, // 更合理的地圖標記大小
        );

        // 使用第一個任務的位置作為標記位置
        final markerData = MarkerData.fromTaskCluster(cluster);

        markers.add(
          Marker(
            markerId: MarkerId('task_cluster_${cluster.hashCode}'),
            position: LatLng(cluster.first['lat'], cluster.first['lng']),
            icon: icon,
            onTap: () => onMarkerTap(markerData),
          ),
        );
      } catch (e) {
        print('生成任務標記失敗: $e');
        // 回退到傳統標記
        for (final task in cluster) {
          final markerData = MarkerData.fromTask(task);
          markers.add(
            createMarker(markerData, onTap: () => onMarkerTap(markerData)),
          );
        }
      }
    }

    return markers;
  }

  /// 按距離聚合任務
  static List<List<Map<String, dynamic>>> _clusterTasksByProximity(
    List<Map<String, dynamic>> tasks, {
    double clusterRadius = 100.0, // 聚合半徑（米）
  }) {
    final clusters = <List<Map<String, dynamic>>>[];
    final processedTasks = <Map<String, dynamic>>{};

    for (final task in tasks) {
      if (processedTasks.contains(task)) continue;

      final cluster = <Map<String, dynamic>>[task];
      processedTasks.add(task);

      // 尋找附近的其他任務
      for (final otherTask in tasks) {
        if (processedTasks.contains(otherTask)) continue;

        final distance = Geolocator.distanceBetween(
          task['lat'],
          task['lng'],
          otherTask['lat'],
          otherTask['lng'],
        );

        if (distance <= clusterRadius) {
          cluster.add(otherTask);
          processedTasks.add(otherTask);
        }
      }

      clusters.add(cluster);
    }

    return clusters;
  }

  /// 處理系統地點標記
  static Future<Set<Marker>> _processSystemLocations({
    required List<Map<String, dynamic>> systemLocations,
    required List<Map<String, dynamic>> userTasks,
    required bool isParentView,
    required Function(MarkerData) onMarkerTap,
    User? currentUser,
  }) async {
    final markers = <Marker>{};

    // 如果是 Player 視角，不顯示系統地點標記
    if (!isParentView) {
      return markers;
    }

    for (var location in systemLocations) {
      final locationCoord = LatLng(location['lat'], location['lng']);

      // 找出該地點附近的任務（100米內）
      final nearbyTasks = <Map<String, dynamic>>[];
      bool hasOwnTaskNearby = false;

      for (var task in userTasks) {
        final taskCoord = LatLng(task['lat'], task['lng']);
        final distance = Geolocator.distanceBetween(
          locationCoord.latitude,
          locationCoord.longitude,
          taskCoord.latitude,
          taskCoord.longitude,
        );

        if (distance <= 100) {
          if (task['userId'] == currentUser?.uid) {
            hasOwnTaskNearby = true;
          } else {
            nearbyTasks.add(task);
          }
        }
      }

      // Parent 視角：如果該地點附近有自己的任務，隱藏系統地點標記
      if (hasOwnTaskNearby) {
        continue; // 跳過這個系統地點標記
      }

      // 使用新的白色圓圈+加號標記
      final systemLocationIcon = await generateSystemLocationMarker();
      final markerData = MarkerData.fromSystemLocation(location);

      markers.add(
        Marker(
          markerId: MarkerId('system_${location['id']}'),
          position: locationCoord,
          icon: systemLocationIcon,
          onTap: () => onMarkerTap(markerData),
        ),
      );
    }

    return markers;
  }

  /// 生成系統地點標記（白色圓圈+加號）
  static Future<BitmapDescriptor> generateSystemLocationMarker({
    double size = 20.0,
    double iconSize = 8.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 提高解析度
    final scaleFactor = 2.0;
    final shadowOffset = 2.0 * scaleFactor;
    final circleRadius = (size / 2) * scaleFactor;

    // 計算畫布大小，需要容納陰影
    final canvasSize = (size + shadowOffset) * scaleFactor;
    final circleCenter = Offset(
      canvasSize / 2 - shadowOffset / 2,
      canvasSize / 2 - shadowOffset / 2,
    );

    final paint = Paint()..isAntiAlias = true;

    // 繪製陰影
    paint.color = Colors.black.withOpacity(0.2);
    canvas.drawCircle(
      circleCenter + Offset(shadowOffset, shadowOffset),
      circleRadius,
      paint,
    );

    // 繪製白色圓圈
    paint.color = Colors.white;
    canvas.drawCircle(circleCenter, circleRadius, paint);

    // 繪製灰色邊框
    paint.color = Colors.grey[300]!;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.0 * scaleFactor;
    canvas.drawCircle(
      circleCenter,
      circleRadius - paint.strokeWidth / 2,
      paint,
    );

    // 繪製加號
    paint.color = Colors.grey[600]!;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.0 * scaleFactor;
    paint.strokeCap = StrokeCap.round;

    final scaledIconSize = iconSize * scaleFactor;
    final halfIcon = scaledIconSize / 2;

    // 水平線
    canvas.drawLine(
      Offset(circleCenter.dx - halfIcon, circleCenter.dy),
      Offset(circleCenter.dx + halfIcon, circleCenter.dy),
      paint,
    );

    // 垂直線
    canvas.drawLine(
      Offset(circleCenter.dx, circleCenter.dy - halfIcon),
      Offset(circleCenter.dx, circleCenter.dy + halfIcon),
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// 更新指定地點的標記類型（當新增任務後調用）
  static Future<Set<Marker>> updateMarkersAfterTaskCreation({
    required Set<Marker> currentMarkers,
    required LatLng newTaskLocation,
    required List<Map<String, dynamic>> systemLocations,
    required List<Map<String, dynamic>> allTasks,
    required bool isParentView,
    required Function(MarkerData) onMarkerTap,
  }) async {
    return generateMarkers(
      systemLocations: systemLocations,
      userTasks: allTasks,
      isParentView: isParentView,
      onMarkerTap: onMarkerTap,
    );
  }

  /// 根據距離聚合任務標記（用於 Player 視角的任務聚合）
  static Map<String, List<Map<String, dynamic>>> clusterTasksByLocation(
    List<Map<String, dynamic>> tasks, {
    double clusterRadius = 50.0, // 聚合半徑（米）
  }) {
    final clusters = <String, List<Map<String, dynamic>>>{};
    final processedTasks = <String>{};
    final currentUser = FirebaseAuth.instance.currentUser;

    for (var task in tasks) {
      // 排除自己的任務
      if (task['userId'] == currentUser?.uid) continue;
      if (processedTasks.contains(task['id'])) continue;

      final taskLat = task['lat'] as double;
      final taskLng = task['lng'] as double;
      final cluster = <Map<String, dynamic>>[task];
      processedTasks.add(task['id']);

      // 尋找附近的其他任務
      for (var otherTask in tasks) {
        if (otherTask['userId'] == currentUser?.uid) continue;
        if (processedTasks.contains(otherTask['id'])) continue;

        final otherLat = otherTask['lat'] as double;
        final otherLng = otherTask['lng'] as double;

        final distance = Geolocator.distanceBetween(
          taskLat,
          taskLng,
          otherLat,
          otherLng,
        );

        if (distance <= clusterRadius) {
          cluster.add(otherTask);
          processedTasks.add(otherTask['id']);
        }
      }

      final clusterId = 'cluster_${task['id']}';
      clusters[clusterId] = cluster;
    }

    return clusters;
  }

  /// 檢查地點是否有任務
  static bool hasTasksAtLocation(
    LatLng location,
    List<Map<String, dynamic>> tasks, {
    double searchRadius = 100.0,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;

    for (var task in tasks) {
      if (task['userId'] == currentUser?.uid) continue;

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        task['lat'],
        task['lng'],
      );

      if (distance <= searchRadius) {
        return true;
      }
    }

    return false;
  }

  /// 獲取地點附近的任務列表
  static List<Map<String, dynamic>> getTasksAtLocation(
    LatLng location,
    List<Map<String, dynamic>> tasks, {
    double searchRadius = 100.0,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final nearbyTasks = <Map<String, dynamic>>[];

    for (var task in tasks) {
      if (task['userId'] == currentUser?.uid) continue;

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        task['lat'],
        task['lng'],
      );

      if (distance <= searchRadius) {
        nearbyTasks.add(task);
      }
    }

    return nearbyTasks;
  }
}
