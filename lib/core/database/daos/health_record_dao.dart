import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'health_record_dao.g.dart';

/// 健康记录数据访问对象
@DriftAccessor(tables: [HealthRecords])
class HealthRecordDao extends DatabaseAccessor<AppDatabase>
    with _$HealthRecordDaoMixin {
  HealthRecordDao(super.db);

  Stream<List<HealthRecord>> watchAll() {
    final query = select(healthRecords)
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 按日期查（同一天只保留一条）
  Future<HealthRecord?> findByDate(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(healthRecords)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .getSingleOrNull();
  }

  Future<HealthRecord?> findById(int id) {
    return (select(healthRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertRecord(HealthRecordsCompanion entry) {
    return into(healthRecords).insert(entry);
  }

  Future<bool> updateRecord(HealthRecord entry) {
    return update(healthRecords).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(healthRecords)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countAll() async => healthRecords.count().getSingle();
}
