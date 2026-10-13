import 'package:flutter/material.dart';

import '../../../../../core/database/database.dart';
import '../../../../../core/models/enums.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/format_utils.dart';
import '../../../providers/study_providers.dart';

/// 图书列表项：书名 / 作者 / 进度条 / 页码 / 状态 / 评分。
///
/// 【点击 vs 长按】点击进入编辑，长按删除（与待办 / 记账一致）。
class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    this.onTap,
    this.onLongPress,
  });

  final Book book;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 各状态对应的强调色
  static Color statusColor(BuildContext context, BookStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case BookStatus.reading:
        return isDark ? const Color(0xFF7FB3E8) : const Color(0xFF2E6CB5);
      case BookStatus.finished:
        return isDark ? const Color(0xFF8CD9A8) : const Color(0xFF2E8B57);
      case BookStatus.paused:
        return isDark ? const Color(0xFFB0A9A0) : const Color(0xFF7A7069);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = BookStatus.fromCode(book.status);
    final color = statusColor(context, status);
    final progress = bookProgress(book);
    final hasPages = book.totalPages > 0;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(label: status.label, color: color),
                ],
              ),
              if (book.author != null && book.author!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  book.author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              if (hasPages) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasPages
                          ? '${book.currentPage} / ${book.totalPages} 页'
                          : '未填写页数',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (hasPages)
                    Text(
                      FormatUtils.percent(progress),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(
                              color: color,
                              fontWeight: AppTypography.titleWeight),
                    ),
                  if (book.rating != null) ...[
                    const SizedBox(width: 10),
                    _RatingStars(rating: book.rating!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态小胶囊
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: AppTypography.titleWeight,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 1-5 星评分展示（只读）
class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star : Icons.star_border,
            size: 14,
            color: i <= rating ? color : color.withValues(alpha: 0.35),
          ),
      ],
    );
  }
}
