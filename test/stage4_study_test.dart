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
import 'package:personal_manager/features/study/providers/study_providers.dart';
import 'package:personal_manager/features/study/ui/books/book_form_page.dart';
import 'package:personal_manager/features/study/ui/books/book_list_page.dart';
import 'package:personal_manager/features/study/ui/books/widgets/book_tile.dart';
import 'package:personal_manager/features/study/ui/checkins/checkin_form_page.dart';
import 'package:personal_manager/features/study/ui/checkins/checkin_page.dart';
import 'package:personal_manager/features/study/ui/courses/course_form_page.dart';
import 'package:personal_manager/features/study/ui/courses/course_list_page.dart';
import 'package:personal_manager/features/study/ui/courses/widgets/course_tile.dart';
import 'package:personal_manager/features/study/ui/goals/goal_form_page.dart';
import 'package:personal_manager/features/study/ui/goals/study_goal_page.dart';
import 'package:personal_manager/features/study/ui/study_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.4 学习管理测试。
///
/// 覆盖验收要求（开发计划 §4.4）：
///   1. 录一本书和一门课，进度可更新；
///   2. 连续打卡 3 天显示连续天数；
///   3. 建 2 个目标可标记完成。
///
/// 另外覆盖：
/// - `computeStreak` 纯函数的各种边界（今天没打 / 断签 / 空集合）
/// - `bookProgress` / `courseProgress` 除零与 clamp
/// - `BookActions` / `CourseActions` / `StudyGoalActions` 的业务规则
///   （书名课程名必填、当前页不超总页数、非读完清空评分、
///   全部完成强制置 completed、类型过滤）
/// - 4 个 Tab 的 UI（列表、表单、筛选、切换）
void main() {
  late AppDatabase db;

  /// 点击表单页底部的提交按钮。
  ///
  /// 【为什么要单独抽出来】提交按钮是表单 `ListView` 的**最后一个 child**，
  /// 而 `ListView` 惰性构建 —— 视口不够高时它**不在 Element 树上**，
  /// 直接 `find.widgetWithText(FilledButton, '加本书')` 会得到 0 个。
  /// 本文件统一用 [useLargeViewport] 把视口放大到 1200x2400，
  /// 按钮因此始终在树上。
  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  /// 点 `TabBar` 里的某个 Tab（按标签文字）。
  ///
  /// 【⛔ 为什么不能直接 `tester.tap(find.widgetWithText(Tab, '目标'))`】
  /// 阶段 4.4 首轮验证实测会刷出**两条**：
  /// ```
  /// Warning: A call to tap() with finder "Found 1 widget with type "Tab" ..."
  ///   derived an Offset (Offset(1050.0, 92.0)) that would not hit test
  ///   on the specified widget.
  /// ```
  /// 根因（已查 `flutter/lib/src/material/tabs.dart` 源码确认）：
  /// `Tab extends StatelessWidget`，其 `build` 返回
  /// `SizedBox(child: Center(widthFactor: 1.0, child: label))`
  /// —— `SizedBox` / `Center` 的 `hitTestSelf` 都是 false，**不参与 hit-test**。
  /// 真正接收点击的是 `TabBar` 给每个 tab 裹的 **`InkWell`**
  /// （`tabs.dart` 里 `wrappedTabs[index] = InkWell(onTap: () => _handleTap(index), ...)`）。
  ///
  /// 【为什么这条警告必须修，不能留】
  /// 测试当时是**绿的**（点中心恰好仍落在同一槽位，`TabBarView` 照样切页），
  /// 但那是**依赖布局巧合**；且警告噪音会**掩盖真问题**
  /// —— 下一轮再出现同类警告时就分不清是不是新问题（见 MEMORY.md C31
  /// "靠侥幸通过比报错更危险"、C12b"先问是不是在视口外/不受命中"）。
  ///
  /// 【为什么用 `find.descendant(of: TabBar, ...)` 限定】
  /// 「打卡」「目标」等文案在页面内容里**也会出现**
  /// （如 `checkin_form_page.dart` 的按钮 label 就是「打卡」）
  /// —— 不限定作用域会命中多处（见 MEMORY.md C37）。
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

  /// 直接往库里塞一本书，返回 id。
  Future<int> seedBook({
    String title = '示例书',
    String? author,
    int currentPage = 0,
    int totalPages = 0,
    BookStatus status = BookStatus.reading,
    int? rating,
    String? note,
  }) {
    return db.bookDao.insertBook(
      BooksCompanion.insert(
        title: title,
        author: Value(author),
        currentPage: Value(currentPage),
        totalPages: Value(totalPages),
        status: status.code,
        rating: Value(rating),
        note: Value(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 直接往库里塞一门课，返回 id。
  Future<int> seedCourse({
    String name = '示例课',
    String? platform,
    int totalChapters = 0,
    int completedChapters = 0,
    DateTime? startDate,
    DateTime? dueDate,
    ProgressStatus status = ProgressStatus.ongoing,
  }) {
    return db.courseDao.insertCourse(
      CoursesCompanion.insert(
        name: name,
        platform: Value(platform),
        totalChapters: Value(totalChapters),
        completedChapters: Value(completedChapters),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        status: status.code,
      ),
    );
  }

  /// 直接往库里塞一条打卡，返回 id。
  Future<int> seedCheckin({
    required DateTime date,
    String content = '',
    int minutes = 0,
    bool goalMet = false,
  }) {
    final d = DateTime(date.year, date.month, date.day);
    return db.studyCheckinDao.insertCheckin(
      StudyCheckinsCompanion.insert(
        date: d,
        content: Value(content),
        minutes: Value(minutes),
        goalMet: Value(goalMet),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 直接往库里塞一个目标，返回 id。
  Future<int> seedGoal({
    String name = '示例目标',
    StudyGoalType type = StudyGoalType.other,
    DateTime? dueDate,
    bool isCompleted = false,
  }) {
    return db.studyGoalDao.insertGoal(
      StudyGoalsCompanion.insert(
        name: name,
        type: type.code,
        dueDate: Value(dueDate),
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
  ///
  /// 【⚠️ 为什么 provider 要以**闭包**传入，而不是写成
  ///   `firstOf(c, someProvider, ...)` 这样的形参】
  /// `ProviderContainer.listen` 的形参类型是 `ProviderListenable<T>`，
  /// 但 **`ProviderListenable` **不在** `package:flutter_riverpod/flutter_riverpod.dart`
  /// 的导出清单里** —— 它只在 `package:riverpod/misc.dart` 里导出。
  /// 而本项目 pubspec 只声明了 `flutter_riverpod`（`riverpod` 是**传递依赖**），
  /// 直接 `import 'package:riverpod/misc.dart'` 会触发
  /// `depend_on_referenced_packages` 且不严谨。
  ///
  /// 所以这里改成**把 `listen(...)` 本身作为闭包传进来**：
  /// 泛型 `T` 由 `read` / `listen` 两个闭包的返回类型推断，
  /// helper 完全不需要写 provider 的类型。这也是 4.3 `stage4_ledger_test.dart`
  /// 里 `readList` / `readCategoryCount` 的做法（就地 `c.listen(...)`）。
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
  // 验收 1：录一本书和一门课，进度可更新
  // =========================================================================
  group('验收 1：录一本书和一门课，进度可更新', () {
    test('新增一本书，进度随「当前页/总页数」实时计算', () async {
      final c = await makeContainer();
      final actions = c.read(bookActionsProvider);

      final id = await actions.create(
        title: '深入理解计算机系统',
        author: 'Randal E. Bryant',
        totalPages: 800,
      );

      var book = await db.bookDao.findById(id);
      expect(book, isNotNull);
      expect(book!.title, '深入理解计算机系统');
      expect(book.author, 'Randal E. Bryant');
      expect(book.totalPages, 800);
      expect(book.currentPage, 0);
      expect(book.status, BookStatus.reading.code);
      // 0 / 800
      expect(bookProgress(book), 0.0);

      // 更新进度到 200 / 800 = 25%
      await actions.updateProgress(book: book, currentPage: 200);
      book = (await db.bookDao.findById(id))!;
      expect(book.currentPage, 200);
      expect(bookProgress(book), closeTo(0.25, 1e-9));

      // 再更新到 400 / 800 = 50%
      await actions.updateProgress(book: book, currentPage: 400);
      book = (await db.bookDao.findById(id))!;
      expect(bookProgress(book), closeTo(0.5, 1e-9));
    });

    test('新增一门课，进度随「已完成/总章节」实时计算', () async {
      final c = await makeContainer();
      final actions = c.read(courseActionsProvider);

      final id = await actions.create(
        name: 'Flutter 实战',
        platform: 'B站',
        totalChapters: 40,
      );

      var course = await db.courseDao.findById(id);
      expect(course, isNotNull);
      expect(course!.name, 'Flutter 实战');
      expect(course.platform, 'B站');
      expect(course.totalChapters, 40);
      expect(course.completedChapters, 0);
      expect(course.status, ProgressStatus.ongoing.code);
      expect(courseProgress(course), 0.0);

      // 完成 10 章 → 25%
      await actions.updateProgress(course: course, completedChapters: 10);
      course = (await db.courseDao.findById(id))!;
      expect(course.completedChapters, 10);
      expect(courseProgress(course), closeTo(0.25, 1e-9));
      expect(course.status, ProgressStatus.ongoing.code);

      // 完成全部 40 章 → 100% 且状态自动变为 completed
      await actions.updateProgress(course: course, completedChapters: 40);
      course = (await db.courseDao.findById(id))!;
      expect(course.completedChapters, 40);
      expect(courseProgress(course), 1.0);
      expect(
        course.status,
        ProgressStatus.completed.code,
        reason: '完成全部章节后应自动标记为已完成',
      );
    });

    test('列表流能读到刚录入的书与课', () async {
      final c = await makeContainer();
      await seedBook(title: '一本在读书', totalPages: 300, currentPage: 60);
      await seedCourse(name: '一门在学课', totalChapters: 20, completedChapters: 5);

      final books = await firstOf(
        c,
        () => c.listen(bookListProvider, (_, _) {}),
        () => c.read(bookListProvider.future),
      );
      final courses = await firstOf(
        c,
        () => c.listen(courseListProvider, (_, _) {}),
        () => c.read(courseListProvider.future),
      );

      expect(books.map((b) => b.title), contains('一本在读书'));
      expect(courses.map((x) => x.name), contains('一门在学课'));
    });
  });

  // =========================================================================
  // 验收 2：连续打卡 3 天显示连续天数
  // =========================================================================
  group('验收 2：连续打卡 3 天显示连续天数', () {
    test('连续打卡 3 天（含今天）→ 连续天数为 3', () async {
      final c = await makeContainer();
      final actions = c.read(studyCheckinActionsProvider);
      final now = DateTime.now();

      await actions.create(date: DateTime(now.year, now.month, now.day - 2));
      await actions.create(date: DateTime(now.year, now.month, now.day - 1));
      await actions.create(date: now);

      expect(await actions.streak(), 3);
    });

    test('连续 3 天但今天还没打 → 仍显示 3（从昨天起算，不清零）', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 3));
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 2));
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 1));

      final streak = await c.read(studyCheckinActionsProvider).streak();
      expect(
        streak,
        3,
        reason: '今天还没打卡时，应从昨天起算，而不是清零',
      );
    });

    test('断签（昨天没打）→ 连续天数为 0', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 5));
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 4));

      expect(await c.read(studyCheckinActionsProvider).streak(), 0);
    });

    test('同一天多条打卡记录只算 1 天', () async {
      final c = await makeContainer();
      final now = DateTime.now();
      await seedCheckin(date: now, content: '上午', minutes: 30);
      await seedCheckin(date: now, content: '下午', minutes: 45);

      expect(await c.read(studyCheckinActionsProvider).streak(), 1);
    });
  });

  // =========================================================================
  // computeStreak 纯函数边界
  // =========================================================================
  group('computeStreak 纯函数', () {
    final ref = DateTime(2026, 5, 20);

    test('空集合 → 0', () {
      expect(computeStreak(const <DateTime>[], ref), 0);
    });

    test('只有今天 → 1', () {
      expect(computeStreak([DateTime(2026, 5, 20)], ref), 1);
    });

    test('只有昨天（今天没打）→ 1', () {
      expect(computeStreak([DateTime(2026, 5, 19)], ref), 1);
    });

    test('前天打、昨天没打、今天没打 → 0', () {
      expect(computeStreak([DateTime(2026, 5, 18)], ref), 0);
    });

    test('带时分秒也能正确归一化', () {
      expect(
        computeStreak([
          DateTime(2026, 5, 20, 23, 59),
          DateTime(2026, 5, 19, 0, 1),
        ], ref),
        2,
      );
    });

    test('跨月连续', () {
      // 4/30, 5/1, 5/2 → 参考日 5/2
      expect(
        computeStreak([
          DateTime(2026, 4, 30),
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 2),
        ], DateTime(2026, 5, 2)),
        3,
      );
    });

    test('中断前的长 streak 不计入', () {
      // 5/1~5/3 连续，然后断了，5/19~5/20 连续
      expect(
        computeStreak([
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 2),
          DateTime(2026, 5, 3),
          DateTime(2026, 5, 19),
          DateTime(2026, 5, 20),
        ], ref),
        2,
      );
    });
  });

  // =========================================================================
  // 验收 3：建 2 个目标可标记完成
  // =========================================================================
  group('验收 3：建 2 个目标可标记完成', () {
    test('建 2 个目标，可分别标记完成', () async {
      final c = await makeContainer();
      final actions = c.read(studyGoalActionsProvider);

      final id1 = await actions.create(
        name: '读完《原则》',
        type: StudyGoalType.reading,
        dueDate: DateTime(2026, 12, 31),
      );
      final id2 = await actions.create(
        name: '学完 Flutter 课程',
        type: StudyGoalType.course,
      );

      // 都还没完成
      expect(await db.studyGoalDao.countPending(), 2);

      // 标记第 1 个完成
      await actions.toggleCompleted(id: id1, isCompleted: true);
      expect((await db.studyGoalDao.findById(id1))!.isCompleted, isTrue);
      expect((await db.studyGoalDao.findById(id2))!.isCompleted, isFalse);
      expect(await db.studyGoalDao.countPending(), 1);

      // 标记第 2 个完成
      await actions.toggleCompleted(id: id2, isCompleted: true);
      expect((await db.studyGoalDao.findById(id2))!.isCompleted, isTrue);
      expect(await db.studyGoalDao.countPending(), 0);

      // 取消第 1 个的完成状态
      await actions.toggleCompleted(id: id1, isCompleted: false);
      expect((await db.studyGoalDao.findById(id1))!.isCompleted, isFalse);
      expect(await db.studyGoalDao.countPending(), 1);
    });

    test('目标流按完成状态筛选', () async {
      final c = await makeContainer();
      await seedGoal(name: '未完成目标');
      await seedGoal(name: '已完成目标', isCompleted: true);

      // 全部
      final all = await firstOf(
        c,
        () => c.listen(studyGoalListProvider, (_, _) {}),
        () => c.read(studyGoalListProvider.future),
      );
      expect(all.length, 2);

      // 只看未完成
      c.read(studyGoalFilterProvider.notifier).setCompleted(false);
      final pending = await firstOf(
        c,
        () => c.listen(studyGoalListProvider, (_, _) {}),
        () => c.read(studyGoalListProvider.future),
      );
      expect(pending.map((g) => g.name), ['未完成目标']);

      // 只看已完成
      c.read(studyGoalFilterProvider.notifier).setCompleted(true);
      final done = await firstOf(
        c,
        () => c.listen(studyGoalListProvider, (_, _) {}),
        () => c.read(studyGoalListProvider.future),
      );
      expect(done.map((g) => g.name), ['已完成目标']);
    });

    test('目标流按类型筛选', () async {
      final c = await makeContainer();
      await seedGoal(name: '读书目标', type: StudyGoalType.reading);
      await seedGoal(name: '课程目标', type: StudyGoalType.course);
      await seedGoal(name: '复习目标', type: StudyGoalType.review);

      c.read(studyGoalFilterProvider.notifier).setType(StudyGoalType.course);
      final list = await firstOf(
        c,
        () => c.listen(studyGoalListProvider, (_, _) {}),
        () => c.read(studyGoalListProvider.future),
      );
      expect(list.map((g) => g.name), ['课程目标']);
    });
  });

  // =========================================================================
  // 业务规则
  // =========================================================================
  group('BookActions 业务规则', () {
    test('书名必填（纯空白视为空）', () async {
      final c = await makeContainer();
      final actions = c.read(bookActionsProvider);
      expect(
        () => actions.create(title: '   '),
        throwsArgumentError,
      );
    });

    test('书名两端空白被 trim', () async {
      final c = await makeContainer();
      final id = await c.read(bookActionsProvider).create(title: '  三体  ');
      expect((await db.bookDao.findById(id))!.title, '三体');
    });

    test('只有「读完」状态才保留评分', () async {
      final c = await makeContainer();
      final actions = c.read(bookActionsProvider);

      // 在读 + 传了评分 → 评分被清空
      final id1 = await actions.create(
        title: '在读的书',
        status: BookStatus.reading,
        rating: 4,
      );
      expect((await db.bookDao.findById(id1))!.rating, isNull);

      // 读完 + 评分 → 保留
      final id2 = await actions.create(
        title: '读完的书',
        status: BookStatus.finished,
        rating: 4,
      );
      expect((await db.bookDao.findById(id2))!.rating, 4);
    });

    test('评分被 clamp 到 1~5', () async {
      final c = await makeContainer();
      final actions = c.read(bookActionsProvider);
      final hi = await actions.create(
        title: 'A',
        status: BookStatus.finished,
        rating: 99,
      );
      final lo = await actions.create(
        title: 'B',
        status: BookStatus.finished,
        rating: -3,
      );
      expect((await db.bookDao.findById(hi))!.rating, 5);
      expect((await db.bookDao.findById(lo))!.rating, 1);
    });

    test('读完后再切回在读 → 评分被清空', () async {
      final c = await makeContainer();
      final actions = c.read(bookActionsProvider);
      final id = await actions.create(
        title: '书',
        status: BookStatus.finished,
        rating: 5,
      );
      final book = (await db.bookDao.findById(id))!;

      await actions.update(
        book: book,
        title: book.title,
        currentPage: book.currentPage,
        totalPages: book.totalPages,
        status: BookStatus.reading,
        rating: book.rating,
      );
      expect((await db.bookDao.findById(id))!.rating, isNull);
    });

    test('总页数为 0 时不校验当前页上限', () async {
      final c = await makeContainer();
      final id = await c.read(bookActionsProvider).create(
            title: '未填页数的书',
            currentPage: 999,
          );
      expect((await db.bookDao.findById(id))!.currentPage, 999);
    });

    test('筛选：只看「读完」', () async {
      final c = await makeContainer();
      await seedBook(title: '在读书', status: BookStatus.reading);
      await seedBook(title: '读完书', status: BookStatus.finished);
      await seedBook(title: '搁置书', status: BookStatus.paused);

      c.read(bookFilterProvider.notifier).setStatus(BookStatus.finished);
      final list = await firstOf(
        c,
        () => c.listen(bookListProvider, (_, _) {}),
        () => c.read(bookListProvider.future),
      );
      expect(list.map((b) => b.title), ['读完书']);
    });
  });

  group('CourseActions 业务规则', () {
    test('课程名必填', () async {
      final c = await makeContainer();
      expect(
        () => c.read(courseActionsProvider).create(name: '  '),
        throwsArgumentError,
      );
    });

    test('手动选 ongoing 但已完成==总章节 → 强制 completed', () async {
      final c = await makeContainer();
      final id = await c.read(courseActionsProvider).create(
            name: '课',
            totalChapters: 10,
            completedChapters: 10,
            status: ProgressStatus.ongoing,
          );
      expect(
        (await db.courseDao.findById(id))!.status,
        ProgressStatus.completed.code,
      );
    });

    test('总章节为 0 时不强制 completed', () async {
      final c = await makeContainer();
      final id = await c.read(courseActionsProvider).create(
            name: '课',
            totalChapters: 0,
            completedChapters: 0,
            status: ProgressStatus.ongoing,
          );
      expect(
        (await db.courseDao.findById(id))!.status,
        ProgressStatus.ongoing.code,
      );
    });

    test('筛选：只看「已完成」', () async {
      final c = await makeContainer();
      await seedCourse(name: '进行中的课');
      await seedCourse(
        name: '完成的课',
        totalChapters: 5,
        completedChapters: 5,
        status: ProgressStatus.completed,
      );

      c.read(courseFilterProvider.notifier).setStatus(ProgressStatus.completed);
      final list = await firstOf(
        c,
        () => c.listen(courseListProvider, (_, _) {}),
        () => c.read(courseListProvider.future),
      );
      expect(list.map((x) => x.name), ['完成的课']);
    });
  });

  group('StudyGoalActions 业务规则', () {
    test('目标名必填', () async {
      final c = await makeContainer();
      expect(
        () => c.read(studyGoalActionsProvider).create(name: '   '),
        throwsArgumentError,
      );
    });

    test('isGoalOverdue：未完成 + 有截止日 + 已过 → true', () {
      final ref = DateTime(2026, 6, 1);
      expect(
        isGoalOverdue(
          StudyGoal(
            id: 1,
            name: 'x',
            type: 'other',
            dueDate: DateTime(2026, 5, 31),
            isCompleted: false,
            createdAt: ref,
          ),
          ref,
        ),
        isTrue,
      );
    });

    test('isGoalOverdue：已完成 → false（不算逾期）', () {
      final ref = DateTime(2026, 6, 1);
      expect(
        isGoalOverdue(
          StudyGoal(
            id: 1,
            name: 'x',
            type: 'other',
            dueDate: DateTime(2026, 5, 31),
            isCompleted: true,
            createdAt: ref,
          ),
          ref,
        ),
        isFalse,
      );
    });

    test('isGoalOverdue：无截止日 → false', () {
      final ref = DateTime(2026, 6, 1);
      expect(
        isGoalOverdue(
          StudyGoal(
            id: 1,
            name: 'x',
            type: 'other',
            dueDate: null,
            isCompleted: false,
            createdAt: ref,
          ),
          ref,
        ),
        isFalse,
      );
    });

    test('isGoalOverdue：今天到期 → false（当天不算逾期）', () {
      final ref = DateTime(2026, 6, 1);
      expect(
        isGoalOverdue(
          StudyGoal(
            id: 1,
            name: 'x',
            type: 'other',
            dueDate: DateTime(2026, 6, 1),
            isCompleted: false,
            createdAt: ref,
          ),
          ref,
        ),
        isFalse,
      );
    });
  });

  // =========================================================================
  // 进度计算边界
  // =========================================================================
  group('进度计算边界', () {
    test('bookProgress：总页数 0 → 0（不除零）', () {
      final book = Book(
        id: 1,
        title: 'x',
        currentPage: 50,
        totalPages: 0,
        status: 'reading',
        createdAt: DateTime(2026),
      );
      expect(bookProgress(book), 0.0);
    });

    test('bookProgress：当前页超总页数 → clamp 到 1.0', () {
      final book = Book(
        id: 1,
        title: 'x',
        currentPage: 500,
        totalPages: 100,
        status: 'reading',
        createdAt: DateTime(2026),
      );
      expect(bookProgress(book), 1.0);
    });

    test('courseProgress：总章节 0 → 0', () {
      final course = Course(
        id: 1,
        name: 'x',
        totalChapters: 0,
        completedChapters: 5,
        status: 'ongoing',
      );
      expect(courseProgress(course), 0.0);
    });

    test('courseProgress：clamp 到 1.0', () {
      final course = Course(
        id: 1,
        name: 'x',
        totalChapters: 10,
        completedChapters: 99,
        status: 'ongoing',
      );
      expect(courseProgress(course), 1.0);
    });
  });

  // =========================================================================
  // 月份 / 日期工具
  // =========================================================================
  group('日期工具', () {
    test('dayStart 去掉时分秒', () {
      expect(
        dayStart(DateTime(2026, 5, 20, 13, 45, 30)),
        DateTime(2026, 5, 20),
      );
    });

    test('shiftDay 跨月正确', () {
      expect(shiftDay(DateTime(2026, 5, 1), -1), DateTime(2026, 4, 30));
    });

    test('isSameDay 只比年月日', () {
      expect(
        isSameDay(DateTime(2026, 5, 20, 1), DateTime(2026, 5, 20, 23)),
        isTrue,
      );
      expect(isSameDay(DateTime(2026, 5, 20), DateTime(2026, 5, 21)), isFalse);
    });

    test('shiftMonth / monthStart', () {
      expect(monthStart(DateTime(2026, 5, 20)), DateTime(2026, 5, 1));
      expect(shiftMonth(DateTime(2026, 5, 1), -1), DateTime(2026, 4, 1));
      expect(shiftMonth(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
    });
  });

  // =========================================================================
  // 月度打卡聚合
  // =========================================================================
  group('月度打卡聚合', () {
    test('当月打卡天数与总时长', () async {
      final c = await makeContainer();
      final month = currentMonth();
      await seedCheckin(date: month, minutes: 30);
      await seedCheckin(date: shiftDay(month, 1), minutes: 45);
      await seedCheckin(date: shiftDay(month, 2), minutes: 60);

      final summary = await firstOf(
        c,
        () => c.listen(monthCheckinSummaryProvider, (_, _) {}),
        () => c.read(monthCheckinSummaryProvider.future),
      );
      expect(summary.days, 3);
      expect(summary.totalMinutes, 135);
    });

    test('上个月的记录不计入本月', () async {
      final c = await makeContainer();
      final month = currentMonth();
      await seedCheckin(date: month, minutes: 30);
      await seedCheckin(date: shiftMonth(month, -1), minutes: 999);

      final summary = await firstOf(
        c,
        () => c.listen(monthCheckinSummaryProvider, (_, _) {}),
        () => c.read(monthCheckinSummaryProvider.future),
      );
      expect(summary.days, 1);
      expect(summary.totalMinutes, 30);
    });

    test('同一天多条：天数算 1，时长累加', () async {
      final c = await makeContainer();
      await seedCheckin(date: currentMonth(), minutes: 20);
      await seedCheckin(date: currentMonth(), minutes: 40);

      final summary = await firstOf(
        c,
        () => c.listen(monthCheckinSummaryProvider, (_, _) {}),
        () => c.read(monthCheckinSummaryProvider.future),
      );
      expect(summary.days, 1);
      expect(summary.totalMinutes, 60);
    });
  });

  // =========================================================================
  // UI：读书 Tab
  // =========================================================================
  group('读书 Tab UI', () {
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
          child: const MaterialApp(home: BookListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态与新增引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有书'), findsOneWidget);
      expect(find.text('点右下角「加本书」记录阅读进度'), findsOneWidget);
    });

    testWidgets('渲染书籍：书名、作者、页码、进度百分比', (tester) async {
      await seedBook(
        title: '三体',
        author: '刘慈欣',
        currentPage: 150,
        totalPages: 300,
      );
      await pumpPage(tester);

      expect(find.text('三体'), findsOneWidget);
      expect(find.text('刘慈欣'), findsOneWidget);
      expect(find.text('150 / 300 页'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // 【⚠️ 必须限定到 BookTile 内】
      // 「在读」有两个来源：① 顶部筛选栏的 ChoiceChip  ② 卡片上的状态胶囊。
      // 直接 `find.text('在读')` 会命中 2 个（见 §5.8 / C27）。
      // 这里要断言的是**卡片上的状态胶囊**，所以用 descendant 限定作用域 ——
      // 而不是放宽成 findsWidgets（那是降低验收标准）。
      expect(
        find.descendant(of: find.byType(BookTile), matching: find.text('在读')),
        findsOneWidget,
      );
    });

    testWidgets('读完的书显示评分星星', (tester) async {
      await seedBook(
        title: '读完的书',
        currentPage: 200,
        totalPages: 200,
        status: BookStatus.finished,
        rating: 4,
      );
      await pumpPage(tester);

      expect(
        find.descendant(of: find.byType(BookTile), matching: find.text('读完')),
        findsOneWidget,
      );
      expect(find.text('100%'), findsOneWidget);
      // 4 个实心 + 1 个空心
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    testWidgets('按状态筛选：选「读完」只剩读完的书', (tester) async {
      await seedBook(title: '在读书', status: BookStatus.reading);
      await seedBook(title: '读完书', status: BookStatus.finished);
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '读完'));
      await tester.pumpAndSettle();

      expect(find.text('读完书'), findsOneWidget);
      expect(find.text('在读书'), findsNothing);
    });

    testWidgets('长按弹删除确认，确认后消失', (tester) async {
      await seedBook(title: '待删的书');
      await pumpPage(tester);

      await tester.longPress(find.text('待删的书'));
      await tester.pumpAndSettle();
      expect(find.text('删除书籍'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      await settleAfterWrite(tester);

      expect(find.text('待删的书'), findsNothing);
      expect(find.text('还没有书'), findsOneWidget);
    });

    testWidgets('点「加本书」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '加本书'));
      await tester.pumpAndSettle();
      expect(find.byType(BookFormPage), findsOneWidget);
    });

    testWidgets('点书籍进入编辑页并回填', (tester) async {
      await seedBook(title: '可编辑的书', totalPages: 100, currentPage: 20);
      await pumpPage(tester);

      await tester.tap(find.text('可编辑的书'));
      await tester.pumpAndSettle();

      expect(find.byType(BookFormPage), findsOneWidget);
      expect(find.text('编辑书籍'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '可编辑的书'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：读书表单页
  // =========================================================================
  group('读书表单页', () {
    Future<void> pumpForm(WidgetTester tester, {Book? book}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: BookFormPage(book: book)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('新增：书名为空时保存被拦截', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '加本书');
      await tester.pump();

      expect(find.text('请输入书名'), findsOneWidget);
      expect(await db.bookDao.countAll(), 0);
    });

    testWidgets('新增：填写后保存成功并写库', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '书名'),
        '活着',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '作者（可选）'),
        '余华',
      );
      await tapSubmit(tester, '加本书');
      await tester.pumpAndSettle();

      final books = await db.bookDao.findAll();
      expect(books.length, 1);
      expect(books.first.title, '活着');
      expect(books.first.author, '余华');
    });

    testWidgets('切到「读完」后才出现评分选项', (tester) async {
      await pumpForm(tester);
      // 初始为「在读」，不应有评分标题
      expect(find.text('评分'), findsNothing);

      await tester.tap(find.text('读完'));
      await tester.pumpAndSettle();

      expect(find.text('评分'), findsOneWidget);
    });

    testWidgets('编辑模式：回填原值', (tester) async {
      final id = await seedBook(
        title: '原书名',
        author: '原作者',
        totalPages: 500,
        currentPage: 100,
      );
      final book = (await db.bookDao.findById(id))!;

      await pumpForm(tester, book: book);

      expect(find.text('编辑书籍'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '原书名'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '原作者'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '100'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '500'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：课程 Tab
  // =========================================================================
  group('课程 Tab UI', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: CourseListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有课程'), findsOneWidget);
    });

    testWidgets('渲染课程：名称、平台、章节进度', (tester) async {
      await seedCourse(
        name: 'Flutter 实战',
        platform: 'B站',
        totalChapters: 40,
        completedChapters: 10,
      );
      await pumpPage(tester);

      expect(find.text('Flutter 实战'), findsOneWidget);
      expect(find.text('B站'), findsOneWidget);
      expect(find.text('已完成 10 / 40 章'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      // 「进行中」同样有两个来源（筛选 chip + 卡片胶囊），限定到 CourseTile
      expect(
        find.descendant(of: find.byType(CourseTile), matching: find.text('进行中')),
        findsOneWidget,
      );
    });

    testWidgets('点「加课程」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '加课程'));
      await tester.pumpAndSettle();
      expect(find.byType(CourseFormPage), findsOneWidget);
    });

    testWidgets('按状态筛选：选「已完成」只剩完成的课', (tester) async {
      await seedCourse(name: '进行中的课');
      await seedCourse(
        name: '完成的课',
        totalChapters: 3,
        completedChapters: 3,
        status: ProgressStatus.completed,
      );
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '已完成'));
      await tester.pumpAndSettle();

      expect(find.text('完成的课'), findsOneWidget);
      expect(find.text('进行中的课'), findsNothing);
    });
  });

  // =========================================================================
  // UI：课程表单页
  // =========================================================================
  group('课程表单页', () {
    Future<void> pumpForm(WidgetTester tester, {Course? course}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: CourseFormPage(course: course)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('课程名为空时保存被拦截', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '加课程');
      await tester.pump();

      expect(find.text('请输入课程名'), findsOneWidget);
      expect(await db.courseDao.countAll(), 0);
    });

    testWidgets('已完成章节超过总章节时被拦截', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '课程名'),
        '课',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '总章节数'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '已完成章节'),
        '20',
      );
      await tapSubmit(tester, '加课程');
      await tester.pumpAndSettle();

      expect(find.text('已完成章节不能超过总章节'), findsOneWidget);
      expect(await db.courseDao.countAll(), 0);
    });

    testWidgets('填写完整后保存成功并写库', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '课程名'),
        '数据结构',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '总章节数'),
        '30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '已完成章节'),
        '5',
      );
      await tapSubmit(tester, '加课程');
      await tester.pumpAndSettle();

      final courses = await db.courseDao.findAll();
      expect(courses.length, 1);
      expect(courses.first.name, '数据结构');
      expect(courses.first.totalChapters, 30);
      expect(courses.first.completedChapters, 5);
    });
  });

  // =========================================================================
  // UI：打卡 Tab
  // =========================================================================
  group('打卡 Tab UI', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: CheckinPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态与打卡引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有打卡记录'), findsOneWidget);
      expect(find.text('点右下角「今日打卡」记下今天的学习'), findsOneWidget);
    });

    testWidgets('连续打卡 3 天显示「3 天」', (tester) async {
      final now = DateTime.now();
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 2));
      await seedCheckin(date: DateTime(now.year, now.month, now.day - 1));
      await seedCheckin(date: now);

      await pumpPage(tester);

      expect(find.text('连续打卡'), findsOneWidget);
      expect(find.text('3 天'), findsWidgets);
    });

    testWidgets('本月统计显示打卡天数与总时长', (tester) async {
      final month = currentMonth();
      await seedCheckin(date: month, minutes: 30);
      await seedCheckin(date: shiftDay(month, 1), minutes: 45);

      await pumpPage(tester);

      expect(find.text('2 天'), findsWidgets);
      expect(find.text('1小时15分'), findsOneWidget);
    });

    testWidgets('打卡记录列表显示日期与时长', (tester) async {
      await seedCheckin(date: DateTime.now(), content: '读《原则》', minutes: 45);
      await pumpPage(tester);

      expect(find.text('今天'), findsOneWidget);
      expect(find.text('45分钟'), findsWidgets);
      expect(find.text('读《原则》'), findsOneWidget);
    });

    testWidgets('点「今日打卡」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '今日打卡'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckinFormPage), findsOneWidget);
    });

    testWidgets('月份切换显示上个月', (tester) async {
      await pumpPage(tester);
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 1);

      expect(find.text('${now.year} 年 ${now.month} 月'), findsOneWidget);

      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();

      expect(find.text('${prev.year} 年 ${prev.month} 月'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：打卡表单页
  // =========================================================================
  group('打卡表单页', () {
    Future<void> pumpForm(WidgetTester tester, {StudyCheckin? entry}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: CheckinFormPage(entry: entry)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('填写时长与内容后保存成功', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '学习时长（分钟）'),
        '60',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '学习内容（可选）'),
        '刷算法题',
      );
      await tapSubmit(tester, '打卡');
      await tester.pumpAndSettle();

      final list = await db.studyCheckinDao.findAll();
      expect(list.length, 1);
      expect(list.first.minutes, 60);
      expect(list.first.content, '刷算法题');
    });

    testWidgets('时长为空时按 0 处理（允许不填）', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '打卡');
      await tester.pumpAndSettle();

      final list = await db.studyCheckinDao.findAll();
      expect(list.length, 1);
      expect(list.first.minutes, 0);
    });

    testWidgets('编辑模式回填原值', (tester) async {
      final id = await seedCheckin(
        date: DateTime.now(),
        content: '原内容',
        minutes: 30,
      );
      final entry = (await db.studyCheckinDao.findById(id))!;

      await pumpForm(tester, entry: entry);

      expect(find.text('编辑打卡'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '原内容'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '30'), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：目标 Tab
  // =========================================================================
  group('目标 Tab UI', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: StudyGoalPage()),
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

    testWidgets('空列表显示空状态', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有学习目标'), findsOneWidget);
    });

    testWidgets('建 2 个目标，勾选后可标记完成', (tester) async {
      final id1 = await seedGoal(name: '目标一', type: StudyGoalType.reading);
      await seedGoal(name: '目标二', type: StudyGoalType.course);
      await pumpPage(tester);

      expect(find.text('目标一'), findsOneWidget);
      expect(find.text('目标二'), findsOneWidget);

      // 勾选第 1 个
      final cb = find.byType(Checkbox).first;
      await tester.tap(cb);
      await settleAfterWrite(tester);

      expect((await db.studyGoalDao.findById(id1))!.isCompleted, isTrue);
    });

    testWidgets('目标显示类型标签', (tester) async {
      await seedGoal(name: '读书目标', type: StudyGoalType.reading);
      await pumpPage(tester);
      // 「读书」既是筛选 chip 也是类型标签
      expect(find.text('读书'), findsWidgets);
    });

    testWidgets('逾期目标显示「已逾期」', (tester) async {
      final now = DateTime.now();
      await seedGoal(
        name: '逾期目标',
        dueDate: DateTime(now.year, now.month, now.day - 1),
      );
      await pumpPage(tester);

      expect(find.textContaining('已逾期'), findsOneWidget);
    });

    testWidgets('筛选：只看未完成', (tester) async {
      await seedGoal(name: '未完成的目标');
      await seedGoal(name: '已完成的目标', isCompleted: true);
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '未完成'));
      await tester.pumpAndSettle();

      expect(find.text('未完成的目标'), findsOneWidget);
      expect(find.text('已完成的目标'), findsNothing);
    });

    testWidgets('点「加目标」打开表单页', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, '加目标'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalFormPage), findsOneWidget);
    });
  });

  // =========================================================================
  // UI：目标表单页
  // =========================================================================
  group('目标表单页', () {
    Future<void> pumpForm(WidgetTester tester, {StudyGoal? goal}) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(home: GoalFormPage(goal: goal)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('目标名为空时保存被拦截', (tester) async {
      await pumpForm(tester);
      await tapSubmit(tester, '加目标');
      await tester.pump();

      expect(find.text('请输入目标名称'), findsOneWidget);
      expect(await db.studyGoalDao.countAll(), 0);
    });

    testWidgets('填写名称与类型后保存成功', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '目标名称'),
        '读完《设计模式》',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '读书'));
      await tester.pumpAndSettle();
      await tapSubmit(tester, '加目标');
      await tester.pumpAndSettle();

      final goals = await db.studyGoalDao.findAll();
      expect(goals.length, 1);
      expect(goals.first.name, '读完《设计模式》');
      expect(goals.first.type, StudyGoalType.reading.code);
    });
  });

  // =========================================================================
  // UI：学习管理 Tab 容器
  // =========================================================================
  group('学习管理页面容器', () {
    Future<void> pumpPage(WidgetTester tester) async {
      useLargeViewport(tester);
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: StudyPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('4 个 Tab 标签齐全', (tester) async {
      await pumpPage(tester);
      expect(find.text('读书'), findsWidgets);
      expect(find.text('课程'), findsWidgets);
      expect(find.text('打卡'), findsWidgets);
      expect(find.text('目标'), findsWidgets);
    });

    testWidgets('默认显示读书 Tab', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有书'), findsOneWidget);
    });

    testWidgets('点「目标」切到目标 Tab', (tester) async {
      await pumpPage(tester);
      await tapTab(tester, '目标');
      await tester.pumpAndSettle();
      expect(find.text('还没有学习目标'), findsOneWidget);
    });

    testWidgets('点「打卡」切到打卡 Tab', (tester) async {
      await pumpPage(tester);
      await tapTab(tester, '打卡');
      await tester.pumpAndSettle();
      expect(find.text('还没有打卡记录'), findsOneWidget);
    });
  });
}
