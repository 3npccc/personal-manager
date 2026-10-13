import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/book_dao.dart';
import 'daos/category_dao.dart';
import 'daos/course_dao.dart';
import 'daos/habit_checkin_dao.dart';
import 'daos/habit_dao.dart';
import 'daos/health_record_dao.dart';
import 'daos/ledger_dao.dart';
import 'daos/life_memo_dao.dart';
import 'daos/note_dao.dart';
import 'daos/project_dao.dart';
import 'daos/study_checkin_dao.dart';
import 'daos/study_goal_dao.dart';
import 'daos/todo_dao.dart';
import 'daos/work_journal_dao.dart';
import 'daos/work_log_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// 应用数据库。
///
/// 【约定】
/// - 金额一律整数「分」，禁止 double。
/// - schemaVersion 从 1 开始，改表结构时递增并在 migration 中写迁移逻辑。
/// - 改表后固定执行：
///     dart run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    // 通用
    Todos,
    Notes,
    LedgerRecords,
    Categories,
    // 学习
    Books,
    Courses,
    StudyCheckins,
    StudyGoals,
    // 工作
    Projects,
    WorkLogs,
    WorkJournals,
    // 生活
    Habits,
    HabitCheckins,
    HealthRecords,
    LifeMemos,
  ],
  daos: [
    TodoDao,
    NoteDao,
    LedgerDao,
    CategoryDao,
    BookDao,
    CourseDao,
    StudyCheckinDao,
    StudyGoalDao,
    ProjectDao,
    WorkLogDao,
    WorkJournalDao,
    HabitDao,
    HabitCheckinDao,
    HealthRecordDao,
    LifeMemoDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 生产环境：由 drift_flutter 决定数据文件位置（Windows: 用户文档目录）
  AppDatabase() : super(_openConnection());

  /// 测试环境：注入内存数据库。
  ///
  /// 【为什么包一层 DatabaseConnection 而不是直接 super(executor)】
  /// drift 默认在「最后一个订阅者离开」时不同步关闭查询流，而是
  /// `Timer.run(...)` 延迟一个事件循环（为了给 StreamBuilder 重建时
  /// 复用缓存的机会，见 drift stream_queries.dart 的注释）。
  /// 这个 timer 会触发 flutter_test 的框架级断言：
  ///   「A Timer is still pending even after the widget tree was disposed」
  /// 该断言在测试体结束、widget 树销毁时由 binding 立即执行，
  /// 任何 `addTearDown` 里的补救都来不及（时序上晚于断言）。
  ///
  /// drift 官方为此提供了 `closeStreamsSynchronously` 开关：置 true 后
  /// `markAsClosed` 直接同步执行、**根本不创建 timer**。
  /// 这正是「测试里出现持久 timer」场景的官配解法，故测试连接统一开启。
  AppDatabase.forTesting(QueryExecutor executor)
      : super(DatabaseConnection(
          executor,
          closeStreamsSynchronously: true,
        ));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // 建全部表
          await m.createAll();
          // 初始化内置分类（仅首次创建时执行一次）
          await categoryDao.ensureBuiltInCategories();
        },
        onUpgrade: (m, from, to) async {
          // schemaVersion 1 暂无升级逻辑。
          // 后续改表时在此按 from/to 逐版本处理，禁止直接删库。
        },
        beforeOpen: (details) async {
          // 外键约束必须开启，否则 references 不生效
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// 打开本地数据库连接（跨 Windows / Android）
QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'personal_manager',
  );
}
