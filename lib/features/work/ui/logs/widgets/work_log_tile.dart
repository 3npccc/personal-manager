import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/format_utils.dart';

/// 工时列表项：日期 / 项目名 / 时长 / 摘要。
///
/// 【为什么项目名要传进来而不是从 project 对象取】`WorkLog` 表里只有
/// `projectId`（外键），项目名要另查。列表页已经为统计聚合加载了项目列表，
/// 顺手把名字传下来，比每个 item 各查一次库省得多。
class WorkLogTile extends StatelessWidget {
  const WorkLogTile({
    super.key,
    required this.log,
    required this.projectName,
    this.onTap,
    this.onLongPress,
  });

  final WorkLog log;

  /// 项目显示名（项目已删除时由调用方传「（已删除项目）」）
  final String projectName;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            projectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: AppTypography.titleWeight,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (log.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        log.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      FormatUtils.date(log.date),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.minutes(log.minutes),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: AppTypography.titleWeight,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${log.minutes} 分钟',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
