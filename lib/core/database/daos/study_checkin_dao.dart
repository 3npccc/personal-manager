import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'study_checkin_dao.g.dart';

/// 学习打卡数据访问对象
@DriftAccessor(tables: [StudyCheckins])
class StudyCheckinDao extends DatabaseAccessor<AppDatabase>
    with _$StudyCheckinDaoMixin {
  StudyCheckinDao(super.db);

  /// 监听打卡记录，按日期倒序
  Stream<List<StudyCheckin>> watchAll() {
    final query = select(studyCheckins)
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 监听指定月份内的打卡记录
  Stream<List<StudyCheckin>> watchMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final query = select(studyCheckins)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end))
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<StudyCheckin?> findById(int id) {
    return (select(studyCheckins)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 查找某一天的打卡（用于判断今天是否已打卡）
  Future<StudyCheckin?> findByDate(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(studyCheckins)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .getSingleOrNull();
  }

  /// 一次性查询（测试用，见 book_dao.dart 里 findAll 的说明）
  Future<List<StudyCheckin>> findAll() {
    final query = select(studyCheckins)
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    return query.get();
  }

  Future<int> insertCheckin(StudyCheckinsCompanion entry) {
    return into(studyCheckins).insert(entry);
  }

  Future<bool> updateCheckin(StudyCheckin entry) {
    return update(studyCheckins).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(studyCheckins)..where((t) => t.id.equals(id))).go();
  }

  /// 全部打卡日期（去重、升序），用于计算连续打卡天数
  Future<List<DateTime>> allCheckinDates() async {
    final query = selectOnly(studyCheckins)
      ..addColumns([studyCheckins.date])
      ..groupBy([studyCheckins.date])
      ..orderBy([
        OrderingTerm(
          expression: studyCheckins.date,
          mode: OrderingMode.asc,
        ),
      ]);
    final rows = await query.get();
    final result = <DateTime>[];
    for (final row in rows) {
      final d = row.read(studyCheckins.date);
      if (d != null) {
        result.add(DateTime(d.year, d.month, d.day));
      }
    }
    return result;
  }

  /// 指定月份总学习时长（分钟）
  Future<int> totalMinutesOfMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final sum = studyCheckins.minutes.sum();
    final query = selectOnly(studyCheckins)
      ..addColumns([sum])
      ..where(studyCheckins.date.isBiggerOrEqualValue(start) &
          studyCheckins.date.isSmallerThanValue(end));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  Future<int> countAll() async => studyCheckins.count().getSingle();
}
