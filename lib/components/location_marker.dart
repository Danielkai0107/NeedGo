import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../styles/app_colors.dart';

/// Google Maps風格的位置標記生成器
class LocationMarker {
  /// 生成Google Maps風格的當前位置標記
  static Future<BitmapDescriptor> generateCurrentLocationMarker({
    double size = 16.0,
    double bearing = 0.0, // 方向角度（0度為北）
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 提高解析度
    final scaleFactor = 2.0;
    final totalSize = size * scaleFactor;
    final center = Offset(totalSize / 2, totalSize / 2);

    final paint = Paint()..isAntiAlias = true;

    // App primary color
    final primaryColor = AppColors.primary;
    final whiteColor = Colors.white;
    final shadowColor = Colors.black.withOpacity(0.3);

    // 繪製陰影
    paint.color = shadowColor;
    canvas.drawCircle(center + const Offset(2, 2), totalSize * 0.3, paint);

    // 繪製外圈（primary色）
    paint.color = primaryColor;
    canvas.drawCircle(center, totalSize * 0.3, paint);

    // 繪製內圈（白色）
    paint.color = whiteColor;
    canvas.drawCircle(center, totalSize * 0.12, paint);

    // 繪製方向指示器（小箭頭）
    if (bearing != 0.0) {
      _drawDirectionArrow(
        canvas,
        center,
        bearing,
        totalSize * 0.25,
        primaryColor,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(totalSize.toInt(), totalSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// 繪製方向指示器
  static void _drawDirectionArrow(
    Canvas canvas,
    Offset center,
    double bearing,
    double radius,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    // 將角度轉換為弧度（0度為北方）
    final radians = (bearing - 90) * math.pi / 180;

    // 計算箭頭的三個點
    final arrowLength = radius * 0.4;
    final arrowWidth = radius * 0.2;

    final tip = Offset(
      center.dx + arrowLength * math.cos(radians),
      center.dy + arrowLength * math.sin(radians),
    );

    final left = Offset(
      center.dx +
          (arrowLength * 0.6) * math.cos(radians) -
          arrowWidth * math.sin(radians),
      center.dy +
          (arrowLength * 0.6) * math.sin(radians) +
          arrowWidth * math.cos(radians),
    );

    final right = Offset(
      center.dx +
          (arrowLength * 0.6) * math.cos(radians) +
          arrowWidth * math.sin(radians),
      center.dy +
          (arrowLength * 0.6) * math.sin(radians) -
          arrowWidth * math.cos(radians),
    );

    // 繪製箭頭
    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(left.dx, left.dy);
    path.lineTo(right.dx, right.dy);
    path.close();

    canvas.drawPath(path, paint);
  }
}
