import 'package:flutter/material.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/scene_tag.dart';

/// 单条笔记卡片：标题 + 正文摘要 + 场景 + 更新时间。
///
/// [keyword] 非空时，标题与正文里命中的片段会**高亮显示** ——
/// 这是"搜索命中"最直观的反馈，也是用户判断"为什么这条被搜出来"的依据。
class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.note,
    this.keyword,
    this.onTap,
    this.onLongPress,
  });

  final Note note;

  /// 当前搜索关键字；用于高亮命中片段
  final String? keyword;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scene = Scene.fromCode(note.scene);
    final body = note.content.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HighlightedText(
                text: note.title,
                keyword: keyword,
                maxLines: 2,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppTypography.titleWeight,
                ),
                highlightStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppTypography.titleWeight,
                  color: scheme.onSurface,
                  backgroundColor: scheme.primaryContainer,
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                _HighlightedText(
                  text: body,
                  keyword: keyword,
                  maxLines: 3,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  highlightStyle: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    backgroundColor: scheme.primaryContainer,
                    fontWeight: AppTypography.titleWeight,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SceneTag(scene: scene, dense: true),
                  _metaText(
                    context,
                    '更新于 ${FormatUtils.friendlyDate(note.updatedAt)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// 把 [text] 中所有 [keyword] 出现处用 [highlightStyle] 渲染。
///
/// 不区分大小写；[keyword] 为空时退化为普通 [Text]。
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.keyword,
    required this.style,
    required this.highlightStyle,
    this.maxLines,
  });

  final String text;
  final String? keyword;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final kw = keyword?.trim();
    if (kw == null || kw.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final lowerKw = kw.toLowerCase();
    var start = 0;

    while (true) {
      final idx = lower.indexOf(lowerKw, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: highlightStyle,
        ),
      );
      start = idx + kw.length;
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
