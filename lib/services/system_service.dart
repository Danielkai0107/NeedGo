// lib/services/system_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SystemService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 緩存系統配置
  static Map<String, String>? _cachedSystemConfig;
  static DateTime? _configCacheExpiry;

  /// 獲取服務條款
  static Future<String> getTermsOfService() async {
    final config = await _getSystemConfig();
    return config['terms_of_service'] ?? '服務條款內容載入中...';
  }

  /// 獲取隱私政策
  static Future<String> getPrivacyPolicy() async {
    final config = await _getSystemConfig();
    return config['privacy_policy'] ?? '隱私政策內容載入中...';
  }

  /// 從系統集合中獲取配置（帶緩存）
  static Future<Map<String, String>> _getSystemConfig() async {
    try {
      // 檢查緩存是否有效（緩存30分鐘）
      final now = DateTime.now();
      if (_cachedSystemConfig != null &&
          _configCacheExpiry != null &&
          now.isBefore(_configCacheExpiry!)) {
        return _cachedSystemConfig!;
      }

      // 從 Firestore 讀取系統配置
      final querySnapshot = await _firestore
          .collection('system')
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final systemData = querySnapshot.docs.first.data();

        final config = {
          'terms_of_service': systemData['terms_of_service']?.toString() ?? '',
          'privacy_policy': systemData['privacy_policy']?.toString() ?? '',
        };

        // 更新緩存
        _cachedSystemConfig = config;
        _configCacheExpiry = now.add(const Duration(minutes: 30));

        return config;
      } else {
        return {
          'terms_of_service': '服務條款內容暫時無法載入',
          'privacy_policy': '隱私政策內容暫時無法載入',
        };
      }
    } catch (e) {
      print('❌ 獲取系統配置失敗: $e');
      return {'terms_of_service': '服務條款內容載入失敗', 'privacy_policy': '隱私政策內容載入失敗'};
    }
  }

  /// 清除系統配置緩存
  static void clearConfigCache() {
    _cachedSystemConfig = null;
    _configCacheExpiry = null;
  }
}
