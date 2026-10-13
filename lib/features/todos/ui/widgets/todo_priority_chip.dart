import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';

/// 待办优先级标签：低 / 中 / 高，颜色区分。
///
/// 颜色约定（沿用场景色板的中性化处理）：
/// - 高：暖红（警示）
/// - 中：琥珀（提醒）
/// - 低：灰蓝（中性）
/// 深浅色主题各一套，保证对比度。
class TodoPriorityChip extends StatelessWidget {
  const TodoPriorityChip({
    super.key,
    required this.priority,
    this.dense = true,
  });

  final TodoPriority priority;
  final bool dense;

  /// 优先级对应的强调色
  static Color colorOf(BuildContext context, TodoPriority priority) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (priority) {
      case TodoPriority.high:
        return isDark ? const Color(0xFFEF8A8A) : const Color(0xFFC0392B);
      case TodoPriority.medium:
        return isDark ? const Color(0xFFE5C07B) : const Color(0xFFB8860B);
      case TodoPriority.low:
        return isDark ? const Color(0xFF9AA7B8) : const Color(0xFF5A6C7D);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, priority);
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
        priority.label,
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
