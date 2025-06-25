# AuthGate 登入狀態判斷機制使用說明

## 概述

AuthGate 是一個 Flutter 元件，專門用於處理 Firebase Authentication 的登入狀態判斷。它會自動偵測使用者的登入狀態，並根據狀態決定顯示相應的頁面。

## 功能特點

✅ **自動登入狀態偵測**：使用 `FirebaseAuth.instance.authStateChanges()` 即時監聽登入狀態變化  
✅ **StatelessWidget 設計**：符合現代 Flutter 開發最佳實務  
✅ **載入狀態顯示**：使用 `CircularProgressIndicator` 避免閃屏問題  
✅ **錯誤處理**：完整的錯誤處理機制和用戶友好的錯誤畫面  
✅ **註冊狀態檢查**：自動檢查用戶是否已完成註冊流程  
✅ **無縫用戶體驗**：平滑的頁面切換，無需手動判斷 `currentUser`

## 實作原理

### 1. 登入狀態監聽

```dart
StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(),
  builder: (context, snapshot) {
    // 處理各種狀態
  },
)
```

### 2. 三種主要狀態

- **載入中**：`ConnectionState.waiting` - 顯示載入畫面
- **未登入**：`user == null` - 顯示登入頁面 (AuthView)
- **已登入**：`user != null` - 檢查註冊狀態後決定頁面

### 3. 註冊狀態檢查

```dart
Future<bool> _checkIfUserRegistered(String uid) async {
  final userDoc = await FirebaseFirestore.instance
      .collection('user')
      .doc(uid)
      .get();
  return userDoc.exists;
}
```

## 使用方式

### 1. 在 main.dart 中設定入口

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'services/firebase_config.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Your App',
      initialRoute: '/',  // AuthGate 會在 '/' 路由自動載入
      onGenerateRoute: Routes.generate,
    );
  }
}
```

### 2. 路由配置

```dart
// lib/routes.dart
import 'screens/auth_gate.dart';

class Routes {
  static Route<dynamic> generate(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const AuthGate());
      // 其他路由...
    }
  }
}
```

### 3. 直接使用 AuthGate

```dart
// 如果不使用路由系統，也可以直接在 MaterialApp 中使用
MaterialApp(
  home: const AuthGate(),
  // 其他配置...
)
```

## 頁面流程圖

```
App 啟動
    ↓
AuthGate 載入
    ↓
檢查 Firebase Auth 狀態
    ↓
┌─────────────────┬─────────────────┐
│   未登入       │     已登入      │
│      ↓         │       ↓         │
│  AuthView      │  檢查註冊狀態   │
│  (登入頁面)    │       ↓         │
│               │ ┌─────────────┐  │
│               │ │   已註冊    │  │
│               │ │      ↓      │  │
│               │ │ ParentView  │  │
│               │ │  (主畫面)   │  │
│               │ └─────────────┘  │
│               │ ┌─────────────┐  │
│               │ │   未註冊    │  │
│               │ │      ↓      │  │
│               │ │   登出並    │  │
│               │ │ 返回登入頁   │ │
│               │ └─────────────┘  │
└─────────────────┴─────────────────┘
```

## 載入狀態設計

AuthGate 提供了優雅的載入畫面，包含：

- **應用程式 Logo**：自動載入 `assets/logo.png`，載入失敗時顯示預設圖標
- **載入指示器**：藍色的 `CircularProgressIndicator`
- **狀態文字**：「正在檢查登入狀態...」
- **錯誤處理**：網路錯誤時顯示友好的錯誤畫面

## 自訂配置

### 1. 修改載入畫面樣式

```dart
// 在 AuthGate 中的 _buildLoadingScreen() 方法
Widget _buildLoadingScreen() {
  return Scaffold(
    backgroundColor: Colors.white, // 可自訂背景顏色
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 自訂 Logo 大小和樣式
          SizedBox(
            width: 120,  // 可調整大小
            height: 120,
            child: Image.asset('assets/your_logo.png'), // 使用您的 Logo
          ),
          // 自訂載入指示器顏色
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
          // 自訂文字內容和樣式
          Text('Loading...'), // 可改為英文或其他語言
        ],
      ),
    ),
  );
}
```

### 2. 修改用戶集合名稱

如果您的 Firestore 用戶集合不是 `user`，請修改：

```dart
// 在 _checkIfUserRegistered 方法中
final userDoc = await FirebaseFirestore.instance
    .collection('users') // 改為您的集合名稱
    .doc(uid)
    .get();
```

### 3. 添加額外的註冊檢查條件

```dart
Future<bool> _checkIfUserRegistered(String uid) async {
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('user')
        .doc(uid)
        .get();

    if (!userDoc.exists) return false;

    // 添加額外檢查條件
    final userData = userDoc.data()!;
    return userData['isProfileComplete'] == true; // 例如檢查資料完整性
  } catch (e) {
    return false;
  }
}
```

## 注意事項

1. **Firebase 初始化**：確保在使用 AuthGate 前已正確初始化 Firebase
2. **網路連接**：AuthGate 需要網路連接來檢查 Firestore 中的用戶資料
3. **錯誤處理**：建議根據您的應用需求自訂錯誤處理邏輯
4. **性能考量**：AuthGate 會在每次 Auth 狀態變化時檢查註冊狀態，對於大量用戶的應用建議添加快取機制

## 疑難排解

### 問題：一直顯示載入畫面

**解決方案**：

1. 檢查 Firebase 配置是否正確
2. 確認網路連接正常
3. 查看控制台錯誤訊息

### 問題：登入後還是顯示登入頁面

**解決方案**：

1. 檢查 Firestore 中是否存在用戶文件
2. 確認集合名稱是否為 `user`
3. 檢查用戶文件的 UID 是否正確

### 問題：頁面切換不流暢

**解決方案**：

1. 確保所有頁面都正確實作了 `build` 方法
2. 檢查是否有循環依賴的導入

## 版本兼容性

- Flutter SDK: 3.x
- firebase_auth: ^5.6.0
- cloud_firestore: ^5.6.9

## 結語

AuthGate 提供了一個完整、可靠的登入狀態管理解決方案。它遵循 Flutter 最佳實務，提供良好的用戶體驗，並且易於自訂和擴展。
