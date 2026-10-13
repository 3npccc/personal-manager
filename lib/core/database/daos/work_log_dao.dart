import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'work_log_dao.g.dart';

/// 工时记录数据访问对象
@DriftAccessor(tables: [WorkLogs, Projects])
class WorkLogDao extends DatabaseAccessor<AppDatabase> with _$WorkLogDaoMixin {
  WorkLogDao(super.db);

  /// 监听工时记录，可按项目 / 日期范围筛选
  Stream<List<WorkLog>> watchAll({
    int? projectId,
    DateTime? start,
    DateTime? end,
  }) {
    final query = select(workLogs);
    if (projectId != null) {
      query.where((t) => t.projectId.equals(projectId));
    }
    if (start != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(start));
    }
    if (end != null) {
      query.where((t) => t.date.isSmallerThanValue(end));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<WorkLog?> findById(int id) {
    return (select(workLogs)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertLog(WorkLogsCompanion entry) {
    return into(workLogs).insert(entry);
  }

  Future<bool> updateLog(WorkLog entry) {
    return update(workLogs).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(workLogs)..where((t) => t.id.equals(id))).go();
  }

  /// 周报聚合：指定时间范围内，按项目分组合计工时与摘要
  Future<List<ProjectWorkSummary>> summaryByProject(
      DateTime start, DateTime end) async {
    final query = selectOnly(workLogs)
      ..addColumns([workLogs.minutes.sum(), workLogs.projectId])
      ..where(workLogs.date.isBiggerOrEqualValue(start) &
          workLogs.date.isSmallerThanValue(end))
      ..groupBy([workLogs.projectId]);

    final rows = await query.get();

    // 取出项目名，避免在循环里重复查询
    final projects = await select(this.projects).get();
    final nameMap = {for (final p in projects) p.id: p.name};

    return [
      for (final row in rows)
        ProjectWorkSummary(
          projectId: row.read(workLogs.projectId)!,
          projectName: nameMap[row.read(workLogs.projectId)] ?? '（已删除项目）',
          totalMinutes: row.read(workLogs.minutes.sum()) ?? 0,
        ),
    ];
  }

  /// 指定时间范围内的日志明细（周报正文用）
  Future<List<WorkLog>> findBetween(DateTime start, DateTime end) {
    final query = select(workLogs)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end))
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
      ]);
    return query.get();
  }

  /// 某项目的累计工时（分钟）
  Future<int> totalMinutesOfProject(int projectId) async {
    final sum = workLogs.minutes.sum();
    final query = selectOnly(workLogs)
      ..addColumns([sum])
      ..where(workLogs.projectId.equals(projectId));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  Future<int> countAll() async => workLogs.count().getSingle();
}

/// 按项目聚合的工时统计（周报用）
class ProjectWorkSummary {
  const ProjectWorkSummary({
    required this.projectId,
    required this.projectName,
    required this.totalMinutes,
  });

  final int projectId;
  final String projectName;
  final int totalMinutes;
}
