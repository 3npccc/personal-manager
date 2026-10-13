import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/motion.dart';
import '../providers/ledger_providers.dart';
import 'category_manage_page.dart';
import 'ledger_form_page.dart';
import 'widgets/ledger_tile.dart';
import 'widgets/monthly_stats_card.dart';

/// 记账页：月度统计卡 + 类型/分类筛选 + 记录列表 + 记一笔。
///
/// 分类名需要按 `categoryId` 反查，因此这里同时监听分类流，
/// 在构建列表时建一个 `id -> name` 的映射表。
class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(ledgerListProvider);
    final asyncCategories = ref.watch(categoryListProvider(null));
    final filter = ref.watch(ledgerFilterProvider);

    // 分类名映射；分类还没加载完时退化成「分类 #id」，
    // 保证列表不会因为分类流慢而整块卡在 loading。
    // 【API 备注】riverpod 3.4.3 的 AsyncValue 只有 `.value`（可空）与
    // `.requireValue`（非空，loading 态会抛），**没有 `valueOrNull`**，
    // 这里用 `.value`。
    final nameById = <int, String>{
      for (final c in asyncCategories.value ?? const <Category>[])
        c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('记账'),
        actions: [
          IconButton(
            tooltip: '重置筛选',
            onPressed: filter.isUnfiltered
                ? null
                : () => ref.read(ledgerFilterProvider.notifier).resetFilters(),
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
          IconButton(
            tooltip: '分类管理',
            onPressed: () => _openCategoryManage(context),
            icon: const Icon(Icons.category_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: Column(
        children: [
          const MonthlyStatsCard(),
          const _LedgerFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<LedgerRecord>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.receipt_long_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '本月还没有记账' : '没有符合条件的记录',
                subtitle: filter.isUnfiltered
                    ? '点右下角「记一笔」开始记录收支'
                    : '试试切换类型 / 分类，或换个月份',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () => ref
                            .read(ledgerFilterProvider.notifier)
                            .resetFilters(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: LedgerTile(
                      record: record,
                      categoryName:
                          nameById[record.categoryId] ?? '分类 #${record.categoryId}',
                      onTap: () => _openForm(context, record: record),
                      onLongPress: () => _confirmDelete(context, ref, record),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {LedgerRecord? record}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LedgerFormPage(record: record),
      ),
    );
  }

  Future<void> _openCategoryManage(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CategoryManagePage(),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LedgerRecord record,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除记录',
      message: '确定删除这条记录吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(ledgerActionsProvider).remove(record.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 类型 + 分类筛选条
class _LedgerFilterBar extends ConsumerWidget {
  const _LedgerFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(ledgerFilterProvider);
    final notifier = ref.read(ledgerFilterProvider.notifier);

    // 只有选定类型时才展示分类下拉 —— 全部分类混在一起太长且无意义。
    final asyncCategories = filter.type == null
        ? null
        : ref.watch(categoriesOfTypeProvider(filter.type!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: filter.type == null,
                    onSelected: (_) => notifier.setType(null),
                  ),
                  for (final t in LedgerType.values) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(t.label),
                      selected: filter.type == t,
                      onSelected: (selected) =>
                          notifier.setType(selected ? t : null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (asyncCategories != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: asyncCategories.when(
                loading: () => const SizedBox(height: 40),
                error: (_, _) => const SizedBox(height: 40),
                data: (categories) {
                  final ids = categories.map((c) => c.id).toSet();
                  final safeValue =
                      (filter.categoryId != null &&
                              ids.contains(filter.categoryId))
                          ? filter.categoryId
                          : null;
                  return DropdownButtonFormField<int>(
                    initialValue: safeValue,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    hint: const Text('全部分类'),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: notifier.setCategory,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
