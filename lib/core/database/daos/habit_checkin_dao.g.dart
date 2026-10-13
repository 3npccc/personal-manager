// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit_checkin_dao.dart';

// ignore_for_file: type=lint
mixin _$HabitCheckinDaoMixin on DatabaseAccessor<AppDatabase> {
  $HabitsTable get habits => attachedDatabase.habits;
  $HabitCheckinsTable get habitCheckins => attachedDatabase.habitCheckins;
  HabitCheckinDaoManager get managers => HabitCheckinDaoManager(this);
}

class HabitCheckinDaoManager {
  final _$HabitCheckinDaoMixin _db;
  HabitCheckinDaoManager(this._db);
  $$HabitsTableTableManager get habits =>
      $$HabitsTableTableManager(_db.attachedDatabase, _db.habits);
  $$HabitCheckinsTableTableManager get habitCheckins =>
      $$HabitCheckinsTableTableManager(_db.attachedDatabase, _db.habitCheckins);
}
