# CreateEditTaskBottomSheet 使用說明

## 組件概述

`CreateEditTaskBottomSheet` 是一個功能完整的多步驟任務創建/編輯底部彈窗組件，提供以下特性：

### 核心功能

- 🎯 **5 步驟流程**：基礎資訊 → 任務內容 → 圖片上傳 → 報價選項 → 預覽送出
- 📊 **進度條顯示**：清晰顯示當前步驟進度
- 🔄 **雙模式支援**：新增和編輯任務
- 📱 **響應式設計**：適配不同螢幕尺寸
- ✅ **表單驗證**：確保數據完整性

### 步驟詳情

#### 步驟 1：基礎資訊

- 任務標題輸入
- 日期選擇（限今天或明天）
- 時間選擇（原生時間選擇器）

#### 步驟 2：任務內容

- 多行文字描述輸入

#### 步驟 3：圖片上傳

- 最多 3 張圖片上傳
- 2MB 大小限制
- 自動正方形裁切

#### 步驟 4：報價選項

- 0-1000 元價格範圍
- 100 元遞增單位
- 滑桿和快速選擇

#### 步驟 5：預覽送出

- 完整資訊預覽
- 最終確認送出

## 使用方式

### 1. 新增任務

```dart
// 顯示新增任務彈窗
CreateEditTaskBottomSheet.show(
  context,
  onSubmit: (TaskData taskData) {
    // 處理任務數據
    print('新任務：${taskData.title}');

    // 您可以在這裡：
    // - 保存到資料庫
    // - 更新UI狀態
    // - 顯示成功訊息
  },
);
```

### 2. 編輯任務

```dart
// 顯示編輯任務彈窗
CreateEditTaskBottomSheet.show(
  context,
  existingTask: existingTaskMap, // 現有任務數據
  onSubmit: (TaskData taskData) {
    // 處理更新的任務數據
    print('更新任務：${taskData.title}');
  },
);
```

### 3. 任務數據格式

```dart
// TaskData 類別包含以下屬性：
class TaskData {
  String title;           // 任務標題
  DateTime? date;         // 日期
  TimeOfDay? time;        // 時間
  String content;         // 任務內容
  List<Uint8List> images; // 圖片數據
  int price;              // 報價金額
}

// 轉換為 JSON 格式
Map<String, dynamic> taskJson = taskData.toJson();
```

## 完整範例

```dart
import 'package:flutter/material.dart';
import 'components/create_edit_task_bottom_sheet.dart';

class TaskManagementPage extends StatefulWidget {
  @override
  _TaskManagementPageState createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage> {
  List<TaskData> tasks = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('任務管理'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showCreateTask,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return ListTile(
            title: Text(task.title),
            subtitle: Text(task.content),
            trailing: Text('NT\$ ${task.price}'),
            onTap: () => _showEditTask(task, index),
          );
        },
      ),
    );
  }

  void _showCreateTask() {
    CreateEditTaskBottomSheet.show(
      context,
      onSubmit: (taskData) {
        setState(() {
          tasks.add(taskData);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('任務創建成功！')),
        );
      },
    );
  }

  void _showEditTask(TaskData task, int index) {
    CreateEditTaskBottomSheet.show(
      context,
      existingTask: task.toJson(),
      onSubmit: (taskData) {
        setState(() {
          tasks[index] = taskData;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('任務更新成功！')),
        );
      },
    );
  }
}
```

## 依賴需求

確保您的 `pubspec.yaml` 包含以下依賴：

```yaml
dependencies:
  flutter:
    sdk: flutter
  image_picker: ^0.8.7+4
  crop_your_image: ^2.0.0
```

## 注意事項

1. **圖片處理**：圖片會自動裁切為正方形格式
2. **日期限制**：只能選擇今天或明天的日期
3. **檔案大小**：每張圖片限制 2MB
4. **表單驗證**：必填欄位未完成時無法進入下一步
5. **狀態管理**：組件內部管理所有表單狀態

## 自訂配置

您可以根據需求修改以下設定：

- 圖片上傳數量限制
- 檔案大小限制
- 價格範圍設定
- 日期選擇限制
- UI 主題色彩

## 效能最佳化建議

1. 圖片上傳後建議壓縮處理
2. 大量任務時可考慮分頁載入
3. 異步操作時適當顯示載入狀態
4. 合理使用 setState 避免不必要的重建

---

這個組件提供了完整的任務創建和編輯功能，適合各種任務管理應用場景。

## 新版本資料結構

新版本支援以下完整的資料結構：

