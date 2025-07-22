import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 人臉比較結果類
class FaceComparisonResult {
  final bool isSuccess;
  final double? similarity;
  final String? errorMessage;
  final String? errorCode;
  final FaceMatchQuality? quality;

  FaceComparisonResult({
    required this.isSuccess,
    this.similarity,
    this.errorMessage,
    this.errorCode,
    this.quality,
  });

  bool get isVerified => isSuccess && similarity != null && similarity! >= 80.0;
}

/// 人臉匹配品質信息
class FaceMatchQuality {
  final double confidence;
  final Map<String, dynamic> sourceImageQuality;
  final Map<String, dynamic> targetImageQuality;

  FaceMatchQuality({
    required this.confidence,
    required this.sourceImageQuality,
    required this.targetImageQuality,
  });
}

class RekognitionService {
  static String get _accessKey => dotenv.env['AWS_ACCESS_KEY_ID'] ?? '';
  static String get _secretKey => dotenv.env['AWS_SECRET_ACCESS_KEY'] ?? '';
  static String get _region => dotenv.env['AWS_REGION'] ?? 'us-east-1';
  static const String _service = 'rekognition';

  /// 測試憑證是否正確加載（僅用於調試）
  static void testCredentials() {
    print('🔍 測試 AWS 憑證加載:');
    print(
      '   Access Key: ${_accessKey.isEmpty ? " 未設定" : "已設定 (${_accessKey.substring(0, 8)}...)"}',
    );
    print(
      '   Secret Key: ${_secretKey.isEmpty ? " 未設定" : "已設定 (${_secretKey.length} 字符)"}',
    );
    print('   Region: $_region');
    print('   所有環境變數: ${dotenv.env.keys.toList()}');
  }

  /// 比較兩張照片的相似度
  /// 返回 FaceComparisonResult 對象，包含相似度和錯誤信息
  static Future<FaceComparisonResult> compareFaces(
    Uint8List sourceImage,
    Uint8List targetImage,
  ) async {
    try {
      // 檢查憑證是否存在
      if (_accessKey.isEmpty || _secretKey.isEmpty) {
        print(
          ' AWS 憑證檢查失敗: AccessKey=${_accessKey.isEmpty ? "空" : "已設定"}, SecretKey=${_secretKey.isEmpty ? "空" : "已設定"}',
        );
        return FaceComparisonResult(
          isSuccess: false,
          errorMessage: 'AWS 憑證未設定',
          errorCode: 'MISSING_CREDENTIALS',
        );
      }

      print('AWS 憑證檢查通過');
      print('🌍 使用 AWS 區域: $_region');

      // 檢查圖片文件大小（AWS Rekognition 限制 5MB）
      const maxSize = 5 * 1024 * 1024; // 5MB

      if (sourceImage.length > maxSize) {
        return FaceComparisonResult(
          isSuccess: false,
          errorMessage:
              '源圖片過大：${(sourceImage.length / 1024 / 1024).toStringAsFixed(1)}MB，最大支持 5MB',
          errorCode: 'IMAGE_TOO_LARGE',
        );
      }

      if (targetImage.length > maxSize) {
        return FaceComparisonResult(
          isSuccess: false,
          errorMessage:
              '目標圖片過大：${(targetImage.length / 1024 / 1024).toStringAsFixed(1)}MB，最大支持 5MB',
          errorCode: 'IMAGE_TOO_LARGE',
        );
      }

      print(
        '📏 圖片大小檢查通過 - 源圖片: ${(sourceImage.length / 1024).toStringAsFixed(1)}KB, 目標圖片: ${(targetImage.length / 1024).toStringAsFixed(1)}KB',
      );

      final endpoint = 'https://rekognition.$_region.amazonaws.com/';

      // 構建請求體
      final body = json.encode({
        'SourceImage': {'Bytes': base64Encode(sourceImage)},
        'TargetImage': {'Bytes': base64Encode(targetImage)},
        'SimilarityThreshold': 70, // 設定相似度閾值
      });

      print('📦 請求體大小: ${body.length} bytes');

      // 構建 AWS 簽名
      final headers = await _buildHeaders(body);

      print('🔑 請求標頭已生成');
      print('📡 發送請求到: $endpoint');

      // 發送請求
      final response = await http.post(
        Uri.parse(endpoint),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // 檢查是否有匹配的人臉
        if (responseData['FaceMatches'] != null &&
            responseData['FaceMatches'].isNotEmpty) {
          final faceMatch = responseData['FaceMatches'][0];
          final similarity = faceMatch['Similarity'].toDouble();
          final face = faceMatch['Face'];

          // 提取品質信息
          FaceMatchQuality? quality;
          if (face['Quality'] != null) {
            quality = FaceMatchQuality(
              confidence: face['Confidence'].toDouble(),
              sourceImageQuality:
                  responseData['SourceImageFace']?['Quality'] ?? {},
              targetImageQuality: face['Quality'] ?? {},
            );
          }

          return FaceComparisonResult(
            isSuccess: true,
            similarity: similarity,
            quality: quality,
          );
        } else {
          // 沒有匹配的人臉
          return FaceComparisonResult(
            isSuccess: true,
            similarity: 0.0,
            errorMessage: _getNoMatchReason(responseData),
            errorCode: 'NO_FACE_MATCH',
          );
        }
      } else {
        print(' Rekognition API 錯誤: ${response.statusCode}');
        print('錯誤內容: ${response.body}');

        final errorData = json.decode(response.body);
        final errorType = errorData['__type'] ?? 'Unknown';
        final errorMessage = errorData['message'] ?? '未知錯誤';

        return FaceComparisonResult(
          isSuccess: false,
          errorMessage: _getErrorMessage(
            response.statusCode,
            errorType,
            errorMessage,
          ),
          errorCode: errorType,
        );
      }
    } catch (e) {
      return FaceComparisonResult(
        isSuccess: false,
        errorMessage: '網絡連接失敗或服務暫時不可用',
        errorCode: 'NETWORK_ERROR',
      );
    }
  }

