// lib/main.dart

import 'package:flutter/material.dart';
import 'services/firebase_config.dart';
import 'routes.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 應用程式主入口
/// AuthGate 會自動處理登入狀態判斷：
/// - 未登入：顯示 AuthView (手機驗證登入)
/// - 已登入且已註冊：顯示 ParentView (主畫面)
/// - 已登入但未註冊：重新導向到註冊流程
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 載入環境變數
  await dotenv.load(fileName: ".env");

  // 初始化 Firebase
  await FirebaseConfig.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVP App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // 優化主題配色
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      // 初始路由設定為 '/', 會自動載入 AuthGate
      initialRoute: '/',
      onGenerateRoute: Routes.generate,
      // 關閉 debug 模式下的橫幅
      debugShowCheckedModeBanner: false,
    );
  }
}