```dart
final TaskData taskData = TaskData(
  title: '幫忙搬家具',           // 任務標題
  date: '2024-01-15T09:00:00Z', // ISO 8601 格式日期
  time: {'hour': 14, 'minute': 30}, // 時間對象
  content: '需要幫忙搬運沙發和桌子到新家', // 詳細內容
  images: [                     // 圖片 URL 列表
    'https://example.com/image1.jpg',
    'https://example.com/image2.jpg',
  ],
  price: 500,                   // 報酬金額 0-1000
  address: '台北市信義區...',    // 地址
  lat: 25.047924,              // 緯度
  lng: 121.517081,             // 經度
);
```

## 任務詳情顯示更新

### 新增的顯示元素

1. **任務標題區域**: 顯示 `title` 或 `name` 欄位
2. **執行時間區域**: 格式化顯示日期和時間
3. **任務報酬區域**: 顯示價格資訊
4. **任務圖片區域**: 水平滾動顯示多張圖片
5. **改進的內容顯示**: 增加背景色和邊框

### 支援的組件

- `TaskDetailBottomSheet` (用於 parent_view)
- `LocationDetailBottomSheet` (用於 player_view)

### 兼容性

- ✅ 完全向下兼容舊資料格式
- ✅ 自動檢測資料類型並適配顯示
- ✅ 優雅降級，缺少的欄位不會顯示錯誤

### 資料庫儲存格式

```dart
// Firestore 文檔結構
{
  'title': '任務標題',           // String (新)
  'name': '任務名稱',            // String (舊，向下兼容)
  'date': '2024-01-15T09:00:00Z', // String ISO 8601 (新)
  'time': {                     // Map (新)
    'hour': 14,
    'minute': 30
  },
  'price': 500,                 // int 0-1000 (新)
  'images': [                   // List<String> (新)
    'url1', 'url2', 'url3'
  ],
  'content': '任務內容',         // String
  'address': '地址',            // String
  'lat': 25.047924,            // double
  'lng': 121.517081,           // double
  'userId': 'user123',         // String
  'applicants': [],            // List<String>
  'createdAt': Timestamp,      // Timestamp
  'status': 'open',            // String
}
```

## 基本使用

### 新建任務（新 API）

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => DraggableScrollableSheet(
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    builder: (context, scrollController) =>
      CreateEditTaskBottomSheet.create(
        onSubmit: (taskData) async {
          // 處理新任務資料
          await saveTaskToFirestore(taskData);
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
        scrollController: scrollController,
      ),
  ),
);
```

### 編輯任務（新 API）

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => DraggableScrollableSheet(
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    builder: (context, scrollController) =>
      CreateEditTaskBottomSheet.edit(
        taskData: existingTaskData,
        onSubmit: (updatedTaskData) async {
          // 處理更新的任務資料
          await updateTaskInFirestore(taskId, updatedTaskData);
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
        scrollController: scrollController,
      ),
  ),
);
```

### 舊版兼容使用（向下兼容）

```dart
// 舊的 API 仍然可以使用
showCreateEditTaskBottomSheet(
  context: context,
  task: existingTask, // 可選，編輯模式
  onSubmit: (taskData) {
    // 處理任務資料
  },
);
```

## 5 步驟流程

### Step 1: 基礎資訊

- 任務標題輸入
- 日期選擇（今天/明天）
- 時間選擇（小時:分鐘）

### Step 2: 任務內容

- 多行文字輸入框
- 最多 500 字描述

### Step 3: 圖片上傳

- 最多上傳 3 張圖片
- 每張圖片限制 2MB
- 自動正方形裁切
- 支援刪除已上傳圖片

### Step 4: 報價選項

- 滑桿選擇 0-1000 元
- 100 元為一個單位
- 即時顯示選擇金額

### Step 5: 預覽送出

- 完整資訊預覽
- 確認送出或返回修改

## 進度顯示

- 5 等分線性進度條
- 步驟圓點指示器
- 目前步驟高亮顯示

## 控制按鈕

- **上一步**: 返回前一步驟
- **下一步**: 進入下一步驟
- **送出**: 完成任務創建/編輯
- **取消**: 關閉彈窗

## 表單驗證

- Step 1: 必須輸入標題
- Step 2: 內容可選
- Step 3: 圖片可選
- Step 4: 價格預設為 0
- Step 5: 最終驗證

## 錯誤處理

- 網路錯誤重試機制
- 圖片上傳失敗提示
- 表單驗證錯誤提示
- 用戶友好的錯誤訊息

## 響應式設計

- 適配不同螢幕尺寸
- 鍵盤彈出時自動調整
- 橫豎屏切換支援
- 安全區域適配

## 注意事項

1. 使用前確保已配置 Firebase Storage
2. 圖片上傳需要網路連接
3. 建議在正式環境中加入更多錯誤處理
4. 可根據需求自定義樣式主題
