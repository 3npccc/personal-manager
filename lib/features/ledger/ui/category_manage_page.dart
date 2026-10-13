import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/motion.dart';
import '../providers/ledger_providers.dart';

/// 分类管理页：收入 / 支出两个 Tab，各自列出分类。
///
/// 【业务规则】
/// - 内置分类（`isCustom == false`）只能改名，不能删除。
/// - 自定义分类可以删除；但**被记账记录引用的分类禁止删除**。
class CategoryManagePage extends ConsumerWidget {
  const CategoryManagePage({super.key, this.initialType = LedgerType.expense});

  /// 打开时默认停留的 Tab
  final LedgerType initialType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: LedgerType.values.length,
      initialIndex: LedgerType.values.indexOf(initialType),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分类管理'),
          bottom: TabBar(
            tabs: [
              for (final t in LedgerType.values) Tab(text: t.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in LedgerType.values) _CategoryTab(type: t),
          ],
        ),
      ),
    );
  }
}

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.type});

  final LedgerType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(categoryListProvider(type.code));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增分类'),
      ),
      body: AsyncValueView<List<Category>>(
        value: asyncList,
        isEmpty: (list) => list.isEmpty,
        empty: const EmptyState(
          icon: Icons.category_outlined,
          title: '还没有分类',
          subtitle: '点右下角「新增分类」开始添加',
        ),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final category = list[index];
            return StaggeredListItem(
              index: index,
              child: ListTile(
                leading: Icon(
                  category.isCustom
                      ? Icons.label_outline
                      : Icons.label_important_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(category.name),
                subtitle: Text(category.isCustom ? '自定义' : '内置'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '重命名',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openEditor(
                        context,
                        ref,
                        category: category,
                      ),
                    ),
                    IconButton(
                      tooltip: category.isCustom ? '删除' : '内置分类不可删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: category.isCustom
                          ? () => _confirmDelete(context, ref, category)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 新增 / 重命名分类。用对话框收集名称，避免再开一个整页。
  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(
        title: category == null ? '新增${type.label}分类' : '重命名分类',
        initialName: category?.name ?? '',
      ),
    );
    if (name == null || !context.mounted) return;

    final actions = ref.read(categoryActionsProvider);
    try {
      if (category == null) {
        await actions.create(type: type, name: name);
      } else {
        await actions.rename(category: category, name: name);
      }
    } on ArgumentError catch (e) {
      if (!context.mounted) return;
      // `ArgumentError.toString()` 会带 "Invalid argument(s): " 前缀，
      // 这里剥掉，只把业务文案给用户看。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Invalid argument(s): ', '')),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除分类',
      message: '确定删除「${category.name}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;

    final removed =
        await ref.read(categoryActionsProvider).remove(category.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? '已删除「${category.name}」'
              : '「${category.name}」已被记账记录引用，无法删除',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 分类名称输入对话框。
///
/// 【为什么单独抽成一个 StatefulWidget，而不在 `_openEditor` 里
///  用局部变量持有 controller】
/// 局部变量写法需要在 `await showDialog(...)` 之后手动 `dispose()`。
/// 但那时对话框的退场动画**还没播完**，`TextFormField` 仍挂在树上，
/// 提前 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
/// 把它做成 StatefulWidget，让 `dispose()` 由框架在**真正卸载后**调用，
/// 既无泄漏也不会有时序问题。
class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.initialName,
  });

  final String title;
  final String initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: '分类名称',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            final text = (v ?? '').trim();
            if (text.isEmpty) return '请输入分类名称';
            if (text.length > 50) return '名称不能超过 50 字';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
