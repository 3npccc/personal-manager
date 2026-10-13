// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_record_dao.dart';

// ignore_for_file: type=lint
mixin _$HealthRecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $HealthRecordsTable get healthRecords => attachedDatabase.healthRecords;
  HealthRecordDaoManager get managers => HealthRecordDaoManager(this);
}

class HealthRecordDaoManager {
  final _$HealthRecordDaoMixin _db;
  HealthRecordDaoManager(this._db);
  $$HealthRecordsTableTableManager get healthRecords =>
      $$HealthRecordsTableTableManager(_db.attachedDatabase, _db.healthRecords);
}
