import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/ledger_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';

/// 阶段 4.7 概览首页的数据层。
///
/// 【范围（用户已确认：先做三块基础）】
///   1. 今日待办：未完成待办的数量 + 今日待办列表；
///   2. 本月收支：本月收入 / 支出 / 结余；
///   3. 笔记统计：笔记总数 + 按场景拆分。
///
/// 【跨模块聚合暂缓】「进行中项目数」「今日是否打卡」等跨模块提醒，
/// 按用户确认的分步策略留到 4.8 之后补 —— 这里**不预先造接口**，
/// 避免留下没人用的死代码。
///
/// 【为什么全部用 StreamProvider】
/// 概览页是「写库 → 统计立刻变」的典型场景。若用 FutureProvider，
/// 每次新增都要手动 `ref.invalidate`，漏一处就出现"数字不刷新"的 bug。
/// 复用 drift 的 watch 流即可做到自动重算（与 4.3 `monthlySummaryProvider`
/// 同一策略）。

/// ---------------------------------------------------------------------------
/// 块 ① 今日待办
/// ---------------------------------------------------------------------------

/// 今日待办列表（截止日期在今日内，或没有截止日期的未完成项）。
///
/// 直接复用 `TodoDao.watchToday()` —— 排序与筛选规则由 DAO 统一维护，
/// 概览页不另写一套（避免两处规则走样）。
final homeTodayTodosProvider =
    StreamProvider.autoDispose<List<Todo>>((ref) {
  return ref.watch(todoDaoProvider).watchToday();
});

/// 今日待办数量。
///
/// 【为什么从 [homeTodayTodosProvider] 派生而不是再查一次库】
/// 两个独立查询在 drift 的推送时序上可能短暂不一致（一个已更新、
/// 另一个还没），派生能保证「数字」与「列表长度」永远相等。
final homeTodayTodoCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(homeTodayTodosProvider).value?.length ?? 0;
});

/// 待办总数（含已完成），用于「今日待办」块副文案。
final homeTodoTotalProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(todoDaoProvider).countAll();
});

/// ---------------------------------------------------------------------------
/// 块 ② 本月收支
/// ---------------------------------------------------------------------------

/// 当前月（归一化到 1 号 00:00）。
///
/// 【为什么归一化】含日/时/分的 `DateTime.now()` 每次取值都不同，
/// 若直接塞进 provider 参数会导致 stream 无限重建。归一化后
/// 「同一个月」在 `==` 下稳定相等（与 4.3 `currentMonth()` 同一做法）。
DateTime homeCurrentMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

/// 本月收入 / 支出 / 结余（单位：分）。
///
/// 【为什么不用 `LedgerDao.summaryOfMonth` 的 Future】
/// 那是**一次性查询**，新增一笔账后不会自动重算。这里复用
/// `watchAll(month:)` 流自行聚合 —— 与 4.3 `monthlySummaryProvider`
/// 完全一致的算法，保证两处口径相同。
final homeMonthlySummaryProvider =
    StreamProvider.autoDispose<LedgerSummary>((ref) {
  final dao = ref.watch(ledgerDaoProvider);
  return dao.watchAll(month: homeCurrentMonth()).map((records) {
    var income = 0;
    var expense = 0;
    for (final r in records) {
      switch (r.type) {
        case 'income':
          income += r.amountCents;
        case 'expense':
          expense += r.amountCents;
      }
    }
    return LedgerSummary(
      incomeCents: income,
      expenseCents: expense,
      balanceCents: income - expense,
    );
  });
});

/// ---------------------------------------------------------------------------
/// 块 ③ 笔记统计
/// ---------------------------------------------------------------------------

/// 笔记总数。
final homeNoteTotalProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(noteDaoProvider).countAll();
});

/// 笔记按场景拆分（scene code → 数量）。
///
/// 【⚠️ 为什么不用 `StreamProvider` 包 `countByScene`】
/// `NoteDao` 目前**只有一次性 `countByScene()`**，没有对应的 watch 版本。
/// 若为它新加一个 `watchCountByScene()`，会动到阶段 2 已验收的 DAO；
/// 本阶段的设计原则是「不改已验收的数据层」。
/// 折中做法：watch **已有**的 `watchAll()` 流，在内存里按场景聚合 ——
/// 效果与 watch 版完全等价（写库即推送），且零 DAO 改动。
final homeNoteCountBySceneProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(noteDaoProvider).watchAll().map((notes) {
    final result = <String, int>{};
    for (final n in notes) {
      result[n.scene] = (result[n.scene] ?? 0) + 1;
    }
    return result;
  });
});

/// 把「scene code → 数量」整理成「稳定顺序 + 全场景齐全」的列表。
///
/// 【为什么要补齐 0】`countByScene` 只返回**有记录**的场景。
/// 若某场景一篇笔记都没有，UI 上会缺一格，看起来像 bug。
/// 这里按 [Scene.values] 顺序输出，缺失的场景补 0。
///
/// 【纯函数，可单测】输入输出都不依赖数据库与 Flutter。
List<SceneCount> normalizeSceneCounts(Map<String, int> raw) {
  return <SceneCount>[
    for (final scene in Scene.values)
      SceneCount(scene: scene, count: raw[scene.code] ?? 0),
  ];
}

/// 一个场景的笔记数量（用于 UI 展示）
class SceneCount {
  const SceneCount({required this.scene, required this.count});

  final Scene scene;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SceneCount && other.scene == scene && other.count == count;

  @override
  int get hashCode => Object.hash(scene, count);

  @override
  String toString() => 'SceneCount(${scene.code}: $count)';
}
