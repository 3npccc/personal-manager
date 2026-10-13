import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/motion.dart';
import '../providers/todo_providers.dart';
import 'todo_form_page.dart';
import 'widgets/todo_tile.dart';

/// 待办列表页：筛选栏 + 列表 + 新增按钮。
class TodoListPage extends ConsumerWidget {
  const TodoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(todoListProvider);
    final filter = ref.watch(todoFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          IconButton(
            tooltip: '重置筛选',
            onPressed: filter.isUnfiltered
                ? null
                : () => ref.read(todoFilterProvider.notifier).reset(),
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增待办'),
      ),
      body: Column(
        children: [
          const _TodoFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<Todo>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.task_alt
                    : Icons.filter_alt_off_outlined,
                title: filter.isUnfiltered ? '还没有待办' : '没有符合条件的待办',
                subtitle: filter.isUnfiltered
                    ? '点右下角「新增待办」开始记录'
                    : '试试切换筛选条件',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(todoFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final todo = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: TodoTile(
                      todo: todo,
                      onToggle: (value) => ref
                          .read(todoActionsProvider)
                          .toggle(todo.id, value),
                      onTap: () => _openForm(context, ref, todo: todo),
                      onLongPress: () => _confirmDelete(context, ref, todo),
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

  /// 打开新增 / 编辑表单
  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Todo? todo,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TodoFormPage(todo: todo),
      ),
    );
  }

  /// 删除前二次确认
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除待办',
      message: '确定删除「${todo.title}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok) return;
    await ref.read(todoActionsProvider).remove(todo.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 筛选栏：场景 + 完成状态。
///
/// 用两行 ChoiceChip，点已选中的项可取消（回到"全部"）。
class _TodoFilterBar extends ConsumerWidget {
  const _TodoFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(todoFilterProvider);
    final notifier = ref.read(todoFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部场景'),
                  selected: filter.scene == null,
                  onSelected: (_) => notifier.setScene(null),
                ),
                for (final scene in Scene.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(scene.label),
                    selected: filter.scene == scene,
                    onSelected: (selected) =>
                        notifier.setScene(selected ? scene : null),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部状态'),
                  selected: filter.isCompleted == null,
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
        ],
      ),
    );
  }
}
