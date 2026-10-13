import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'life_memo_dao.g.dart';

/// 生活备忘数据访问对象
@DriftAccessor(tables: [LifeMemos])
class LifeMemoDao extends DatabaseAccessor<AppDatabase>
    with _$LifeMemoDaoMixin {
  LifeMemoDao(super.db);

  Stream<List<LifeMemo>> watchAll({bool? isCompleted}) {
    final query = select(lifeMemos);
    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.isCompleted, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.remindAt, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<LifeMemo?> findById(int id) {
    return (select(lifeMemos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertMemo(LifeMemosCompanion entry) {
    return into(lifeMemos).insert(entry);
  }

  Future<bool> updateMemo(LifeMemo entry) {
    return update(lifeMemos).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(lifeMemos)..where((t) => t.id.equals(id))).go();
  }

  Future<void> toggleCompleted(int id, bool isCompleted) async {
    await (update(lifeMemos)..where((t) => t.id.equals(id))).write(
      LifeMemosCompanion(isCompleted: Value(isCompleted)),
    );
  }

  Future<int> countPending() async {
    final count = lifeMemos.id.count();
    final query = selectOnly(lifeMemos)
      ..addColumns([count])
      ..where(lifeMemos.isCompleted.equals(false));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countAll() async => lifeMemos.count().getSingle();
}
