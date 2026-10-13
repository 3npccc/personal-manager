import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../providers/study_providers.dart';
import 'checkin_form_page.dart';
import 'widgets/checkin_calendar.dart';

/// 学习打卡 Tab：连续天数卡 + 本月统计 + 月历 + 打卡记录列表。
class CheckinPage extends ConsumerWidget {
  const CheckinPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(checkinMonthProvider);
    final asyncMonth = ref.watch(checkinMonthListProvider);
    final asyncSummary = ref.watch(monthCheckinSummaryProvider);
    final asyncStreak = ref.watch(checkinStreakProvider);
    final asyncList = ref.watch(checkinListProvider);

    // 日历打点：只要月份记录
    final checkedDays = <DateTime>{
      for (final r in asyncMonth.value ?? const <StudyCheckin>[])
        dayStart(r.date),
    };

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          // 连续打卡 + 本月统计
          Row(
            children: [
              Expanded(
                child: StatCard(
                  dense: true,
                  icon: Icons.local_fire_department,
                  label: '连续打卡',
                  value: asyncStreak.when(
                    loading: () => '—',
                    error: (_, _) => '—',
                    data: (n) => '$n 天',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  dense: true,
                  icon: Icons.check_circle_outline,
                  label: '本月打卡',
                  value: asyncSummary.when(
                    loading: () => '—',
                    error: (_, _) => '—',
                    data: (s) => '${s.days} 天',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  dense: true,
                  icon: Icons.timer_outlined,
                  label: '本月时长',
                  value: asyncSummary.when(
                    loading: () => '—',
                    error: (_, _) => '—',
                    data: (s) => FormatUtils.minutes(s.totalMinutes),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 月份切换 + 日历
          SectionHeader(
            title: '${month.year} 年 ${month.month} 月',
            icon: Icons.calendar_month,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '上个月',
                  onPressed: () => ref
                      .read(checkinMonthProvider.notifier)
                      .previousMonth(),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () =>
                      ref.read(checkinMonthProvider.notifier).nextMonth(),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CheckinCalendar(
                month: month,
                checkedDays: checkedDays,
              ),
            ),
          ),
          const SizedBox(height: 20),

          const SectionHeader(title: '打卡记录', icon: Icons.event_note),
          AsyncValueView<List<StudyCheckin>>(
            value: asyncList,
            isEmpty: (list) => list.isEmpty,
            empty: const EmptyState(
              icon: Icons.event_available_outlined,
              title: '还没有打卡记录',
              subtitle: '点右下角「今日打卡」记下今天的学习',
            ),
            data: (list) => Column(
              children: [
                for (final entry in list) ...[
                  _CheckinTile(
                    entry: entry,
                    onTap: () => _openForm(context, entry: entry),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.event_available),
        label: const Text('今日打卡'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {StudyCheckin? entry}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => CheckinFormPage(entry: entry)),
    );
  }
}

/// 单条打卡记录
class _CheckinTile extends StatelessWidget {
  const _CheckinTile({required this.entry, this.onTap});

  final StudyCheckin entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = isSameDay(entry.date, DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                entry.goalMet
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: entry.goalMet ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isToday
                              ? '今天'
                              : FormatUtils.date(entry.date),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          FormatUtils.minutes(entry.minutes),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                    ),
                    if (entry.content.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
