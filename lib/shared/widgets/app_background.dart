import 'package:flutter/material.dart';

/// 应用背景：柔和品牌色光晕 + 基础表面色。
///
/// ## 它的第一职责其实是"给毛玻璃当素材"
///
/// `BackdropFilter` 模糊的是"背后已绘制的像素"。纯色背景下模糊前后完全一致，
/// 玻璃就看不出来。所以这里放两团**径向渐变光晕**，让背景有明暗层次，
/// 导航栏和浮层模糊后才会有 iOS 那种"雾气"质感。
///
/// ## 为什么全部从 [ColorScheme] 派生
///
/// 硬编码色值会导致深色主题下背景与主题脱节（比如深色下还透出浅蓝光晕）。
/// 用 `scheme.primary` / `scheme.tertiary` 能自动跟随明暗与品牌色变化。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // 光晕透明度：深色主题要稍强一点，否则在黑底上看不出层次。
    final a1 = dark ? 0.22 : 0.18;
    final a2 = dark ? 0.16 : 0.12;

    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Stack(
        children: <Widget>[
          // 左上：主色光晕
          Positioned(
            left: -120,
            top: -140,
            child: _Blob(
              size: 420,
              color: scheme.primary.withValues(alpha: a1),
            ),
          ),
          // 右下：第三色光晕，形成对角呼应
          Positioned(
            right: -100,
            bottom: -160,
            child: _Blob(
              size: 460,
              color: scheme.tertiary.withValues(alpha: a2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一团径向渐变的柔光（边缘完全淡出，无硬边）。
class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
