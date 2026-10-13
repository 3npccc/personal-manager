import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/study_providers.dart';
import 'goal_form_page.dart';

/// 学习目标 Tab：完成状态 / 类型筛选 + 目标列表 + 新增。
class StudyGoalPage extends ConsumerWidget {
  const StudyGoalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(studyGoalListProvider);
    final filter = ref.watch(studyGoalFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _GoalFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<StudyGoal>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered ? Icons.flag_outlined : Icons.search_off,
                title: filter.isUnfiltered ? '还没有学习目标' : '没有符合条件的目标',
                subtitle: filter.isUnfiltered
                    ? '点右下角「加目标」设定一个目标'
                    : '试试切换筛选条件',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(studyGoalFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final goal = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: _GoalTile(
                      goal: goal,
                      onTap: () => _openForm(context, goal: goal),
                      onToggle: (value) => ref
                          .read(studyGoalActionsProvider)
                          .toggleCompleted(id: goal.id, isCompleted: value),
                      onLongPress: () => _confirmDelete(context, ref, goal),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('加目标'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {StudyGoal? goal}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GoalFormPage(goal: goal)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StudyGoal goal,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除目标',
      message: '确定删除「${goal.name}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(studyGoalActionsProvider).remove(goal.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 目标列表项：复选框 + 名称 + 类型标签 + 截止日期（逾期红字）
class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    this.onTap,
    this.onToggle,
    this.onLongPress,
  });

  final StudyGoal goal;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = StudyGoalType.fromCode(goal.type);
    final overdue = isGoalOverdue(goal, DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(
            children: [
              Checkbox(
                value: goal.isCompleted,
                onChanged: (v) => onToggle?.call(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      goal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: goal.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: goal.isCompleted
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _TypeTag(label: type.label),
                        if (goal.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              overdue
                                  ? '已逾期 · ${FormatUtils.date(goal.dueDate)}'
                                  : '截止 ${FormatUtils.date(goal.dueDate)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: overdue
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                                fontWeight: overdue
                                    ? AppTypography.titleWeight
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目标类型小标签
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: scheme.onSecondaryContainer,
          fontWeight: AppTypography.titleWeight,
        ),
      ),
    );
  }
}

/// 目标筛选条：完成状态 + 类型
class _GoalFilterBar extends ConsumerWidget {
  const _GoalFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(studyGoalFilterProvider);
    final notifier = ref.read(studyGoalFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部状态'),
              selected: filter.isCompleted == null,
              onSelected: (_) => notifier.setCompleted(null),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('未完成'),
              selected: filter.isCompleted == false,
              onSelected: (selected) =>
                  notifier.setCompleted(selected ? false : null),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('已完成'),
              selected: filter.isCompleted == true,
              onSelected: (selected) =>
                  notifier.setCompleted(selected ? true : null),
            ),
            const SizedBox(width: 16),
            for (final t in StudyGoalType.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(t.label),
                selected: filter.type == t,
                onSelected: (selected) =>
                    notifier.setType(selected ? t : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
