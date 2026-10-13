// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'study_goal_dao.dart';

// ignore_for_file: type=lint
mixin _$StudyGoalDaoMixin on DatabaseAccessor<AppDatabase> {
  $StudyGoalsTable get studyGoals => attachedDatabase.studyGoals;
  StudyGoalDaoManager get managers => StudyGoalDaoManager(this);
}

class StudyGoalDaoManager {
  final _$StudyGoalDaoMixin _db;
  StudyGoalDaoManager(this._db);
  $$StudyGoalsTableTableManager get studyGoals =>
      $$StudyGoalsTableTableManager(_db.attachedDatabase, _db.studyGoals);
}
