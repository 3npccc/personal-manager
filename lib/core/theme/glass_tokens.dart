import 'package:flutter/material.dart';

/// 毛玻璃（glassmorphism）设计令牌 —— **全局唯一样式来源**。
///
/// ## 背景：为什么只能"自己画"
///
/// Windows 上的原生毛玻璃有两种：**Mica**（Win11 22000+）和 **Acrylic**
/// （Win10 1803+）。但实测本机是 **Windows 10 22H2 (10.0.19045)**：
///
/// - Mica：系统不支持（需 Win11）；
/// - Acrylic：系统层在 1903+ 之后对第三方窗口大幅收紧，普通应用基本拿不到；
///   即使硬调 `DwmSetWindowAttribute` 也只对**窗口非客户区**生效，
///   管不到 Flutter 绘制的整个界面。
///
/// 所以本项目的毛玻璃**全部在 Flutter 层用 `BackdropFilter` 实现**。
/// 原理是：把"已经画在它下面的像素"做一次高斯模糊再贴回来。
/// 因为窗口背景不透明（用户选定，不做透桌面），模糊对象是应用自己的渐变背景，
/// 视觉上就是 iOS 那种"内容从半透明玻璃后面透出来"的效果。
///
/// ## 性能分区（用户选定）
///
/// `BackdropFilter` 每帧都要重新采样 + 模糊它覆盖的整块区域，**很贵**。
/// 所以按"面积 × 数量"分区：
///
/// | 区域 | 方案 | 原因 |
/// |---|---|---|
/// | 导航栏、浮层（Dialog / SnackBar） | **真** `BackdropFilter` | 数量固定，面积可控 |
/// | 内容卡片 | 半透明 + 描边 + 柔和阴影 **模拟** | 列表里可能上百个，逐个模糊会掉帧 |
///
/// ## 两份 API 的由来
///
/// `AppTheme._build(Brightness)` 在 `MaterialApp` 之前构造，**拿不到
/// `BuildContext`**，却要填 `CardThemeData.color` / `SnackBarThemeData`。
/// 所以这里以 `(ColorScheme, Brightness)` 版为**唯一实现**，
/// `context` 版只是它的薄包装 —— 保证"主题里定义的卡片色"与
/// "页面里 `GlassCard` 自己算的卡片色"永远一致（玻璃色差是最常见的坑）。
class GlassTokens {
  GlassTokens._();

  /// 毛玻璃模糊半径（逻辑像素）。
  ///
  /// 8 是**实测平衡点**：再小（≤4）看不出玻璃感，只剩"半透明方块"；
  /// 再大（≥16）边缘会糊成一团、文字发虚，且在集成显卡上明显掉帧。
  /// 导航栏因为面积大、下面内容变化频繁，单独用更大一点的 14（见 app_shell）。
  static const double blur = 8;

  /// 导航栏 / 浮层玻璃表面的不透明度。
  ///
  /// 0.72 的含义：72% 的底色盖上来、28% 的背景从玻璃后面透出。
  /// 低于 0.6 会让背景内容干扰前景可读性；高于 0.85 就看不出玻璃了。
  static const double surfaceAlpha = 0.72;

  /// 卡片（模拟玻璃）表面的不透明度。
  ///
  /// 卡片不用真模糊，所以靠 alpha 更实一点（0.85）保证内容清晰。
  static const double cardAlpha = 0.85;

  /// 玻璃高光描边的不透明度 —— 模拟"玻璃边缘反光"。
  static const double borderAlpha = 0.55;

  /// 玻璃层默认圆角
  static const BorderRadius radius = BorderRadius.all(Radius.circular(12));

  // ---------------------------------------------------------------------------
  // 核心实现（无 context）
  // ---------------------------------------------------------------------------

