// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_dao.dart';

// ignore_for_file: type=lint
mixin _$CourseDaoMixin on DatabaseAccessor<AppDatabase> {
  $CoursesTable get courses => attachedDatabase.courses;
  CourseDaoManager get managers => CourseDaoManager(this);
}

class CourseDaoManager {
  final _$CourseDaoMixin _db;
  CourseDaoManager(this._db);
  $$CoursesTableTableManager get courses =>
      $$CoursesTableTableManager(_db.attachedDatabase, _db.courses);
}
