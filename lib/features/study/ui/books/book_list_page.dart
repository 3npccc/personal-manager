import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/study_providers.dart';
import 'book_form_page.dart';
import 'widgets/book_tile.dart';

/// 读书 Tab：状态筛选 + 图书列表 + 新增。
class BookListPage extends ConsumerWidget {
  const BookListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(bookListProvider);
    final filter = ref.watch(bookFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _BookFilterBar(),
          const Divider(height: 1),          Expanded(
            child: AsyncValueView<List<Book>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.menu_book_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有书' : '没有符合条件的书',
                subtitle: filter.isUnfiltered
                    ? '点右下角「加本书」记录阅读进度'
                    : '试试切换到其它状态',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(bookFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final book = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: BookTile(
                      book: book,
                      onTap: () => _openForm(context, book: book),
                      onLongPress: () => _confirmDelete(context, ref, book),
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
        label: const Text('加本书'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {Book? book}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => BookFormPage(book: book)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除书籍',
      message: '确定删除《${book.title}》吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(bookActionsProvider).remove(book.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 阅读状态筛选条
class _BookFilterBar extends ConsumerWidget {
  const _BookFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookFilterProvider);
    final notifier = ref.read(bookFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: filter.status == null,
              onSelected: (_) => notifier.setStatus(null),
            ),
            for (final s in BookStatus.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(s.label),
                selected: filter.status == s,
                onSelected: (selected) => notifier.setStatus(selected ? s : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
