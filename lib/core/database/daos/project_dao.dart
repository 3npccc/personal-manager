import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'project_dao.g.dart';

/// 项目数据访问对象
@DriftAccessor(tables: [Projects])
class ProjectDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectDaoMixin {
  ProjectDao(super.db);

  Stream<List<Project>> watchAll({String? status}) {
    final query = select(projects);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.status, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<List<Project>> findAll() => select(projects).get();

  Future<Project?> findById(int id) {
    return (select(projects)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertProject(ProjectsCompanion entry) {
    return into(projects).insert(entry);
  }

  Future<bool> updateProject(Project entry) {
    return update(projects).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(projects)..where((t) => t.id.equals(id))).go();
  }

  /// 更新进度，并在达到 100% 时自动标记为已完成
  Future<void> updateProgress(int id, int progress) async {
    final clamped = progress.clamp(0, 100);
    await (update(projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        progress: Value(clamped),
        status: clamped >= 100 ? const Value('completed') : Value.absent(),
      ),
    );
  }

  /// 进行中的项目数（首页提醒用）
  Future<int> countOngoing() async {
    final count = projects.id.count();
    final query = selectOnly(projects)
      ..addColumns([count])
      ..where(projects.status.equals('ongoing'));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countAll() async => projects.count().getSingle();
}
