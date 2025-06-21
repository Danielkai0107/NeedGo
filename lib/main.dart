// lib/main.dart

import 'package:flutter/material.dart';
import 'services/firebase_config.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先移除 dotenv 相關，或用 try/catch 包起來
  // await dotenv.load(fileName: '.env');

  await FirebaseConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVP App',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      onGenerateRoute: Routes.generate,
    );
  }
}
