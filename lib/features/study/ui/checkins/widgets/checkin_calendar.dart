import 'package:flutter/material.dart';

import '../../../../../core/theme/app_typography.dart';

/// 简单月历：7 列网格，标出「今天」与「已打卡」的日子。
///
/// 【为什么自己画而不是用第三方日历包】
/// 需求只要"简单日历视图"，而第三方日历包体积大、样式难统一、
/// 且引入来路不明的依赖违反项目"尽量不用来路不明的第三方插件"的约束。
/// 这里 40 行就能画完，且完全可控。
///
/// 【为什么没有"选中某天"的能力】
/// 打卡的入口只有「今天打卡」—— 补打以前的卡属于数据修补，
/// 不是这个页面的职责（编辑已有记录可走列表长按）。
class CheckinCalendar extends StatelessWidget {
  const CheckinCalendar({
    super.key,
    required this.month,
    required this.checkedDays,
    this.today,
  });

  /// 要显示的月份（只用到 year / month）
  final DateTime month;

  /// 已打卡的日期集合（内部会归一化到当天 00:00 再比较）
  final Set<DateTime> checkedDays;

  /// 「今天」；不传则取 `DateTime.now()`
  final DateTime? today;

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final todayDay = _dayStart(today ?? DateTime.now());

    final firstOfMonth = DateTime(month.year, month.month, 1);
    // Flutter 的 weekday: 1=周一 ... 7=周日。中文日历习惯周一开头。
    final leadingBlanks = firstOfMonth.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final checked = <DateTime>{for (final d in checkedDays) _dayStart(d)};

    const weekLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in weekLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final date = DateTime(month.year, month.month, day);
            return _DayCell(
              day: day,
              checked: checked.contains(date),
              isToday: date == todayDay,
            );
          },
        ),
      ],
    );
  }
}

/// 单日格子：有打卡 → 实心圆底；今天 → 描边
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.checked,
    required this.isToday,
  });

  final int day;
  final bool checked;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bg = checked ? scheme.primary : Colors.transparent;
    final fg = checked ? scheme.onPrimary : scheme.onSurface;
    final border = isToday
        ? Border.all(color: scheme.primary, width: 1.5)
        : null;

    return Semantics(
      label: checked ? '$day 日 已打卡' : '$day 日',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg,
            fontWeight: checked || isToday ? AppTypography.titleWeight : null,
          ),
        ),
      ),
    );
  }
}
