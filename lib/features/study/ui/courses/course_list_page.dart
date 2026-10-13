import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/study_providers.dart';
import 'course_form_page.dart';
import 'widgets/course_tile.dart';

/// 课程 Tab：状态筛选 + 课程列表 + 新增。
class CourseListPage extends ConsumerWidget {
  const CourseListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(courseListProvider);
    final filter = ref.watch(courseFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _CourseFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<Course>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.school_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有课程' : '没有符合条件的课程',
                subtitle: filter.isUnfiltered
                    ? '点右下角「加课程」跟踪学习进度'
                    : '试试切换到其它状态',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () =>
                            ref.read(courseFilterProvider.notifier).reset(),
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final course = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: CourseTile(
                      course: course,
                      onTap: () => _openForm(context, course: course),
                      onLongPress: () => _confirmDelete(context, ref, course),
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
        label: const Text('加课程'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {Course? course}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => CourseFormPage(course: course)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Course course,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除课程',
      message: '确定删除「${course.name}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(courseActionsProvider).remove(course.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 课程状态筛选条
class _CourseFilterBar extends ConsumerWidget {
  const _CourseFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(courseFilterProvider);
    final notifier = ref.read(courseFilterProvider.notifier);

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
            for (final s in ProgressStatus.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(s.label),
                selected: filter.status == s,
                onSelected: (selected) =>
                    notifier.setStatus(selected ? s : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
