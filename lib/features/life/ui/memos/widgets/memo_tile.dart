import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/format_utils.dart';

/// 单条生活备忘卡片：勾选框 + 标题 + 内容摘要 + 提醒时间。
///
/// 【为什么用 `Card` + `InkWell` 而不是 `AppCard`】
/// `AppCard` 只有 `onTap`，不支持 `onLongPress`；本卡片需要长按删除
/// （与 4.1~4.5 的列表项一致，C42）。
///
/// 【勾选框语义】点勾选框 = 切换完成状态；点卡片 = 打开编辑。
/// 两者职责分开，避免"想编辑却误标完成"。
class MemoTile extends StatelessWidget {
  const MemoTile({
    super.key,
    required this.memo,
    required this.onToggle,
    this.onTap,
    this.onLongPress,
  });

  final LifeMemo memo;

  /// 切换完成状态
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = memo.content.trim();
    final done = memo.isCompleted;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: done,
                onChanged: (v) => onToggle(v ?? false),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memo.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: AppTypography.titleWeight,
                          // 已完成 → 标题加删除线，一眼可见
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _meta(
                            context,
                            '创建于 ${FormatUtils.date(memo.createdAt)}',
                          ),
                          if (memo.remindAt != null)
                            _remind(context, memo.remindAt!),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  /// 提醒时间标签。
  ///
  /// 【第一版仅展示】不做系统通知（见需求说明书的范围界定）；
  /// 过期未完成的用 error 色提示，方便一眼看到。
  Widget _remind(BuildContext context, DateTime remindAt) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = !memo.isCompleted && remindAt.isBefore(DateTime.now());

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.alarm,
          size: 13,
          color: overdue ? scheme.error : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          FormatUtils.dateTime(remindAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: overdue ? scheme.error : scheme.onSurfaceVariant,
            fontWeight: overdue ? AppTypography.titleWeight : null,
          ),
        ),
      ],
    );
  }
}
