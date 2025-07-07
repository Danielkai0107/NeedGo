# 地圖標記與彈窗交互系統使用指南

## 系統概述

本系統實現了完整的地圖標記與彈窗交互功能，支援 ParentView（發布者）與 PlayerView（陪伴者）兩種視角，使用 Google Maps Flutter 插件，提供統一的 Material 設計風格。

## 核心組件

### 1. MapMarkerManager（地圖標記管理器）

- 統一管理三種不同類型的地圖標記
- 提供標記顏色和圖標的規範化管理
- 支援動態標記生成和更新

### 2. TaskDetailSheet（任務詳情彈窗）

- 顯示完整的任務資訊
- 支援 Parent/Player 雙視角
- 提供編輯、刪除、申請等操作

### 3. LocationInfoSheet（地點資訊彈窗）

- 顯示系統預設地點的詳細資訊
- 計算交通資訊和距離
- 支援任務列表顯示和快速操作

## Marker 類型與顏色規範

| 類型               | 顏色    | 說明                 |
| ------------------ | ------- | -------------------- |
| PresetMarker       | 🔵 藍色 | 系統預設地點         |
| CustomMarker       | 🟢 綠色 | 使用者發布的任務     |
| ActivePresetMarker | 🟠 橙色 | 有任務的系統預設地點 |

## 雙視角行為差異

### ParentView（發布者視角）

- 顯示：自己的任務（綠色）+ 系統地點（藍色）
- 功能：編輯/刪除自己的任務，在系統地點新增任務

### PlayerView（陪伴者視角）

- 顯示：他人任務（綠色）+ 系統地點（藍色/橙色）
- 功能：申請任務，查看地點資訊和任務列表

## 使用方法

### 1. 基本設置

```dart
// 在 ParentView 或 PlayerView 中
Set<Marker> _markers = {};
MarkerData? _selectedMarker;

void _updateMarkers() {
  MapMarkerManager.generateMarkers(
    systemLocations: _systemLocations,
    userTasks: _allPosts,
    isParentView: false, // true for ParentView
    onMarkerTap: _handleMarkerTap,
    currentLocation: _myLocation,
  ).then((markers) {
    if (mounted) {
      setState(() {
        _markers = markers;
      });
    }
  });
}
```

### 2. 標記點擊處理

```dart
void _handleMarkerTap(MarkerData markerData) {
  if (markerData.type == MarkerType.custom) {
    _showTaskDetailSheet(markerData);
  } else {
    _showLocationInfoSheet(markerData);
  }
}
```

### 3. 彈窗顯示

```dart
void _showTaskDetailSheet(MarkerData markerData) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) => TaskDetailSheet(
      taskData: markerData.data,
      isParentView: widget.isParentView,
      currentLocation: _myLocation,
      onTaskUpdated: _updateMarkers,
    ),
  );
}
```

## 特色功能

1. **智能標記管理**：自動根據地點和任務關係切換標記顏色
2. **響應式彈窗**：可拖拽調整高度的底部彈窗
3. **交通資訊計算**：自動計算多種交通方式的時間和距離
4. **任務聚合顯示**：同一地點的多個任務統一管理
5. **完整向下兼容**：支援現有資料格式

## 最佳實踐

1. **效能最佳化**：使用 `mounted` 檢查，避免記憶體洩漏
2. **錯誤處理**：完整的異常處理和使用者提示
3. **使用者體驗**：統一的動畫效果和交互模式
4. **代碼維護**：模組化設計，清晰的介面定義

這個系統提供了完整的地圖交互解決方案，易於集成和擴展。