  /// 玻璃表面的填充色（导航栏 / 浮层用）。
  ///
  /// 浅色主题用**白**（叠加后提亮，像磨砂白玻璃）；
  /// 深色主题用**主题高表面色**（叠加后压暗，像深色烟熏玻璃）。
  /// 关键：不能深浅都用同一种，否则深色主题下会出现"发灰的亮块"。
  static Color surfaceFor(ColorScheme scheme, Brightness brightness) {
    final base = brightness == Brightness.light
        ? Colors.white
        : scheme.surfaceContainerHigh;
    return base.withValues(alpha: surfaceAlpha);
  }

  /// 卡片的模拟玻璃填充色（比 [surfaceFor] 更实一些）。
  static Color cardSurfaceFor(ColorScheme scheme, Brightness brightness) {
    final base = brightness == Brightness.light
        ? Colors.white
        : scheme.surfaceContainerHigh;
    return base.withValues(alpha: cardAlpha);
  }

  /// 玻璃边缘高光描边色。
  static Color borderFor(ColorScheme scheme, Brightness brightness) {
    return brightness == Brightness.light
        ? Colors.white.withValues(alpha: borderAlpha)
        : scheme.outlineVariant.withValues(alpha: borderAlpha);
  }

  /// 卡片投影的主色（供 `CardThemeData.shadowColor` 使用）。
  ///
  /// Material 的 `Card` 只接受**单一** shadowColor，抹不出 [shadowFor] 那种
  /// 双层过渡，所以这里取双层里较深的那一档作为代表色。
  static Color shadowColorFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return (dark ? Colors.black : const Color(0xFF2B3A55))
        .withValues(alpha: dark ? 0.30 : 0.10);
  }

  /// 卡片下方柔和的投影 —— 让"玻璃片"看起来是**浮在**背景上的。
  ///
  /// 用两层（近处窄而深 + 远处宽而浅）而不是单层：单层阴影要么边缘太硬、
  /// 要么范围太大像黑眼圈；两层叠加才接近真实环境光。
  static List<BoxShadow> shadowFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final c = (dark ? Colors.black : const Color(0xFF2B3A55))
        .withValues(alpha: dark ? 0.30 : 0.06);
    return <BoxShadow>[
      BoxShadow(color: c, blurRadius: 2, offset: const Offset(0, 1)),
      BoxShadow(color: c, blurRadius: 12, offset: const Offset(0, 4)),
    ];
  }

  // ---------------------------------------------------------------------------
  // context 包装（页面里用这组）
  // ---------------------------------------------------------------------------

  /// [surfaceFor] 的 context 版。
  static Color surface(BuildContext context) {
    final t = Theme.of(context);
    return surfaceFor(t.colorScheme, t.brightness);
  }

  /// [cardSurfaceFor] 的 context 版。
  static Color cardSurface(BuildContext context) {
    final t = Theme.of(context);
    return cardSurfaceFor(t.colorScheme, t.brightness);
  }

  /// [borderFor] 的 context 版。
  static Color border(BuildContext context) {
    final t = Theme.of(context);
    return borderFor(t.colorScheme, t.brightness);
  }

  /// [shadowFor] 的 context 版。
  static List<BoxShadow> shadow(BuildContext context) {
    return shadowFor(Theme.of(context).brightness);
  }

  /// 玻璃面板（导航栏 / 浮层）的统一装饰。
  static BoxDecoration panelDecoration(
    BuildContext context, {
    BorderRadius? borderRadius,
    bool border = true,
  }) {
    return BoxDecoration(
      color: surface(context),
      borderRadius: borderRadius ?? radius,
      border: border
          ? Border.all(color: GlassTokens.border(context), width: 1)
          : null,
    );
  }

  /// 卡片（模拟玻璃）的统一装饰。
  static BoxDecoration cardDecoration(
    BuildContext context, {
    BorderRadius? borderRadius,
    Color? tint,
  }) {
    return BoxDecoration(
      color: tint ?? cardSurface(context),
      borderRadius: borderRadius ?? radius,
      border: Border.all(color: border(context), width: 1),
      boxShadow: shadow(context),
    );
  }
}
