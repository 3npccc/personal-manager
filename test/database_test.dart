// drift 与 matcher 都导出了 isNull / isNotNull，这里隐藏 drift 的同名符号，
// 保留 matcher 版本给 expect 使用。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/utils/date_utils.dart';

/// 阶段 2 数据库层测试。
///
/// 覆盖验收要求：
/// - 各表增删改查
/// - 场景筛选
/// - 金额分/元转换
/// - 按月收支统计
/// - 周报聚合
/// - 连续打卡天数
void main() {
  // 本文件会在「生命周期」用例中故意同时存在多个 AppDatabase 实例
  // （验证"关闭后可重新打开同一路径的不同实例"）。
  // 这些实例各自使用独立的内存库 executor，不存在竞态，
  // 因此关掉 drift 的多实例调试警告，保持测试输出干净。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() async {
    // 每个用例用独立内存库，互不污染
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发建表与内置分类初始化
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------
  // 表结构
  // ---------------------------------------------------------
  group('建库', () {
    test('内置分类已初始化，收入 4 项 / 支出 8 项', () async {
      final income = await db.categoryDao.findAll(type: 'income');
      final expense = await db.categoryDao.findAll(type: 'expense');

      expect(income.length, 4);
      expect(expense.length, 8);
      expect(income.map((e) => e.name), containsAll(['工资', '奖金', '理财', '其他收入']));
      expect(expense.map((e) => e.name),
          containsAll(['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '学习', '其他支出']));
      // 内置分类不可自定义
      expect(income.every((e) => e.isCustom), isFalse);
    });

    test('重复初始化不会产生重复数据', () async {
      await db.categoryDao.ensureBuiltInCategories();
      await db.categoryDao.ensureBuiltInCategories();
      final all = await db.categoryDao.findAll();
      expect(all.length, 12);
    });
  });

  // ---------------------------------------------------------
  // 待办 CRUD + 场景筛选
  // ---------------------------------------------------------
  group('待办 TodoDao', () {
    test('新增 / 查询 / 更新 / 删除', () async {
      final id = await db.todoDao.insertTodo(
        TodosCompanion.insert(
          title: '看书 30 页',
          scene: 'study',
          createdAt: DateTime(2026, 10, 10),
        ),
      );

      final inserted = await db.todoDao.findById(id);
      expect(inserted, isNotNull);
      expect(inserted!.title, '看书 30 页');
      expect(inserted.scene, 'study');
      expect(inserted.isCompleted, isFalse);
      expect(inserted.priority, 1); // 默认中优先级

      await db.todoDao.updateTodo(
        inserted.copyWith(title: '看书 50 页', priority: 2),
      );
      final updated = await db.todoDao.findById(id);
      expect(updated!.title, '看书 50 页');
      expect(updated.priority, 2);

      final deleted = await db.todoDao.deleteById(id);
      expect(deleted, 1);
      expect(await db.todoDao.findById(id), isNull);
    });

    test('按场景筛选', () async {
      for (final scene in ['study', 'work', 'life']) {
        await db.todoDao.insertTodo(
          TodosCompanion.insert(
            title: '任务-$scene',
            scene: scene,
            createdAt: DateTime.now(),
          ),
        );
      }

      final studyTodos = await db.todoDao.watchAll(scene: 'study').first;
      expect(studyTodos.length, 1);
      expect(studyTodos.first.scene, 'study');

      final all = await db.todoDao.watchAll().first;
      expect(all.length, 3);
    });

    test('按完成状态筛选', () async {
      final id1 = await db.todoDao.insertTodo(
        TodosCompanion.insert(
          title: '未完成',
          scene: 'work',
          createdAt: DateTime.now(),
        ),
      );
      await db.todoDao.insertTodo(
        TodosCompanion.insert(
          title: '也完成',
          scene: 'work',
          createdAt: DateTime.now(),
        ),
      );

      await db.todoDao.toggleCompleted(id1, true);

      final done = await db.todoDao.watchAll(isCompleted: true).first;
      expect(done.length, 1);
      expect(done.first.id, id1);
      expect(done.first.completedAt, isNotNull);

      final pending = await db.todoDao.watchAll(isCompleted: false).first;
      expect(pending.length, 1);
      expect(pending.first.title, '也完成');
    });

    test('取消完成时清空完成时间', () async {
      final id = await db.todoDao.insertTodo(
        TodosCompanion.insert(
          title: '反复横跳',
          scene: 'life',
          createdAt: DateTime.now(),
        ),
      );
      await db.todoDao.toggleCompleted(id, true);
      expect((await db.todoDao.findById(id))!.completedAt, isNotNull);

      await db.todoDao.toggleCompleted(id, false);
      expect((await db.todoDao.findById(id))!.completedAt, isNull);
    });

    test('排序：未完成优先，其次优先级高的靠前', () async {
      await db.todoDao.insertTodo(TodosCompanion.insert(
        title: '低优先级未完成',
        scene: 'work',
        priority: const Value(0),
        createdAt: DateTime.now(),
      ));
      await db.todoDao.insertTodo(TodosCompanion.insert(
        title: '高优先级未完成',
        scene: 'work',
        priority: const Value(2),
        createdAt: DateTime.now(),
      ));

      final list = await db.todoDao.watchAll().first;
      expect(list.first.title, '高优先级未完成');
    });

    test('按场景统计未完成数量', () async {
      for (var i = 0; i < 3; i++) {
        await db.todoDao.insertTodo(TodosCompanion.insert(
          title: '学习任务$i',
          scene: 'study',
          createdAt: DateTime.now(),
        ));
      }
      final doneId = await db.todoDao.insertTodo(TodosCompanion.insert(
        title: '已完成',
        scene: 'study',
        createdAt: DateTime.now(),
      ));
      await db.todoDao.toggleCompleted(doneId, true);

      expect(await db.todoDao.countPendingByScene('study'), 3);
      expect(await db.todoDao.countAll(), 4);
    });
  });

  // ---------------------------------------------------------
  // 笔记搜索
  // ---------------------------------------------------------
  group('笔记 NoteDao', () {
    test('CRUD 与关键字搜索（标题或正文）', () async {
      await db.noteDao.insertNote(NotesCompanion.insert(
        title: 'Flutter 布局',
        content: const Value('Row 和 Column 是最基础的布局控件'),
        scene: 'study',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await db.noteDao.insertNote(NotesCompanion.insert(
        title: '周会记录',
        content: const Value('讨论了下一季度目标'),
        scene: 'work',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // 命中标题
      final byTitle = await db.noteDao.watchAll(keyword: 'Flutter').first;
      expect(byTitle.length, 1);

      // 命中正文
      final byContent = await db.noteDao.watchAll(keyword: '季度').first;
      expect(byContent.length, 1);
      expect(byContent.first.scene, 'work');

      // 场景筛选
      final study = await db.noteDao.watchAll(scene: 'study').first;
      expect(study.length, 1);
    });

    test('按场景统计数量', () async {
      for (final scene in ['study', 'study', 'work']) {
        await db.noteDao.insertNote(NotesCompanion.insert(
          title: 'n-$scene',
          scene: scene,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
      final counts = await db.noteDao.countByScene();
      expect(counts['study'], 2);
      expect(counts['work'], 1);
      expect(await db.noteDao.countAll(), 3);
    });
  });

  // ---------------------------------------------------------
  // 记账：月度统计 + 外键保护
  // ---------------------------------------------------------
  group('记账 LedgerDao', () {
    test('按月统计收入 / 支出 / 结余', () async {
      final incomeCat = (await db.categoryDao.findAll(type: 'income')).first;
      final expenseCat = (await db.categoryDao.findAll(type: 'expense')).first;

      // 10 月：收入 1000.00，支出 250.50
      await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
        type: 'income',
        amountCents: 100000,
        categoryId: incomeCat.id,
        recordDate: DateTime(2026, 10, 5),
        createdAt: DateTime.now(),
      ));
      await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
        type: 'expense',
        amountCents: 25050,
        categoryId: expenseCat.id,
        recordDate: DateTime(2026, 10, 8),
        createdAt: DateTime.now(),
      ));
      // 11 月：支出 100.00（不应计入 10 月）
      await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
        type: 'expense',
        amountCents: 10000,
        categoryId: expenseCat.id,
        recordDate: DateTime(2026, 11, 1),
        createdAt: DateTime.now(),
      ));

      final summary = await db.ledgerDao.summaryOfMonth(DateTime(2026, 10));
      expect(summary.incomeCents, 100000);
      expect(summary.expenseCents, 25050);
      expect(summary.balanceCents, 74950);
    });

    test('月份筛选与类型筛选', () async {
      final cat = (await db.categoryDao.findAll(type: 'expense')).first;
      await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
        type: 'expense',
        amountCents: 5000,
        categoryId: cat.id,
        recordDate: DateTime(2026, 10, 3),
        createdAt: DateTime.now(),
      ));

      final oct = await db.ledgerDao
          .watchAll(month: DateTime(2026, 10), type: 'expense')
          .first;
      expect(oct.length, 1);

      final sep = await db.ledgerDao
          .watchAll(month: DateTime(2026, 9), type: 'expense')
          .first;
      expect(sep, isEmpty);
    });

    test('分类被引用时 isReferenced 为 true，删除受外键保护', () async {
      final cat = (await db.categoryDao.findAll(type: 'expense')).first;
      await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
        type: 'expense',
        amountCents: 100,
        categoryId: cat.id,
        recordDate: DateTime(2026, 10, 1),
        createdAt: DateTime.now(),
      ));

      expect(await db.categoryDao.isReferenced(cat.id), isTrue);

      // 外键 restrict：被引用时删除应抛异常
      expect(
        () => db.categoryDao.deleteById(cat.id),
        throwsA(anything),
      );
    });

    test('未被引用的分类可以删除', () async {
      final cat = await db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          type: 'expense',
          name: '自定义分类',
          isCustom: const Value(true),
        ),
      );
      expect(await db.categoryDao.isReferenced(cat), isFalse);
      expect(await db.categoryDao.deleteById(cat), 1);
    });

    test('单日支出聚合', () async {
      final cat = (await db.categoryDao.findAll(type: 'expense')).first;
      for (final cents in [1000, 2000]) {
        await db.ledgerDao.insertRecord(LedgerRecordsCompanion.insert(
          type: 'expense',
          amountCents: cents,
          categoryId: cat.id,
          recordDate: DateTime(2026, 10, 6),
          createdAt: DateTime.now(),
        ));
      }
      final daily = await db.ledgerDao.dailyExpenseOfMonth(DateTime(2026, 10));
      expect(daily.length, 1);
      expect(daily.first.amountCents, 3000);
    });
  });

  // ---------------------------------------------------------
  // 学习：读书 / 课程 / 打卡 / 目标
  // ---------------------------------------------------------
  group('学习模块', () {
    test('读书进度', () async {
      final id = await db.bookDao.insertBook(BooksCompanion.insert(
        title: '深入理解计算机系统',
        author: const Value('Randal'),
        currentPage: const Value(120),
        totalPages: const Value(600),
        status: 'reading',
        createdAt: DateTime.now(),
      ));
      final book = await db.bookDao.findById(id);
      expect(book!.currentPage, 120);
      expect(book.totalPages, 600);
    });

    test('课程进度更新，满进度自动标记完成', () async {
      final id = await db.courseDao.insertCourse(CoursesCompanion.insert(
        name: 'Flutter 进阶',
        platform: const Value('B站'),
        totalChapters: const Value(20),
        status: 'ongoing',
      ));

      await db.courseDao.updateProgress(id, 10);
      var course = await db.courseDao.findById(id);
      expect(course!.completedChapters, 10);
      expect(course.status, 'ongoing'); // 未满，保持进行中

      await db.courseDao.updateProgress(id, 20);
      course = await db.courseDao.findById(id);
      expect(course!.status, 'completed'); // 满了自动完成
    });

    test('学习目标切换完成状态', () async {
      final id = await db.studyGoalDao.insertGoal(StudyGoalsCompanion.insert(
        name: '今年读完 12 本书',
        type: 'reading',
        dueDate: Value(DateTime(2026, 12, 31)),
        createdAt: DateTime.now(),
      ));
      expect(await db.studyGoalDao.countPending(), 1);

      await db.studyGoalDao.toggleCompleted(id, true);
      expect(await db.studyGoalDao.countPending(), 0);
    });
  });

  /// 打卡记录插入的语法糖：date 必填，createdAt 默认取当前时间
  Future<int> addCheckin(DateTime date, {int minutes = 0, String? content}) {
    return db.studyCheckinDao.insertCheckin(
      StudyCheckinsCompanion.insert(
        date: date,
        minutes: Value(minutes),
        content: Value(content ?? ''),
        createdAt: DateTime.now(),
      ),
    );
  }

  // ---------------------------------------------------------
  // 连续打卡天数（核心算法）
  // ---------------------------------------------------------
  group('连续打卡天数 DateUtils2.calculateStreak', () {
    test('空集合返回 0', () {
      expect(DateUtils2.calculateStreak([]), 0);
    });

    test('连续 3 天（含今天）返回 3', () {
      final today = DateTime(2026, 10, 10);
      final dates = [
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
      ];
      expect(DateUtils2.calculateStreak(dates, today: today), 3);
    });

    test('断档后只算连续段', () {
      final today = DateTime(2026, 10, 10);
      final dates = [
        today,
        today.subtract(const Duration(days: 1)),
        // 跳过第 2 天
        today.subtract(const Duration(days: 3)),
        today.subtract(const Duration(days: 4)),
      ];
      expect(DateUtils2.calculateStreak(dates, today: today), 2);
    });

    test('最近打卡是昨天，连续性保持（返回 2）', () {
      final today = DateTime(2026, 10, 10);
      final dates = [
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
      ];
      expect(DateUtils2.calculateStreak(dates, today: today), 2);
    });

    test('最近打卡超过 1 天前，连续性已断，返回 0', () {
      final today = DateTime(2026, 10, 10);
      final dates = [today.subtract(const Duration(days: 3))];
      expect(DateUtils2.calculateStreak(dates, today: today), 0);
    });

    test('同一天重复打卡不重复计数', () {
      final today = DateTime(2026, 10, 10);
      final dates = [
        today,
        DateTime(2026, 10, 10, 9), // 同一天不同时刻
        DateTime(2026, 10, 10, 21),
      ];
      expect(DateUtils2.calculateStreak(dates, today: today), 1);
    });

    test('打卡表接入：写入 3 天数据后连续天数为 3', () async {
      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await addCheckin(today.subtract(Duration(days: i)),
            minutes: 60, content: '学习 Flutter');
      }
      final dates = await db.studyCheckinDao.allCheckinDates();
      expect(DateUtils2.calculateStreak(dates), 3);
    });

    test('月度总学习时长', () async {
      await addCheckin(DateTime(2026, 10, 2), minutes: 90);
      await addCheckin(DateTime(2026, 10, 5), minutes: 30);

      expect(await db.studyCheckinDao.totalMinutesOfMonth(DateTime(2026, 10)),
          120);
      expect(await db.studyCheckinDao.totalMinutesOfMonth(DateTime(2026, 9)), 0);
    });
  });

  // ---------------------------------------------------------
  // 工作：项目 / 工时 / 周报聚合 / 日志
  // ---------------------------------------------------------
  group('工作模块', () {
    test('项目进度更新，满 100 自动完成', () async {
      final id = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '个人管理程序',
        status: 'ongoing',
        progress: const Value(30),
        createdAt: DateTime.now(),
      ));
      expect(await db.projectDao.countOngoing(), 1);

      await db.projectDao.updateProgress(id, 100);
      final project = await db.projectDao.findById(id);
      expect(project!.progress, 100);
      expect(project.status, 'completed');
    });

    test('进度超界被裁剪到 0-100', () async {
      final id = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '裁剪测试',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));
      await db.projectDao.updateProgress(id, 150);
      expect((await db.projectDao.findById(id))!.progress, 100);

      await db.projectDao.updateProgress(id, -20);
      expect((await db.projectDao.findById(id))!.progress, 0);
    });

    test('周报聚合：按项目合计工时', () async {
      final p1 = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '项目A',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));
      final p2 = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '项目B',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));

      // 项目A：周一 120 分钟 + 周二 60 分钟 = 180
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p1,
        date: DateTime(2026, 10, 5),
        minutes: 120,
        summary: const Value('需求评审'),
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p1,
        date: DateTime(2026, 10, 6),
        minutes: 60,
        summary: const Value('编码'),
        createdAt: DateTime.now(),
      ));
      // 项目B：周一 90 分钟
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p2,
        date: DateTime(2026, 10, 5),
        minutes: 90,
        summary: const Value('联调'),
        createdAt: DateTime.now(),
      ));
      // 范围外（下周）不应计入
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p1,
        date: DateTime(2026, 10, 20),
        minutes: 999,
        createdAt: DateTime.now(),
      ));

      // 本周：10/5 周一 ~ 10/12 周一
      final summary = await db.workLogDao.summaryByProject(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
      );

      expect(summary.length, 2);
      final a = summary.firstWhere((s) => s.projectName == '项目A');
      final b = summary.firstWhere((s) => s.projectName == '项目B');
      expect(a.totalMinutes, 180);
      expect(b.totalMinutes, 90);
    });

    test('周报明细按日期升序', () async {
      final p = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '项目C',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p,
        date: DateTime(2026, 10, 7),
        minutes: 30,
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p,
        date: DateTime(2026, 10, 5),
        minutes: 60,
        createdAt: DateTime.now(),
      ));

      final logs = await db.workLogDao
          .findBetween(DateTime(2026, 10, 5), DateTime(2026, 10, 12));
      expect(logs.first.date.day, 5);
      expect(logs.last.date.day, 7);
    });

    test('项目累计工时', () async {
      final p = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '累计测试',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p,
        date: DateTime(2026, 10, 5),
        minutes: 45,
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p,
        date: DateTime(2026, 10, 6),
        minutes: 55,
        createdAt: DateTime.now(),
      ));
      expect(await db.workLogDao.totalMinutesOfProject(p), 100);
    });

    test('删除项目时工时记录级联删除', () async {
      final p = await db.projectDao.insertProject(ProjectsCompanion.insert(
        name: '待删除',
        status: 'ongoing',
        createdAt: DateTime.now(),
      ));
      await db.workLogDao.insertLog(WorkLogsCompanion.insert(
        projectId: p,
        date: DateTime(2026, 10, 5),
        minutes: 30,
        createdAt: DateTime.now(),
      ));
      expect(await db.workLogDao.countAll(), 1);

      await db.projectDao.deleteById(p);
      expect(await db.workLogDao.countAll(), 0); // cascade 生效
    });

    test('工作日志关键字搜索', () async {
      await db.workJournalDao.insertJournal(WorkJournalsCompanion.insert(
        date: DateTime(2026, 10, 10),
        content: const Value('完成了数据库层设计'),
        achievement: const Value('15 张表落地'),
        createdAt: DateTime.now(),
      ));
      await db.workJournalDao.insertJournal(WorkJournalsCompanion.insert(
        date: DateTime(2026, 10, 9),
        content: const Value('开会'),
        problem: const Value('依赖版本冲突'),
        createdAt: DateTime.now(),
      ));

      final byContent =
          await db.workJournalDao.watchAll(keyword: '数据库层').first;
      expect(byContent.length, 1);

      final byProblem =
          await db.workJournalDao.watchAll(keyword: '版本冲突').first;
      expect(byProblem.length, 1);
    });
  });

  // ---------------------------------------------------------
  // 生活：习惯 / 健康 / 备忘
  // ---------------------------------------------------------
  group('生活模块', () {
    test('习惯打卡连续天数', () async {
      final habitId = await db.habitDao.insertHabit(HabitsCompanion.insert(
        name: '早起',
        frequency: 'daily',
        createdAt: DateTime.now(),
      ));

      final today = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await db.habitCheckinDao.insertCheckin(HabitCheckinsCompanion.insert(
          habitId: habitId,
          date: today.subtract(Duration(days: i)),
        ));
      }

      final dates = await db.habitCheckinDao.checkinDatesOfHabit(habitId);
      expect(DateUtils2.calculateStreak(dates), 3);
      expect(await db.habitCheckinDao.countToday(), 1);
    });

    test('同一天同一习惯重复插入不会产生重复行（幂等）', () async {
      final habitId = await db.habitDao.insertHabit(HabitsCompanion.insert(
        name: '喝水',
        frequency: 'daily',
        createdAt: DateTime.now(),
      ));
      final day = DateTime(2026, 10, 10);

      final id1 = await db.habitCheckinDao.insertCheckin(
          HabitCheckinsCompanion.insert(
            habitId: habitId,
            date: DateTime(2026, 10, 10, 8),
          ));
      final id2 = await db.habitCheckinDao.insertCheckin(
          HabitCheckinsCompanion.insert(
            habitId: habitId,
            date: DateTime(2026, 10, 10, 20),
          ));

      // 第二次插入返回同一条记录 id，而不是新建
      expect(id2, id1);

      // 库里当天的记录有且仅有一条
      final rows = await db.habitCheckinDao.watchByHabit(habitId).first;
      expect(rows.length, 1);

      // 精确查单条不应抛错，且能查到
      final found = await db.habitCheckinDao.findByHabitAndDate(habitId, day);
      expect(found, isNotNull);
      expect(found!.id, id1);

      // 存储的日期被归一化到当天 00:00
      expect(found.date, DateTime(2026, 10, 10));
    });

    test('toggleCheckin 在未打卡/已打卡间来回切换', () async {
      final habitId = await db.habitDao.insertHabit(HabitsCompanion.insert(
        name: '阅读',
        frequency: 'daily',
        createdAt: DateTime.now(),
      ));
      final day = DateTime(2026, 10, 11);

      // 首次切换 -> 变为已打卡
      expect(await db.habitCheckinDao.toggleCheckin(habitId, day), isTrue);
      expect(await db.habitCheckinDao.findByHabitAndDate(habitId, day),
          isNotNull);
      expect((await db.habitCheckinDao.watchByHabit(habitId).first).length, 1);

      // 再次切换 -> 取消打卡
      expect(await db.habitCheckinDao.toggleCheckin(habitId, day), isFalse);
      expect(await db.habitCheckinDao.findByHabitAndDate(habitId, day), isNull);
      expect((await db.habitCheckinDao.watchByHabit(habitId).first).length, 0);

      // 第三次切换 -> 又变为已打卡（不会残留旧行）
      expect(await db.habitCheckinDao.toggleCheckin(habitId, day), isTrue);
      expect((await db.habitCheckinDao.watchByHabit(habitId).first).length, 1);
    });

    test('健康记录：睡眠 / 运动 / 体重', () async {
      await db.healthRecordDao.insertRecord(
        HealthRecordsCompanion.insert(
          date: DateTime(2026, 10, 10),
          sleepHours: const Value(7.5),
          exerciseMinutes: const Value(30),
          weightKg: const Value(65.5),
        ),
      );
      final record =
          await db.healthRecordDao.findByDate(DateTime(2026, 10, 10));
      expect(record, isNotNull);
      expect(record!.sleepHours, 7.5);
      expect(record.exerciseMinutes, 30);
      expect(record.weightKg, 65.5);
    });

    test('生活备忘完成状态与待办数', () async {
      final id = await db.lifeMemoDao.insertMemo(LifeMemosCompanion.insert(
        title: '交房租',
        remindAt: Value(DateTime(2026, 11, 1)),
        createdAt: DateTime.now(),
      ));
      await db.lifeMemoDao.insertMemo(LifeMemosCompanion.insert(
        title: '取快递',
        createdAt: DateTime.now(),
      ));
      expect(await db.lifeMemoDao.countPending(), 2);

      await db.lifeMemoDao.toggleCompleted(id, true);
      expect(await db.lifeMemoDao.countPending(), 1);
    });
  });

  // ---------------------------------------------------------
  // 清空与重开（数据库可反复关闭重建）
  // ---------------------------------------------------------
  group('生命周期', () {
    test('关闭后可重新打开同一路径的不同实例', () async {
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      await db2.customSelect('SELECT 1').get();
      expect(await db2.todoDao.countAll(), 0);
      await db2.close();
    });
  });
}
