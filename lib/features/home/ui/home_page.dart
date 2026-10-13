import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/ledger_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/scene_tag.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../todos/providers/todo_providers.dart';
import '../../todos/ui/todo_form_page.dart';
import '../../todos/ui/widgets/todo_tile.dart';
import '../providers/home_providers.dart';

/// 概览页三块统计区块的定位键。
///
/// 【为什么需要它们】三块区块内部都用 [StatCard] 渲染数字，
/// 会出现**多个值完全相同的 `Text`**（如待办 0 与工作场景 0 都是 `"0"`）。
/// 测试若只写 `find.text('0')` 会把全页同值文本一起数进来，
/// 断言就变成了"碰运气"。用 key 把断言限定到目标区块内，
/// 既精确又让页面结构自描述（规则 22：绝不用 `findsWidgets` 含糊断言）。
const Key homeTodayTodoSectionKey = ValueKey('home-section-today-todos');
const Key homeMonthlyLedgerSectionKey = ValueKey('home-section-monthly-ledger');
const Key homeNoteStatsSectionKey = ValueKey('home-section-note-stats');
const Key homeQuickActionsKey = ValueKey('home-section-quick-actions');

/// 概览首页（阶段 4.7）。
///
/// 【范围（用户已确认：先做三块基础）】
///   1. 今日待办 —— 数量 + 列表 + 可直接勾选；
///   2. 本月收支 —— 收入 / 支出 / 结余；
///   3. 笔记统计 —— 总数 + 按场景拆分；
///   4. 四个快速新增入口 —— 待办 / 笔记 / 记一笔 / 打卡。
///
/// 【跨模块聚合暂缓】「进行中项目数」「今日是否打卡」等留到 4.8 之后。
///
/// 【为什么所有统计都用 `AsyncValueView` 包起来】
/// 首页在 AppShell 的 `IndexedStack` 里**永远被构建**（见 5.5），
/// 因此它对数据源的加载状态最敏感。统一三态视图能避免"数字闪成 0
/// 又跳回真实值"这类观感问题。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('概览'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _refresh(context, ref),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const <Widget>[
          _QuickActions(),
          SizedBox(height: 8),
          _TodayTodoSection(),
          SizedBox(height: 8),
          _MonthlyLedgerSection(),
          SizedBox(height: 8),
          _NoteStatsSection(),
        ],
      ),
    );
  }

  /// 手动刷新：把首页依赖的统计 provider 全部 invalidate。
  ///
  /// 【为什么需要它】流式 provider 本就会自动推送，正常不需要刷新。
  /// 但用户从"跟当前月无关"的页面切换月份等边缘情况下，
  /// 手动兜底一次能让观感更确定（且成本极低）。
  void _refresh(BuildContext context, WidgetRef ref) {
    ref.invalidate(homeTodayTodosProvider);
    ref.invalidate(homeTodoTotalProvider);
    ref.invalidate(homeMonthlySummaryProvider);
    ref.invalidate(homeNoteTotalProvider);
    ref.invalidate(homeNoteCountBySceneProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已刷新'), duration: Duration(seconds: 1)),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 块 ④ 快速新增入口
/// ---------------------------------------------------------------------------

/// 四个快速入口：待办 / 笔记 / 记一笔 / 打卡。
///
/// 【"打卡"入口的实现说明】
/// 本阶段只做「跳到生活页的习惯 Tab」—— 不直接弹打卡表单，
/// 因为打卡必须绑定到某个具体习惯。跳过去由用户在习惯列表里点，
/// 语义更清晰，也避免首页引入对 4.6 表单的耦合。
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: homeQuickActionsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '快速新增', icon: Icons.bolt_outlined),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.add_task,
                label: '待办',
                onTap: () => _openTodoForm(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.note_add_outlined,
                label: '笔记',
                onTap: () => _goTo(context, ref, 'notes'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.account_balance_wallet_outlined,
                label: '记一笔',
                onTap: () => _goTo(context, ref, 'ledger'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.favorite_outline,
                label: '打卡',
                onTap: () => _goTo(context, ref, 'life'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 打开「新增待办」表单（复制 4.1 的入口，不改 4.1 的页面）
  Future<void> _openTodoForm(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TodoFormPage()),
    );
  }

  /// 切换到某个导航页（首页 → 其它页）
  void _goTo(BuildContext context, WidgetRef ref, String navId) {
    ref.read(navIndexProvider.notifier).selectById(navId);
  }
}

/// 单个快速入口按钮
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 块 ① 今日待办
/// ---------------------------------------------------------------------------

class _TodayTodoSection extends ConsumerWidget {
  const _TodayTodoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncToday = ref.watch(homeTodayTodosProvider);
    final totalAsync = ref.watch(homeTodoTotalProvider);

    return Column(
      key: homeTodayTodoSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '今日待办',
          icon: Icons.check_circle_outline,
          trailing: TextButton(
            onPressed: () => ref.read(navIndexProvider.notifier).selectById(
                  'todos',
                ),
            child: const Text('查看全部'),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StatCard(
                dense: true,
                label: '今日待办',
                value: '${asyncToday.value?.length ?? 0}',
                icon: Icons.today_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                dense: true,
                label: '待办总数',
                value: totalAsync.value == null ? '—' : '${totalAsync.value}',
                icon: Icons.list_alt_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AsyncValueView<List<Todo>>(
          value: asyncToday,
          isEmpty: (list) => list.isEmpty,
          empty: const EmptyState(
            icon: Icons.task_alt,
            title: '今天没有待办',
            subtitle: '点上方「待办」快速新增一条',
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final todo in list) ...[
                TodoTile(
                  todo: todo,
                  onToggle: (value) =>
                      ref.read(todoActionsProvider).toggle(todo.id, value),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// 块 ② 本月收支
/// ---------------------------------------------------------------------------

class _MonthlyLedgerSection extends ConsumerWidget {
  const _MonthlyLedgerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSummary = ref.watch(homeMonthlySummaryProvider);
    final currency = ref.watch(currencySymbolProvider);
    final scheme = Theme.of(context).colorScheme;

    /// 中式习惯：收入红、支出绿（与 4.3 记账页一致）
    final incomeColor = scheme.error;
    final expenseColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6FCF97)
        : const Color(0xFF2E8B57);

    return Column(
      key: homeMonthlyLedgerSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '本月收支（${FormatUtils.month(homeCurrentMonth())}）',
          icon: Icons.account_balance_wallet_outlined,
          trailing: TextButton(
            onPressed: () =>
                ref.read(navIndexProvider.notifier).selectById('ledger'),
            child: const Text('去记账'),
          ),
        ),
        AsyncValueView<LedgerSummary>(
          value: asyncSummary,
          data: (summary) => Row(
            children: [
              Expanded(
                child: StatCard(
                  dense: true,
                  label: '收入',
                  value: FormatUtils.centsToYuan(
                    summary.incomeCents,
                    withSymbol: true,
                    symbol: currency,
                  ),
                  valueColor: incomeColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  dense: true,
                  label: '支出',
                  value: FormatUtils.centsToYuan(
                    summary.expenseCents,
                    withSymbol: true,
                    symbol: currency,
                  ),
                  valueColor: expenseColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  dense: true,
                  label: '结余',
                  value: FormatUtils.centsToYuan(
                    summary.balanceCents,
                    withSymbol: true,
                    symbol: currency,
                  ),
                ),
              ),
            ],
          ),
          loading: const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// 块 ③ 笔记统计
/// ---------------------------------------------------------------------------

class _NoteStatsSection extends ConsumerWidget {
  const _NoteStatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(homeNoteTotalProvider);
    final bySceneAsync = ref.watch(homeNoteCountBySceneProvider);

    return Column(
      key: homeNoteStatsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '笔记统计',
          icon: Icons.sticky_note_2_outlined,
          trailing: TextButton(
            onPressed: () =>
                ref.read(navIndexProvider.notifier).selectById('notes'),
            child: const Text('查看全部'),
          ),
        ),
        AsyncValueView<int>(
          value: totalAsync,
          loading: const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (total) => Row(
            children: [
              Expanded(
                child: StatCard(
                  dense: true,
                  label: '笔记总数',
                  value: '$total',
                  icon: Icons.notes_outlined,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AsyncValueView<Map<String, int>>(
          value: bySceneAsync,
          data: (raw) {
            final counts = normalizeSceneCounts(raw);
            return Row(
              children: [
                for (var i = 0; i < counts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _SceneCountCard(item: counts[i]),
                  ),
                ],
              ],
            );
          },
          loading: const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

/// 单个场景的笔记数卡片
class _SceneCountCard extends StatelessWidget {
  const _SceneCountCard({required this.item});

  final SceneCount item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = SceneTag.colorOf(context, item.scene);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.scene.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item.count}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppTypography.titleWeight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
