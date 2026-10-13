// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'study_checkin_dao.dart';

// ignore_for_file: type=lint
mixin _$StudyCheckinDaoMixin on DatabaseAccessor<AppDatabase> {
  $StudyCheckinsTable get studyCheckins => attachedDatabase.studyCheckins;
  StudyCheckinDaoManager get managers => StudyCheckinDaoManager(this);
}

class StudyCheckinDaoManager {
  final _$StudyCheckinDaoMixin _db;
  StudyCheckinDaoManager(this._db);
  $$StudyCheckinsTableTableManager get studyCheckins =>
      $$StudyCheckinsTableTableManager(_db.attachedDatabase, _db.studyCheckins);
}
