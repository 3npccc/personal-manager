import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// 概览/统计用的数字卡片：一个标签 + 一个大数字 + 可选副文案/图标。
///
/// 颜色约定（跟随全局）：
/// - 传入 [valueColor] 时数字用该色；不传则用主题 onSurface。
/// - 收支场景：收入用红、支出用绿（A股/中式习惯），由调用方传色，
///   本组件不硬编码红绿，避免在其他语义下被误用。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.valueColor,
    this.onTap,
    this.dense = false,
  });

  /// 小标签，如「本月支出」
  final String label;

  /// 主数值文本，已格式化好（如 `¥1,250.00`）
  final String value;

  /// 副文案，如「较上月 +12%」
  final String? subtitle;

  /// 可选的左上角图标
  final IconData? icon;

  /// 数字颜色；不传用主题色
  final Color? valueColor;

  final VoidCallback? onTap;

  /// 紧凑模式：更小的字号与内边距，用于横排放多个卡片
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = (dense
            ? theme.textTheme.titleMedium
            : theme.textTheme.headlineSmall)
        ?.copyWith(
      fontWeight: AppTypography.titleWeight,
      color: valueColor ?? scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final content = Padding(
      padding: EdgeInsets.all(dense ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: dense ? 14 : 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (dense
                          ? theme.textTheme.labelSmall
                          : theme.textTheme.labelMedium)
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 6 : 10),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}
