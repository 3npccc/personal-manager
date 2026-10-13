import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/models/enums.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/format_utils.dart';
import '../../../providers/study_providers.dart';

/// 课程列表项：课程名 / 平台 / 进度条 / 章节数 / 状态 / 计划完成时间。
class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    this.onTap,
    this.onLongPress,
  });

  final Course course;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ProgressStatus.fromCode(course.status);
    final color = statusColor(context, status);
    final progress = courseProgress(course);
    final hasChapters = course.totalChapters > 0;

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
                      course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: AppTypography.titleWeight,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (course.platform != null && course.platform!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  course.platform!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              if (hasChapters) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasChapters
                          ? '已完成 ${course.completedChapters} / ${course.totalChapters} 章'
                          : '未填写章节数',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (hasChapters)
                    Text(
                      FormatUtils.percent(progress),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(
                              color: color,
                              fontWeight: AppTypography.titleWeight),
                    ),
                ],
              ),
              if (course.dueDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  '计划完成：${FormatUtils.date(course.dueDate)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
