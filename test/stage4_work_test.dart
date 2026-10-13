import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/daos/work_log_dao.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/models/enums.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:personal_manager/features/work/providers/work_providers.dart';
import 'package:personal_manager/features/work/ui/journals/journal_form_page.dart';
import 'package:personal_manager/features/work/ui/journals/journal_list_page.dart';
import 'package:personal_manager/features/work/ui/logs/work_log_form_page.dart';
import 'package:personal_manager/features/work/ui/logs/work_log_list_page.dart';
import 'package:personal_manager/features/work/ui/projects/project_form_page.dart';
import 'package:personal_manager/features/work/ui/projects/project_list_page.dart';
import 'package:personal_manager/features/work/ui/projects/widgets/project_tile.dart';
import 'package:personal_manager/features/work/ui/reports/report_page.dart';
import 'package:personal_manager/features/work/ui/work_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.5 工作管理测试。
///
/// 覆盖验收要求（开发计划 §4.5）：
///   建项目录 3 天工时 → 一键生成周报 → 文本可复制；日志可搜。
///
/// 另外覆盖：
/// - `ReportRange` 的三种范围工厂（本周 / 上周 / 本月）与 `days`
/// - `buildReportText` 纯函数（含工时汇总、占位提示、右开区间展示）
/// - `projectProgress` 除零与 clamp
/// - `ProjectFilter` / `WorkLogFilter` / `JournalFilter` 值对象的 `==` / `hashCode`
/// - `ProjectActions` / `WorkLogActions` / `JournalActions` 的业务规则
///   （名称必填、进度 0~100、工时 > 0、日志内容必填、100% 自动 completed）
/// - 4 个 Tab 的 UI（列表、表单、筛选、切换）
void main() {
  late AppDatabase db;

  /// 点击表单页底部的提交按钮。
  ///
  /// 【为什么要单独抽出来】提交按钮是表单 `ListView` 的**最后一个 child**，
  /// 而 `ListView` 惰性构建 —— 视口不够高时它**不在 Element 树上**，
  /// 直接 `find.widgetWithText(FilledButton, '加项目')` 会得到 0 个。
  /// 本文件统一用 [useLargeViewport] 把视口放大到 1200x2400，
  /// 按钮因此始终在树上。
  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  /// 点 `TabBar` 里的某个 Tab（按标签文字）。
  ///
  /// 【⛔ 为什么不能直接 `tester.tap(find.widgetWithText(Tab, '项目'))`】
  /// 阶段 4.4 实测会刷出 `Warning: A call to tap() ... would not hit test
  /// on the specified widget`。
  /// 根因（已查 `flutter/lib/src/material/tabs.dart` 源码确认）：
  /// `Tab extends StatelessWidget`，其 `build` 返回
  /// `SizedBox(child: Center(widthFactor: 1.0, child: label))`
  /// —— `SizedBox` / `Center` 的 `hitTestSelf` 都是 false，**不参与 hit-test**。
  /// 真正接收点击的是 `TabBar` 给每个 tab 裹的 **`InkWell`**。
  ///
  /// 测试当时可能是绿的（点中心恰好仍落在同一槽位），但那是
  /// **依赖布局巧合**；且警告噪音会掩盖真问题（见 C31 / C42）。
  ///
  /// 【为什么用 `find.descendant(of: TabBar, ...)` 限定】
  /// 「项目」「工时」「周报」「日志」这些文案在页面内容里**也会出现**
  /// （如空状态标题「还没有工时记录」含"工时"、FAB 文案「记工时」等）
  /// —— 不限定作用域会命中多处（见 C37）。
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
  /// **根本不在 Element 树上**，`find.text('...')` 会得到 0 个。
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
  /// 该 await 会**永久挂起**（10 分钟后被测试级超时杀掉）。
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

  /// 直接往库里塞一个项目，返回 id。
  Future<int> seedProject({
    String name = '示例项目',
    ProgressStatus status = ProgressStatus.ongoing,
    int progress = 0,
    int priority = 1,
    DateTime? startDate,
    DateTime? dueDate,
    String? note,
  }) {
    return db.projectDao.insertProject(
      ProjectsCompanion.insert(
        name: name,
        status: status.code,
        progress: Value(progress),
        priority: Value(priority),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        note: Value(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 直接往库里塞一条工时，返回 id。
  Future<int> seedLog({
    required int projectId,
    required DateTime date,
    int minutes = 60,
    String summary = '',
  }) {
    final d = DateTime(date.year, date.month, date.day);
    return db.workLogDao.insertLog(
      WorkLogsCompanion.insert(
        projectId: projectId,
        date: d,
        minutes: minutes,
        summary: Value(summary),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 直接往库里塞一条日志，返回 id。
  Future<int> seedJournal({
    required DateTime date,
    int? projectId,
    String content = '今天的工作内容',
    String? achievement,
    String? problem,
  }) {
    final d = DateTime(date.year, date.month, date.day);
    return db.workJournalDao.insertJournal(
      WorkJournalsCompanion.insert(
        date: d,
        projectId: Value(projectId),
        // `content` 在表里是 `withDefault` → drift 归为可选列，
        // `WorkJournalsCompanion.insert` 形参类型是 `Value<String>`。
        content: Value(content),
        achievement: Value(achievement),
        problem: Value(problem),
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
  ///
  /// 【⚠️ 为什么 provider 要以**闭包**传入】
  /// `ProviderContainer.listen` 的形参类型是 `ProviderListenable<T>`，
  /// 但 **`ProviderListenable` **不在** `flutter_riverpod.dart` 的导出清单里**
  /// （只在 `riverpod/misc.dart` 导出，而本项目只声明了 `flutter_riverpod`）。
  /// 所以这里把 `listen(...)` 本身作为闭包传进来，泛型 `T` 由两个闭包
  /// 的返回类型推断，helper 完全不需要写 provider 的类型（见 C34）。
  Future<T> firstOf<T>(
    ProviderContainer c,
    ProviderSubscription<AsyncValue<T>> Function() listen,
    Future<T> Function() read,
  ) async {
    final sub = listen();
    try {
      for (var i = 0; i < 5; i++) {
        await null;
      }
      return await read();
    } finally {
      sub.close();
    }
  }

  // =========================================================================
  // 验收：建项目录 3 天工时 → 一键生成周报 → 文本可复制
  // =========================================================================
  group('验收：建项目录 3 天工时 → 生成周报 → 文本可复制', () {
    test('项目 + 3 天工时，周报正确聚合出总工时与按项目分组', () async {
      final c = await makeContainer();
      final actions = c.read(workLogActionsProvider);

      final pid = await seedProject(name: '内部管理工具');
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day - 2);
      final day2 = DateTime(now.year, now.month, now.day - 1);
      final day3 = DateTime(now.year, now.month, now.day);

      await actions.create(projectId: pid, date: day1, minutes: 120, summary: '需求梳理');
      await actions.create(projectId: pid, date: day2, minutes: 90, summary: '数据库设计');
      await actions.create(projectId: pid, date: day3, minutes: 150, summary: '界面开发');

      // 累计 360 分钟
      expect(await actions.totalMinutesOfProject(pid), 360);

      // 用"近 7 天"做范围，确保 3 条都落在里面
      final start = DateTime(now.year, now.month, now.day - 6);
      final end = DateTime(now.year, now.month, now.day + 1);

      // ① 走 ACtions 透传的 DAO 聚合（周报页用的就是它）
      final groups = await actions.summaryBetween(start, end);
      expect(groups.length, 1);
      expect(groups.first.projectName, '内部管理工具');
      expect(groups.first.totalMinutes, 360);

      final logs = await db.workLogDao.findBetween(start, end);
      expect(logs.length, 3);
      // findBetween 按日期升序
      expect(logs.first.date, day1);
      expect(logs.last.date, day3);
    });
  });

  // =========================================================================
  // 验收：日志可搜
  // =========================================================================
  group('验收：日志可搜', () {
    test('按关键字搜索日志内容 / 成果 / 问题', () async {
      final c = await makeContainer();
      final now = DateTime.now();

      await seedJournal(
        date: now,
        content: '完成登录模块联调',
        achievement: '登录成功率 100%',
      );
      await seedJournal(
        date: now,
        content: '修复导出乱码',
        problem: '字符集处理有遗漏',
      );

      // 搜"登录" → 命中第 1 条
      final r1 = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(r1.length, 2);

      c.read(journalFilterProvider.notifier).setKeyword('登录');
      final r2 = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(r2.length, 1);
      expect(r2.first.content, '完成登录模块联调');

      // 搜"字符集" → 命中第 2 条（在 problem 字段里）
      c.read(journalFilterProvider.notifier).setKeyword('字符集');
      final r3 = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(r3.length, 1);
      expect(r3.first.content, '修复导出乱码');

      // 搜不存在的 → 空
      c.read(journalFilterProvider.notifier).setKeyword('不存在的关键字');
      final r4 = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(r4, isEmpty);
    });

    test('清空关键字后恢复全部', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedJournal(date: now, content: '甲');
      await seedJournal(date: now, content: '乙');

      final notifier = c.read(journalFilterProvider.notifier);
      notifier.setKeyword('甲');
      var list = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(list.length, 1);

      notifier.setKeyword('');
      list = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(list.length, 2);
    });
  });

  // =========================================================================
  // 纯函数：项目进度
  // =========================================================================
  group('projectProgress 纯函数', () {
    Project make(int progress) => Project(
          id: 1,
          name: 'p',
          status: ProgressStatus.ongoing.code,
          progress: progress,
          priority: 1,
          createdAt: DateTime.now(),
        );

    test('0 → 0.0，50 → 0.5，100 → 1.0', () {
      expect(projectProgress(make(0)), 0.0);
      expect(projectProgress(make(50)), closeTo(0.5, 1e-9));
      expect(projectProgress(make(100)), 1.0);
    });

    test('越界值被 clamp 到 0.0~1.0', () {
      expect(projectProgress(make(-10)), 0.0);
      expect(projectProgress(make(180)), 1.0);
    });
  });

  // =========================================================================
  // 纯函数：项目优先级标签
  // =========================================================================
  group('projectPriorityLabel 纯函数', () {
    test('0/1/2 → 低/中/高', () {
      expect(projectPriorityLabel(0), '低');
      expect(projectPriorityLabel(1), '中');
      expect(projectPriorityLabel(2), '高');
    });

    test('非法值兜底为「低」（不抛异常）', () {
      expect(projectPriorityLabel(9), '低');
      expect(projectPriorityLabel(-1), '低');
    });
  });

  // =========================================================================
  // 纯函数：周报范围
  // =========================================================================
  group('ReportRange 范围工厂', () {
    test('本周是「周一 00:00 ~ 下周一 00:00」，共 7 天', () {
      // 2026-10-07 是星期三
      final wed = DateTime(2026, 10, 7);
      final r = ReportRange.thisWeek(today: wed);
      expect(r.start, DateTime(2026, 10, 5)); // 周一
      expect(r.end, DateTime(2026, 10, 12)); // 下周一
      expect(r.days, 7);
    });

    test('周日也归入「本周」（周一为起点）', () {
      final sun = DateTime(2026, 10, 11); // 星期日
      final r = ReportRange.thisWeek(today: sun);
      expect(r.start, DateTime(2026, 10, 5));
      expect(r.end, DateTime(2026, 10, 12));
    });

    test('上周 = 本周整体往前移 7 天', () {
      final wed = DateTime(2026, 10, 7);
      final r = ReportRange.lastWeek(today: wed);
      expect(r.start, DateTime(2026, 9, 28));
      expect(r.end, DateTime(2026, 10, 5));
      expect(r.days, 7);
    });

    test('本月是「1 号 ~ 下月 1 号」', () {
      final r = ReportRange.thisMonth(today: DateTime(2026, 10, 15));
      expect(r.start, DateTime(2026, 10, 1));
      expect(r.end, DateTime(2026, 11, 1));
      expect(r.days, 31);
    });

    test('值对象 == / hashCode：同范围相等，不同范围不等', () {
      final a = ReportRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 8));
      final b = ReportRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 8));
      final c = ReportRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 9));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  // =========================================================================
  // 纯函数：周报文本生成
  // =========================================================================
  group('buildReportText 纯函数', () {
    WeeklyReportData makeData({
      required List<ProjectWorkSummary> groups,
      required List<WorkLog> logs,
      required int totalMinutes,
      DateTime? start,
      DateTime? end,
    }) {
      return WeeklyReportData(
        range: ReportRange(
          start: start ?? DateTime(2026, 10, 5),
          end: end ?? DateTime(2026, 10, 12),
        ),
        groups: groups,
        logs: logs,
        totalMinutes: totalMinutes,
      );
    }

    test('含标题 / 工时汇总 / 三段结构，且区间右端减一天展示', () {
      final text = buildReportText(
        data: makeData(
          groups: const [
            ProjectWorkSummary(
              projectId: 1,
              projectName: '项目 A',
              totalMinutes: 480,
            ),
            ProjectWorkSummary(
              projectId: 2,
              projectName: '项目 B',
              totalMinutes: 270,
            ),
          ],
          logs: const [],
          totalMinutes: 750,
        ),
        highlights: '完成了登录模块',
        plans: '推进报表功能',
      );

      // range.end = 2026-10-12（右开），展示应为 10-11
      expect(text, contains('工作周报（2026-10-05 ~ 2026-10-11）'));
      expect(text, contains('一、工时汇总（共 12小时30分）'));
      expect(text, contains('· 项目 A：8小时'));
      expect(text, contains('· 项目 B：4小时30分'));
      expect(text, contains('二、本周重点'));
      expect(text, contains('完成了登录模块'));
      expect(text, contains('三、下周计划'));
      expect(text, contains('推进报表功能'));
    });

    test('无工时时提示「本期间没有工时记录」', () {
      final text = buildReportText(
        data: makeData(groups: const [], logs: const [], totalMinutes: 0),
      );
      expect(text, contains('本期间没有工时记录'));
    });

    test('重点 / 计划为空时显示「（待补充）」占位', () {
      final text = buildReportText(
        data: makeData(groups: const [], logs: const [], totalMinutes: 0),
      );
      expect(text, contains('（待补充）'));
    });

    test('重点 / 计划只有空白字符时同样视为未填', () {
      final text = buildReportText(
        data: makeData(groups: const [], logs: const [], totalMinutes: 0),
        highlights: '   \n  ',
        plans: '\t',
      );
      // 出现两次「（待补充）」：重点 + 计划
      expect('（待补充）'.allMatches(text).length, 2);
    });
  });

  // =========================================================================
  // 值对象：筛选条件
  // =========================================================================
  group('筛选值对象 == / hashCode', () {
    test('ProjectFilter：同状态同优先级相等', () {
      const a = ProjectFilter(status: ProgressStatus.ongoing, priority: 2);
      const b = ProjectFilter(status: ProgressStatus.ongoing, priority: 2);
      const c = ProjectFilter(status: ProgressStatus.ongoing, priority: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('ProjectFilter：clearStatus / clearPriority 生效', () {
      const f = ProjectFilter(status: ProgressStatus.ongoing, priority: 1);
      expect(f.copyWith(clearStatus: true).status, isNull);
      expect(f.copyWith(clearPriority: true).priority, isNull);
      // 不 clear 时保留原值
      expect(f.copyWith().status, ProgressStatus.ongoing);
      expect(f.isUnfiltered, isFalse);
      expect(const ProjectFilter().isUnfiltered, isTrue);
    });

    test('WorkLogFilter：clearRange 同时清空起止', () {
      final f = WorkLogFilter(
        projectId: 3,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 8),
      );
      final cleared = f.copyWith(clearRange: true);
      expect(cleared.start, isNull);
      expect(cleared.end, isNull);
      expect(cleared.projectId, 3, reason: '清空日期不应影响项目筛选');

      final clearedProject = f.copyWith(clearProject: true);
      expect(clearedProject.projectId, isNull);
      expect(clearedProject.start, DateTime(2026, 10, 1));
    });

    test('JournalFilter：daoKeyword 空串归一化成 null', () {
      expect(const JournalFilter().daoKeyword, isNull);
      expect(const JournalFilter(keyword: '  ').daoKeyword, isNull);
      expect(const JournalFilter(keyword: ' abc ').daoKeyword, 'abc');
    });
  });

  // =========================================================================
  // 业务规则：ProjectActions
  // =========================================================================
  group('ProjectActions 业务规则', () {
    test('项目名为空 → 抛 ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      expect(
        () => actions.create(name: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('名称首尾空白被 trim', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final id = await actions.create(name: '  带空格的 项目  ');
      final p = await db.projectDao.findById(id);
      expect(p!.name, '带空格的 项目');
    });

    test('进度越界被 clamp 到 0~100', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final id = await actions.create(name: '越界项目', progress: 500);
      final p = await db.projectDao.findById(id);
      expect(p!.progress, 100);
    });

    test('优先级越界被 clamp 到 0~2', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final id = await actions.create(name: '优先级越界', priority: 9);
      final p = await db.projectDao.findById(id);
      expect(p!.priority, 2);
    });

    test('进度到 100% 时自动置为「已完成」（规则来自 DAO）', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final id = await actions.create(name: '全完成项目');

      await actions.updateProgress(id: id, progress: 60);
      var p = await db.projectDao.findById(id);
      expect(p!.progress, 60);
      expect(p.status, ProgressStatus.ongoing.code);

      await actions.updateProgress(id: id, progress: 100);
      p = await db.projectDao.findById(id);
      expect(p!.progress, 100);
      expect(
        p.status,
        ProgressStatus.completed.code,
        reason: '进度 100% 应自动标记为已完成',
      );
    });

    test('编辑时可把 note 置空（空串 → null）', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final id = await actions.create(name: '带笔记项目', note: '原笔记');
      var p = (await db.projectDao.findById(id))!;
      expect(p.note, '原笔记');

      await actions.update(
        project: p,
        name: p.name,
        status: ProgressStatus.ongoing,
        progress: p.progress,
        priority: p.priority,
        note: '   ',
      );
      p = (await db.projectDao.findById(id))!;
      expect(p.note, isNull);
    });

    test('筛选：按状态只看进行中', () async {
      final c = await makeContainer();
      await seedProject(name: '进行中项目');
      await seedProject(name: '已完成项目', status: ProgressStatus.completed);

      c.read(projectFilterProvider.notifier).setStatus(ProgressStatus.ongoing);
      final list = await firstOf(
        c,
        () => c.listen(projectListProvider, (_, _) {}),
        () => c.read(projectListProvider.future),
      );
      expect(list.map((p) => p.name), contains('进行中项目'));
      expect(list.map((p) => p.name), isNot(contains('已完成项目')));
    });

    test('筛选：按优先级筛选（在内存里做，不改 DAO）', () async {
      final c = await makeContainer();
      await seedProject(name: '高优项目', priority: 2);
      await seedProject(name: '低优项目', priority: 0);

      c.read(projectFilterProvider.notifier).setPriority(2);
      final list = await firstOf(
        c,
        () => c.listen(projectListProvider, (_, _) {}),
        () => c.read(projectListProvider.future),
      );
      expect(list.length, 1);
      expect(list.first.name, '高优项目');
    });
  });

  // =========================================================================
  // 业务规则：WorkLogActions
  // =========================================================================
  group('WorkLogActions 业务规则', () {
    test('新增工时记录，日期归一化到当天 00:00', () async {
      final c = await makeContainer();
      final actions = c.read(workLogActionsProvider);
      final pid = await seedProject(name: 'P');

      final id = await actions.create(
        projectId: pid,
        date: DateTime(2026, 10, 7, 15, 30, 45),
        minutes: 90,
        summary: '  写代码  ',
      );
      final log = await db.workLogDao.findById(id);
      expect(log!.date, DateTime(2026, 10, 7));
      expect(log.minutes, 90);
      expect(log.summary, '写代码', reason: '摘要应 trim');
    });

    test('时长必须 > 0（assert）', () async {
      final c = await makeContainer();
      final actions = c.read(workLogActionsProvider);
      final pid = await seedProject(name: 'P');
      expect(
        () => actions.create(projectId: pid, minutes: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('summary 留空时存空串（表默认值）', () async {
      final c = await makeContainer();
      final actions = c.read(workLogActionsProvider);
      final pid = await seedProject(name: 'P');
      final id = await actions.create(projectId: pid, minutes: 30);
      final log = await db.workLogDao.findById(id);
      expect(log!.summary, '');
    });

    test('按项目筛选工时', () async {
      final c = await makeContainer();
      final p1 = await seedProject(name: '甲项目');
      final p2 = await seedProject(name: '乙项目');
      final now = DateTime.now();
      await seedLog(projectId: p1, date: now, minutes: 60);
      await seedLog(projectId: p2, date: now, minutes: 30);

      c.read(workLogFilterProvider.notifier).setProject(p1);
      final list = await firstOf(
        c,
        () => c.listen(workLogListProvider, (_, _) {}),
        () => c.read(workLogListProvider.future),
      );
      expect(list.length, 1);
      expect(list.first.projectId, p1);
    });

    test('按日期范围筛选工时（右开区间）', () async {
      final c = await makeContainer();
      final pid = await seedProject(name: 'P');
      await seedLog(projectId: pid, date: DateTime(2026, 10, 1), minutes: 10);
      await seedLog(projectId: pid, date: DateTime(2026, 10, 5), minutes: 20);
      await seedLog(projectId: pid, date: DateTime(2026, 10, 8), minutes: 30);

      c.read(workLogFilterProvider.notifier).setRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 8),
      );
      final list = await firstOf(
        c,
        () => c.listen(workLogListProvider, (_, _) {}),
        () => c.read(workLogListProvider.future),
      );
      // 10-01 与 10-05 在内；10-08 是右开边界，不含
      expect(list.length, 2);
      expect(list.map((l) => l.minutes), containsAll(<int>[10, 20]));
    });

    test('删除项目会级联删除其工时记录', () async {
      final c = await makeContainer();
      final actions = c.read(projectActionsProvider);
      final pid = await seedProject(name: '待删除项目');
      await seedLog(projectId: pid, date: DateTime.now(), minutes: 60);
      expect(await db.workLogDao.countAll(), 1);

      await actions.remove(pid);
      expect(await db.workLogDao.countAll(), 0, reason: '外键 cascade 应生效');
    });
  });

  // =========================================================================
  // 业务规则：JournalActions
  // =========================================================================
  group('JournalActions 业务规则', () {
    test('工作内容为空 → 抛 ArgumentError', () async {
      final c = await makeContainer();
      final actions = c.read(journalActionsProvider);
      expect(
        () => actions.create(content: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('achievement / problem 空串归一化成 null', () async {
      final c = await makeContainer();
      final actions = c.read(journalActionsProvider);
      final id = await actions.create(
        content: '内容',
        achievement: '   ',
        problem: '',
      );
      final j = await db.workJournalDao.findById(id);
      expect(j!.achievement, isNull);
      expect(j.problem, isNull);
    });

    test('关联项目可空；按项目筛选日志', () async {
      final c = await makeContainer();
      final pid = await seedProject(name: '项目 X');
      final now = DateTime.now();
      await seedJournal(date: now, projectId: pid, content: '关联项目的日志');
      await seedJournal(date: now, content: '没有关联项目的日志');

      c.read(journalFilterProvider.notifier).setProject(pid);
      final list = await firstOf(
        c,
        () => c.listen(journalListProvider, (_, _) {}),
        () => c.read(journalListProvider.future),
      );
      expect(list.length, 1);
      expect(list.first.content, '关联项目的日志');
    });

    test('删除项目后日志的 projectId 置为 null（setNull）', () async {
      // 【为什么不需要 container】本用例只验证**数据库层的外键行为**
      // （`onDelete: setNull`），直接走 `db` 即可，无需 provider。
      final pid = await seedProject(name: '待删项目');
      final id = await seedJournal(date: DateTime.now(), projectId: pid);

      await db.projectDao.deleteById(pid);
      final j = await db.workJournalDao.findById(id);
      expect(j, isNotNull, reason: '日志本身不应被删除');
      expect(j!.projectId, isNull);
    });
  });

  // =========================================================================
  // 统计：按项目分组
  // =========================================================================
  group('按项目分组统计', () {
    test('同一项目多条工时会合并求和，并按工时降序', () async {
      final c = await makeContainer();
      final p1 = await seedProject(name: '多条目项目');
      final p2 = await seedProject(name: '少条目项目');
      final now = DateTime.now();

      await seedLog(projectId: p1, date: now, minutes: 100);
      await seedLog(projectId: p1, date: now, minutes: 200);
      await seedLog(projectId: p2, date: now, minutes: 50);

      final groups = await firstOf(
        c,
        () => c.listen(workLogGroupedProvider, (_, _) {}),
        () => c.read(workLogGroupedProvider.future),
      );

      expect(groups.length, 2);
      expect(groups.first.projectName, '多条目项目');
      expect(groups.first.totalMinutes, 300);
      expect(groups.first.logCount, 2);
      expect(groups.last.projectName, '少条目项目');
      expect(groups.last.totalMinutes, 50);
      expect(groups.last.logCount, 1);
    });

    test('WorkLogGroup.durationText 是「x小时y分」', () {
      const g = WorkLogGroup(
        projectId: 1,
        projectName: 'p',
        totalMinutes: 150,
        logCount: 2,
      );
      expect(g.durationText, '2小时30分');
    });
  });

  // =========================================================================
  // UI：工作管理页面容器
  // =========================================================================
  group('工作管理页面容器', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: WorkPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认进入「项目」Tab，显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有项目'), findsOneWidget);
      // 顶层标题
      expect(find.text('工作管理'), findsOneWidget);
    });

    testWidgets('点「工时」切到工时 Tab', (tester) async {
      await pumpPage(tester);
      await tapTab(tester, '工时');
      await tester.pumpAndSettle();
      expect(find.byType(WorkLogListPage), findsOneWidget);
      expect(find.text('还没有工时记录'), findsOneWidget);
    });

    testWidgets('点「周报」切到周报 Tab', (tester) async {
      await pumpPage(tester);
      await tapTab(tester, '周报');
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);
    });

    testWidgets('点「日志」切到日志 Tab', (tester) async {
      await pumpPage(tester);
      await tapTab(tester, '日志');
      await tester.pumpAndSettle();
      expect(find.byType(JournalListPage), findsOneWidget);
      expect(find.text('还没有工作日志'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：项目 Tab
  // =========================================================================
  group('项目 Tab', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: ProjectListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('空列表显示空状态与新增引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有项目'), findsOneWidget);
      expect(find.text('点右下角「加项目」创建一个'), findsOneWidget);
    });

    testWidgets('列表显示项目名与进度百分比', (tester) async {
      await seedProject(name: '进度项目', progress: 40);
      await pumpPage(tester);

      expect(
        find.descendant(
          of: find.byType(ProjectTile),
          matching: find.text('进度项目'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ProjectTile),
          matching: find.text('40%'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('列表显示优先级标签', (tester) async {
      await seedProject(name: '高优项目', priority: 2);
      await pumpPage(tester);

      expect(
        find.descendant(
          of: find.byType(ProjectTile),
          matching: find.text('高优先级'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('筛选：按「已完成」只看已完成项目', (tester) async {
      await seedProject(name: '进行中的项目');
      await seedProject(name: '已完成的项目', status: ProgressStatus.completed);
      await pumpPage(tester);

      await tester.tap(
        find.widgetWithText(ChoiceChip, ProgressStatus.completed.label),
      );
      await tester.pumpAndSettle();

      expect(find.text('已完成的项目'), findsOneWidget);
      expect(find.text('进行中的项目'), findsNothing);
    });

    testWidgets('长按项目弹出删除确认', (tester) async {
      await seedProject(name: '待删项目');
      await pumpPage(tester);

      await tester.longPress(find.text('待删项目'));
      await tester.pumpAndSettle();
      expect(find.text('删除项目'), findsOneWidget);
    });

    testWidgets('点「加项目」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '加项目'));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectFormPage), findsOneWidget);
    });

    testWidgets('通过表单新建项目后列表出现该项目', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '加项目'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '项目名称'),
        '新项目甲',
      );
      await tapSubmit(tester, '加项目');
      await settleAfterWrite(tester);
      // 表单页已 pop，回到列表
      expect(find.byType(ProjectFormPage), findsNothing);
      expect(find.text('新项目甲'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：项目表单页
  // =========================================================================
  group('项目表单页', () {
    Future<void> pumpForm(WidgetTester tester, {Project? project}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: ProjectFormPage(project: project)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('项目名为空时保存被拦截', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '加项目');
      await tester.pump();
      expect(find.text('请输入项目名称'), findsOneWidget);
      expect(await db.projectDao.countAll(), 0);
    });

    testWidgets('编辑已有项目时字段回填', (tester) async {
      final id = await seedProject(name: '回填项目', progress: 30, priority: 2);
      final p = await db.projectDao.findById(id);
      await pumpForm(tester, project: p);

      expect(find.byType(ProjectFormPage), findsOneWidget);
      // 名称回填：label「项目名称」由 `InputDecoration` 渲染成 Text，
      // `widgetWithText(TextFormField, ...)` 的用法在 4.2 已验证可行。
      expect(
        find.widgetWithText(TextFormField, '项目名称'),
        findsOneWidget,
      );
      expect(find.text('回填项目'), findsOneWidget);
      // 进度回填：直接读 `Slider` 的 value，**不**靠 `find.text('30%')`。
      // 【为什么】表单页里 `'${_progress.round()}%'` 有**两处来源**：
      //   第 251 行进度标题的 `Text`、第 263 行 `Slider` 的 `label`
      // —— 裸 `find.text('30%')` 会命中几处取决于 `Slider.label` 当时
      // 是否在树上（拖动才显示），是典型的 C37「同一文案多来源」。
      // 断言 Slider 的 value 是**语义更强**、不依赖渲染巧合的做法。
      expect(tester.widget<Slider>(find.byType(Slider)).value, 30.0);
    });
  });

  // =========================================================================
  // UI：工时 Tab
  // =========================================================================
  group('工时 Tab', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: WorkLogListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有工时记录'), findsOneWidget);
    });

    testWidgets('列表显示工时明细与按项目统计', (tester) async {
      final pid = await seedProject(name: '统计项目');
      final now = DateTime.now();
      await seedLog(projectId: pid, date: now, minutes: 60, summary: '写代码');
      await seedLog(projectId: pid, date: now, minutes: 120, summary: '改 bug');
      await pumpPage(tester);

      // 明细区标题（含条数）
      expect(find.text('工时明细（2 条）'), findsOneWidget);
      // 明细卡片：摘要与单条时长（60 → 1小时，120 → 2小时）
      expect(find.text('写代码'), findsOneWidget);
      expect(find.text('改 bug'), findsOneWidget);
      expect(find.text('1小时'), findsOneWidget);
      expect(find.text('2小时'), findsOneWidget);
      // 【分组统计行】用**唯一**文本锚定，不用 `findsWidgets`：
      //   - `'2 条'` 只在 `_GroupStatRow` 出现（明细卡片不渲染"条"）
      //   - `'统计项目'` 在本页共 **4 处**来源，必须数清：
      //       ① `_WorkLogFilterBar` 的项目筛选 `ChoiceChip(label: Text(p.name))`
      //          （渲染**所有项目名**，与当前日志无关）
      //       ② `_GroupStatRow` 的分组项目名（1 组）
      //       ③④ `WorkLogTile` × 2 条明细的项目名
      //     故必须 `findsNWidgets(4)`，不能放宽成 `findsWidgets`
      //     （见 C37 / 纪律：不靠放宽断言让测试通过）。
      expect(find.text('2 条'), findsOneWidget);
      expect(find.text('统计项目'), findsNWidgets(4));
      // 合计 180 分钟 = 3小时：只在统计行出现（明细两条分别是 1/2 小时）
      expect(find.text('3小时'), findsOneWidget);
    });

    testWidgets('点「记工时」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '记工时'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkLogFormPage), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：工时表单页
  // =========================================================================
  group('工时表单页', () {
    Future<void> pumpForm(WidgetTester tester, {WorkLog? log}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: WorkLogFormPage(log: log)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('没有项目时提示先去建项目', (tester) async {
      await pumpForm(tester);
      expect(find.text('还没有项目，请先到「项目」页新建一个项目。'), findsOneWidget);
    });

    testWidgets('时长留空时保存被拦截', (tester) async {
      await seedProject(name: '有项目了');
      await pumpForm(tester);
      await tapSubmit(tester, '记工时');
      await tester.pump();
      expect(find.text('请输入时长'), findsOneWidget);
      expect(await db.workLogDao.countAll(), 0);
    });
  });

  // =========================================================================
  // UI：周报 Tab
  // =========================================================================
  group('周报 Tab', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: ReportPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('本周没有工时时显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('该时间段没有工时记录'), findsOneWidget);
    });

    testWidgets('本周有工时时显示汇总与可复制文本', (tester) async {
      final pid = await seedProject(name: '周报项目');
      // 用"今天"确保落在本周范围内
      await seedLog(projectId: pid, date: DateTime.now(), minutes: 480);
      await pumpPage(tester);

      expect(find.text('工时汇总'), findsOneWidget);
      expect(find.text('共 8小时'), findsOneWidget);
      expect(find.text('复制周报'), findsOneWidget);
      // 【为什么是 2 而不是 findsWidgets】「周报项目」在树上有**两处**：
      //   1. 汇总区那一行项目名（`report_page.dart` 的 `g.projectName`）
      //   2. `SelectableText(buildReportText(...))` 里的「· 周报项目：8小时」
      // 数清为 2 是**更强的断言**（哪里少了一处会立刻失败），
      // 用 `findsWidgets` 等于放宽（见纪律：不靠放宽断言过关）。
      expect(find.textContaining('周报项目'), findsNWidgets(2));
      // 生成文本里应含"一、工时汇总"
      expect(find.textContaining('一、工时汇总'), findsOneWidget);
    });

    testWidgets('切到「本月」也是可选范围', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '本月'));
      await tester.pumpAndSettle();
      // 本月无记录 → 空状态
      expect(find.text('该时间段没有工时记录'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：日志 Tab
  // =========================================================================
  group('日志 Tab', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: JournalListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有工作日志'), findsOneWidget);
    });

    testWidgets('搜索框输入关键字后列表过滤', (tester) async {
      final now = DateTime.now();
      await seedJournal(date: now, content: '完成登录模块联调');
      await seedJournal(date: now, content: '整理会议纪要');
      await pumpPage(tester);

      expect(find.text('完成登录模块联调'), findsOneWidget);
      expect(find.text('整理会议纪要'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '登录');
      await tester.pumpAndSettle();

      expect(find.text('完成登录模块联调'), findsOneWidget);
      expect(find.text('整理会议纪要'), findsNothing);
    });

    testWidgets('点「写日志」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '写日志'));
      await tester.pumpAndSettle();
      expect(find.byType(JournalFormPage), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：日志表单页
  // =========================================================================
  group('日志表单页', () {
    Future<void> pumpForm(WidgetTester tester, {WorkJournal? journal}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: JournalFormPage(journal: journal)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('工作内容为空时保存被拦截', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '写日志');
      await tester.pump();
      expect(find.text('请输入工作内容'), findsOneWidget);
      expect(await db.workJournalDao.countAll(), 0);
    });

    testWidgets('编辑已有日志时字段回填', (tester) async {
      final id = await seedJournal(
        date: DateTime.now(),
        content: '原始日志内容',
        achievement: '原始成果',
      );
      final j = await db.workJournalDao.findById(id);
      await pumpForm(tester, journal: j);

      expect(find.byType(JournalFormPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.text('原始日志内容'),
        ),
        findsOneWidget,
      );
    });
  });
}
