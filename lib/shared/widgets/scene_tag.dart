import 'package:flutter/material.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_typography.dart';

/// 场景标签（学习 / 工作 / 生活），颜色随场景变化
class SceneTag extends StatelessWidget {
  const SceneTag({super.key, required this.scene, this.dense = false});

  final Scene scene;

  /// 紧凑模式：更小的字号和内边距
  final bool dense;

  /// 场景对应的强调色
  static Color colorOf(BuildContext context, Scene scene) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (scene) {
      case Scene.study:
        return isDark ? const Color(0xFF7FB3E8) : const Color(0xFF2E6CB5);
      case Scene.work:
        return isDark ? const Color(0xFFE8A87F) : const Color(0xFFC2662B);
      case Scene.life:
        return isDark ? const Color(0xFF8CD9A8) : const Color(0xFF2E8B57);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, scene);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        scene.label,
        style: TextStyle(
          color: color,
          fontSize: dense ? 10 : 11,
          fontWeight: AppTypography.titleWeight,
          height: 1.3,
        ),
      ),
    );
  }
}
