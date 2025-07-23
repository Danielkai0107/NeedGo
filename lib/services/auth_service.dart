// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 用戶狀態流
  Stream<User?> get userChanges => _auth.authStateChanges();

  // 獲取當前用戶
  User? get currentUser => _auth.currentUser;

  // Google 登入
  Future<User?> signInWithGoogle() async {
    try {
      // 觸發 Google 登入流程
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // 用戶取消登入
        return null;
      }

      // 獲取認證憑證
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 創建 Firebase 認證憑證
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 使用憑證登入 Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      return userCredential.user;
    } catch (e) {
      throw Exception('Google 登入失敗: ${e.toString()}');
    }
  }

  // 登出
  Future<void> signOut() async {
    try {
      print('🚀 開始登出流程...');

      // 1. 檢查並執行 Google 登出
      bool googleSignedIn = false;
      try {
        googleSignedIn = await _googleSignIn.isSignedIn();
        if (googleSignedIn) {
          await _googleSignIn.signOut();
          print('Google 登出成功');
        } else {
          print('ℹ️ Google 未登入狀態，跳過登出');
        }
      } catch (e) {
        print('⚠️ Google 登出警告: $e');
        // Google 登出失敗不應該阻止 Firebase 登出
      }

      // 2. 謹慎處理 Google 連接斷開
      // 只有在確實登入的情況下才嘗試斷開連接
      if (googleSignedIn) {
        try {
          // 檢查是否還有其他Google服務正在使用
          final currentAccount = _googleSignIn.currentUser;
          if (currentAccount != null) {
            await _googleSignIn.disconnect();
            print('Google 連接已斷開');
          } else {
            print('ℹ️ Google 連接已經斷開，無需重複操作');
          }
        } catch (e) {
          // 特定錯誤處理 - 某些情況下斷開連接失敗是正常的
          final errorMessage = e.toString();
          if (errorMessage.contains('Failed to disconnect') ||
              errorMessage.contains('status')) {
            print('ℹ️ Google 連接斷開完成（系統已自動處理）');
          } else {
            print('⚠️ Google 斷開連接警告: $e');
          }
        }
      }

      // 3. Firebase 登出
      await _auth.signOut();
      print('Firebase 登出成功');

      print('✅ 完整登出流程完成');
    } catch (e) {
      print('❌ 登出過程中發生錯誤: $e');

      // 即使發生錯誤，也要嘗試 Firebase 登出
      try {
        await _auth.signOut();
        print('Firebase 強制登出成功');
      } catch (authError) {
        print('❌ Firebase 登出也失敗: $authError');
        throw Exception('登出失敗: ${authError.toString()}');
      }
    }
  }

  /// 記錄用戶同意聲明
  Future<void> recordUserConsent() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('用戶未登入');
    }

    try {
      final now = DateTime.now();
      final consentData = {
        'consentTimestamp': Timestamp.fromDate(now),
        'consentVersion': '1.0', // 可以根據版本管理
        'updatedAt': Timestamp.fromDate(now),
      };

      // 檢查用戶文檔是否存在
      final userDoc = await _firestore.collection('user').doc(user.uid).get();
      
      if (userDoc.exists) {
        // 用戶已存在，更新同意聲明記錄
        await _firestore.collection('user').doc(user.uid).update(consentData);
        print('✅ 已更新現有用戶的同意聲明記錄');
      } else {
        // 新用戶，創建基本資料並記錄同意聲明
        final basicUserData = {
          'userId': user.uid,
          'email': user.email ?? '',
          'name': user.displayName ?? '',
          'avatarUrl': user.photoURL ?? '',
          'phoneNumber': user.phoneNumber ?? '',
          'createdAt': Timestamp.fromDate(now),
          ...consentData,
          // 其他預設值
          'isVerified': false,
          'subscriptionStatus': 'free',
        };
        
        await _firestore.collection('user').doc(user.uid).set(basicUserData);
        print('✅ 已為新用戶創建資料並記錄同意聲明');
      }
    } catch (e) {
      print('❌ 記錄同意聲明失敗: $e');
      throw Exception('記錄同意聲明失敗: $e');
    }
  }

  /// 檢查用戶是否已同意聲明
  Future<bool> hasUserConsented() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final userDoc = await _firestore.collection('user').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        return data['consentTimestamp'] != null;
      }
      return false;
    } catch (e) {
      print('❌ 檢查同意聲明狀態失敗: $e');
      return false;
    }
  }
}
