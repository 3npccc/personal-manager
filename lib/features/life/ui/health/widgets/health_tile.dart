import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/utils/format_utils.dart';
import '../../../providers/life_providers.dart';

/// 健康记录列表项：日期 + 睡眠 / 运动 / 体重。
class HealthTile extends StatelessWidget {
  const HealthTile({
    super.key,
    required this.record,
    this.onTap,
    this.onLongPress,
  });

  final HealthRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                FormatUtils.date(record.date),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      icon: Icons.bedtime_outlined,
                      label: '睡眠',
                      value: sleepHoursText(record.sleepHours),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      icon: Icons.directions_run,
                      label: '运动',
                      value: exerciseText(record.exerciseMinutes),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      icon: Icons.monitor_weight_outlined,
                      label: '体重',
                      value: weightText(record.weightKg),
                    ),
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

/// 单项指标（图标 + 名称 + 数值）
class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
