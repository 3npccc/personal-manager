import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/ledger_dao.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../providers/ledger_providers.dart';

/// 月度统计卡片：月份切换 + 收入 / 支出 / 结余三块数字。
///
/// 【颜色约定】遵循中式（A 股）习惯：
/// 收入 = 红、支出 = 绿。结余按正负取同色系
/// （正数红、负数绿、零用主题中性色）。
class MonthlyStatsCard extends ConsumerWidget {
  const MonthlyStatsCard({super.key});

  /// 收入色（红）
  static const Color incomeColor = Color(0xFFD32F2F);

  /// 支出色（绿）
  static const Color expenseColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(ledgerFilterProvider).month;
    final asyncSummary = ref.watch(monthlySummaryProvider);
    final notifier = ref.read(ledgerFilterProvider.notifier);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            _MonthSwitcher(
              month: month,
              onPrevious: notifier.previousMonth,
              onNext: notifier.nextMonth,
              onReset: notifier.resetMonth,
            ),
            const SizedBox(height: 8),
            asyncSummary.when(
              loading: () => const SizedBox(
                height: 72,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 72,
                child: Center(child: Text('统计失败：$e')),
              ),
              data: (s) => _StatsRow(summary: s),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onReset,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final isThisMonth = isCurrentMonth(month);
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Text(
              FormatUtils.month(month),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: AppTypography.titleWeight,
                  ),
            ),
          ),
        ),
        if (!isThisMonth)
          IconButton(
            tooltip: '回到本月',
            onPressed: onReset,
            icon: const Icon(Icons.today_outlined),
          ),
        IconButton(
          tooltip: '下个月',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});

  final LedgerSummary summary;

  @override
  Widget build(BuildContext context) {
    final balance = summary.balanceCents;
    final balanceColor = balance > 0
        ? MonthlyStatsCard.incomeColor
        : (balance < 0 ? MonthlyStatsCard.expenseColor : null);

    // 【为什么用 IntrinsicHeight + stretch】
    // 三张卡片的文案长度不同（「¥9200.50」比「¥0.00」宽），
    // 若各按自身高度渲染，卡片高度会参差不齐、视觉上很乱。
    // `Row` 的 `CrossAxisAlignment.stretch` 需要行有确定高度才生效，
    // 而这里的行高由子项决定 —— 用 `IntrinsicHeight` 先把行高定下来，
    // 再 stretch，三张卡就等高。子项只有 3 个、极浅，无性能顾虑。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatCard(
              dense: true,
              label: '收入',
              value: FormatUtils.centsToYuan(
                summary.incomeCents,
                withSymbol: true,
              ),
              valueColor: MonthlyStatsCard.incomeColor,
              icon: Icons.trending_up,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatCard(
              dense: true,
              label: '支出',
              value: FormatUtils.centsToYuan(
                summary.expenseCents,
                withSymbol: true,
              ),
              valueColor: MonthlyStatsCard.expenseColor,
              icon: Icons.trending_down,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatCard(
              dense: true,
              label: '结余',
              value: FormatUtils.centsToYuan(balance, withSymbol: true),
              valueColor: balanceColor,
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
