import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../providers/life_providers.dart';

/// 单个习惯卡片：名称 + 频率标签 + 连续天数 + 今日打卡按钮。
///
/// 【为什么不直接用 `AppCard`】`AppCard` 只支持 `onTap`，不支持
/// `onLongPress`；本卡片需要长按删除（与 4.1~4.5 的列表项一致），
/// 故按 `WorkLogTile` 的写法用 `Card` + `InkWell` 直接拼。
///
/// 【为什么要传 `streak` / `checkedToday` 而不是自己 watch】
/// 卡片会被列表大量复用；若每张卡各自 `ref.watch(streakProvider)`，
/// 一次列表刷新会触发 N 次独立异步查询。由列表统一查好再透传，
/// 既减少查询，也让测试可以只测列表页。
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.habit,
    required this.streak,
    required this.checkedToday,
    required this.onTap,
    required this.onToggleToday,
    required this.onLongPress,
  });

  final Habit habit;
  final int streak;
  final bool checkedToday;
  final VoidCallback onTap;
  final VoidCallback onToggleToday;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frequency = HabitFrequency.fromCode(habit.frequency);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconButton(
                tooltip: checkedToday ? '取消今日打卡' : '今日打卡',
                onPressed: onToggleToday,
                icon: Icon(
                  checkedToday
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: checkedToday ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(habit.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Tag(text: frequency.label),
                        const SizedBox(width: 8),
                        Text(
                          streak > 0 ? '连续 $streak 天' : '还没有连续记录',
                          style: theme.textTheme.bodySmall,
                        ),
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

/// 小标签
class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
