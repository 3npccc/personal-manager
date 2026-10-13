import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/work_providers.dart';
import 'journal_form_page.dart';

/// 日志 Tab：关键字搜索 + 项目筛选 + 日志列表 + 新增。
class JournalListPage extends ConsumerStatefulWidget {
  const JournalListPage({super.key});

  @override
  ConsumerState<JournalListPage> createState() => _JournalListPageState();
}

class _JournalListPageState extends ConsumerState<JournalListPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(journalListProvider);
    final filter = ref.watch(journalFilterProvider);
    final asyncProjects = ref.watch(projectListProvider);

    final nameMap = <int, String>{
      for (final p in asyncProjects.value ?? const <Project>[]) p.id: p.name,
    };

    return Scaffold(
      body: Column(
        children: [
          _JournalFilterBar(searchCtrl: _searchCtrl),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<List<WorkJournal>>(
              value: asyncList,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: filter.isUnfiltered
                    ? Icons.edit_note_outlined
                    : Icons.search_off,
                title: filter.isUnfiltered ? '还没有工作日志' : '没有符合条件的日志',
                subtitle: filter.isUnfiltered
                    ? '点右下角「写日志」记录今天的工作'
                    : '试试换个关键字',
                action: filter.isUnfiltered
                    ? null
                    : FilledButton.tonal(
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(journalFilterProvider.notifier).reset();
                        },
                        child: const Text('重置筛选'),
                      ),
              ),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final journal = list[index];
                  return StaggeredListItem(
                    index: index,
                    child: _JournalTile(
                      journal: journal,
                      projectName: journal.projectId == null
                          ? null
                          : (nameMap[journal.projectId] ?? '（已删除项目）'),
                      onTap: () => _openForm(context, journal: journal),
                      onLongPress: () => _confirmDelete(context, ref, journal),
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
        label: const Text('写日志'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {WorkJournal? journal}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JournalFormPage(journal: journal),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkJournal journal,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除日志',
      message: '确定删除这条工作日志吗？此操作不可撤销。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(journalActionsProvider).remove(journal.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}

/// 日志列表项：日期 / 项目标签 / 内容 / 成果 / 问题
class _JournalTile extends StatelessWidget {
  const _JournalTile({
    required this.journal,
    this.projectName,
    this.onTap,
    this.onLongPress,
  });

  final WorkJournal journal;

  /// 关联项目名；null = 未关联
  final String? projectName;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    FormatUtils.date(journal.date),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: AppTypography.titleWeight,
                    ),
                  ),
                  if (projectName != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          projectName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: scheme.onSecondaryContainer,
                            fontWeight: AppTypography.titleWeight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                journal.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              if (journal.achievement != null &&
                  journal.achievement!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SubLine(
                  icon: Icons.emoji_events_outlined,
                  label: '成果',
                  text: journal.achievement!,
                  color: scheme.tertiary,
                ),
              ],
              if (journal.problem != null && journal.problem!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _SubLine(
                  icon: Icons.report_problem_outlined,
                  label: '问题',
                  text: journal.problem!,
                  color: scheme.error,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「成果 / 问题」小行
class _SubLine extends StatelessWidget {
  const _SubLine({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          '$label：',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: AppTypography.titleWeight,
          ),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 日志筛选条：搜索框 + 项目
class _JournalFilterBar extends ConsumerWidget {
  const _JournalFilterBar({required this.searchCtrl});

  final TextEditingController searchCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(journalFilterProvider);
    final notifier = ref.read(journalFilterProvider.notifier);
    final asyncProjects = ref.watch(projectListProvider);
    final projects = asyncProjects.value ?? const <Project>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索内容 / 成果 / 问题',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: filter.keyword.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '清除',
                      onPressed: () {
                        searchCtrl.clear();
                        notifier.setKeyword('');
                      },
                    ),
            ),
            onChanged: (v) => notifier.setKeyword(v),
          ),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部项目'),
                    selected: filter.projectId == null,
                    onSelected: (_) => notifier.setProject(null),
                  ),
                  for (final p in projects) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(p.name),
                      selected: filter.projectId == p.id,
                      onSelected: (selected) =>
                          notifier.setProject(selected ? p.id : null),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