  /// 構建 AWS 簽名頭部
  static Future<Map<String, String>> _buildHeaders(String body) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDate(now);
    final timeStamp = _formatDateTime(now);

    print('⏰ 時間戳: $timeStamp, 日期戳: $dateStamp');

    final host = 'rekognition.$_region.amazonaws.com';
    final target = 'RekognitionService.CompareFaces';

    print('🎯 目標服務: $target');
    print('🏠 主機地址: $host');

    // 構建 canonical request
    final canonicalHeaders =
        'host:$host\n'
        'x-amz-date:$timeStamp\n'
        'x-amz-target:$target\n';

    final signedHeaders = 'host;x-amz-date;x-amz-target';

    final payloadHash = sha256.convert(utf8.encode(body)).toString();

    final canonicalRequest =
        'POST\n'
        '/\n'
        '\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';

    // 構建 string to sign
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$_region/$_service/aws4_request';
    final stringToSign =
        '$algorithm\n'
        '$timeStamp\n'
        '$credentialScope\n'
        '${sha256.convert(utf8.encode(canonicalRequest))}';

    // 計算簽名
    final signature = _calculateSignature(stringToSign, dateStamp);

    // 構建 Authorization header
    final authorization =
        '$algorithm '
        'Credential=$_accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    return {
      'Host': host,
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Date': timeStamp,
      'X-Amz-Target': target,
      'Authorization': authorization,
    };
  }

  /// 計算 AWS 簽名
  static String _calculateSignature(String stringToSign, String dateStamp) {
    print('🔐 開始計算簽名');
    print('   String to sign: $stringToSign');
    print('   Date stamp: $dateStamp');
    print('   Secret key 長度: ${_secretKey.length}');

    final kDate = _hmacSha256(utf8.encode('AWS4' + _secretKey), dateStamp);
    final kRegion = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, _service);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = _hmacSha256(kSigning, stringToSign);

    final signatureHex = signature
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    print('🔑 計算得到的簽名: $signatureHex');
    return signatureHex;
  }

  /// HMAC-SHA256 加密
  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  /// 格式化日期 (YYYYMMDD)
  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// 格式化日期時間 (YYYYMMDDTHHMMSSZ)
  static String _formatDateTime(DateTime date) {
    return '${_formatDate(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  /// 獲取無匹配原因的詳細說明
  static String _getNoMatchReason(Map<String, dynamic> responseData) {
    // 檢查是否檢測到人臉
    final sourceImageFace = responseData['SourceImageFace'];
    final unMatchedFaces = responseData['UnmatchedFaces'] ?? [];

    if (sourceImageFace == null) {
      return '原始照片中未檢測到人臉，請確保照片清晰且包含完整人臉';
    }

    if (unMatchedFaces.isEmpty) {
      return '當前照片中未檢測到人臉，請確保照片清晰且包含完整人臉';
    }

    // 如果有檢測到人臉但不匹配
    final sourceQuality = sourceImageFace['Quality'];
    if (sourceQuality != null) {
      final brightness = sourceQuality['Brightness'] ?? 0.0;
      final sharpness = sourceQuality['Sharpness'] ?? 0.0;

      if (brightness < 30) {
        return '照片過暗，請在光線充足的環境下拍攝';
      } else if (brightness > 90) {
        return '照片過亮，請避免強光直射';
      } else if (sharpness < 50) {
        return '照片模糊，請保持手機穩定重新拍攝';
      }
    }

    return '人臉相似度不足，請確保為本人拍攝且表情自然';
  }

  /// 獲取錯誤訊息的詳細說明
  static String _getErrorMessage(
    int statusCode,
    String errorType,
    String errorMessage,
  ) {
    // 首先檢查特定的錯誤類型（不管狀態碼）
    if (errorType.contains('AccessDeniedException')) {
      return 'AWS 權限不足：該用戶沒有使用 Amazon Rekognition 的權限\n'
          '請在 AWS IAM 中為用戶添加 "AmazonRekognitionReadOnlyAccess" 權限';
    }

    if (errorType.contains('UnrecognizedClientException')) {
      return 'AWS 憑證無效：Access Key 或 Secret Key 錯誤\n'
          '請檢查 .env 文件中的 AWS 憑證是否正確';
    }

    // 然後按狀態碼分類
    switch (statusCode) {
      case 400:
        if (errorType.contains('InvalidImageFormatException')) {
          return '照片格式不支持，請選擇 JPEG 或 PNG 格式的照片';
        } else if (errorType.contains('ImageTooLargeException')) {
          return '照片文件過大，請選擇小於 5MB 的照片';
        } else if (errorType.contains('InvalidParameterException')) {
          return '請求參數錯誤，請重新拍攝照片';
        } else if (errorType.contains('InvalidS3ObjectException')) {
          return '照片數據錯誤，請重新拍攝';
        }
        return '照片格式或內容有問題，請重新拍攝';
      case 403:
        return 'AWS 訪問被拒絕，請檢查權限設置';
      case 429:
        return '請求過於頻繁，請稍後再試';
      case 500:
        return 'AWS 服務器內部錯誤，請稍後再試';
      case 503:
        return 'AWS 服務暫時不可用，請稍後再試';
      default:
        return '驗證失敗：$errorMessage';
    }
  }
}
