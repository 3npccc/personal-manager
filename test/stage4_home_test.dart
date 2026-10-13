import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/models/enums.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:personal_manager/features/home/providers/home_providers.dart';
import 'package:personal_manager/features/home/ui/home_page.dart';
import 'package:personal_manager/features/todos/ui/todo_form_page.dart';
import 'package:personal_manager/features/todos/ui/widgets/todo_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.7 概览首页测试。
///
/// 覆盖范围（`开发计划.md §4.7` 原文 + 用户确认的「先做三块基础」）：
///   1. 今日待办数量与列表；
///   2. 本月收入 / 支出 / 结余；
///   3. 笔记总数及「按场景拆分」；
///   4. 四个快速新增入口；
///   5. **新增任意数据后统计同步刷新**（这是 §4.7 的硬要求）。
///
/// 另外覆盖：
/// - `normalizeSceneCounts` 纯函数（补齐 0 / 顺序稳定）
/// - `SceneCount` 值对象的相等性
/// - `homeCurrentMonth` 归一化（只保留年月）
/// - `homeTodayTodoCountProvider` 与列表长度一致
void main() {
  late AppDatabase db;

  /// 把测试视口放大到足以容纳整页内容。
  ///
  /// 【为什么】首页在 `ListView` 里放下四块内容，Flutter 默认视口只有
  /// 800x600，`ListView` **惰性构建** → 视口外的块不在 Element 树上，
  /// `find.text('笔记统计')` 会得到 0 个（C12b）。
  void useLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发 onCreate（建表 + 内置分类）
    await db.customSelect('SELECT 1').get();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个带内存库 override 的容器。
  ///
  /// 【⚠️ 绝不写 `await Future.delayed(...)`】`test()` 跑在 FakeAsync zone，
  /// 该 await 会**永久挂起**（C7）。
  Future<ProviderContainer> makeContainer() async {
    final settings = await SettingsService.create();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsServiceProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 读取一个 `StreamProvider.autoDispose` 的首值（listen 占订阅再取）。
  ///
  /// 【为什么不能裸 `read(provider.future)`】autoDispose 的 provider 没有
  /// 监听者时，取到 future 后会立刻调度销毁 → 抛
  /// 「disposed during loading state」。
  Future<T> firstOf<T>(
    ProviderContainer container,
    StreamProvider<T> provider,
  ) async {
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    return container.read(provider.future);
  }

  /// 等某个 stream provider 推出**满足条件**的值（写库后断言用）。
  ///
  /// 【为什么不用 `await read(p.future)` 再读 `.value`】
  /// 写库后 drift 的推送要跨若干 microtask 才到达；`read(p.future)` 在
  /// 已加载的情况下可能立刻返回**旧的**已缓存值 → 断言读到过期数据。
  /// 这里用监听流 + [Completer]，只在"条件成立"时完成，天然屏蔽这种竞态。
  ///
  /// 【⚠️ 只在纯 `test()` 里用】`testWidgets` 跑在 FakeAsync zone，
  /// 流不会被自动推进（C7/C8）。
  Future<T> waitFor<T>(
    ProviderContainer container,
    StreamProvider<T> provider,
    bool Function(T value) predicate,
  ) {
    final completer = Completer<T>();
    final sub = container.listen(provider, (_, next) {
      final value = next.value;
      if (value != null && predicate(value) && !completer.isCompleted) {
        completer.complete(value);
      }
    });
    addTearDown(sub.close);
    final cached = container.read(provider).value;
    if (cached != null && predicate(cached) && !completer.isCompleted) {
      completer.complete(cached);
    }
    return completer.future;
  }

  // ---- 种子函数 -----------------------------------------------------------

  /// 塞一条待办，返回 id。
  Future<int> seedTodo({
    String title = '示例待办',
    Scene scene = Scene.life,
    int priority = 1,
    DateTime? dueDate,
    bool isCompleted = false,
    DateTime? completedAt,
  }) {
    return db.todoDao.insertTodo(
      TodosCompanion.insert(
        title: title,
        scene: scene.code,
        priority: Value(priority),
        dueDate: Value(dueDate),
        isCompleted: Value(isCompleted),
        completedAt: Value(completedAt),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 塞一条笔记，返回 id。
  Future<int> seedNote({
    String title = '示例笔记',
    Scene scene = Scene.life,
  }) {
    final ts = DateTime.now();
    return db.noteDao.insertNote(
      NotesCompanion.insert(
        title: title,
        scene: scene.code,
        createdAt: ts,
        updatedAt: ts,
      ),
    );
  }

  /// 取一个可用分类 id（内置分类在 onCreate 时已插入）。
  Future<int> firstCategoryId(LedgerType type) async {
    final list = await db.categoryDao.findAll(type: type.code);
    return list.first.id;
  }

  /// 塞一条账目，返回 id。金额单位「分」，必须为正整数。
  Future<int> seedLedger({
    required LedgerType type,
    required int amountCents,
    required int categoryId,
    DateTime? recordDate,
  }) {
    return db.ledgerDao.insertRecord(
      LedgerRecordsCompanion.insert(
        type: type.code,
        amountCents: amountCents,
        categoryId: categoryId,
        recordDate: recordDate ?? DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// pump 首页（带内存库 + 设置服务 override）。
  ///
  /// 【⚠️ 必须一起 override `settingsServiceProvider`】
  /// 首页用到两个依赖设置服务的 provider：
  /// - `currencySymbolProvider`（本月收支金额符号）
  /// - `navIndexProvider`（快速入口按 id 切页）
  /// 它们默认实现是 `throw UnimplementedError`，不 override 会在 build 时直接崩。
  Future<void> pumpHome(WidgetTester tester) async {
    useLargeViewport(tester);
    final settings = await SettingsService.create();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsServiceProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // =========================================================================
  // 纯函数 / 值对象
  // =========================================================================

  group('normalizeSceneCounts 场景计数归一化', () {
    test('空 map → 三个场景全部补 0', () {
      final result = normalizeSceneCounts(const <String, int>{});
      expect(result.length, Scene.values.length);
      expect(result.every((e) => e.count == 0), isTrue);
    });

    test('顺序固定为 Scene.values 顺序（学习 / 工作 / 生活）', () {
      final result = normalizeSceneCounts(const <String, int>{
        'life': 5,
        'work': 2,
        'study': 9,
      });
      expect(
        result.map((e) => e.scene).toList(),
        <Scene>[Scene.study, Scene.work, Scene.life],
      );
    });

    test('缺失的场景补 0，已有的保留', () {
      final result = normalizeSceneCounts(const <String, int>{'study': 3});
      expect(result[0].scene, Scene.study);
      expect(result[0].count, 3);
      expect(result[1].count, 0);
      expect(result[2].count, 0);
    });

    test('未知的 key 被忽略（不新增条目）', () {
      final result = normalizeSceneCounts(const <String, int>{
        'study': 1,
        'unknown_scene': 99,
      });
      expect(result.length, Scene.values.length);
      expect(result.fold<int>(0, (sum, e) => sum + e.count), 1);
    });
  });

  group('SceneCount 值对象', () {
    test('相同字段相等且 hashCode 相同', () {
      const a = SceneCount(scene: Scene.study, count: 3);
      const b = SceneCount(scene: Scene.study, count: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('字段不同则不相等', () {
      expect(
        const SceneCount(scene: Scene.study, count: 3),
        isNot(const SceneCount(scene: Scene.study, count: 4)),
      );
      expect(
        const SceneCount(scene: Scene.study, count: 3),
        isNot(const SceneCount(scene: Scene.work, count: 3)),
      );
    });
  });

  group('homeCurrentMonth 月份归一化', () {
    test('只保留年与月（日时分秒归零到 1 号 00:00）', () {
      final m = homeCurrentMonth();
      expect(m.day, 1);
      expect(m.hour, 0);
      expect(m.minute, 0);
      expect(m.second, 0);
      expect(m.millisecond, 0);
    });

    test('两次调用结果相等（同月内稳定，不会导致 stream 重建）', () {
      expect(homeCurrentMonth(), homeCurrentMonth());
    });
  });

  // =========================================================================
  // 块 ① 今日待办
  // =========================================================================

  group('今日待办 provider', () {
    test('没有待办时列表为空且计数为 0', () async {
      final c = await makeContainer();
      final list = await firstOf(c, homeTodayTodosProvider);
      expect(list, isEmpty);
      expect(c.read(homeTodayTodoCountProvider), 0);
    });

    test('无截止日期的未完成待办算作今日待办', () async {
      final c = await makeContainer();
      await seedTodo(title: '买牛奶');

      final list = await firstOf(c, homeTodayTodosProvider);
      expect(list.length, 1);
      expect(list.first.title, '买牛奶');
      expect(c.read(homeTodayTodoCountProvider), 1);
    });

    test('已完成的待办不算今日待办', () async {
      final c = await makeContainer();
      await seedTodo(
        title: '已完成',
        isCompleted: true,
        completedAt: DateTime.now(),
      );

      final list = await firstOf(c, homeTodayTodosProvider);
      expect(list, isEmpty);
    });

    test('截止日期在今天的待办算今日待办', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedTodo(
        title: '今天到期',
        dueDate: DateTime(now.year, now.month, now.day, 12),
      );

      final list = await firstOf(c, homeTodayTodosProvider);
      expect(list.length, 1);
      expect(list.first.title, '今天到期');
    });

    test('截止日期在明天的待办不算今日待办', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedTodo(
        title: '明天到期',
        dueDate: DateTime(now.year, now.month, now.day + 1, 12),
      );

      final list = await firstOf(c, homeTodayTodosProvider);
      expect(list, isEmpty);
    });

    test('待办总数含已完成', () async {
      final c = await makeContainer();
      await seedTodo(title: 'A');
      await seedTodo(
        title: 'B',
        isCompleted: true,
        completedAt: DateTime.now(),
      );

      expect(await c.read(homeTodoTotalProvider.future), 2);
    });
  });

  // =========================================================================
  // 块 ② 本月收支
  // =========================================================================

  group('本月收支 provider', () {
    test('没有记录时三项全为 0', () async {
      final c = await makeContainer();
      final summary = await firstOf(c, homeMonthlySummaryProvider);
      expect(summary.incomeCents, 0);
      expect(summary.expenseCents, 0);
      expect(summary.balanceCents, 0);
    });

    test('收入 / 支出分别求和，结余 = 收入 - 支出', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      final incomeCat = await firstCategoryId(LedgerType.income);
      final expenseCat = await firstCategoryId(LedgerType.expense);

      await seedLedger(
        type: LedgerType.income,
        amountCents: 500000, // 5000.00
        categoryId: incomeCat,
        recordDate: now,
      );
      await seedLedger(
        type: LedgerType.expense,
        amountCents: 12345, // 123.45
        categoryId: expenseCat,
        recordDate: now,
      );

      final summary = await firstOf(c, homeMonthlySummaryProvider);
      expect(summary.incomeCents, 500000);
      expect(summary.expenseCents, 12345);
      expect(summary.balanceCents, 500000 - 12345);
    });

    test('结余可以为负（支出大于收入）', () async {
      final c = await makeContainer();
      final expenseCat = await firstCategoryId(LedgerType.expense);
      await seedLedger(
        type: LedgerType.expense,
        amountCents: 20000,
        categoryId: expenseCat,
      );

      final summary = await firstOf(c, homeMonthlySummaryProvider);
      expect(summary.balanceCents, -20000);
    });

    test('上个月的记录不计入本月', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1, 15);
      final incomeCat = await firstCategoryId(LedgerType.income);

      await seedLedger(
        type: LedgerType.income,
        amountCents: 999999,
        categoryId: incomeCat,
        recordDate: prevMonth,
      );

      final summary = await firstOf(c, homeMonthlySummaryProvider);
      expect(summary.incomeCents, 0);
    });
  });

  // =========================================================================
  // 块 ③ 笔记统计
  // =========================================================================

  group('笔记统计 provider', () {
    test('没有笔记时总数为 0', () async {
      final c = await makeContainer();
      expect(await c.read(homeNoteTotalProvider.future), 0);
    });

    test('总数统计全部笔记', () async {
      final c = await makeContainer();
      await seedNote(title: 'N1', scene: Scene.study);
      await seedNote(title: 'N2', scene: Scene.work);
      await seedNote(title: 'N3', scene: Scene.life);

      expect(await c.read(homeNoteTotalProvider.future), 3);
    });

    test('场景拆分正确且补齐缺失场景', () async {
      final c = await makeContainer();
      await seedNote(title: 'S1', scene: Scene.study);
      await seedNote(title: 'S2', scene: Scene.study);
      await seedNote(title: 'W1', scene: Scene.work);

      final raw = await firstOf(c, homeNoteCountBySceneProvider);
      expect(raw['study'], 2);
      expect(raw['work'], 1);
      expect(raw.containsKey('life'), isFalse); // 原始 map 只含有记录的

      final normalized = normalizeSceneCounts(raw);
      expect(normalized[0].count, 2); // study
      expect(normalized[1].count, 1); // work
      expect(normalized[2].count, 0); // life 补齐
    });
  });

  // =========================================================================
  // 同步刷新（§4.7 硬要求：新增任意数据后统计同步刷新）
  // =========================================================================

  group('写库后统计自动刷新', () {
    test('新增笔记后笔记统计变化', () async {
      final c = await makeContainer();
      // 先确认起始状态为 0
      final before = await firstOf(c, homeNoteCountBySceneProvider);
      expect(before['study'] ?? 0, 0);

      // 写库 → drift stream 应推送新值
      await seedNote(title: '新增', scene: Scene.study);

      final raw = await waitFor(
        c,
        homeNoteCountBySceneProvider,
        (m) => (m['study'] ?? 0) == 1,
      );
      expect(raw['study'], 1);
    });

    test('新增账目后本月统计变化', () async {
      final c = await makeContainer();
      final before = await firstOf(c, homeMonthlySummaryProvider);
      expect(before.incomeCents, 0);

      final incomeCat = await firstCategoryId(LedgerType.income);
      await seedLedger(
        type: LedgerType.income,
        amountCents: 100000,
        categoryId: incomeCat,
      );

      final summary = await waitFor(
        c,
        homeMonthlySummaryProvider,
        (s) => s.incomeCents == 100000,
      );
      expect(summary.incomeCents, 100000);
      expect(summary.balanceCents, 100000);
    });
  });

  // =========================================================================
  // UI：三块基础
  // =========================================================================

  group('首页 UI 三块基础', () {
    testWidgets('空数据时显示空状态与 0 统计', (tester) async {
      await pumpHome(tester);

      expect(find.text('概览'), findsOneWidget);
      expect(find.text('快速新增'), findsOneWidget);

      // 「今日待办」既是区块标题也是 StatCard 标签 → 恰好 2 处（C37：数清来源）
      expect(find.text('今日待办'), findsNWidgets(2));
      expect(find.text('笔记统计'), findsOneWidget);
      expect(find.text('笔记总数'), findsOneWidget);
      expect(find.text('今天没有待办'), findsOneWidget);
    });

    testWidgets('显示今日待办列表并可勾选完成', (tester) async {
      final id = await seedTodo(title: '交周报');
      await pumpHome(tester);

      final todos = find.byKey(homeTodayTodoSectionKey);
      expect(
        find.descendant(of: todos, matching: find.byType(TodoTile)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: todos, matching: find.text('交周报')),
        findsOneWidget,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect((await db.todoDao.findById(id))!.isCompleted, isTrue);
    });

    testWidgets('本月收支显示收入 / 支出 / 结余', (tester) async {
      final incomeCat = await firstCategoryId(LedgerType.income);
      final expenseCat = await firstCategoryId(LedgerType.expense);
      await seedLedger(
        type: LedgerType.income,
        amountCents: 300000,
        categoryId: incomeCat,
      );
      await seedLedger(
        type: LedgerType.expense,
        amountCents: 50000,
        categoryId: expenseCat,
      );
      await pumpHome(tester);

      // 限定到本月收支区块内（同页另有「今日待办」区块也会渲染数字）
      final ledger = find.byKey(homeMonthlyLedgerSectionKey);
      expect(
        find.descendant(of: ledger, matching: find.text('收入')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ledger, matching: find.text('支出')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ledger, matching: find.text('结余')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ledger, matching: find.text('¥3000.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ledger, matching: find.text('¥500.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ledger, matching: find.text('¥2500.00')),
        findsOneWidget,
      );
    });

    testWidgets('笔记统计显示总数与三个场景', (tester) async {
      await seedNote(title: 'N1', scene: Scene.study);
      await seedNote(title: 'N2', scene: Scene.study);
      await pumpHome(tester);

      // 【为什么必须限定作用域】本页「今日待办」区块的两个 StatCard 也是 0，
      // 「工作 / 生活」两张场景卡也是 0 —— 全页共有 4 个 Text('0')，
      // 直接 find.text('0') 会连待办区一起数进来，断言就成了碰运气。
      // 用 find.descendant 锚定到笔记统计区块内，才是这条用例真正要断言的。
      final noteStats = find.byKey(homeNoteStatsSectionKey);

      expect(
        find.descendant(of: noteStats, matching: find.text('笔记总数')),
        findsOneWidget,
      );
      // 三个场景标签各 1 个（来自 _SceneCountCard）
      expect(
        find.descendant(of: noteStats, matching: find.text('学习')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: noteStats, matching: find.text('工作')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: noteStats, matching: find.text('生活')),
        findsOneWidget,
      );
      // 区块内「2」恰 2 处：总数 StatCard + 学习场景卡
      expect(
        find.descendant(of: noteStats, matching: find.text('2')),
        findsNWidgets(2),
      );
      // 区块内「0」恰 2 处：工作场景卡 + 生活场景卡
      expect(
        find.descendant(of: noteStats, matching: find.text('0')),
        findsNWidgets(2),
      );
    });
  });

  // =========================================================================
  // UI：快速入口
  // =========================================================================

  group('首页 UI 快速入口', () {
    testWidgets('四个入口按钮都渲染', (tester) async {
      await pumpHome(tester);

      // 限定到快速入口区块内，每个 label 恰好 1 个（规则 22：不用 findsWidgets）
      final quick = find.byKey(homeQuickActionsKey);
      expect(
        find.descendant(of: quick, matching: find.text('待办')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quick, matching: find.text('笔记')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quick, matching: find.text('记一笔')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quick, matching: find.text('打卡')),
        findsOneWidget,
      );
    });

    testWidgets('点「待办」入口打开新增待办表单', (tester) async {
      await pumpHome(tester);

      // 快速入口里 label 为「待办」的按钮
      await tester.tap(find.widgetWithText(Card, '待办').first);
      await tester.pumpAndSettle();

      expect(find.byType(TodoFormPage), findsOneWidget);
    });

    testWidgets('点「记一笔」入口切到记账页', (tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsServiceProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(navIndexProvider), 0);

      await tester.tap(find.text('记一笔'));
      await tester.pumpAndSettle();

      // 导航索引应切换到「记账」（kNavDestinations 第 4 项 = 索引 3）
      expect(container.read(navIndexProvider), 3);
    });
  });
}
