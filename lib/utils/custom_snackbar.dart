import 'package:flutter/material.dart';

/// 自定義 SnackBar 工具類
/// 提供統一的樣式和位置管理
class CustomSnackBar {
  // 私有構造函數，防止實例化
  CustomSnackBar._();

  /// 清除當前顯示的 SnackBar
  /// 用於在顯示底部彈窗之前避免UI衝突
  static void clear(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  /// 顯示自定義樣式的 SnackBar
  /// [context] - BuildContext
  /// [message] - 要顯示的訊息
  /// [iconColor] - 圖標顏色（可選）
  /// [icon] - 圖標（可選）
  /// [backgroundColor] - 背景顏色（可選，默認白色）
  static void show(
    BuildContext context,
    String message, {
    Color? iconColor,
    IconData? icon,
    Color? backgroundColor,
  }) {
    // 先清除現有的 SnackBar，避免重疊
    clear(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon ?? Icons.check_circle_outline,
              color: iconColor ?? Colors.green[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor ?? Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 120, // 固定位置，避免與底部彈窗衝突
        ),
        duration: const Duration(seconds: 2), // 縮短顯示時間
      ),
    );
  }

  /// 顯示成功訊息
  static void showSuccess(BuildContext context, String message) {
    show(
      context,
      message,
      iconColor: Colors.green[600],
      icon: Icons.check_circle_outline,
      backgroundColor: Colors.white,
    );
  }

  /// 顯示錯誤訊息
  static void showError(BuildContext context, String message) {
    show(
      context,
      message,
      iconColor: Colors.red[600],
      icon: Icons.error_outline,
      backgroundColor: Colors.red[50],
    );
  }

  /// 顯示警告訊息
  static void showWarning(BuildContext context, String message) {
    show(
      context,
      message,
      iconColor: Colors.orange[600],
      icon: Icons.warning_outlined,
      backgroundColor: Colors.orange[50],
    );
  }

  /// 顯示信息訊息
  static void showInfo(BuildContext context, String message) {
    show(
      context,
      message,
      iconColor: Colors.blue[600],
      icon: Icons.info_outline,
      backgroundColor: Colors.blue[50],
    );
  }
}
