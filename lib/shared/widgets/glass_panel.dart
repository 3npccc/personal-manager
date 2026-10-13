import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/glass_tokens.dart';

/// 真·毛玻璃面板：内容下方的像素会被高斯模糊后透出来。
///
/// ## 它到底做了什么
///
/// 结构是两层叠放：
///
/// ```text
/// Stack
///  ├─ BackdropFilter(blur)   ← 把"下面已画的像素"模糊
///  └─ Container(半透明色)     ← 盖一层带透明度的主题色，得到"玻璃感"
/// ```
///
/// ⚠️ 只有 `BackdropFilter` 是不够的 —— 它只负责模糊，不负责上色。
/// 少了上面的半透明 `Container`，视觉上相当于"直接对着背景虚化"，
/// 会被误认成渲染错误。两者必须成对出现。
///
/// ## 什么时候该用它
///
/// **只用在数量固定、面积可控的地方**：导航栏、Dialog、SnackBar、下拉菜单。
/// 列表里的卡片请用 [GlassCard]，它用"半透明 + 描边 + 阴影"模拟玻璃，
/// 成本几乎为零。原因见 [GlassTokens] 的性能分区说明。
///
/// ## 用法
///
/// ```dart
/// GlassPanel(
///   borderRadius: BorderRadius.circular(12),
///   child: Padding(padding: EdgeInsets.all(16), child: Text('内容')),
/// )
/// ```
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = GlassTokens.radius,
    this.blur = GlassTokens.blur,
    this.blurEnabled = true,
    this.border = true,
    this.padding,
  });

  final Widget child;

  /// 圆角。裁剪与装饰共用同一份，避免"模糊溢出圆角"的经典 bug。
  final BorderRadius borderRadius;

  /// 模糊半径（σ）。默认 [GlassTokens.blur]。
  final double blur;

  /// 是否真正启用模糊。
  ///
  /// 关闭后退化为"半透明面板"（视觉上仍是一只浅色玻璃，只是不模糊背景）。
  /// 用于：① 低端设备降级；② widget 测试（`BackdropFilter` 在测试环境
  /// 会强制走真实的 `SceneBuilder`，既慢又没必要）。
  final bool blurEnabled;

  /// 是否画边缘高光描边。
  final bool border;

  /// 内边距（可选；也可以自己在 child 里 padding）。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    // 上色层：半透明主题色 + 高光描边。这一层是"玻璃"的可见部分。
    content = DecoratedBox(
      decoration: GlassTokens.panelDecoration(
        context,
        borderRadius: borderRadius,
        border: border,
      ),
      child: content,
    );

    if (blurEnabled) {
      // 模糊层必须在**下面**：BackdropFilter 模糊的是它自己背后已绘制的像素，
      // 若把它放在上色层之上，会把上色层也一起模糊掉（颜色被洗淡）。
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(borderRadius: borderRadius, child: content);
    }

    return content;
  }
}

/// 模拟玻璃卡片：**不用** `BackdropFilter`，靠半透明 + 描边 + 柔和阴影
/// 做出"玻璃片浮在背景上"的观感。
///
/// 与 [GlassPanel] 的分工：
/// - [GlassCard] 用在**列表 / 网格**里（可能上百个实例），成本 ~0；
/// - [GlassPanel] 用在**固定少数几处**（导航栏、浮层），成本较高但效果好。
///
/// 用法与 `Card` 基本一致：
///
/// ```dart
/// GlassCard(onTap: () {}, child: Text('内容'))
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = GlassTokens.radius,
    this.tint,
    this.enableHoverLift = true,
  });

  final Widget child;

  /// 点击回调。非空时启用 InkWell 水波纹 + hover 抬升。
  final VoidCallback? onTap;

  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// 覆盖填充色（例如状态色卡片）。为 null 时用 [GlassTokens.cardDecoration]。
  final Color? tint;

  /// 鼠标悬停时是否轻微抬升并加深阴影（见 [HoverLift]）。
  final bool enableHoverLift;

  @override
  Widget build(BuildContext context) {
    final decoration = GlassTokens.cardDecoration(
      context,
      borderRadius: borderRadius,
      tint: tint,
    );

    Widget content = Padding(padding: padding, child: child);

    if (onTap != null) {
      content = Material(
        // 透明 Material：只为让 InkWell 的水波纹有地方画，
        // 颜色仍由外层 DecoratedBox 决定。
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: content,
        ),
      );
    }

    Widget card = DecoratedBox(
      decoration: decoration,
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );

    if (onTap != null && enableHoverLift) {
      card = HoverLift(borderRadius: borderRadius, child: card);
    }
    return card;
  }
}

/// 交互反馈：鼠标悬停时轻微抬升。
///
/// 用 [MouseRegion] 而非 `InkWell.hoverColor`，因为我们要动的是**几何**
/// （位移），不是颜色。
///
/// ⚠️ 位移用 [Transform.translate] 而不是 `AnimatedSlide`：
/// `AnimatedSlide.offset` 是**相对自身尺寸的比例**，`lift=2` 写成
/// `offset: Offset(0, -0.02)` 会随控件高度变化（高度 50 时移动 1px，
/// 高度 200 时移动 4px），不是我们要的"固定像素抬升"。
///
/// 过渡 120ms —— 比 Material 默认的 200ms 更"跟手"，又不至于快到显得跳。
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.borderRadius = GlassTokens.radius,
    this.lift = 2,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 上抬位移（逻辑像素）。
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _hovered ? -widget.lift : 0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}
