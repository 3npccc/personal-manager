import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../providers/life_providers.dart';
import 'habit_form_page.dart';
import 'widgets/habit_tile.dart';

/// 习惯 Tab：统计条 + 习惯列表（连续天数 / 今日打卡）+ 新增。
class HabitListPage extends ConsumerWidget {
  const HabitListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(habitListProvider);

    return Scaffold(
      body: AsyncValueView<List<Habit>>(
        value: asyncList,
        isEmpty: (list) => list.isEmpty,
        empty: const EmptyState(
          icon: Icons.repeat,
          title: '还没有习惯',
          subtitle: '点右下角「加习惯」养成第一个好习惯',
        ),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _HabitSummary(list: list);
            }
            return StaggeredListItem(
              index: index - 1,
              child: _HabitRow(habit: list[index - 1]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('加习惯'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {Habit? habit}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => HabitFormPage(habit: habit)),
    );
  }
}

/// 单行习惯：自己查连续天数与今日打卡态。
///
/// 【为什么这里可以各自 watch】习惯数量是人手维护的（个位数到几十），
/// 不是日志那种成百上千条的列表，逐项查询可接受；且能让卡片职责单一。
class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStreak = ref.watch(habitStreakProvider(habit.id));
    final streak = asyncStreak.value ?? 0;
    // 今日打卡态：用「今天是否在打卡日期集合里」判定，
    // 复用同一份数据，避免多开一个查询。
    final asyncDates = ref.watch(habitCheckinDatesProvider(habit.id));
    final today = lifeToday();
    final checkedToday = (asyncDates.value ?? const <DateTime>[])
        .any((d) => d.year == today.year &&
            d.month == today.month &&
            d.day == today.day);

    return HabitTile(
      habit: habit,
      streak: streak,
      checkedToday: checkedToday,
      onTap: () => _openForm(context, habit: habit),
      onToggleToday: () => _toggleToday(context, ref),
      onLongPress: () => _confirmDelete(context, ref),
    );
  }

  Future<void> _openForm(BuildContext context, {Habit? habit}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => HabitFormPage(habit: habit)),
    );
  }

  Future<void> _toggleToday(BuildContext context, WidgetRef ref) async {
    await ref.read(habitActionsProvider).toggleCheckin(habit.id, lifeToday());
    if (!context.mounted) return;
    // 打卡后连续天数与今日态都要重算 —— invalidate 依赖链上游即可：
    // habitCheckinDatesProvider 变了，habitStreakProvider 会跟着失效。
    ref.invalidate(habitCheckinDatesProvider(habit.id));
    ref.invalidate(habitStreakProvider(habit.id));
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除习惯',
      message: '确定删除「${habit.name}」吗？\n打卡记录会一并删除，此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(habitActionsProvider).remove(habit.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 顶部统计：习惯数 / 今天已打卡
class _HabitSummary extends ConsumerWidget {
  const _HabitSummary({required this.list});

  final List<Habit> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncToday = ref.watch(todayCheckedHabitCountProvider);
    final todayCount = asyncToday.value ?? 0;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: '习惯总数',
            value: '${list.length}',
            icon: Icons.repeat,
            dense: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '今天已打卡',
            value: '$todayCount',
            icon: Icons.check_circle_outline,
            dense: true,
          ),
        ),
      ],
    );
  }
}
