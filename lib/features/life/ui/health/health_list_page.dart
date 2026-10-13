import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/motion.dart';
import '../../providers/life_providers.dart';
import 'health_form_page.dart';
import 'widgets/health_tile.dart';

/// 健康 Tab：按日期倒序的健康记录列表 + 新增。
///
/// 【同日一条规则】由 `HealthActions.upsert` 保证：同一天再录会
/// **更新**已有的那条，而不是新增（`findByDate` 只返回一条）。
class HealthListPage extends ConsumerWidget {
  const HealthListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(healthRecordListProvider);

    return Scaffold(
      body: AsyncValueView<List<HealthRecord>>(
        value: asyncList,
        isEmpty: (list) => list.isEmpty,
        empty: const EmptyState(
          icon: Icons.monitor_heart_outlined,
          title: '还没有健康记录',
          subtitle: '点右下角「记健康」记录今天的睡眠与运动',
        ),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final record = list[index];
            return StaggeredListItem(
              index: index,
              child: HealthTile(
                record: record,
                onTap: () => _openForm(context, record: record),
                onLongPress: () => _confirmDelete(context, ref, record),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('记健康'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {HealthRecord? record}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HealthFormPage(record: record),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    HealthRecord record,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除记录',
      message: '确定删除这条健康记录吗？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(healthActionsProvider).remove(record.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }
}
