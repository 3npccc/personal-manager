import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/motion.dart';
import '../providers/note_providers.dart';
import 'note_editor_page.dart';
import 'widgets/note_tile.dart';

/// 笔记列表页：搜索栏 + 场景筛选 + 列表 + 新增按钮。
class NoteListPage extends ConsumerWidget {
  const NoteListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(noteListProvider);
    final filter = ref.watch(noteFilterProvider);
    final searching = filter.normalizedKeyword != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            tooltip: '重置筛选',
            onPressed: filter.isUnfiltered
                ? null
                : () => ref.read(noteFilterProvider.notifier).reset(),
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('新建笔记'),
      ),
      body: Column(
        children: [
          const _NoteSearchBar(),
          const _NoteSceneFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<Note>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.sticky_note_2_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有笔记' : '没有符合条件的笔记',
                subtitle: filter.isUnfiltered
                    ? '点右下角「新建笔记」开始记录'
                    : (searching ? '换个关键字，或试试切换场景' : '试试切换场景'),
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(noteFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final note = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: NoteTile(
                      note: note,
                      keyword: filter.normalizedKeyword,
                      onTap: () => _openEditor(context, note: note),
                      onLongPress: () => _confirmDelete(context, ref, note),
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

  /// 打开新建 / 编辑页
  Future<void> _openEditor(BuildContext context, {Note? note}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorPage(note: note),
      ),
    );
  }

  /// 删除前二次确认
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除笔记',
      message: '确定删除「${note.title}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok) return;
    await ref.read(noteActionsProvider).remove(note.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 搜索栏。
///
/// 【为什么要"提交式"搜索】
/// 见 `note_providers.dart` 中 `NoteFilter` 的注释：逐字符搜索会不断重建
/// drift stream。这里用 `TextEditingController` 持有草稿，只在用户按下
/// 回车 / 点搜索图标 / 点清除时才写回 provider。
class _NoteSearchBar extends ConsumerStatefulWidget {
  const _NoteSearchBar();

  @override
  ConsumerState<_NoteSearchBar> createState() => _NoteSearchBarState();
}

class _NoteSearchBarState extends ConsumerState<_NoteSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(noteFilterProvider.notifier).setKeyword(_controller.text);
    FocusScope.of(context).unfocus();
  }

  void _clear() {
    _controller.clear();
    ref.read(noteFilterProvider.notifier).setKeyword(null);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // 外部（如"重置筛选"）清空关键字时，同步清掉输入框文本。
    final keyword = ref.watch(noteFilterProvider).normalizedKeyword;
    ref.listen<NoteFilter>(noteFilterProvider, (prev, next) {
      final nextKw = next.normalizedKeyword ?? '';
      if (nextKw != _controller.text) {
        _controller.text = nextKw;
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: '搜索标题或正文，回车确认',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: keyword == null
              ? IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _submit,
                )
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.clear),
                  onPressed: _clear,
                ),
        ),
      ),
    );
  }
}

/// 场景筛选：全部 / 学习 / 工作 / 生活
class _NoteSceneFilterBar extends ConsumerWidget {
  const _NoteSceneFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noteFilterProvider);
    final notifier = ref.read(noteFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: SingleChildScrollView(
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
    );
  }
}
