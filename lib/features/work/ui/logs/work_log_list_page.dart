import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../providers/work_providers.dart';
import 'widgets/work_log_tile.dart';
import 'work_log_form_page.dart';

/// 工时 Tab：按项目分组统计 + 明细列表 + 新增。
class WorkLogListPage extends ConsumerWidget {
  const WorkLogListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLogs = ref.watch(workLogListProvider);
    final asyncGroups = ref.watch(workLogGroupedProvider);
    final asyncProjects = ref.watch(projectListProvider);
    final filter = ref.watch(workLogFilterProvider);

    // 项目 id -> 名称（明细列表显示用）
    final nameMap = <int, String>{
      for (final p in asyncProjects.value ?? const <Project>[]) p.id: p.name,
    };

    return Scaffold(
      body: Column(
        children: [
          const _WorkLogFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<WorkLog>>(
              value: asyncLogs,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.timer_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有工时记录' : '没有符合条件的记录',
                subtitle: filter.isUnfiltered
                    ? '点右下角「记工时」开始记录'
                    : '试试切换筛选条件',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(workLogFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  // 分组统计（任一未就绪就跳过，不显示半份数据）
                  if (!asyncGroups.isLoading &&
                      (asyncGroups.value?.isNotEmpty ?? false)) ...[
                    SectionHeader(
                      title: '按项目统计',
                      icon: Icons.pie_chart_outline,
                    ),
                    for (final g in asyncGroups.value!)
                      _GroupStatRow(group: g),
                    const SizedBox(height: 12),
                  ],
                  SectionHeader(
                    title: '工时明细（${list.length} 条）',
                    icon: Icons.list_alt_outlined,
                  ),
                  for (final log in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: WorkLogTile(
                        log: log,
                        projectName: nameMap[log.projectId] ?? '（已删除项目）',
                        onTap: () => _openForm(context, log: log),
                        onLongPress: () => _confirmDelete(context, ref, log),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('记工时'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {WorkLog? log}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => WorkLogFormPage(log: log)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkLog log,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除工时记录',
      message: '确定删除这条工时记录吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(workLogActionsProvider).remove(log.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 一个项目的工时合计行
class _GroupStatRow extends StatelessWidget {
  const _GroupStatRow({required this.group});

  final WorkLogGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            '${group.logCount} 条',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            group.durationText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: AppTypography.titleWeight,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 工时筛选条：项目 + 日期范围（本周 / 本月 / 全部）
class _WorkLogFilterBar extends ConsumerWidget {
  const _WorkLogFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(workLogFilterProvider);
    final notifier = ref.read(workLogFilterProvider.notifier);
    final asyncProjects = ref.watch(projectListProvider);
    final projects = asyncProjects.value ?? const <Project>[];

    final hasRange = filter.start != null || filter.end != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部日期'),
                  selected: !hasRange,
                  onSelected: (_) => notifier.setRange(),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本周'),
                  selected: hasRange && _isThisWeek(filter),
                  onSelected: (selected) {
                    if (!selected) {
                      notifier.setRange();
                      return;
                    }
                    final r = _thisWeekRange();
                    notifier.setRange(start: r.$1, end: r.$2);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本月'),
                  selected: hasRange && _isThisMonth(filter),
                  onSelected: (selected) {
                    if (!selected) {
                      notifier.setRange();
                      return;
                    }
                    final r = _thisMonthRange();
                    notifier.setRange(start: r.$1, end: r.$2);
                  },
                ),
              ],
            ),
          ),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部项目'),
                    selected: filter.projectId == null,
                    onSelected: (_) => notifier.setProject(null),
                  ),
                  for (final p in projects) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(p.name),
                      selected: filter.projectId == p.id,
                      onSelected: (selected) =>
                          notifier.setProject(selected ? p.id : null),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 本周范围（周一 ~ 下周一）
  (DateTime, DateTime) _thisWeekRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    return (start, start.add(const Duration(days: 7)));
  }

  /// 本月范围（1 号 ~ 下月 1 号）
  (DateTime, DateTime) _thisMonthRange() {
    final now = DateTime.now();
    return (
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month + 1, 1),
    );
  }

  bool _isThisWeek(WorkLogFilter f) {
    final r = _thisWeekRange();
    return f.start == r.$1 && f.end == r.$2;
  }

  bool _isThisMonth(WorkLogFilter f) {
    final r = _thisMonthRange();
    return f.start == r.$1 && f.end == r.$2;
  }
}
