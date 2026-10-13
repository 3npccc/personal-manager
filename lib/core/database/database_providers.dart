import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'database.dart';

/// 应用数据库实例。
///
/// 【约定】
/// - 生产环境不 override，直接用 [AppDatabase]（文件落在用户文档目录）。
/// - 测试环境必须 override 成内存库，例如：
///   `appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory()))`
/// - 用 `ref.onDispose(db.close)` 保证 provider 销毁时释放连接，
///   避免 drift 报「同一 QueryExecutor 被多个 AppDatabase 使用」。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------------------------------------------------------------------------
// DAO Provider
// ---------------------------------------------------------------------------
// 说明：DAO 本身是极轻量的对象（只是一个持有 db 引用的包装），
// 因此这里每个 DAO 用 `ref.watch(appDatabaseProvider)` 取库后 new 出来即可，
// 不需要做实例缓存。这也保证了「测试换库 → DAO 自动跟着换」。

final todoDaoProvider = Provider<TodoDao>(
  (ref) => ref.watch(appDatabaseProvider).todoDao,
);

final noteDaoProvider = Provider<NoteDao>(
  (ref) => ref.watch(appDatabaseProvider).noteDao,
);

final ledgerDaoProvider = Provider<LedgerDao>(
  (ref) => ref.watch(appDatabaseProvider).ledgerDao,
);

final categoryDaoProvider = Provider<CategoryDao>(
  (ref) => ref.watch(appDatabaseProvider).categoryDao,
);

final bookDaoProvider = Provider<BookDao>(
  (ref) => ref.watch(appDatabaseProvider).bookDao,
);

final courseDaoProvider = Provider<CourseDao>(
  (ref) => ref.watch(appDatabaseProvider).courseDao,
);

final studyCheckinDaoProvider = Provider<StudyCheckinDao>(
  (ref) => ref.watch(appDatabaseProvider).studyCheckinDao,
);

final studyGoalDaoProvider = Provider<StudyGoalDao>(
  (ref) => ref.watch(appDatabaseProvider).studyGoalDao,
);

final projectDaoProvider = Provider<ProjectDao>(
  (ref) => ref.watch(appDatabaseProvider).projectDao,
);

final workLogDaoProvider = Provider<WorkLogDao>(
  (ref) => ref.watch(appDatabaseProvider).workLogDao,
);

final workJournalDaoProvider = Provider<WorkJournalDao>(
  (ref) => ref.watch(appDatabaseProvider).workJournalDao,
);

final habitDaoProvider = Provider<HabitDao>(
  (ref) => ref.watch(appDatabaseProvider).habitDao,
);

final habitCheckinDaoProvider = Provider<HabitCheckinDao>(
  (ref) => ref.watch(appDatabaseProvider).habitCheckinDao,
);

final healthRecordDaoProvider = Provider<HealthRecordDao>(
  (ref) => ref.watch(appDatabaseProvider).healthRecordDao,
);

final lifeMemoDaoProvider = Provider<LifeMemoDao>(
  (ref) => ref.watch(appDatabaseProvider).lifeMemoDao,
);
