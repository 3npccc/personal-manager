import 'package:flutter/material.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';

/// 单条记账记录。
///
/// 左侧是分类名与备注，右侧是带正负号的金额 —— 收入 `+`、支出 `-`。
///
/// 【颜色约定】遵循中式（A 股）习惯：收入红、支出绿。
class LedgerTile extends StatelessWidget {
  const LedgerTile({
    super.key,
    required this.record,
    required this.categoryName,
    this.onTap,
    this.onLongPress,
  });

  final LedgerRecord record;

  /// 分类名由调用方传入 —— 记录表只存 `categoryId`，
  /// 分类流是另一条数据来源，在这里再查一次会多一层异步分支。
  final String categoryName;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 收入红：0xD32F2F
  static const Color incomeColor = Color(0xFFD32F2F);

  /// 支出绿：0x2E7D32
  static const Color expenseColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = LedgerType.fromCode(record.type);
    final isIncome = type == LedgerType.income;
    final color = isIncome ? incomeColor : expenseColor;
    final sign = isIncome ? '+' : '-';
    final scene = record.scene == null ? null : Scene.fromCode(record.scene);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(
                  isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: AppTypography.titleWeight,
                            ),
                          ),
                        ),
                        if (scene != null) ...[
                          const SizedBox(width: 6),
                          _SceneTag(scene: scene),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        FormatUtils.date(record.recordDate),
                        if ((record.note ?? '').isNotEmpty) record.note!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${FormatUtils.centsToYuan(record.amountCents, withSymbol: true)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: AppTypography.titleWeight,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 场景小标签（学习 / 工作 / 生活）
class _SceneTag extends StatelessWidget {
  const _SceneTag({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        scene.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
      ),
    );
  }
}
