import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'study_goal_dao.g.dart';

/// 学习目标数据访问对象
@DriftAccessor(tables: [StudyGoals])
class StudyGoalDao extends DatabaseAccessor<AppDatabase>
    with _$StudyGoalDaoMixin {
  StudyGoalDao(super.db);

  Stream<List<StudyGoal>> watchAll({bool? isCompleted}) {
    final query = select(studyGoals);
    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.isCompleted, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<StudyGoal?> findById(int id) {
    return (select(studyGoals)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 一次性查询（测试用，见 book_dao.dart 里 findAll 的说明）
  Future<List<StudyGoal>> findAll({bool? isCompleted}) {
    final query = select(studyGoals);
    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.isCompleted, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<int> insertGoal(StudyGoalsCompanion entry) {
    return into(studyGoals).insert(entry);
  }

  Future<bool> updateGoal(StudyGoal entry) {
    return update(studyGoals).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(studyGoals)..where((t) => t.id.equals(id))).go();
  }

  /// 切换完成状态
  Future<void> toggleCompleted(int id, bool isCompleted) async {
    await (update(studyGoals)..where((t) => t.id.equals(id))).write(
      StudyGoalsCompanion(isCompleted: Value(isCompleted)),
    );
  }

  /// 未完成目标数（首页提醒用）
  Future<int> countPending() async {
    final count = studyGoals.id.count();
    final query = selectOnly(studyGoals)
      ..addColumns([count])
      ..where(studyGoals.isCompleted.equals(false));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countAll() async => studyGoals.count().getSingle();
}
