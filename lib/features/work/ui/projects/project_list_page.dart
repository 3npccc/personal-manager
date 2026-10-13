import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../providers/work_providers.dart';
import 'project_form_page.dart';
import 'widgets/project_tile.dart';

/// 项目 Tab：状态/优先级筛选 + 顶部统计 + 项目列表 + 新增。
class ProjectListPage extends ConsumerWidget {
  const ProjectListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(projectListProvider);
    final filter = ref.watch(projectFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _ProjectFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<Project>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.folder_special_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有项目' : '没有符合条件的项目',
                subtitle: filter.isUnfiltered
                    ? '点右下角「加项目」创建一个'
                    : '试试切换筛选条件',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(projectFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  // 第 0 项是统计条
                  if (index == 0) {
                    return _ProjectSummary(list: list);
                  }
                  final project = list[index - 1];
                  return StaggeredListItem(
                    index: index - 1,
                    child: ProjectTile(
                      project: project,
                      onTap: () => _openForm(context, project: project),
                      onLongPress: () =>
                          _confirmDelete(context, ref, project),
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
        label: const Text('加项目'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {Project? project}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ProjectFormPage(project: project)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除项目',
      message: '确定删除「${project.name}」吗？\n关联的工时记录会一并删除，此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(projectActionsProvider).remove(project.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 顶部统计：项目数 / 进行中 / 已完成
class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.list});

  final List<Project> list;

  @override
  Widget build(BuildContext context) {
    // 统计从已加载列表本地数 —— 不再额外开流查询，避免 FakeAsync 陷阱（C22）
    final ongoing = list
        .where((p) => p.status == ProgressStatus.ongoing.code)
        .length;
    final completed = list
        .where((p) => p.status == ProgressStatus.completed.code)
        .length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: '项目总数',
            value: '${list.length}',
            icon: Icons.folder_special_outlined,
            dense: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '进行中',
            value: '$ongoing',
            icon: Icons.play_circle_outline,
            dense: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '已完成',
            value: '$completed',
            icon: Icons.check_circle_outline,
            dense: true,
          ),
        ),
      ],
    );
  }
}

/// 项目筛选条：状态 + 优先级
class _ProjectFilterBar extends ConsumerWidget {
  const _ProjectFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(projectFilterProvider);
    final notifier = ref.read(projectFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部状态'),
              selected: filter.status == null,
              onSelected: (_) => notifier.setStatus(null),
            ),
            for (final s in ProgressStatus.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(s.label),
                selected: filter.status == s,
                onSelected: (selected) =>
                    notifier.setStatus(selected ? s : null),
              ),
            ],
            const SizedBox(width: 16),
            ChoiceChip(
              label: const Text('全部优先级'),
              selected: filter.priority == null,
              onSelected: (_) => notifier.setPriority(null),
            ),
            for (final p in const <int>[0, 1, 2]) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(projectPriorityLabel(p)),
                selected: filter.priority == p,
                onSelected: (selected) =>
                    notifier.setPriority(selected ? p : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
