import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import '../styles/app_colors.dart';

/// 頭像地圖標記生成器
class AvatarMapMarker {
  /// 生成單一頭像標記
  static Future<BitmapDescriptor> generateSingleAvatarMarker({
    required String? avatarUrl,
    required double size,
    double borderWidth = 2, // 固定1px邊框 (2 * 2.0 scaleFactor = 1.6px)
    Color borderColor = Colors.white,
    Color backgroundColor = Colors.white,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 提高解析度：使用2倍大小繪製，最後縮放
    final scaleFactor = 1.45;
    final totalSize = (size + borderWidth * 2) * scaleFactor;
    final paint = Paint()..isAntiAlias = true;

    // 繪製白色外框
    paint.color = borderColor;
    canvas.drawCircle(
      Offset(totalSize / 2, totalSize / 2),
      totalSize / 2,
      paint,
    );

    // 繪製頭像背景
    paint.color = backgroundColor;
    canvas.drawCircle(
      Offset(totalSize / 2, totalSize / 2),
      (totalSize - borderWidth * 2 * scaleFactor) / 2,
      paint,
    );

    // 載入並繪製頭像
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        final image = await _loadNetworkImage(avatarUrl);
        final avatarSize = (size - borderWidth * 2) * scaleFactor;
        final avatarRect = Rect.fromCenter(
          center: Offset(totalSize / 2, totalSize / 2),
          width: avatarSize,
          height: avatarSize,
        );

        // 裁切圓形
        canvas.clipRRect(
          RRect.fromRectAndRadius(avatarRect, Radius.circular(avatarSize / 2)),
        );

        // 繪製頭像 - 保持原比例，使用 cover 效果
        _drawImageWithAspectRatio(canvas, image, avatarRect);
      } catch (e) {
        print('載入頭像失敗: $e');
        // 繪製預設圖標
        _drawDefaultIcon(
          canvas,
          totalSize / 2,
          totalSize / 2,
          size * 0.4 * scaleFactor,
        );
      }
    } else {
      // 繪製預設圖標
      _drawDefaultIcon(
        canvas,
        totalSize / 2,
        totalSize / 2,
        size * 0.4 * scaleFactor,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(totalSize.toInt(), totalSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// 生成重疊頭像標記（2個頭像）
  static Future<BitmapDescriptor> generateOverlappingAvatarsMarker({
    required List<Map<String, dynamic>> tasks,
    required double size,
    double borderWidth = 2, // 固定1px邊框 (2 * 2.0 scaleFactor = 1.6px)
    Color borderColor = Colors.white,
    Color backgroundColor = Colors.white,
    double overlapPercentage = 0.65,
  }) async {
    if (tasks.isEmpty) {
      throw ArgumentError('至少需要一個任務');
    }

    if (tasks.length == 1) {
      return generateSingleAvatarMarker(
        avatarUrl: await _getAvatarUrl(tasks[0]['userId']),
        size: size,
        borderWidth: borderWidth,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
      );
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 提高解析度
    final scaleFactor = 1.45;
    final avatarSize = size * scaleFactor; // 保持和單一頭像相同大小
    final offset = avatarSize * (1 - overlapPercentage);
    final totalWidth =
        (size + offset / scaleFactor + borderWidth * 2) * scaleFactor;
    final totalHeight = (size + borderWidth * 2) * scaleFactor;

    final paint = Paint()..isAntiAlias = true;

    // 繪製第一個頭像（在後面）
    await _drawSingleAvatar(
      canvas,
      await _getAvatarUrl(tasks[0]['userId']),
      Offset(borderWidth * scaleFactor, borderWidth * scaleFactor),
      avatarSize,
      borderWidth * scaleFactor,
      borderColor,
      backgroundColor,
    );

    // 繪製第二個頭像（在前面，重疊）
    await _drawSingleAvatar(
      canvas,
      await _getAvatarUrl(tasks[1]['userId']),
      Offset(borderWidth * scaleFactor + offset, borderWidth * scaleFactor),
      avatarSize,
      borderWidth * scaleFactor,
      borderColor,
      backgroundColor,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      totalWidth.toInt(),
      totalHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// 生成多任務標記（2個頭像 + 數字提示）
  static Future<BitmapDescriptor> generateMultipleTasksMarker({
    required List<Map<String, dynamic>> tasks,
    required double size,
    double borderWidth = 2, // 固定1px邊框 (2 * 2.0 scaleFactor = 1.6px)
    Color borderColor = Colors.white,
    Color backgroundColor = Colors.white,
    Color badgeColor = Colors.red,
    Color textColor = Colors.white,
    double overlapPercentage = 0.65,
  }) async {
    if (tasks.length < 3) {
      return generateOverlappingAvatarsMarker(
        tasks: tasks,
        size: size,
        borderWidth: borderWidth,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
        overlapPercentage: overlapPercentage,
      );
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 提高解析度
    final scaleFactor = 1.45;
    final avatarSize = size * scaleFactor; // 保持和單一頭像相同大小
    final offset = avatarSize * (1 - overlapPercentage);
    final badgeSize = avatarSize * 0.3; // 稍微縮小徽章以適應
    final totalWidth =
        borderWidth * scaleFactor + offset + avatarSize + badgeSize / 4;
    final totalHeight = borderWidth * scaleFactor + avatarSize + badgeSize / 4;

    // 繪製第一個頭像（在後面）
    await _drawSingleAvatar(
      canvas,
      await _getAvatarUrl(tasks[0]['userId']),
      Offset(borderWidth * scaleFactor, borderWidth * scaleFactor),
      avatarSize,
      borderWidth * scaleFactor,
      borderColor,
      backgroundColor,
    );

    // 繪製第二個頭像（在前面，重疊）
    await _drawSingleAvatar(
      canvas,
      await _getAvatarUrl(tasks[1]['userId']),
      Offset(borderWidth * scaleFactor + offset, borderWidth * scaleFactor),
      avatarSize,
      borderWidth * scaleFactor,
      borderColor,
      backgroundColor,
    );

    // 繪製數字徽章 - 對齊頭像右側和底部
    final avatarRight = borderWidth * scaleFactor + offset + avatarSize;
    final avatarBottom = borderWidth * scaleFactor + avatarSize;

    final badgeCenter = Offset(
      avatarRight - badgeSize / 4, // 略微重疊在頭像右邊
      avatarBottom - badgeSize / 4, // 略微重疊在頭像底部
    );

    final badgePaint = Paint()..isAntiAlias = true;

    // 繪製徽章陰影 (微妙的陰影效果)
    badgePaint.color = Colors.black.withValues(alpha: 0.1);
    canvas.drawCircle(
      badgeCenter + const Offset(1, 1),
      badgeSize / 2,
      badgePaint,
    );

    // 徽章背景 (白色背景)
    badgePaint.color = Colors.white;
    canvas.drawCircle(badgeCenter, badgeSize / 2, badgePaint);

    // 移除外框 - 不繪製邊框

    // 繪製數字 - 提高解析度
    final textPainter = TextPainter(
      text: TextSpan(
        text: '+${tasks.length - 2}',
        style: TextStyle(
          color: AppColors.primary, // 使用 AppColors.primary
          fontSize: badgeSize * 0.6, // 增大文字大小
          fontWeight: FontWeight.bold,
          fontFamily: 'system', // 使用系統字體
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.0), // 確保文字清晰
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - textPainter.width / 2,
        badgeCenter.dy - textPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      totalWidth.toInt(),
      totalHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// 根據任務數量自動選擇合適的標記類型
  static Future<BitmapDescriptor> generateTasksMarker({
    required List<Map<String, dynamic>> tasks,
    double size = 90.0, // 合理的地圖標記大小
    double borderWidth = 2, // 固定1px邊框 (2 * 2.0 scaleFactor = 1.6px)
    Color borderColor = Colors.white,
    Color backgroundColor = Colors.white,
    Color badgeColor = Colors.red,
    Color textColor = Colors.white,
    double overlapPercentage = 0.65,
  }) async {
    if (tasks.isEmpty) {
      throw ArgumentError('任務列表不能為空');
    }

    if (tasks.length == 1) {
      return generateSingleAvatarMarker(
        avatarUrl: await _getAvatarUrl(tasks[0]['userId']),
        size: size,
        borderWidth: borderWidth,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
      );
    } else if (tasks.length == 2) {
      return generateOverlappingAvatarsMarker(
        tasks: tasks,
        size: size,
        borderWidth: borderWidth,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
        overlapPercentage: overlapPercentage,
      );
    } else {
      return generateMultipleTasksMarker(
        tasks: tasks,
        size: size,
        borderWidth: borderWidth,
        borderColor: borderColor,
        backgroundColor: backgroundColor,
        badgeColor: badgeColor,
        textColor: textColor,
        overlapPercentage: overlapPercentage,
      );
    }
  }

  /// 私有方法：載入網路圖片
  static Future<ui.Image> _loadNetworkImage(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('無法載入圖片: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    // 保持原始解析度，不進行額外的縮放
    final codec = await ui.instantiateImageCodec(
      bytes,
      allowUpscaling: false, // 不允許放大
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 私有方法：繪製保持原比例的圖片
  static void _drawImageWithAspectRatio(
    Canvas canvas,
    ui.Image image,
    Rect targetRect,
  ) {
    final imageAspect = image.width / image.height;
    final targetAspect = targetRect.width / targetRect.height;

    Rect srcRect;
    if (imageAspect > targetAspect) {
      // 圖片較寬，裁切左右兩側
      final cropWidth = image.height * targetAspect;
      final cropX = (image.width - cropWidth) / 2;
      srcRect = Rect.fromLTWH(cropX, 0, cropWidth, image.height.toDouble());
    } else {
      // 圖片較高，裁切上下兩側
      final cropHeight = image.width / targetAspect;
      final cropY = (image.height - cropHeight) / 2;
      srcRect = Rect.fromLTWH(0, cropY, image.width.toDouble(), cropHeight);
    }

    // 使用高質量插值繪製圖片
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;

    canvas.drawImageRect(image, srcRect, targetRect, paint);
  }

  /// 私有方法：繪製單一頭像
  static Future<void> _drawSingleAvatar(
    Canvas canvas,
    String? avatarUrl,
    Offset position,
    double size,
    double borderWidth,
    Color borderColor,
    Color backgroundColor,
  ) async {
    final paint = Paint()..isAntiAlias = true;
    final center = Offset(position.dx + size / 2, position.dy + size / 2);

    // 繪製邊框
    paint.color = borderColor;
    canvas.drawCircle(center, size / 2, paint);

    // 繪製背景
    paint.color = backgroundColor;
    canvas.drawCircle(center, (size - borderWidth * 2) / 2, paint);

    // 繪製頭像或預設圖標
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        final image = await _loadNetworkImage(avatarUrl);
        final avatarSize = size - borderWidth * 2;
        final avatarRect = Rect.fromCenter(
          center: center,
          width: avatarSize,
          height: avatarSize,
        );

        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(avatarRect, Radius.circular(avatarSize / 2)),
        );

        // 繪製頭像 - 保持原比例，使用 cover 效果
        _drawImageWithAspectRatio(canvas, image, avatarRect);
        canvas.restore();
      } catch (e) {
        print('載入頭像失敗: $e');
        _drawDefaultIcon(canvas, center.dx, center.dy, size * 0.4);
      }
    } else {
      _drawDefaultIcon(canvas, center.dx, center.dy, size * 0.4);
    }
  }

  /// 私有方法：繪製預設圖標
  static void _drawDefaultIcon(Canvas canvas, double x, double y, double size) {
    final paint = Paint()
      ..color =
          Colors.grey[700]! // 稍微深一點讓它在白色背景上更明顯
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 繪製簡單的人形圖標
    // 頭部
    canvas.drawCircle(Offset(x, y - size * 0.2), size * 0.25, paint);

    // 身體
    final bodyPath = Path();
    bodyPath.moveTo(x - size * 0.3, y + size * 0.1);
    bodyPath.lineTo(x - size * 0.15, y + size * 0.5);
    bodyPath.lineTo(x + size * 0.15, y + size * 0.5);
    bodyPath.lineTo(x + size * 0.3, y + size * 0.1);
    bodyPath.close();

    canvas.drawPath(bodyPath, paint);
  }

  /// 私有方法：從用戶ID獲取頭像URL
  static Future<String?> _getAvatarUrl(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        return data?['avatarUrl']?.toString();
      }
      return null;
    } catch (e) {
      print('獲取用戶頭像失敗: $e');
      return null;
    }
  }
}
