// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_config.dart';
import 'services/chat_service.dart';
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 監聽用戶登入狀態變化
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // 用戶登入時設置為在線狀態
        ChatService.updateOnlineStatus(true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // 應用程式重新進入前台，設置為在線狀態
        ChatService.updateOnlineStatus(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 應用程式進入後台或被關閉，設置為離線狀態
        ChatService.updateOnlineStatus(false);
        break;
      default:
        break;
    }
  }

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
