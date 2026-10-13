import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:personal_manager/features/life/providers/life_providers.dart';
import 'package:personal_manager/features/life/ui/habits/habit_form_page.dart';
import 'package:personal_manager/features/life/ui/habits/habit_list_page.dart';
import 'package:personal_manager/features/life/ui/habits/widgets/habit_tile.dart';
import 'package:personal_manager/features/life/ui/health/health_form_page.dart';
import 'package:personal_manager/features/life/ui/health/health_list_page.dart';
import 'package:personal_manager/features/life/ui/health/widgets/health_tile.dart';
import 'package:personal_manager/features/life/ui/life_page.dart';
import 'package:personal_manager/features/life/ui/memos/memo_form_page.dart';
import 'package:personal_manager/features/life/ui/memos/memo_list_page.dart';
import 'package:personal_manager/features/life/ui/memos/widgets/memo_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.6 生活管理测试。
///
/// 覆盖验收要求（开发计划 §4.6）：
///   1. 建习惯打卡 3 天（连续天数 = 3）；
///   2. 录睡眠 / 运动各一条；
///   3. 备忘可标记完成。
///
/// 另外覆盖：
/// - `computeHabitStreak` 纯函数的边界（今天没打 / 昨天没打 / 断签 / 空集合）
/// - `sleepHoursText` / `exerciseText` / `weightText` 纯函数
/// - `HabitFrequency.fromCode` 兜底
/// - `MemoFilter` 值对象相等性（`hashCode` 单字段，C33）
/// - `HabitActions` / `HealthActions` / `MemoActions` 的业务规则
///   （名称必填、同日 upsert 覆盖、完成状态切换、频率更新）
/// - 3 个 Tab 的 UI（列表、表单、筛选、切换）
void main() {
  late AppDatabase db;

  /// 点击表单页底部的提交按钮。
  ///
  /// 【为什么要单独抽出来】提交按钮是表单 `ListView` 的**最后一个 child**，
  /// 而 `ListView` 惰性构建 —— 视口不够高时它**不在 Element 树上**，
  /// 直接 `find.widgetWithText(FilledButton, '加习惯')` 会得到 0 个。
  /// 本文件统一用 [useLargeViewport] 把视口放大到 1200x2400，
  /// 按钮因此始终在树上。
  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  /// 点 `TabBar` 里的某个 Tab（按标签文字）。
  ///
  /// 【⛔ 为什么不能直接 `tester.tap(find.widgetWithText(Tab, '备忘'))`】
  /// `Tab extends StatelessWidget`，其 `build` 返回
  /// `SizedBox(child: Center(...))` —— `hitTestSelf` 都是 false，
  /// **不参与 hit-test**；真正接收点击的是 `TabBar` 裹的 `InkWell`（C42）。
  ///
  /// 【为什么用 `find.descendant(of: TabBar, ...)` 限定】
  /// 「健康」「备忘」等文案在页面内容里**也会出现**，不限定作用域会命中多处
  /// （C37 / 规则 22）。
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find
          .ancestor(
            of: find.descendant(
              of: find.byType(TabBar),
              matching: find.text(label),
            ),
            matching: find.byType(InkWell),
          )
          .first,
    );
  }

  /// 把测试视口放大到足以容纳整页内容（内部列表不再需要滚动）。
  ///
  /// 【为什么要这么做】Flutter 测试默认视口只有 800x600，而
  /// `ListView` / `ListView.separated` 是**惰性构建**的 —— 视口外的列表项
  /// **根本不在 Element 树上**，`find.text('...')` 会得到 0 个（C12b）。
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
    // 触发 onCreate（建表）。不跑一次查询的话内存库可能尚未真正打开。
    await db.customSelect('SELECT 1').get();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个带内存库 override 的容器。
  ///
  /// 【⚠️ 绝不要在这里写 `await Future.delayed(...)`】
  /// `test()` 跑在 FakeAsync zone 里，`Future.delayed` 不会自行推进，
  /// 需要 `tester.pump` 驱动时钟；`test()` 里没有 tester，
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

  /// 直接往库里塞一个习惯，返回 id。
  Future<int> seedHabit({
    String name = '示例习惯',
    HabitFrequency frequency = HabitFrequency.daily,
  }) {
    return db.habitDao.insertHabit(
      HabitsCompanion.insert(
        name: name,
        frequency: frequency.code,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 直接往库里塞一条打卡，返回 id。
  Future<int> seedCheckin(int habitId, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return db.habitCheckinDao.insertCheckin(
      HabitCheckinsCompanion.insert(habitId: habitId, date: d),
    );
  }

  /// 直接往库里塞一条健康记录，返回 id。
  Future<int> seedHealth({
    required DateTime date,
    double? sleepHours,
    int? exerciseMinutes,
    double? weightKg,
  }) {
    final d = DateTime(date.year, date.month, date.day);
    return db.healthRecordDao.insertRecord(
      HealthRecordsCompanion.insert(
        date: d,
        sleepHours: Value(sleepHours),
        exerciseMinutes: Value(exerciseMinutes),
        weightKg: Value(weightKg),
      ),
    );
  }

  /// 直接往库里塞一条备忘，返回 id。
  Future<int> seedMemo({
    String title = '示例备忘',
    String content = '',
    DateTime? remindAt,
    bool isCompleted = false,
  }) {
    return db.lifeMemoDao.insertMemo(
      LifeMemosCompanion.insert(
        title: title,
        content: Value(content),
        remindAt: Value(remindAt),
        isCompleted: Value(isCompleted),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 读取一个 `StreamProvider.autoDispose` 的首值。
  ///
  /// 【为什么是 listen + read，而不是裸 read】
  /// autoDispose 的 provider 若没有监听者，`read(provider.future)` 之后
  /// 会立刻调度销毁，流还没吐出第一个值就被 dispose，抛
  /// 「disposed during loading state」。先 `listen` 占住订阅再取。
  Future<T> firstOf<T>(
    ProviderContainer container,
    StreamProvider<T> provider,
  ) async {
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    return container.read(provider.future);
  }

  // =========================================================================
  // 纯函数
  // =========================================================================

  group('computeHabitStreak 连续天数', () {
    final today = DateTime(2026, 10, 11);

    test('空集合返回 0', () {
      expect(computeHabitStreak(const [], today: today), 0);
    });

    test('今天已打 + 昨天已打 + 前天已打 = 3 天', () {
      final dates = [
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 9),
      ];
      expect(computeHabitStreak(dates, today: today), 3);
    });

    test('今天没打但昨天打了 → 连续仍算（不清零）', () {
      final dates = [DateTime(2026, 10, 10), DateTime(2026, 10, 9)];
      expect(computeHabitStreak(dates, today: today), 2);
    });

    test('今天与昨天都没打 → 0（断签）', () {
      final dates = [DateTime(2026, 10, 9), DateTime(2026, 10, 8)];
      expect(computeHabitStreak(dates, today: today), 0);
    });

    test('中间断一天，只算最近的连续段', () {
      final dates = [
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 10),
        // 10-09 缺
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 7),
      ];
      expect(computeHabitStreak(dates, today: today), 2);
    });

    test('同一天重复（带时分秒）只算一天', () {
      final dates = [
        DateTime(2026, 10, 11, 8),
        DateTime(2026, 10, 11, 20),
        DateTime(2026, 10, 10, 9),
      ];
      expect(computeHabitStreak(dates, today: today), 2);
    });

    test('跨月边界连续（10-01 与 09-30）', () {
      final t = DateTime(2026, 10, 1);
      final dates = [DateTime(2026, 10, 1), DateTime(2026, 9, 30)];
      expect(computeHabitStreak(dates, today: t), 2);
    });

    test('跨年边界连续（01-01 与 12-31）', () {
      final t = DateTime(2026, 1, 1);
      final dates = [DateTime(2026, 1, 1), DateTime(2025, 12, 31)];
      expect(computeHabitStreak(dates, today: t), 2);
    });
  });

  group('HabitFrequency', () {
    test('fromCode 正常解析', () {
      expect(HabitFrequency.fromCode('daily'), HabitFrequency.daily);
      expect(HabitFrequency.fromCode('weekly'), HabitFrequency.weekly);
    });

    test('未知值 / null 兜底为每天', () {
      expect(HabitFrequency.fromCode('monthly'), HabitFrequency.daily);
      expect(HabitFrequency.fromCode(null), HabitFrequency.daily);
    });

    test('code 与 label 齐全', () {
      expect(HabitFrequency.daily.code, 'daily');
      expect(HabitFrequency.daily.label, '每天');
      expect(HabitFrequency.weekly.code, 'weekly');
      expect(HabitFrequency.weekly.label, '每周');
    });
  });

  group('健康数值展示纯函数', () {
    test('sleepHoursText', () {
      expect(sleepHoursText(null), '—');
      expect(sleepHoursText(7), '7 小时');
      expect(sleepHoursText(7.5), '7.5 小时');
    });

    test('exerciseText', () {
      expect(exerciseText(null), '—');
      expect(exerciseText(30), '30 分钟');
      expect(exerciseText(0), '0 分钟');
    });

    test('weightText', () {
      expect(weightText(null), '—');
      expect(weightText(65), '65 kg');
      expect(weightText(65.5), '65.5 kg');
    });
  });

  group('MemoFilter 值对象', () {
    test('相同字段相等且 hashCode 相同', () {
      const a = MemoFilter(isCompleted: true);
      const b = MemoFilter(isCompleted: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('不同字段不相等', () {
      expect(const MemoFilter(isCompleted: true),
          isNot(const MemoFilter(isCompleted: false)));
      expect(const MemoFilter(), isNot(const MemoFilter(isCompleted: false)));
    });

    test('isUnfiltered 只在 null 时为真', () {
      expect(const MemoFilter().isUnfiltered, isTrue);
      expect(const MemoFilter(isCompleted: false).isUnfiltered, isFalse);
    });

    test('copyWith clearCompleted 清空筛选', () {
      const f = MemoFilter(isCompleted: true);
      expect(f.copyWith(clearCompleted: true).isCompleted, isNull);
      expect(f.copyWith(isCompleted: false).isCompleted, isFalse);
    });
  });

  // =========================================================================
  // Actions（业务规则）
  // =========================================================================

  group('HabitActions', () {
    test('创建时可以指定频率，默认每天', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id1 = await actions.create(name: '  晨跑  ');
      final id2 = await actions.create(
        name: '读书',
        frequency: HabitFrequency.weekly,
      );

      final h1 = await db.habitDao.findById(id1);
      final h2 = await db.habitDao.findById(id2);
      expect(h1!.name, '晨跑'); // trim 生效
      expect(h1.frequency, 'daily');
      expect(h2!.frequency, 'weekly');
    });

    test('名称为空 / 全空格 → ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      expect(() => actions.create(name: ''), throwsArgumentError);
      expect(() => actions.create(name: '   '), throwsArgumentError);
    });

    test('update 可改名称与频率', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '旧名');
      final habit = (await db.habitDao.findById(id))!;

      final ok = await actions.update(
        habit: habit,
        name: '新名',
        frequency: HabitFrequency.weekly,
      );
      expect(ok, isTrue);
      final after = (await db.habitDao.findById(id))!;
      expect(after.name, '新名');
      expect(after.frequency, 'weekly');
    });

    test('update 名称空 → ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '有效');
      final habit = (await db.habitDao.findById(id))!;
      expect(
        () => actions.update(
          habit: habit,
          name: '  ',
          frequency: HabitFrequency.daily,
        ),
        throwsArgumentError,
      );
    });

    test('toggleCheckin 未打则打、已打则取消', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '习惯');
      final day = DateTime(2026, 10, 11, 22, 30);

      expect(await actions.isCheckedOn(id, day), isFalse);
      expect(await actions.toggleCheckin(id, day), isTrue);
      expect(await actions.isCheckedOn(id, day), isTrue);
      expect(await actions.toggleCheckin(id, day), isFalse);
      expect(await actions.isCheckedOn(id, day), isFalse);
    });

    test('同一天重复打卡幂等（只留一条）', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '习惯');
      final day = DateTime(2026, 10, 11);

      // 打 → 取消 → 再打：只应剩 1 条
      await actions.toggleCheckin(id, day);
      await actions.toggleCheckin(id, day);
      await actions.toggleCheckin(id, day);
      final dates = await db.habitCheckinDao.checkinDatesOfHabit(id);
      expect(dates.length, 1);
    });

    test('打卡 3 天后连续天数为 3', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '习惯');
      final today = lifeToday();
      for (var i = 0; i < 3; i++) {
        await actions.toggleCheckin(id, DateTime(today.year, today.month, today.day - i));
      }
      final dates = await db.habitCheckinDao.checkinDatesOfHabit(id);
      expect(computeHabitStreak(dates, today: today), 3);
    });

    test('删除习惯会级联删除打卡记录', () async {
      final c = await makeContainer();
      final actions = c.read(habitActionsProvider);
      final id = await actions.create(name: '习惯');
      await actions.toggleCheckin(id, DateTime(2026, 10, 11));
      expect(await db.habitCheckinDao.countAll(), 1);

      await actions.remove(id);
      expect(await db.habitDao.countAll(), 0);
      expect(await db.habitCheckinDao.countAll(), 0);
    });
  });

  group('HealthActions', () {
    test('新增某天记录，三个数值都可空', () async {
      final c = await makeContainer();
      final actions = c.read(healthActionsProvider);
      final day = DateTime(2026, 10, 11, 15);
      await actions.upsert(date: day, sleepHours: 7.5, exerciseMinutes: 30);

      final rec = await db.healthRecordDao.findByDate(day);
      expect(rec, isNotNull);
      expect(rec!.sleepHours, 7.5);
      expect(rec.exerciseMinutes, 30);
      expect(rec.weightKg, isNull);
      // 日期归一化到 00:00
      expect(rec.date.hour, 0);
      expect(rec.date.minute, 0);
    });

    test('同一天再录 → 更新而非新增', () async {
      final c = await makeContainer();
      final actions = c.read(healthActionsProvider);
      final day = DateTime(2026, 10, 11);

      final id1 = await actions.upsert(date: day, sleepHours: 6);
      final id2 = await actions.upsert(date: day, sleepHours: 8, weightKg: 65);
      expect(id1, id2);
      expect(await db.healthRecordDao.countAll(), 1);

      final rec = await db.healthRecordDao.findByDate(day);
      expect(rec!.sleepHours, 8);
      expect(rec.weightKg, 65);
    });

    test('带时分秒的同一天按天归一化（仍只一条）', () async {
      final c = await makeContainer();
      final actions = c.read(healthActionsProvider);
      await actions.upsert(date: DateTime(2026, 10, 11, 1), sleepHours: 5);
      await actions.upsert(date: DateTime(2026, 10, 11, 23), sleepHours: 9);
      expect(await db.healthRecordDao.countAll(), 1);
      final rec = await db.healthRecordDao.findByDate(DateTime(2026, 10, 11));
      expect(rec!.sleepHours, 9);
    });

    test('upsert 可把已填数值清回 null', () async {
      final c = await makeContainer();
      final actions = c.read(healthActionsProvider);
      final day = DateTime(2026, 10, 11);
      await actions.upsert(date: day, sleepHours: 7, exerciseMinutes: 20);
      await actions.upsert(date: day, sleepHours: null, exerciseMinutes: null);

      final rec = await db.healthRecordDao.findByDate(day);
      expect(rec!.sleepHours, isNull);
      expect(rec.exerciseMinutes, isNull);
    });

    test('remove 删除记录', () async {
      final c = await makeContainer();
      final actions = c.read(healthActionsProvider);
      final id = await actions.upsert(date: DateTime(2026, 10, 11), sleepHours: 7);
      await actions.remove(id);
      expect(await db.healthRecordDao.countAll(), 0);
    });
  });

  group('MemoActions', () {
    test('创建备忘，内容 trim；标题 trim', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      final id = await actions.create(title: '  交物业费  ', content: '  月底前  ');
      final memo = await db.lifeMemoDao.findById(id);
      expect(memo!.title, '交物业费');
      expect(memo.content, '月底前');
      expect(memo.isCompleted, isFalse);
    });

    test('标题为空 → ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      expect(() => actions.create(title: ''), throwsArgumentError);
      expect(() => actions.create(title: '   '), throwsArgumentError);
    });

    test('toggleCompleted 切换完成状态', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      final id = await actions.create(title: '备忘');

      await actions.toggleCompleted(id, true);
      expect((await db.lifeMemoDao.findById(id))!.isCompleted, isTrue);
      await actions.toggleCompleted(id, false);
      expect((await db.lifeMemoDao.findById(id))!.isCompleted, isFalse);
    });

    test('update 改标题 / 内容 / 提醒时间，并可清空提醒', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      final id = await actions.create(title: '旧标题', content: '旧内容');
      final memo = (await db.lifeMemoDao.findById(id))!;

      final remind = DateTime(2026, 10, 20, 9);
      await actions.update(
        memo: memo,
        title: '新标题',
        content: '新内容',
        remindAt: remind,
      );
      var after = (await db.lifeMemoDao.findById(id))!;
      expect(after.title, '新标题');
      expect(after.content, '新内容');
      expect(after.remindAt, remind);

      await actions.update(
        memo: after,
        title: '新标题',
        content: '新内容',
        remindAt: null,
      );
      after = (await db.lifeMemoDao.findById(id))!;
      expect(after.remindAt, isNull);
    });

    test('update 标题为空 → ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      final id = await actions.create(title: '有效');
      final memo = (await db.lifeMemoDao.findById(id))!;
      expect(
        () => actions.update(memo: memo, title: '  ', content: ''),
        throwsArgumentError,
      );
    });

    test('remove 删除备忘', () async {
      final c = await makeContainer();
      final actions = c.read(memoActionsProvider);
      final id = await actions.create(title: '备忘');
      await actions.remove(id);
      expect(await db.lifeMemoDao.countAll(), 0);
    });
  });

  // =========================================================================
  // Providers（读侧）
  // =========================================================================

  group('providers 读侧', () {
    test('habitStreakProvider 反映连续天数', () async {
      final c = await makeContainer();
      final id = await seedHabit();
      final today = lifeToday();
      for (var i = 0; i < 3; i++) {
        await seedCheckin(
          id,
          DateTime(today.year, today.month, today.day - i),
        );
      }
      final sub = c.listen(habitStreakProvider(id), (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(habitStreakProvider(id).future), 3);
    });

    test('todayCheckedHabitCountProvider 只数今天', () async {
      final c = await makeContainer();
      final id = await seedHabit();
      final today = lifeToday();
      await seedCheckin(id, today);
      await seedCheckin(id, DateTime(today.year, today.month, today.day - 1));

      final sub = c.listen(todayCheckedHabitCountProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(todayCheckedHabitCountProvider.future), 1);
    });

    test('healthRecordListProvider 按日期倒序', () async {
      final c = await makeContainer();
      await seedHealth(date: DateTime(2026, 10, 9), sleepHours: 6);
      await seedHealth(date: DateTime(2026, 10, 11), sleepHours: 8);
      await seedHealth(date: DateTime(2026, 10, 10), sleepHours: 7);

      final list = await firstOf(c, healthRecordListProvider);
      expect(list.map((r) => r.date.day).toList(), [11, 10, 9]);
    });

    test('pendingMemoCountProvider 只数未完成', () async {
      final c = await makeContainer();
      await seedMemo(title: 'A');
      await seedMemo(title: 'B', isCompleted: true);
      await seedMemo(title: 'C');

      final sub = c.listen(pendingMemoCountProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(pendingMemoCountProvider.future), 2);
    });

    test('memoListProvider 随筛选变化', () async {
      final c = await makeContainer();
      await seedMemo(title: 'A');
      await seedMemo(title: 'B', isCompleted: true);

      final sub = c.listen(memoListProvider, (_, _) {});
      addTearDown(sub.close);

      var list = await c.read(memoListProvider.future);
      expect(list.length, 2);

      c.read(memoFilterProvider.notifier).setCompleted(true);
      list = await c.read(memoListProvider.future);
      expect(list.length, 1);
      expect(list.single.title, 'B');
    });
  });

  // =========================================================================
  // UI
  // =========================================================================

  group('习惯 Tab UI', () {
    testWidgets('空列表显示空状态', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HabitListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有习惯'), findsOneWidget);
    });

    testWidgets('列表显示习惯名 + 频率 + 连续天数', (tester) async {
      useLargeViewport(tester);
      final id = await seedHabit(name: '晨跑', frequency: HabitFrequency.daily);
      final today = lifeToday();
      for (var i = 0; i < 3; i++) {
        await seedCheckin(id, DateTime(today.year, today.month, today.day - i));
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HabitListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.descendant(
        of: find.byType(HabitTile),
        matching: find.text('晨跑'),
      ), findsOneWidget);
      expect(find.descendant(
        of: find.byType(HabitTile),
        matching: find.text('连续 3 天'),
      ), findsOneWidget);
    });

    testWidgets('点打卡按钮切换今日状态', (tester) async {
      useLargeViewport(tester);
      final id = await seedHabit(name: '晨跑');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HabitListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 初始未打卡 → 空心圈
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(id, isNotNull);

      // 直接点打卡按钮（不是卡片本身）—— 该 IconButton 就是切换入口
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(await db.habitCheckinDao.countToday(), 1);
    });

    testWidgets('新增习惯表单保存后出现在列表', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HabitListPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('加习惯'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitFormPage), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '早睡');
      await tapSubmit(tester, '加习惯');
      await tester.pumpAndSettle();

      expect(find.byType(HabitFormPage), findsNothing);
      expect(find.text('早睡'), findsOneWidget);
      expect(await db.habitDao.countAll(), 1);
    });
  });

  group('健康 Tab UI', () {
    testWidgets('空列表显示空状态', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HealthListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有健康记录'), findsOneWidget);
    });

    testWidgets('列表显示三项指标', (tester) async {
      useLargeViewport(tester);
      await seedHealth(
        date: DateTime(2026, 10, 11),
        sleepHours: 7.5,
        exerciseMinutes: 30,
        weightKg: 65,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HealthListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HealthTile), findsOneWidget);
      expect(find.text('7.5 小时'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
      expect(find.text('65 kg'), findsOneWidget);
    });

    testWidgets('新增表单保存后出现在列表', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HealthListPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('记健康'));
      await tester.pumpAndSettle();
      expect(find.byType(HealthFormPage), findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '8');
      await tester.enterText(fields.at(1), '45');
      await tapSubmit(tester, '记健康');
      await tester.pumpAndSettle();

      expect(find.byType(HealthFormPage), findsNothing);
      expect(find.text('8 小时'), findsOneWidget);
      expect(find.text('45 分钟'), findsOneWidget);
      expect(await db.healthRecordDao.countAll(), 1);
    });

    testWidgets('负数输入被表单拦住', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HealthFormPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '-1');
      await tapSubmit(tester, '记健康');
      await tester.pumpAndSettle();

      expect(find.text('不能为负数'), findsOneWidget);
      expect(await db.healthRecordDao.countAll(), 0);
    });
  });

  group('备忘 Tab UI', () {
    testWidgets('空列表显示空状态', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: MemoListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有备忘'), findsOneWidget);
    });

    testWidgets('勾选框可标记完成', (tester) async {
      useLargeViewport(tester);
      final id = await seedMemo(title: '交物业费');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: MemoListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemoTile), findsOneWidget);
      expect(find.text('交物业费'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect((await db.lifeMemoDao.findById(id))!.isCompleted, isTrue);
    });

    testWidgets('筛选未完成只显示未完成项', (tester) async {
      useLargeViewport(tester);
      await seedMemo(title: '待办事项');
      await seedMemo(title: '已完成事项', isCompleted: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: MemoListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemoTile), findsNWidgets(2));

      await tester.tap(find.text('未完成'));
      await tester.pumpAndSettle();

      expect(find.byType(MemoTile), findsOneWidget);
      expect(find.text('待办事项'), findsOneWidget);
      expect(find.text('已完成事项'), findsNothing);
    });

    testWidgets('新增备忘表单保存后出现在列表', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: MemoListPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('加备忘'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoFormPage), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '买猫粮');
      await tapSubmit(tester, '加备忘');
      await tester.pumpAndSettle();

      expect(find.byType(MemoFormPage), findsNothing);
      expect(find.text('买猫粮'), findsOneWidget);
      expect(await db.lifeMemoDao.countAll(), 1);
    });
  });

  group('生活管理页（3 Tab 壳）', () {
    testWidgets('默认显示习惯 Tab，可切换到健康 / 备忘', (tester) async {
      useLargeViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: LifePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('生活管理'), findsOneWidget);
      expect(find.byType(HabitListPage), findsOneWidget);

      await tapTab(tester, '健康');
      await tester.pumpAndSettle();
      expect(find.byType(HealthListPage), findsOneWidget);

      await tapTab(tester, '备忘');
      await tester.pumpAndSettle();
      expect(find.byType(MemoListPage), findsOneWidget);
    });
  });
}
