import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/models/enums.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/format_utils.dart';
import '../../../providers/work_providers.dart';

/// 项目列表项：名称 / 状态胶囊 / 优先级 / 进度条 / 起止日期 / 合计工时。
///
/// 【点击 vs 长按】点击进入编辑，长按删除（与待办 / 记账 / 学习一致）。
///
/// 【为什么进度条是「只读」而不是拖动条】
/// 列表项里塞 Slider 会让"点进编辑"与"拖进度"手势互相打架
/// （`Slider` 会吃掉横向拖动手势），且移动端拇指难以精确拖动。
/// 故列表上直接显示进度百分比 + 条；**更新进度的入口在编辑表单**里
/// （那里用的是 `Slider`，交互空间充足）。这与 4.4 课程/读书的做法一致。
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    this.totalMinutes,
    this.onTap,
    this.onLongPress,
  });

  final Project project;

  /// 该项目累计工时（分钟）；null = 未加载，不显示
  final int? totalMinutes;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 各状态对应的强调色
  static Color statusColor(BuildContext context, ProgressStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case ProgressStatus.ongoing:
        return isDark ? const Color(0xFF7FB3E8) : const Color(0xFF2E6CB5);
      case ProgressStatus.completed:
        return isDark ? const Color(0xFF8CD9A8) : const Color(0xFF2E8B57);
      case ProgressStatus.paused:
        return isDark ? const Color(0xFFB0A9A0) : const Color(0xFF7A7069);
    }
  }

  /// 优先级对应的颜色（0 低 / 1 中 / 2 高）
  static Color priorityColor(BuildContext context, int priority) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (priority) {
      case 2:
        return isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
      case 1:
        return isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100);
      default:
        return isDark ? const Color(0xFF90A4AE) : const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ProgressStatus.fromCode(project.status);
    final color = statusColor(context, status);
    final ratio = projectProgress(project);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Chip(label: status.label, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PriorityTag(
                    priority: project.priority,
                    color: priorityColor(context, project.priority),
                  ),
                  if (totalMinutes != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '累计 ${FormatUtils.minutes(totalMinutes!)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateRangeText(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '${project.progress}%',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(
                            color: color, fontWeight: AppTypography.titleWeight),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateRangeText() {
    final s = project.startDate;
    final d = project.dueDate;
    if (s == null && d == null) return '未设置起止时间';
    final start = s == null ? '未设置' : FormatUtils.date(s);
    final end = d == null ? '未设置' : FormatUtils.date(d);
    return '$start ~ $end';
  }
}

/// 状态小胶囊
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: AppTypography.titleWeight,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 优先级小标签
class _PriorityTag extends StatelessWidget {
  const _PriorityTag({required this.priority, required this.color});

  final int priority;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${projectPriorityLabel(priority)}优先级',
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: color,
          fontWeight: AppTypography.titleWeight,
        ),
      ),
    );
  }
}

/// 优先级数值 → 中文（0 低 / 1 中 / 2 高）。
///
/// 【为什么不用 `TodoPriority`】表里 `priority` 存的是 int（0/1/2），
/// 而 `TodoPriority` 是待办模块的枚举（语义虽同，但引入跨模块枚举会让
/// "工作项目的优先级"与"待办优先级"耦合）。这里用一个局部纯函数映射，
/// 保持两个模块独立演进。
String projectPriorityLabel(int priority) {
  switch (priority) {
    case 2:
      return '高';
    case 1:
      return '中';
    default:
      return '低';
  }
}
