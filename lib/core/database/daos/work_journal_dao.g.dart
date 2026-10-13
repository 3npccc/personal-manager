// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_journal_dao.dart';

// ignore_for_file: type=lint
mixin _$WorkJournalDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProjectsTable get projects => attachedDatabase.projects;
  $WorkJournalsTable get workJournals => attachedDatabase.workJournals;
  WorkJournalDaoManager get managers => WorkJournalDaoManager(this);
}

class WorkJournalDaoManager {
  final _$WorkJournalDaoMixin _db;
  WorkJournalDaoManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db.attachedDatabase, _db.projects);
  $$WorkJournalsTableTableManager get workJournals =>
      $$WorkJournalsTableTableManager(_db.attachedDatabase, _db.workJournals);
}
