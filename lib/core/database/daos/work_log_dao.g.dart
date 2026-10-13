// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_log_dao.dart';

// ignore_for_file: type=lint
mixin _$WorkLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProjectsTable get projects => attachedDatabase.projects;
  $WorkLogsTable get workLogs => attachedDatabase.workLogs;
  WorkLogDaoManager get managers => WorkLogDaoManager(this);
}

class WorkLogDaoManager {
  final _$WorkLogDaoMixin _db;
  WorkLogDaoManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db.attachedDatabase, _db.projects);
  $$WorkLogsTableTableManager get workLogs =>
      $$WorkLogsTableTableManager(_db.attachedDatabase, _db.workLogs);
}
