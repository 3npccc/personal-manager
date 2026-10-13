import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/widgets/section_header.dart';

/// 设置页：主题 / 货币符号 / 数据位置 / 关于。
///
/// 本页是阶段 3 的「UI 能通过 provider 读写数据」验收点：
/// - 主题切换 → 立即作用于全应用（MaterialApp.themeMode）
/// - 货币符号 → 立即持久化，重启保留
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currencySymbol = ref.watch(currencySymbolProvider);
    final settings = ref.watch(settingsServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const SectionHeader(title: '外观', icon: Icons.palette_outlined),
          GroupCard(
            children: [
              _ThemeModeTile(current: themeMode),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: '记账偏好',
            icon: Icons.currency_yen,
          ),
          GroupCard(
            children: [
              _CurrencyTile(current: currencySymbol),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '数据', icon: Icons.storage_outlined),
          GroupCard(
            children: [
              const _InfoTile(
                icon: Icons.shield_outlined,
                title: '数据全部保存在本机',
                subtitle: '程序不联网、不上传任何数据，请放心使用',
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.folder_outlined,
                title: '数据库位置',
                subtitle: settings.databasePath ?? '（未能获取，不影响使用）',
                selectable: settings.databasePath != null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '关于', icon: Icons.info_outline),
          const GroupCard(
            children: [
              _InfoTile(
                icon: Icons.apps_outlined,
                title: '个人管理',
                subtitle: '版本 1.0.0（第一版）',
              ),
              Divider(height: 1),
              _InfoTile(
                icon: Icons.memory_outlined,
                title: '技术栈',
                subtitle: 'Flutter · SQLite(drift) · Riverpod · Material 3',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主题模式三选一
class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile({required this.current});

  final ThemeMode current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.brightness_6_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text('主题模式', style: theme.textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('跟随系统'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('深色'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: <ThemeMode>{current},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              ref.read(themeModeProvider.notifier).set(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

/// 货币符号：常用符号快捷选择 + 自定义输入
class _CurrencyTile extends ConsumerStatefulWidget {
  const _CurrencyTile({required this.current});

  final String current;

  @override
  ConsumerState<_CurrencyTile> createState() => _CurrencyTileState();
}

class _CurrencyTileState extends ConsumerState<_CurrencyTile> {
  /// 常用货币符号
  static const List<String> _presets = <String>['¥', '\$', '€', '£'];

  late final TextEditingController _controller =
      TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String symbol) async {
    await ref.read(currencySymbolProvider.notifier).set(symbol);
    if (!mounted) return;
    // 同步回输入框，反映规范化后的值（空输入会回退为 ¥）
    _controller.text = ref.read(currencySymbolProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(currencySymbolProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.currency_yen,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text('货币符号', style: theme.textTheme.bodyLarge),
              const Spacer(),
              Text(
                '当前：$current',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final symbol in _presets)
                ChoiceChip(
                  label: Text(symbol),
                  selected: current == symbol,
                  onSelected: (_) => _apply(symbol),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: '自定义符号',
                    counterText: '',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: _apply,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () => _apply(_controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 只读信息行：图标 + 标题 + 副文本
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selectable = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 是否允许选中复制（路径这类长文本有用）
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 3),
                selectable
                    ? SelectableText(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
