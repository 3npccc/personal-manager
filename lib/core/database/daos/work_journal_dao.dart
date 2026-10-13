import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'work_journal_dao.g.dart';

/// 工作日志数据访问对象
@DriftAccessor(tables: [WorkJournals])
class WorkJournalDao extends DatabaseAccessor<AppDatabase>
    with _$WorkJournalDaoMixin {
  WorkJournalDao(super.db);

  /// 监听日志，可按关键字搜索内容 / 成果 / 问题
  Stream<List<WorkJournal>> watchAll({String? keyword}) {
    final query = select(workJournals);
    final kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) {
      query.where((t) =>
          t.content.like('%$kw%') |
          t.achievement.like('%$kw%') |
          t.problem.like('%$kw%'));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<WorkJournal?> findById(int id) {
    return (select(workJournals)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertJournal(WorkJournalsCompanion entry) {
    return into(workJournals).insert(entry);
  }

  Future<bool> updateJournal(WorkJournal entry) {
    return update(workJournals).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(workJournals)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countAll() async => workJournals.count().getSingle();
}
