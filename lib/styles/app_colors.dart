import 'package:flutter/material.dart';

/// 應用程式顏色設計系統
/// 提供統一的顏色管理
class AppColors {
  AppColors._();

  // ===== 品牌色系 =====
  /// 主要品牌色
  static const Color primary = Color(0xFF0048CC);

  /// 品牌色漸層
  static const Color primaryLight = Color(0xFF3D7BFF);
  static const Color primaryDark = Color(0xFF003399);

  /// 品牌色透明度變化
  static Color primaryWithOpacity(double opacity) =>
      primary.withOpacity(opacity);

  /// 品牌色變化
  static Color primaryShade(int shade) {
    switch (shade) {
      case 50:
        return const Color(0xFFE8F1FF);
      case 100:
        return const Color(0xFFCCDEFF);
      case 200:
        return const Color(0xFF99BBFF);
      case 300:
        return const Color(0xFF6699FF);
      case 400:
        return const Color(0xFF336BFF);
      case 500:
        return primary;
      case 600:
        return const Color(0xFF0040B8);
      case 700:
        return const Color(0xFF0038A3);
      case 800:
        return const Color(0xFF00308F);
      case 900:
        return const Color(0xFF00247A);
      default:
        return primary;
    }
  }

  // ===== 功能色系 =====
  /// 成功色 (綠色)
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color successDark = Color(0xFF388E3C);

  /// 錯誤色 (紅色)
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorDark = Color(0xFFD32F2F);

  /// 警告色 (橙色) - 但非按鈕主色
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFB74D);
  static const Color warningDark = Color(0xFFF57C00);

  // ===== 中性色系 =====
  /// 黑色系
  static const Color black = Color(0xFF000000);
  static const Color blackLight = Color(0xFF212121);
  static const Color blackMedium = Color(0xFF424242);

  /// 白色系
  static const Color white = Color(0xFFFFFFFF);
  static const Color whiteLight = Color(0xFFFAFAFA);
  static const Color whiteMedium = Color(0xFFF5F5F5);

  /// 灰色系
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFBDBDBD);
  static const Color greyDark = Color(0xFF616161);

  /// 灰色變化
  static Color greyShade(int shade) {
    switch (shade) {
      case 50:
        return const Color(0xFFFAFAFA);
      case 100:
        return const Color(0xFFF5F5F5);
      case 200:
        return const Color(0xFFEEEEEE);
      case 300:
        return const Color(0xFFE0E0E0);
      case 400:
        return const Color(0xFFBDBDBD);
      case 500:
        return grey;
      case 600:
        return greyDark;
      case 700:
        return const Color(0xFF424242);
      case 800:
        return const Color(0xFF212121);
      case 900:
        return const Color(0xFF121212);
      default:
        return grey;
    }
  }

  // ===== 特殊用途色彩 =====
  /// 地圖標記色彩 (保持原有顏色)
  static const Color mapPreset = Color(0xFF2196F3); // 藍色
  static const Color mapCustom = Color(0xFF4CAF50); // 綠色
  static const Color mapActive = Color(0xFFFF9800); // 橙色

  /// 聊天室狀態色彩 (保持原有顏色)
  static const Color chatOnline = Color(0xFF4CAF50); // 綠色
  static const Color chatOffline = Color(0xFF9E9E9E); // 灰色

  /// 任務狀態色彩
  static const Color taskOpen = primary; // 使用品牌色
  static const Color taskAccepted = primary; // 使用品牌色
  static const Color taskCompleted = success; // 綠色
  static const Color taskExpired = greyDark; // 灰色

  // ===== 按鈕顏色配置 =====
  /// 主要按鈕 (使用品牌色)
  static const Color buttonPrimary = primary;
  static const Color buttonPrimaryText = white;

  /// 次要按鈕 (使用品牌色邊框)
  static const Color buttonSecondary = white;
  static const Color buttonSecondaryBorder = primary;
  static const Color buttonSecondaryText = primary;

  /// 取消按鈕 (灰色)
  static const Color buttonCancel = white;
  static const Color buttonCancelBorder = greyLight;
  static const Color buttonCancelText = greyDark;

  /// 危險按鈕 (紅色)
  static const Color buttonDanger = error;
  static const Color buttonDangerText = white;

  /// 成功按鈕 (綠色)
  static const Color buttonSuccess = success;
  static const Color buttonSuccessText = white;

  // ===== 背景色系 =====
  /// 應用背景
  static const Color background = Color(0xFFF5F5F5);
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundDark = Color(0xFFEEEEEE);

  /// 卡片背景
  static const Color cardBackground = white;
  static const Color cardBorder = Color(0xFFE0E0E0);

  /// 輸入框背景
  static const Color inputBackground = white;
  static const Color inputBorder = Color(0xFFE0E0E0);
  static const Color inputFocused = primary;

  // ===== 文字色系 =====
  /// 主要文字
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF616161);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFFBDBDBD);

  /// 強調文字
  static const Color textAccent = primary;
  static const Color textSuccess = success;
  static const Color textError = error;
  static const Color textWarning = warning;
}

/// 按鈕樣式快速配置
class AppButtonStyles {
  AppButtonStyles._();

  /// 主要按鈕樣式
  static ButtonStyle primaryButton({
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.buttonPrimary,
      foregroundColor: AppColors.buttonPrimaryText,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
      elevation: 2,
    );
  }

  /// 次要按鈕樣式
  static ButtonStyle secondaryButton({
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.buttonSecondaryText,
      side: BorderSide(color: AppColors.buttonSecondaryBorder),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
    );
  }

  /// 取消按鈕樣式
  static ButtonStyle cancelButton({
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.buttonCancelText,
      side: BorderSide(color: AppColors.buttonCancelBorder),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
    );
  }

  /// 危險按鈕樣式
  static ButtonStyle dangerButton({
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.buttonDanger,
      foregroundColor: AppColors.buttonDangerText,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
      elevation: 2,
    );
  }

  /// 成功按鈕樣式
  static ButtonStyle successButton({
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.buttonSuccess,
      foregroundColor: AppColors.buttonSuccessText,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
      elevation: 2,
    );
  }

  /// 文字按鈕樣式
  static ButtonStyle textButton({
    EdgeInsets? padding,
    Color? foregroundColor,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor ?? AppColors.textSecondary,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}
