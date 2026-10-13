// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'life_memo_dao.dart';

// ignore_for_file: type=lint
mixin _$LifeMemoDaoMixin on DatabaseAccessor<AppDatabase> {
  $LifeMemosTable get lifeMemos => attachedDatabase.lifeMemos;
  LifeMemoDaoManager get managers => LifeMemoDaoManager(this);
}

class LifeMemoDaoManager {
  final _$LifeMemoDaoMixin _db;
  LifeMemoDaoManager(this._db);
  $$LifeMemosTableTableManager get lifeMemos =>
      $$LifeMemosTableTableManager(_db.attachedDatabase, _db.lifeMemos);
}
