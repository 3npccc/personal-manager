import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// 区块标题：小图标 + 标题 + 可选 trailing（如「查看全部」按钮）。
///
/// 用于把长页面切成语义清晰的若干块，避免通篇一个样式。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 12),
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 分组卡片：把一组设置项/表单项包在一个 Card 里，带可选标题。
///
/// 适合「设置」页这种"分组 + 纵向排列的条目"的版式。
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.title,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title!,
              style: AppTextStyles.fieldLabel(context),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
