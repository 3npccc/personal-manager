import 'package:flutter/material.dart';

import 'glass_panel.dart';

/// 通用内容卡片：统一内边距、圆角，以及**模拟毛玻璃**的表面。
///
/// ## 为什么卡片不是真毛玻璃
///
/// 真毛玻璃（`BackdropFilter`）每帧都要对覆盖区域重新采样 + 高斯模糊。
/// 卡片在列表里可能同时存在上百个，逐个模糊会直接掉帧。
/// 所以这里用**半透明 + 高光描边 + 柔和双层阴影**模拟玻璃观感 ——
/// 视觉上同样"浮在渐变背景上"，但渲染成本几乎为零。
///
/// 需要真模糊的地方（导航栏、弹窗、SnackBar）请直接用 `GlassPanel`。
///
/// ## 长按场景（规则 46）
///
/// 如果卡片本身要响应**长按**，请**不要**用本组件 —— `InkWell` 的长按
/// 手势会和内部的滚动 / 拖拽手势打架，导致长按偶发不触发。
/// 这种情况请用裸 `GlassCard` 并自行套 `GestureDetector`。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: padding,
      child: child,
    );
  }
}
