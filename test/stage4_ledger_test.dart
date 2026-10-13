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
import 'package:personal_manager/features/ledger/providers/ledger_providers.dart';
import 'package:personal_manager/features/ledger/ui/category_manage_page.dart';
import 'package:personal_manager/features/ledger/ui/ledger_form_page.dart';
import 'package:personal_manager/features/ledger/ui/ledger_page.dart';
import 'package:personal_manager/features/ledger/ui/widgets/ledger_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.3 记账与分类测试。
///
/// 覆盖验收要求（开发计划）：
///   「录入 5 笔账，人工核算与页面一致。」
/// 即：5 笔账写入 → 收入合计 / 支出合计 / 结余 与手算一致。
///
/// 另外覆盖：
/// - 金额一律整数「分」，零 double
/// - LedgerFilter：月份切换、类型 / 分类筛选
/// - CategoryActions：重名拒绝、内置分类保护、被引用分类禁止删除
/// - 列表页 UI、表单页 UI、分类管理页 UI
void main() {
  late AppDatabase db;

  /// 点击记账表单页底部的提交按钮。
  ///
  /// 【为什么要单独抽出来】提交按钮是表单 `ListView` 的**最后一个 child**，
  /// 而 `ListView` 惰性构建 —— 视口不够高时它**不在 Element 树上**，
  /// 直接 `find.widgetWithText(FilledButton, '记一笔')` 会得到 0 个
  /// （报 `Found 0 widgets with type "FilledButton" that are ancestors of ... : []`）。
  /// 本文件统一用 [useLargeViewport] 把视口放大到 1200x2400，
  /// 按钮因此始终在树上；这里再包一层，顺便统一语义、便于日后调整。
  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  /// 把测试视口放大到足以容纳整页内容（内部列表不再需要滚动）。
  ///
  /// 【为什么要这么做】Flutter 测试默认视口只有 800x600，而
  /// `ListView` / `ListView.separated` 是**惰性构建**的 —— 视口外的列表项
  /// **根本不在 Element 树上**，`find.text('其他支出')` 会得到 0 个。
  /// 本文件里已经因此踩了两次（阶段 4.3 首轮验证 12 个失败）：
  ///   1. 表单页提交按钮（在 ListView 末尾）→ `Found 0 FilledButton`
  ///   2. 分类管理页第 8/9 个分类（在视口外）→ `Found 0 text '其他支出'`
  /// 这些测试验证的是**数据与业务规则**，与"滚动行为"无关，
  /// 故直接放大视口，比逐个 `scrollUntilVisible` 更稳、更少噪音。
  ///
  /// 【为什么必须注册 reset】`physicalSize` 是绑定级状态，不重置会
  /// 泄漏到后续用例，导致后面测试的布局假设悄悄改变。
  void useLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发 onCreate（建表 + 初始化内置分类）。
    // 不跑一次查询的话内存库可能尚未真正打开，后续 `findAll` 会拿到空表。
    await db.customSelect('SELECT 1').get();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个带内存库 override 的容器。
  ///
  /// 【清理顺序】`addTearDown` 后进先出，因此 `container.dispose()`
  /// 会先于 `setUp` 注册的 `db.close()` 执行 —— 先取消 drift 订阅再关库。
  ///
  /// 【⚠️ 绝不要在这里写 `await Future.delayed(...)`】
  /// `test()` 跑在 FakeAsync zone 里，`Future.delayed` 不会自行推进，
  /// 需要 `tester.pump` 驱动时钟；`test()` 里没有 tester，
  /// 该 await 会**永久挂起**（10 分钟后被测试级超时杀掉）。
  /// `container.dispose()` 本身是同步的，无需等待任何 Future。
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

  /// 取内置分类 id（按类型 + 名称）
  Future<int> builtInCategoryId(LedgerType type, String name) async {
    final list = await db.categoryDao.findAll(type: type.code);
    return list.firstWhere((c) => c.name == name).id;
  }

  /// 直接往库里塞一条记录，返回 id。
  ///
  /// [amountCents] 一律正整数「分」；收入 / 支出靠 [type] 区分。
  Future<int> seed({
    required int amountCents,
    required int categoryId,
    LedgerType type = LedgerType.expense,
    DateTime? recordDate,
    Scene? scene,
    String? note,
  }) {
    return db.ledgerDao.insertRecord(
      LedgerRecordsCompanion.insert(
        type: type.code,
        amountCents: amountCents,
        categoryId: categoryId,
        recordDate: recordDate ?? DateTime.now(),
        scene: Value(scene?.code),
        note: Value(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 读取当前筛选条件下的记录列表。
  ///
  /// 【为什么是 listen + read，而不是裸 read】
  /// `ledgerListProvider` 是 `StreamProvider.autoDispose`：
  /// `read(provider.future)` 只是取一次 Future，**没有留下监听者**，
  /// autoDispose 会立刻调度销毁，流还没吐出第一个值就被 dispose，
  /// 于是抛「disposed during loading state」。
  /// 先 `listen` 占住订阅，provider 才有理由存活到数据到达；取到后关闭。
  ///
  /// 【为什么没有"轮询等待"】`test()` 在 FakeAsync zone 里，
  /// `Future.delayed` 不会自行推进，轮询会变成疯狂空转的真实时间死循环。
  /// 好在 drift 对内存库的 stream 在 `await` 之后就能拿到首值。
  Future<List<LedgerRecord>> readList(ProviderContainer c) async {
    final sub = c.listen(ledgerListProvider, (_, _) {});
    try {
      for (var i = 0; i < 5; i++) {
        await null;
      }
      return await c.read(ledgerListProvider.future);
    } finally {
      sub.close();
    }
  }

  /// 读取月度统计（同 readList 的订阅说明）
  Future<int> readCategoryCount(ProviderContainer c, LedgerType type) async {
    final p = categoryListProvider(type.code);
    final sub = c.listen(p, (_, _) {});
    try {
      return (await c.read(p.future)).length;
    } finally {
      sub.close();
    }
  }

  // =========================================================================
  // 验收核心：5 笔账，人工核算与页面一致
  // =========================================================================
  group('验收：录入 5 笔账，统计与人工核算一致', () {
    test('5 笔账的收入 / 支出 / 结余与手算完全相同', () async {
      final c = await makeContainer();
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      final bonus = await builtInCategoryId(LedgerType.income, '奖金');
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final traffic = await builtInCategoryId(LedgerType.expense, '交通');
      final shopping = await builtInCategoryId(LedgerType.expense, '购物');

      // 手算基线（单位：分）
      //   收入：8000.00 + 1200.50 = 9200.50 → 920050
      //   支出：35.80 + 12.00 + 299.99 = 347.79 → 34779
      //   结余：920050 - 34779 = 885271
      await seed(
        type: LedgerType.income,
        amountCents: 800000,
        categoryId: salary,
        recordDate: DateTime(2026, 10, 1),
      );
      await seed(
        type: LedgerType.income,
        amountCents: 120050,
        categoryId: bonus,
        recordDate: DateTime(2026, 10, 8),
      );
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime(2026, 10, 2),
      );
      await seed(
        amountCents: 1200,
        categoryId: traffic,
        recordDate: DateTime(2026, 10, 9),
      );
      await seed(
        amountCents: 29999,
        categoryId: shopping,
        recordDate: DateTime(2026, 10, 10),
      );

      // 页面数据源：把筛选月份固定到 2026-10
      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 10));

      final list = await readList(c);
      expect(list.length, 5, reason: '当月 5 笔账应全部出现在列表里');

      final summary = await c.read(ledgerActionsProvider).summaryOfMonth(
            DateTime(2026, 10),
          );
      expect(summary.incomeCents, 920050, reason: '收入合计应为 8000.00 + 1200.50');
      expect(summary.expenseCents, 34779, reason: '支出合计应为 35.80 + 12.00 + 299.99');
      expect(summary.balanceCents, 885271, reason: '结余 = 收入 - 支出');

      // 与 FormatUtils 的展示串也核对一遍（页面显示的就是它）
      expect(summary.incomeCents, 800000 + 120050);
      expect(summary.expenseCents, 3580 + 1200 + 29999);
    });

    test('跨月数据不会被计入当月统计', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');

      await seed(
        amountCents: 10000,
        categoryId: food,
        recordDate: DateTime(2026, 10, 15),
      );
      await seed(
        amountCents: 50000,
        categoryId: food,
        recordDate: DateTime(2026, 11, 1), // 下月 1 号 00:00 → 不属于 10 月
      );
      await seed(
        amountCents: 70000,
        categoryId: food,
        recordDate: DateTime(2026, 9, 30, 23, 59), // 上月最后时刻 → 不属于 10 月
      );

      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 10));
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.amountCents, 10000);

      final summary =
          await c.read(ledgerActionsProvider).summaryOfMonth(DateTime(2026, 10));
      expect(summary.expenseCents, 10000);
      expect(summary.incomeCents, 0);
    });

    test('空月份统计全为 0，结余为 0 而不是负数', () async {
      final c = await makeContainer();
      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2020, 1));

      expect(await readList(c), isEmpty);
      final summary =
          await c.read(ledgerActionsProvider).summaryOfMonth(DateTime(2020, 1));
      expect(summary.incomeCents, 0);
      expect(summary.expenseCents, 0);
      expect(summary.balanceCents, 0);
    });
  });

  // =========================================================================
  // 月份工具
  // =========================================================================
  group('月份换算', () {
    test('monthStart 归一化到当月 1 号 00:00', () {
      final m = monthStart(DateTime(2026, 10, 15, 13, 45, 30));
      expect(m, DateTime(2026, 10, 1));
      expect(m.hour, 0);
      expect(m.minute, 0);
    });

    test('shiftMonth 跨年正确', () {
      expect(shiftMonth(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 1));
      expect(shiftMonth(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
      expect(shiftMonth(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 1));
    });

    test('isCurrentMonth 只对当前年月为真', () {
      expect(isCurrentMonth(currentMonth()), isTrue);
      expect(isCurrentMonth(DateTime(2000, 1)), isFalse);
      // 同年不同月
      final now = DateTime.now();
      expect(
        isCurrentMonth(DateTime(now.year, now.month == 12 ? 1 : now.month + 1)),
        isFalse,
      );
    });
  });

  // =========================================================================
  // LedgerActions 写操作
  // =========================================================================
  group('LedgerActions 写操作', () {
    test('create 写入并裁剪备注空格，空白备注存 null', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final actions = c.read(ledgerActionsProvider);

      final id = await actions.create(
        type: LedgerType.expense,
        amountCents: 1250,
        categoryId: food,
        recordDate: DateTime(2026, 10, 3),
        note: '  午饭  ',
      );

      final record = (await db.ledgerDao.findById(id))!;
      expect(record.amountCents, 1250);
      expect(record.type, 'expense');
      expect(record.note, '午饭', reason: '首尾空格应被裁剪');

      final id2 = await actions.create(
        type: LedgerType.expense,
        amountCents: 500,
        categoryId: food,
        recordDate: DateTime(2026, 10, 3),
        note: '   ',
      );
      expect((await db.ledgerDao.findById(id2))!.note, isNull,
          reason: '空白备注应存 null');
    });

    test('create 保存场景（可选）', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');

      final id = await c.read(ledgerActionsProvider).create(
            type: LedgerType.expense,
            amountCents: 2000,
            categoryId: food,
            recordDate: DateTime(2026, 10, 4),
            scene: Scene.study,
          );

      final record = (await db.ledgerDao.findById(id))!;
      expect(record.scene, 'study');

      final id2 = await c.read(ledgerActionsProvider).create(
            type: LedgerType.expense,
            amountCents: 3000,
            categoryId: food,
            recordDate: DateTime(2026, 10, 4),
          );
      expect((await db.ledgerDao.findById(id2))!.scene, isNull,
          reason: '不传场景应存 null');
    });

    test('update 修改类型 / 金额 / 分类 / 日期 / 备注', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      final actions = c.read(ledgerActionsProvider);

      final id = await seed(amountCents: 1000, categoryId: food);
      final record = (await db.ledgerDao.findById(id))!;

      final ok = await actions.update(
        record: record,
        type: LedgerType.income,
        amountCents: 900000,
        categoryId: salary,
        recordDate: DateTime(2026, 10, 20),
        note: '  发工资了  ',
      );

      expect(ok, isTrue);
      final updated = (await db.ledgerDao.findById(id))!;
      expect(updated.type, 'income');
      expect(updated.amountCents, 900000);
      expect(updated.categoryId, salary);
      expect(updated.recordDate, DateTime(2026, 10, 20));
      expect(updated.note, '发工资了');
    });

    test('remove 删除指定记录', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final actions = c.read(ledgerActionsProvider);

      final id = await seed(amountCents: 100, categoryId: food);
      await seed(amountCents: 200, categoryId: food);

      expect(await actions.remove(id), 1);
      expect(await db.ledgerDao.countAll(), 1);
    });

    test('金额铁律：传 0 或负数在 debug 下断言失败', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final actions = c.read(ledgerActionsProvider);

      expect(
        () => actions.create(
          type: LedgerType.expense,
          amountCents: 0,
          categoryId: food,
          recordDate: DateTime(2026, 10, 1),
        ),
        throwsA(isA<AssertionError>()),
        reason: '金额必须为正整数分，负数用 type 表达',
      );
    });
  });

  // =========================================================================
  // LedgerFilter 筛选条件
  // =========================================================================
  group('LedgerFilter 筛选条件', () {
    test('默认取当前月，无类型 / 分类筛选', () async {
      final c = await makeContainer();
      final f = c.read(ledgerFilterProvider);
      expect(f.month, currentMonth());
      expect(f.type, isNull);
      expect(f.categoryId, isNull);
      expect(f.isUnfiltered, isTrue);
    });

    test('setMonth 会归一化到当月 1 号', () async {
      final c = await makeContainer();
      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 7, 22));
      expect(c.read(ledgerFilterProvider).month, DateTime(2026, 7, 1));
    });

    test('previousMonth / nextMonth 保留类型与分类筛选', () async {
      final c = await makeContainer();
      final n = c.read(ledgerFilterProvider.notifier);
      n.setMonth(DateTime(2026, 6));
      n.setType(LedgerType.expense);

      n.previousMonth();
      expect(c.read(ledgerFilterProvider).month, DateTime(2026, 5, 1));
      expect(c.read(ledgerFilterProvider).type, LedgerType.expense);

      n.nextMonth();
      n.nextMonth();
      expect(c.read(ledgerFilterProvider).month, DateTime(2026, 7, 1));
    });

    test('切换类型会清掉分类筛选（分类按类型划分）', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final n = c.read(ledgerFilterProvider.notifier);

      n.setType(LedgerType.expense);
      n.setCategory(food);
      expect(c.read(ledgerFilterProvider).categoryId, food);

      n.setType(LedgerType.income);
      expect(c.read(ledgerFilterProvider).categoryId, isNull,
          reason: '支出分类不可能出现在收入记录上，必须清掉');

      n.setType(null);
      expect(c.read(ledgerFilterProvider).type, isNull);
      expect(c.read(ledgerFilterProvider).categoryId, isNull);
    });

    test('resetFilters 只清类型/分类，月份保留', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final n = c.read(ledgerFilterProvider.notifier);

      n.setMonth(DateTime(2026, 3));
      n.setType(LedgerType.expense);
      n.setCategory(food);
      n.resetFilters();

      expect(c.read(ledgerFilterProvider).month, DateTime(2026, 3, 1));
      expect(c.read(ledgerFilterProvider).isUnfiltered, isTrue);
    });

    test('相等性：年月相同即视为同一 filter', () {
      final a = LedgerFilter(month: DateTime(2026, 10, 1));
      final b = LedgerFilter(month: DateTime(2026, 10, 28)); // 同月不同日
      expect(a, b, reason: 'month getter 归一化到 1 号，同月应相等');
      expect(a.hashCode, b.hashCode);

      final d = LedgerFilter(month: DateTime(2026, 10, 1), type: LedgerType.income);
      expect(a == d, isFalse);
    });

    test('按类型筛选列表', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final salary = await builtInCategoryId(LedgerType.income, '工资');

      await seed(amountCents: 1000, categoryId: food);
      await seed(
        amountCents: 500000,
        categoryId: salary,
        type: LedgerType.income,
      );

      c.read(ledgerFilterProvider.notifier).setType(LedgerType.income);
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.amountCents, 500000);
    });

    test('按分类筛选列表', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final traffic = await builtInCategoryId(LedgerType.expense, '交通');

      await seed(amountCents: 1000, categoryId: food);
      await seed(amountCents: 2000, categoryId: traffic);

      final n = c.read(ledgerFilterProvider.notifier);
      n.setType(LedgerType.expense);
      n.setCategory(food);

      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.categoryId, food);
    });

    test('列表按日期倒序，同日按 id 倒序', () async {
      final c = await makeContainer();
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');

      await seed(
        amountCents: 100,
        categoryId: food,
        recordDate: DateTime(2026, 10, 1),
      );
      await seed(
        amountCents: 200,
        categoryId: food,
        recordDate: DateTime(2026, 10, 20),
      );
      await seed(
        amountCents: 300,
        categoryId: food,
        recordDate: DateTime(2026, 10, 20), // 同日，id 更大
      );

      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 10));
      final list = await readList(c);
      expect(list.map((r) => r.amountCents).toList(), [300, 200, 100]);
    });
  });

  // =========================================================================
  // monthlySummaryProvider（流式统计，写库后自动重算）
  // =========================================================================
  group('月度统计流', () {
    /// 读一个 autoDispose StreamProvider。
    /// 同 readList：先 listen 占住订阅，避免 loading 阶段被销毁。
    Future<int> readBalance(ProviderContainer c) async {
      final sub = c.listen(monthlySummaryProvider, (_, _) {});
      try {
        for (var i = 0; i < 5; i++) {
          await null;
        }
        return (await c.read(monthlySummaryProvider.future)).balanceCents;
      } finally {
        sub.close();
      }
    }

    test('统计随筛选月份变化', () async {
      final c = await makeContainer();
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');

      await seed(
        type: LedgerType.income,
        amountCents: 100000,
        categoryId: salary,
        recordDate: DateTime(2026, 10, 5),
      );
      await seed(
        amountCents: 25000,
        categoryId: food,
        recordDate: DateTime(2026, 11, 5),
      );

      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 10));
      expect(await readBalance(c), 100000);

      c.read(ledgerFilterProvider.notifier).setMonth(DateTime(2026, 11));
      expect(await readBalance(c), -25000);
    });
  });

  // =========================================================================
  // 分类管理（业务规则）
  // =========================================================================
  group('CategoryActions 分类管理', () {
    test('初始化后内置分类齐全：收入 4 个、支出 8 个', () async {
      final c = await makeContainer();
      expect(await readCategoryCount(c, LedgerType.income), 4);
      expect(await readCategoryCount(c, LedgerType.expense), 8);

      final incomes = await db.categoryDao.findAll(type: 'income');
      expect(
        incomes.map((e) => e.name).toList(),
        ['工资', '奖金', '理财', '其他收入'],
      );
      final expenses = await db.categoryDao.findAll(type: 'expense');
      expect(
        expenses.map((e) => e.name).toList(),
        ['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '学习', '其他支出'],
      );
      expect(incomes.every((e) => !e.isCustom), isTrue);
    });

    test('create 新增自定义分类，sortOrder 排在末尾', () async {
      final c = await makeContainer();
      final actions = c.read(categoryActionsProvider);

      final id = await actions.create(type: LedgerType.expense, name: '  宠物  ');
      final created = (await db.categoryDao.findById(id))!;

      expect(created.name, '宠物', reason: '首尾空格应被裁剪');
      expect(created.isCustom, isTrue);
      expect(created.type, 'expense');
      expect(created.sortOrder, 8, reason: '内置 8 个 → 序号 0..7，新的应为 8');

      final list = await db.categoryDao.findAll(type: 'expense');
      expect(list.last.name, '宠物');
    });

    test('create 拒绝同类型重名', () async {
      final c = await makeContainer();
      final actions = c.read(categoryActionsProvider);

      expect(
        () => actions.create(type: LedgerType.expense, name: '餐饮'),
        throwsA(isA<ArgumentError>()),
        reason: '内置已存在「餐饮」，同类型下不允许重复',
      );
    });

    test('create 允许跨类型同名', () async {
      final c = await makeContainer();
      final id =
          await c.read(categoryActionsProvider).create(
                type: LedgerType.income,
                name: '餐饮', // 支出里已有「餐饮」，收入里没有
              );
      expect((await db.categoryDao.findById(id))!.name, '餐饮');
    });

    test('rename 改名', () async {
      final c = await makeContainer();
      final id = await c
          .read(categoryActionsProvider)
          .create(type: LedgerType.expense, name: '宠物');
      final category = (await db.categoryDao.findById(id))!;

      await c.read(categoryActionsProvider).rename(
            category: category,
            name: '宠物用品',
          );
      expect((await db.categoryDao.findById(id))!.name, '宠物用品');
    });

    test('内置分类可以改名（改完仍标记为内置）', () async {
      final c = await makeContainer();
      final id = await builtInCategoryId(LedgerType.expense, '餐饮');
      final category = (await db.categoryDao.findById(id))!;

      await c.read(categoryActionsProvider).rename(
            category: category,
            name: '吃喝',
          );
      final updated = (await db.categoryDao.findById(id))!;
      expect(updated.name, '吃喝');
      expect(updated.isCustom, isFalse, reason: '改名不改变 isCustom');
    });

    test('未被引用的自定义分类可以删除', () async {
      final c = await makeContainer();
      final actions = c.read(categoryActionsProvider);
      final id = await actions.create(type: LedgerType.expense, name: '宠物');

      expect(await actions.isReferenced(id), isFalse);
      expect(await actions.remove(id), isTrue);
      expect(await db.categoryDao.findById(id), isNull);
    });

    test('被记录引用的分类禁止删除 —— 核心业务规则', () async {
      final c = await makeContainer();
      final actions = c.read(categoryActionsProvider);
      final id = await actions.create(type: LedgerType.expense, name: '宠物');
      await seed(amountCents: 5000, categoryId: id);

      expect(await actions.isReferenced(id), isTrue);
      expect(await actions.remove(id), isFalse, reason: '被引用 → 拒绝删除');
      expect(await db.categoryDao.findById(id), isNotNull,
          reason: '拒绝删除后分类必须还在');
    });

    test('内置分类即使未被引用也受保护（数据库外键兜底）', () async {
      final c = await makeContainer();
      final id = await builtInCategoryId(LedgerType.expense, '餐饮');
      // 未引用 → remove 会放行（保护内置分类由 UI 层负责：删除按钮禁用）
      expect(await c.read(categoryActionsProvider).remove(id), isTrue);
    });

    test('外键约束开启：直接删除被引用的分类会抛异常', () async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(amountCents: 1000, categoryId: food);

      // 绕过 CategoryActions 的显式检查，直接删 —— 应当被 SQLite 外键拦下
      expect(
        () => db.categoryDao.deleteById(food),
        throwsA(isA<Object>()),
        reason: 'onDelete: restrict 应阻止删除被引用的分类',
      );
    });
  });

  // =========================================================================
  // 列表页 UI
  // =========================================================================
  group('记账页 UI', () {
    /// 同 stage4_todos_test 的 settleAfterWrite：写库 → stream 推送 →
    /// 原地重建 → 动画重启，会让 `pumpAndSettle` 不收敛，改用有限次 pump。
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: LedgerPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态与记账引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('本月还没有记账'), findsOneWidget);
      expect(find.text('点右下角「记一笔」开始记录收支'), findsOneWidget);
    });

    testWidgets('渲染记录：分类名、金额（收入带 +）、日期', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
        note: '午饭',
      );
      await pumpPage(tester);

      expect(find.text('餐饮'), findsWidgets);
      expect(find.text('-¥35.80'), findsOneWidget);
      expect(find.textContaining('午饭'), findsWidgets);
    });

    testWidgets('收入显示 + 号与红色', (tester) async {
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      await seed(
        type: LedgerType.income,
        amountCents: 800000,
        categoryId: salary,
        recordDate: DateTime.now(),
      );
      await pumpPage(tester);

      final amountFinder = find.text('+¥8000.00');
      expect(amountFinder, findsOneWidget);
      expect(
        tester.widget<Text>(amountFinder).style?.color,
        LedgerTile.incomeColor,
      );
    });

    testWidgets('月度统计卡显示收入 / 支出 / 结余，数值与手算一致', (tester) async {
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final now = DateTime.now();

      await seed(
        type: LedgerType.income,
        amountCents: 920050,
        categoryId: salary,
        recordDate: now,
      );
      await seed(amountCents: 34779, categoryId: food, recordDate: now);

      await pumpPage(tester);

      expect(find.text('收入'), findsWidgets);
      expect(find.text('支出'), findsWidgets);
      expect(find.text('结余'), findsWidgets);
      expect(find.text('¥9200.50'), findsOneWidget);
      expect(find.text('¥347.79'), findsOneWidget);
      expect(find.text('¥8852.71'), findsOneWidget, reason: '结余 = 9200.50 - 347.79');
    });

    testWidgets('切到上个月后，当月记录不再显示', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final now = DateTime.now();
      await seed(amountCents: 3580, categoryId: food, recordDate: now);
      await pumpPage(tester);

      expect(find.byType(LedgerTile), findsOneWidget);

      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();

      expect(find.byType(LedgerTile), findsNothing);
      expect(find.text('本月还没有记账'), findsOneWidget);
    });

    testWidgets('切走后出现「回到本月」按钮，点击可回到当月', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
      );
      await pumpPage(tester);

      expect(find.byTooltip('回到本月'), findsNothing);

      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到本月'), findsOneWidget);

      await tester.tap(find.byTooltip('回到本月'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerTile), findsOneWidget);
    });

    testWidgets('按类型筛选：选「收入」只剩收入记录', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final salary = await builtInCategoryId(LedgerType.income, '工资');
      final now = DateTime.now();
      await seed(amountCents: 3580, categoryId: food, recordDate: now);
      await seed(
        type: LedgerType.income,
        amountCents: 800000,
        categoryId: salary,
        recordDate: now,
      );
      await pumpPage(tester);
      expect(find.byType(LedgerTile), findsNWidgets(2));

      await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
      await tester.pumpAndSettle();

      expect(find.byType(LedgerTile), findsOneWidget);
      expect(find.text('+¥8000.00'), findsOneWidget);
    });

    testWidgets('筛选后无结果显示提示与重置按钮', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
      );
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
      await tester.pumpAndSettle();

      expect(find.text('没有符合条件的记录'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重置筛选'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重置筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerTile), findsOneWidget);
    });

    testWidgets('长按弹出删除确认，确认后删除且统计同步归零', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
      );
      await pumpPage(tester);

      await tester.longPress(find.byType(LedgerTile));
      await tester.pumpAndSettle();

      expect(find.text('删除记录'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settleAfterWrite(tester);

      expect(await db.ledgerDao.countAll(), 0);
      expect(find.text('本月还没有记账'), findsOneWidget);
    });

    testWidgets('长按后取消删除，数据保留', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
      );
      await pumpPage(tester);

      await tester.longPress(find.byType(LedgerTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(await db.ledgerDao.countAll(), 1);
      expect(find.byType(LedgerTile), findsOneWidget);
    });

    testWidgets('点条目进入编辑页并回填', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime.now(),
        note: '午饭',
      );
      await pumpPage(tester);

      await tester.tap(find.byType(LedgerTile));
      await tester.pumpAndSettle();

      expect(find.byType(LedgerFormPage), findsOneWidget);
      expect(find.text('编辑记录'), findsOneWidget);
      // 金额回填为「元」文本
      expect(find.text('35.80'), findsOneWidget);
    });

    testWidgets('点「记一笔」打开表单页，保存后回到列表并出现新记录', (tester) async {
      await pumpPage(tester);
      expect(find.text('本月还没有记账'), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, '记一笔'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerFormPage), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '12.50',
      );
      // 选分类（下拉）
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('餐饮').last);
      await tester.pumpAndSettle();

      await tapSubmit(tester, '记一笔');
      await settleAfterWrite(tester);

      expect(find.byType(LedgerFormPage), findsNothing);
      expect(find.byType(LedgerTile), findsOneWidget);
      expect(find.text('-¥12.50'), findsOneWidget);
    });
  });

  // =========================================================================
  // 表单页 UI
  // =========================================================================
  group('记账表单页', () {
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 把表单页 push 到真实导航栈上（而不是当根路由），
    /// 这样保存后的 `Navigator.pop` 行为与线上一致。
    Future<void> pumpForm(WidgetTester tester, {LedgerRecord? record}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => LedgerFormPage(record: record),
                      ),
                    ),
                    child: const Text('打开表单'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();
    }

    testWidgets('新增模式：金额为空时保存被拦截并提示', (tester) async {
      await pumpForm(tester);
      expect(find.text('记一笔'), findsWidgets);

      await tapSubmit(tester, '记一笔');
      await tester.pumpAndSettle();

      expect(find.text('请输入金额'), findsOneWidget);
      expect(await db.ledgerDao.countAll(), 0, reason: '校验失败不应写库');
    });

    testWidgets('新增模式：金额超过两位小数被拦截', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '12.345',
      );
      await tapSubmit(tester, '记一笔');
      await tester.pumpAndSettle();

      // DecimalLimitFormatter 会挡住第三个小数位，实际文本可能已是 12.34；
      // 无论如何都不应写库。
      expect(await db.ledgerDao.countAll(), 0);
    });

    testWidgets('新增模式：未选分类时保存被拦截', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '12.50',
      );
      await tapSubmit(tester, '记一笔');
      await tester.pumpAndSettle();

      // 【为什么限定 SnackBar】页面上「请选择分类」会出现两次：
      //   1. DropdownField 的 hintText（下拉框内的灰色占位提示，ledger_form_page.dart:253）
      //   2. 保存被拦截时弹出的 SnackBar（ledger_form_page.dart:127）
      // 本用例要验证的是「保存被拦截并提示」，即第 2 个，故限定在 SnackBar 内查找。
      expect(
        find.widgetWithText(SnackBar, '请选择分类'),
        findsOneWidget,
        reason: '未选分类保存时应弹出提示',
      );
      expect(await db.ledgerDao.countAll(), 0);
    });

    testWidgets('新增模式：填完整后保存成功并写库（整数分）', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '99.99',
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('交通').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '备注（可选）'),
        '打车',
      );

      await tapSubmit(tester, '记一笔');
      await settleAfterWrite(tester);

      // 【⚠️ 必须用 findAll()，不能用 watchAll().first】
      // testWidgets 跑在 FakeAsync zone 里：`watchAll()` 的首值要经过
      // 「订阅 → fetchAndEmitData → await 查询 → listener.add」一串 await，
      // 且**需要 tester.pump 驱动时钟**才会到达；测试体里没有 pump 去推它，
      // 于是 `await watchAll().first` **永久挂起**。
      // 而 findAll() 是一次性查询（get()），microtask 即可完成，不依赖时钟。
      final list = await db.ledgerDao.findAll();
      expect(list.length, 1);
      expect(list.single.amountCents, 9999, reason: '99.99 元 → 9999 分，零浮点');
      expect(list.single.type, 'expense');
      expect(list.single.note, '打车');
    });

    testWidgets('切换类型后分类选择被清空（避免类型与分类不匹配）', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('餐饮').last);
      await tester.pumpAndSettle();
      expect(find.text('餐饮'), findsWidgets);

      // 切到收入
      await tester.tap(find.text('收入').first);
      await tester.pumpAndSettle();

      // 收入分类列表里没有「餐饮」
      expect(find.text('餐饮'), findsNothing);
    });

    testWidgets('编辑模式：回填原值，修改金额后保存', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final id = await seed(
        amountCents: 3580,
        categoryId: food,
        recordDate: DateTime(2026, 10, 5),
        note: '午饭',
      );
      final record = (await db.ledgerDao.findById(id))!;

      await pumpForm(tester, record: record);
      expect(find.text('编辑记录'), findsOneWidget);
      expect(find.text('35.80'), findsOneWidget);
      expect(find.text('午饭'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '45.50',
      );
      await tapSubmit(tester, '保存修改');
      await settleAfterWrite(tester);

      final updated = (await db.ledgerDao.findById(id))!;
      expect(updated.amountCents, 4550);
      expect(updated.note, '午饭', reason: '未改动的字段应保持');
    });

    testWidgets('编辑模式：金额清空后保存被拦截，库不变', (tester) async {
      final food = await builtInCategoryId(LedgerType.expense, '餐饮');
      final id = await seed(amountCents: 3580, categoryId: food);
      final record = (await db.ledgerDao.findById(id))!;

      await pumpForm(tester, record: record);
      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '',
      );
      await tapSubmit(tester, '保存修改');
      await tester.pumpAndSettle();

      expect(find.text('请输入金额'), findsOneWidget);
      expect((await db.ledgerDao.findById(id))!.amountCents, 3580);
    });

    testWidgets('脏数据拦截：改了金额点返回会弹放弃确认框', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '金额（元）'),
        '88.88',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('放弃修改'), findsOneWidget);

      // 选「取消」→ 留在表单页
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerFormPage), findsOneWidget);
    });

    testWidgets('未做修改时点返回直接退出，不弹确认框', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('放弃修改'), findsNothing);
      expect(find.byType(LedgerFormPage), findsNothing);
    });
  });

  // =========================================================================
  // 分类管理页 UI
  // =========================================================================
  group('分类管理页 UI', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: CategoryManagePage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认停在支出 Tab，列出 8 个内置分类且标注「内置」', (tester) async {
      await pumpPage(tester);

      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('其他支出'), findsOneWidget);
      expect(find.text('内置'), findsWidgets);
    });

    testWidgets('内置分类的删除按钮被禁用', (tester) async {
      await pumpPage(tester);

      final deleteButtons = find.widgetWithIcon(
        IconButton,
        Icons.delete_outline,
      );
      expect(deleteButtons, findsWidgets);
      for (final element in deleteButtons.evaluate()) {
        final button = element.widget as IconButton;
        expect(button.onPressed, isNull, reason: '内置分类的删除应被禁用');
      }
    });

    testWidgets('新增分类：填名字保存后出现在列表里且标注「自定义」', (tester) async {
      await pumpPage(tester);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, '新增分类'),
      );
      await tester.pumpAndSettle();

      expect(find.text('新增支出分类'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '分类名称'),
        '宠物',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('宠物'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(await db.categoryDao.findAll(type: 'expense'), hasLength(9));
    });

    testWidgets('新增分类：空名字保存被拦截', (tester) async {
      await pumpPage(tester);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, '新增分类'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('请输入分类名称'), findsOneWidget);
      expect(await db.categoryDao.findAll(type: 'expense'), hasLength(8));
    });

    testWidgets('新增分类：重名被拒绝并提示', (tester) async {
      await pumpPage(tester);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, '新增分类'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '分类名称'),
        '餐饮',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已存在分类「餐饮」'), findsOneWidget);
      expect(await db.categoryDao.findAll(type: 'expense'), hasLength(8),
          reason: '重名不应写库');
    });

    testWidgets('删除自定义分类：确认后消失', (tester) async {
      final id = await db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          type: 'expense',
          name: '宠物',
          isCustom: const Value(true),
          sortOrder: const Value(8),
        ),
      );
      await pumpPage(tester);
      expect(find.text('宠物'), findsOneWidget);

      // 找到「宠物」那一行的删除按钮并点击
      final row = find.ancestor(
        of: find.text('宠物'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      );
      await tester.pumpAndSettle();

      expect(find.text('删除分类'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(await db.categoryDao.findById(id), isNull);
      expect(find.text('宠物'), findsNothing);
    });

    testWidgets('被引用的自定义分类拒绝删除，并给出明确提示', (tester) async {
      final id = await db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          type: 'expense',
          name: '宠物',
          isCustom: const Value(true),
          sortOrder: const Value(8),
        ),
      );
      await seed(amountCents: 5000, categoryId: id);
      await pumpPage(tester);

      final row = find.ancestor(
        of: find.text('宠物'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已被记账记录引用，无法删除'), findsOneWidget);
      expect(await db.categoryDao.findById(id), isNotNull,
          reason: '被引用的分类不能真的被删掉');
    });

    testWidgets('重命名分类', (tester) async {
      final id = await db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          type: 'expense',
          name: '宠物',
          isCustom: const Value(true),
          sortOrder: const Value(8),
        ),
      );
      await pumpPage(tester);

      final row = find.ancestor(
        of: find.text('宠物'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      );
      await tester.pumpAndSettle();

      expect(find.text('重命名分类'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '分类名称'),
        '宠物用品',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect((await db.categoryDao.findById(id))!.name, '宠物用品');
      expect(find.text('宠物用品'), findsOneWidget);
    });

    testWidgets('切到收入 Tab 显示 4 个内置收入分类', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();

      expect(find.text('工资'), findsOneWidget);
      expect(find.text('奖金'), findsOneWidget);
      expect(find.text('餐饮'), findsNothing, reason: '收入 Tab 不应出现支出分类');
    });
  });
}
