import 'package:flutter/material.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/scene_tag.dart';
import 'todo_priority_chip.dart';

/// 单条待办：复选框 + 标题 + 描述摘要 + 场景/优先级/截止日期。
///
/// 交互：
/// - 点复选框 → 切换完成状态
/// - 点整行 → 编辑
/// - 长按 → 交给外部处理（通常是删除菜单）
class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    this.onToggle,
    this.onTap,
    this.onLongPress,
  });

  final Todo todo;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 截止日期是否已逾期（未完成且早于今天）
  bool get _isOverdue {
    if (todo.isCompleted) return false;
    final due = todo.dueDate;
    if (due == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    return target.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCompleted = todo.isCompleted;
    final scene = Scene.fromCode(todo.scene);
    final priority = TodoPriority.fromValue(todo.priority);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isCompleted,
                onChanged: onToggle == null
                    ? null
                    : (v) => onToggle!(v ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: isCompleted
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                        fontWeight: isCompleted
                            ? AppTypography.bodyWeight
                            : AppTypography.titleWeight,
                      ),
                    ),
                    if ((todo.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        todo.description!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SceneTag(scene: scene, dense: true),
                        TodoPriorityChip(priority: priority),
                        if (todo.dueDate != null) _dueLabel(context),
                        if (isCompleted && todo.completedAt != null)
                          _metaText(
                            context,
                            '完成于 ${FormatUtils.date(todo.completedAt)}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 截止日期标签：逾期用主题错误色强调
  Widget _dueLabel(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = _isOverdue;
    final color = overdue
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_outlined, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          overdue
              ? '逾期 ${FormatUtils.date(todo.dueDate)}'
              : FormatUtils.friendlyDate(todo.dueDate!),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight:
                overdue ? AppTypography.titleWeight : AppTypography.bodyWeight,
          ),
        ),
      ],
    );
  }

  Widget _metaText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
