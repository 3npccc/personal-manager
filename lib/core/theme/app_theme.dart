import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'glass_tokens.dart';

/// 全局主题：Material 3，支持浅色 / 深色，跟随系统或手动指定
class AppTheme {
  AppTheme._();

  /// 品牌主色（沉稳的青蓝色，长时间看不累）
  static const Color _seed = Color(0xFF3A6EA5);

  /// 浅色主题
  static ThemeData get light => _build(Brightness.light);

  /// 深色主题
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    // 排版：取 Material 3 在 Windows 上的字号阶梯（blackRedmond），
    // 再统一收紧字重（标题 w600 / 正文 w400）。
    //
    // 【为什么直接用 `Typography.blackRedmond`】
    // 它是 `Typography` 上的 **静态常量**（typography.dart:568
    // `static const TextTheme blackRedmond = TextTheme(...)`），
    // 不是实例成员 —— 所以**不能**写成 `Typography.material2021(...).blackRedmond`。
    // 它本身就是一份完整的 TextTheme（字号/行高/字间距的几何），
    // 与 `whiteRedmond` 的几何完全相同、只差默认前景色；而 TextTheme 的颜色
    // 最终会被 ThemeData 用 colorScheme 覆盖，所以这里取哪一份都不影响成品颜色。
    final baseText = Typography.blackRedmond;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 全局字体族：Windows 上用「微软雅黑 UI」（系统自带，无需打包）
      fontFamily: AppTypography.fontFamily,
      // 统一字重层级，杜绝"加粗与正常混用"
      textTheme: AppTypography.applyTo(baseText),
      // 【为什么是透明而不是 scheme.surface】
      // 真正的背景由 `MaterialApp.builder` 里的 `AppBackground`（品牌色光晕
      // 渐变）绘制，位于整个 Navigator 之下。这里若填不透明色，每个页面的
      // Scaffold 都会把它盖住，毛玻璃就失去了"素材"。
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        // AppBar 也做半透明，让内容滚到它下面时能透出一点，和毛玻璃风格统一
        backgroundColor: scheme.surface.withValues(alpha: 0.65),
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        // elevation 1 + 自定义 shadowColor：给"模拟玻璃"卡片一层柔和投影，
        // 让它看起来浮在渐变背景上。用 1 而不是 0 是因为 0 时 Material
        // 完全不画阴影；也不用更大的值 —— 那会变成生硬的"厚纸片"。
        elevation: 1,
        shadowColor: GlassTokens.shadowColorFor(brightness),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        // 卡片走"模拟玻璃"：半透明表面 + 高光描边 + 柔和阴影。
        // 真模糊（BackdropFilter）留给导航栏与浮层，见 GlassTokens 的性能分区。
        color: GlassTokens.cardSurfaceFor(scheme, brightness),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: GlassTokens.radius,
          side: BorderSide(color: GlassTokens.borderFor(scheme, brightness)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: AppTypography.titleWeight,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // 浮动 SnackBar 在 Overlay 里，半透明即可看到背景 —— 也是玻璃观感。
        // 用固定深色而不是 surface：SnackBar 需要与页面内容形成明确对比，
        // 跟随主题明暗（亮色主题下也用深底浅字）是 Material 的一贯做法。
        backgroundColor: scheme.inverseSurface.withValues(alpha: 0.92),
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 13,
          fontWeight: AppTypography.bodyWeight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
