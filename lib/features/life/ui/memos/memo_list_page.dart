import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/life_providers.dart';
import 'memo_form_page.dart';
import 'widgets/memo_tile.dart';

/// 备忘 Tab：筛选条（全部 / 未完成 / 已完成）+ 列表 + 新增。
class MemoListPage extends ConsumerWidget {
  const MemoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(memoListProvider);
    final filter = ref.watch(memoFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _MemoFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<LifeMemo>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.push_pin_outlined
                    : Icons.checklist_rtl,
                title: filter.isUnfiltered ? '还没有备忘' : '这里没有备忘',
                subtitle: filter.isUnfiltered
                    ? '点右下角「加备忘」记一条'
                    : '换个筛选条件看看',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(memoFilterProvider.notifier).reset(),
                        child: const Text('显示全部'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final memo = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: MemoTile(
                      memo: memo,
                      onToggle: (v) =>
                          ref.read(memoActionsProvider).toggleCompleted(
                                memo.id,
                                v,
                              ),
                      onTap: () => _openForm(context, memo: memo),
                      onLongPress: () => _confirmDelete(context, ref, memo),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('加备忘'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {LifeMemo? memo}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => MemoFormPage(memo: memo)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LifeMemo memo,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除备忘',
      message: '确定删除「${memo.title}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(memoActionsProvider).remove(memo.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 完成状态筛选：全部 / 未完成 / 已完成
class _MemoFilterBar extends ConsumerWidget {
  const _MemoFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(memoFilterProvider);
    final notifier = ref.read(memoFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: filter.isUnfiltered,
              onSelected: (_) => notifier.setCompleted(null),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('未完成'),
              selected: filter.isCompleted == false,
              onSelected: (selected) =>
                  notifier.setCompleted(selected ? false : null),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('已完成'),
              selected: filter.isCompleted == true,
              onSelected: (selected) =>
                  notifier.setCompleted(selected ? true : null),
            ),
          ],
        ),
      ),
    );
  }
}
