// lib/services/firebase_config.dart
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';  // CLI 產生的檔案

class FirebaseConfig {
  static Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
