import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'note_dao.g.dart';

/// 笔记数据访问对象
@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  /// 监听笔记列表，可按场景筛选、按关键字搜索（标题或正文）、按更新时间倒序
  Stream<List<Note>> watchAll({String? scene, String? keyword}) {
    final query = select(notes);
    if (scene != null) {
      query.where((t) => t.scene.equals(scene));
    }
    final kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) {
      query.where((t) => t.title.like('%$kw%') | t.content.like('%$kw%'));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<Note?> findById(int id) {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 一次性查询全部（排序同 [watchAll]）。
  ///
  /// 与 [watchAll] 的区别：这是**一次性 Future**，不建立 stream 订阅。
  /// 在 `testWidgets`（FakeAsync zone）里做断言时应当用它 ——
  /// `watchAll().first` 的首值要经过「订阅 → fetchAndEmitData → await 查询
  /// → listener.add」一串 await，**需要 tester.pump 驱动时钟**才会到达；
  /// 测试体里没有 pump 去推它，会永久挂起。
  Future<List<Note>> findAll({String? scene, String? keyword}) {
    final query = select(notes);
    if (scene != null) {
      query.where((t) => t.scene.equals(scene));
    }
    final kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) {
      query.where((t) => t.title.like('%$kw%') | t.content.like('%$kw%'));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<int> insertNote(NotesCompanion entry) {
    return into(notes).insert(entry);
  }

  Future<bool> updateNote(Note entry) {
    return update(notes).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(notes)..where((t) => t.id.equals(id))).go();
  }

  /// 按场景统计笔记数量
  Future<Map<String, int>> countByScene() async {
    final count = notes.id.count();
    final query = selectOnly(notes)
      ..addColumns([notes.scene, count])
      ..groupBy([notes.scene]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(notes.scene)!: row.read(count) ?? 0,
    };
  }

  Future<int> countAll() async {
    final count = notes.id.count();
    final query = selectOnly(notes)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
