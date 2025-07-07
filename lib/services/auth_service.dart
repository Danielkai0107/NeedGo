// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get userChanges => _auth.authStateChanges();

  // 手機號碼驗證
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential) verificationCompleted,
    required void Function(FirebaseAuthException) verificationFailed,
    required void Function(String, int?) codeSent,
    required void Function(String) codeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      timeout: const Duration(seconds: 60),
    );
  }

  // 使用認證憑證登入
  Future<User?> signInWithCredential(PhoneAuthCredential credential) async {
    final userCred = await _auth.signInWithCredential(credential);
    return userCred.user;
  }

  // 登出
  Future<void> signOut() async {
    try {
      print('🚀 開始登出流程...');
      
      // 1. 清理所有監聽器
      await ChatService.cancelAllListeners();
      
      // 2. 登出前設置為離線狀態
      await ChatService.updateOnlineStatus(false);
      
      // 3. 執行Firebase登出
      await _auth.signOut();
      
      print('✅ 登出成功');
    } catch (e) {
      print('❌ 登出失敗: $e');
      // 即使更新在線狀態失敗，也要嘗試登出
      try {
        // 確保監聽器被清理
        await ChatService.cancelAllListeners();
        await _auth.signOut();
        print('✅ Firebase 登出成功');
      } catch (authError) {
        print('❌ Firebase 登出失敗: $authError');
        throw authError;
      }
    }
  }

  // 取得當前用戶
  User? get currentUser => _auth.currentUser;
}
