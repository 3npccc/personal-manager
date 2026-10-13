import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import 'empty_state.dart';

/// 阶段 1 占位页：统一展示"待开发"提示。
/// 阶段 4 开发各业务模块时，逐个替换为真实页面。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    this.description,
    this.plannedFeatures = const <String>[],
  });

  /// 页面标题
  final String title;

  /// 页面图标
  final IconData icon;

  /// 一句话说明
  final String? description;

  /// 计划实现的功能点（给用户看的路线图）
  final List<String> plannedFeatures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: plannedFeatures.isEmpty
          ? EmptyState(
              icon: icon,
              title: '$title（待开发）',
              subtitle: description,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 32, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: AppTypography.titleWeight)),
                            if (description != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  description!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('本页规划功能',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: AppTypography.titleWeight,
                              )),
                          const SizedBox(height: 10),
                          for (final feature in plannedFeatures)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Icon(
                                      Icons.circle,
                                      size: 6,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(feature,
                                        style: theme.textTheme.bodyMedium),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
