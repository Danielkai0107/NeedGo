// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_config.dart';
import 'services/chat_service.dart';
import 'routes.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'styles/app_colors.dart';
// 移除 AuthGate import，現在通過路由系統使用

/// 應用程式主入口
/// AuthGate 會自動處理登入狀態判斷：
/// - 未登入：顯示 AuthView (手機驗證登入)
/// - 已登入且已註冊：顯示 ParentView (主畫面)
/// - 已登入但未註冊：重新導向到註冊流程
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 載入環境變數
  await dotenv.load(fileName: ".env");

  // 調試：檢查環境變數是否加載成功
  print('🔧 Environment variables loaded:');
  print('   All keys: ${dotenv.env.keys.toList()}');
  print(
    '   AWS_ACCESS_KEY_ID: ${dotenv.env['AWS_ACCESS_KEY_ID'] != null ? "已設定" : "未設定"}',
  );
  print(
    '   AWS_SECRET_ACCESS_KEY: ${dotenv.env['AWS_SECRET_ACCESS_KEY'] != null ? "已設定" : "未設定"}',
  );

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
  StreamSubscription<User?>? _authStateSubscription;
  User? _currentUser; // 添加當前用戶狀態追蹤

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 監聽用戶登入狀態變化
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      print('🔄 main.dart: Firebase Auth 狀態變化');
      print('🔍 main.dart: 用戶狀態: ${user != null ? "已登入" : "未登入"}');
      if (user != null) {
        print('🔍 main.dart: 用戶資料: uid=${user.uid}, email=${user.email}');

        // 用戶登入時設置為在線狀態
        print('📲 main.dart: 調用 ChatService.updateOnlineStatus(true)');
        ChatService.updateOnlineStatus(true);

        // 啟動聊天室清理定時器
        print('🧹 main.dart: 啟動聊天室清理定時器');
        ChatService.startChatRoomCleanupTimer();
      } else {
        print('📴 main.dart: 用戶登出，停止聊天室清理定時器');
        // 用戶登出時停止聊天室清理定時器
        ChatService.stopChatRoomCleanupTimer();
      }

      // 更新當前用戶狀態，觸發 UI 重建
      if (mounted && _currentUser?.uid != user?.uid) {
        print('🔄 main.dart: 用戶狀態改變，觸發 UI 重建');
        setState(() {
          _currentUser = user;
        });
      }
    });

    // 將監聽器添加到ChatService管理器
    if (_authStateSubscription != null) {
      ChatService.addListener('main_auth_state', _authStateSubscription!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 清理監聽器
    ChatService.removeListener('main_auth_state');
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
        // 優化主題配色 - 使用品牌色
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // 自定義按鈕主題
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: AppButtonStyles.primaryButton(),
        ),
      ),
      // 使用路由系統，支援註冊完成後的導航
      initialRoute: '/',
      onGenerateRoute: Routes.generate,
      // 關閉 debug 模式下的橫幅
      debugShowCheckedModeBanner: false,
    );
  }
}
