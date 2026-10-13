import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'habit_dao.g.dart';

/// 习惯数据访问对象
@DriftAccessor(tables: [Habits])
class HabitDao extends DatabaseAccessor<AppDatabase> with _$HabitDaoMixin {
  HabitDao(super.db);

  Stream<List<Habit>> watchAll() {
    final query = select(habits)
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<List<Habit>> findAll() => select(habits).get();

  Future<Habit?> findById(int id) {
    return (select(habits)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertHabit(HabitsCompanion entry) {
    return into(habits).insert(entry);
  }

  Future<bool> updateHabit(Habit entry) {
    return update(habits).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(habits)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countAll() async => habits.count().getSingle();
}
