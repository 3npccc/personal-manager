import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../providers/work_providers.dart';

/// 周报 Tab：选时间范围 → 聚合工时 → 补「本周重点 / 下周计划」→ 生成可复制文本。
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _highlightsCtrl = TextEditingController();
  final _plansCtrl = TextEditingController();

  @override
  void dispose() {
    _highlightsCtrl.dispose();
    _plansCtrl.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('周报已复制到剪贴板'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _pickCustomRange() async {
    final notifier = ref.read(reportRangeProvider.notifier);
    final current = ref.read(reportRangeProvider);
    final now = DateTime.now();
    // range.end 是右开区间，界面回填时减一天
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(
        start: current.start,
        end: current.end.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    notifier.setCustom(start: picked.start, end: picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final asyncReport = ref.watch(weeklyReportProvider);
    final range = ref.watch(reportRangeProvider);

    return Scaffold(
      body: Column(
        children: [
          _RangeBar(onPickCustom: _pickCustomRange),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<WeeklyReportData>(
              value: asyncReport,
              isEmpty: (data) => data.isEmpty,
              empty: EmptyState(
                icon: Icons.description_outlined,
                title: '该时间段没有工时记录',
                subtitle: '先到「工时」页记录几天工时，再回来生成周报',
              ),
              data: (data) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  SectionHeader(
                    title: '工时汇总',
                    icon: Icons.hourglass_bottom_outlined,
                    trailing: Text(
                      '共 ${FormatUtils.minutes(data.totalMinutes)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: AppTypography.titleWeight,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  for (final g in data.groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.projectName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            FormatUtils.minutes(g.totalMinutes),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    fontWeight: AppTypography.titleWeight),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: '本周重点',
                    icon: Icons.star_outline,
                  ),
                  TextField(
                    controller: _highlightsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '完成了哪些关键事项？',
                      border: OutlineInputBorder(),
                    ),
                    // 输入变化 → 重新生成文本（handleTextChanged 见下）
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: '下周计划',
                    icon: Icons.flag_outlined,
                  ),
                  TextField(
                    controller: _plansCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '下周打算推进什么？',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: '生成结果（可复制）',
                    icon: Icons.content_copy_outlined,
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      buildReportText(
                        data: data,
                        highlights: _highlightsCtrl.text,
                        plans: _plansCtrl.text,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.6,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _copy(
                      buildReportText(
                        data: data,
                        highlights: _highlightsCtrl.text,
                        plans: _plansCtrl.text,
                      ),
                    ),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制周报'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '范围：${FormatUtils.date(range.start)} ~ '
                    '${FormatUtils.date(range.end.subtract(const Duration(days: 1)))}'
                    '（${range.days} 天）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间范围选择条：本周 / 上周 / 本月 / 自定义
class _RangeBar extends ConsumerWidget {
  const _RangeBar({required this.onPickCustom});

  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final notifier = ref.read(reportRangeProvider.notifier);

    final isThisWeek = range == ReportRange.thisWeek();
    final isLastWeek = range == ReportRange.lastWeek();
    final isThisMonth = range == ReportRange.thisMonth();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('本周'),
              selected: isThisWeek,
              onSelected: (_) => notifier.thisWeek(),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('上周'),
              selected: isLastWeek,
              onSelected: (_) => notifier.lastWeek(),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('本月'),
              selected: isThisMonth,
              onSelected: (_) => notifier.thisMonth(),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('自定义'),
              selected: !isThisWeek && !isLastWeek && !isThisMonth,
              onSelected: (_) => onPickCustom(),
            ),
          ],
        ),
      ),
    );
  }
}
