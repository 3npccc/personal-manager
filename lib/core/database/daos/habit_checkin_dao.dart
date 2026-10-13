import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'habit_checkin_dao.g.dart';

/// 习惯打卡数据访问对象
@DriftAccessor(tables: [HabitCheckins])
class HabitCheckinDao extends DatabaseAccessor<AppDatabase>
    with _$HabitCheckinDaoMixin {
  HabitCheckinDao(super.db);

  /// 监听某习惯的全部打卡，按日期倒序
  Stream<List<HabitCheckin>> watchByHabit(int habitId) {
    final query = select(habitCheckins)
      ..where((t) => t.habitId.equals(habitId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<HabitCheckin?> findById(int id) {
    return (select(habitCheckins)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 某习惯在某天是否已打卡（返回当天的记录，最多一条）。
  ///
  /// 正常状态下「同一习惯同一天至多一条」由 [insertCheckin] 保证；
  /// 这里额外用 `limit(1)` 做防御，避免历史脏数据导致 `getSingleOrNull()`
  /// 抛 `Too many elements` 而整个页面崩掉。
  Future<HabitCheckin?> findByHabitAndDate(int habitId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(habitCheckins)
          ..where((t) =>
              t.habitId.equals(habitId) &
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end))
          ..orderBy([
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 插入一条打卡记录（幂等）。
  ///
  /// 「习惯打卡」的业务语义是「每日一次的布尔状态」，同一天重复打卡属于脏数据，
  /// 会污染连续天数与今日打卡统计。因此若该习惯当天已有记录，直接返回已有 id，
  /// 不再新增行。日期会被归一化到当天 00:00。
  ///
  /// 返回该 (habitId, 当天) 对应记录的 id。
  Future<int> insertCheckin(HabitCheckinsCompanion entry) async {
    assert(entry.habitId.present && entry.date.present,
        'insertCheckin 必须提供 habitId 与 date');
    final habitId = entry.habitId.value;
    final raw = entry.date.value;
    final day = DateTime(raw.year, raw.month, raw.day);

    final existing = await findByHabitAndDate(habitId, day);
    if (existing != null) {
      return existing.id;
    }
    return into(habitCheckins).insert(entry.copyWith(date: Value(day)));
  }

  /// 切换某习惯某天的打卡状态：未打卡则插入，已打卡则删除。
  ///
  /// 返回切换后的状态：`true` 表示切换后为「已打卡」。
  Future<bool> toggleCheckin(int habitId, DateTime day) async {
    final existing = await findByHabitAndDate(habitId, day);
    if (existing != null) {
      await deleteById(existing.id);
      return false;
    }
    await insertCheckin(HabitCheckinsCompanion.insert(
      habitId: habitId,
      date: DateTime(day.year, day.month, day.day),
    ));
    return true;
  }

  Future<int> deleteById(int id) {
    return (delete(habitCheckins)..where((t) => t.id.equals(id))).go();
  }

  /// 某习惯的全部打卡日期（去重升序），用于连续天数计算
  Future<List<DateTime>> checkinDatesOfHabit(int habitId) async {
    final query = selectOnly(habitCheckins)
      ..addColumns([habitCheckins.date])
      ..where(habitCheckins.habitId.equals(habitId))
      ..groupBy([habitCheckins.date])
      ..orderBy([
        OrderingTerm(
          expression: habitCheckins.date,
          mode: OrderingMode.asc,
        ),
      ]);
    final rows = await query.get();
    final result = <DateTime>[];
    for (final row in rows) {
      final d = row.read(habitCheckins.date);
      if (d != null) {
        result.add(DateTime(d.year, d.month, d.day));
      }
    }
    return result;
  }

  /// 今日打卡的习惯数量（首页提醒用）
  Future<int> countToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final count = habitCheckins.id.count();
    final query = selectOnly(habitCheckins)
      ..addColumns([count])
      ..where(habitCheckins.date.isBiggerOrEqualValue(start) &
          habitCheckins.date.isSmallerThanValue(end));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countAll() async => habitCheckins.count().getSingle();
}
