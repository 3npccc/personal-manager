import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'book_dao.g.dart';

/// 读书笔记数据访问对象
@DriftAccessor(tables: [Books])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  BookDao(super.db);

  Stream<List<Book>> watchAll({String? status}) {
    final query = select(books);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<Book?> findById(int id) {
    return (select(books)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 一次性查询（测试用）。
  ///
  /// 【为什么需要它】drift 的 `watch()` 首值在 `testWidgets` 的 FakeAsync
  /// zone 里**必须由 `tester.pump` 驱动时钟**才会到达；测试里直接
  /// `await watchAll().first` 会**永久挂起**（阶段 4.1 踩过）。
  /// 断言"库里有什么"用一次性查询即可。
  Future<List<Book>> findAll({String? status}) {
    final query = select(books);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<int> insertBook(BooksCompanion entry) {
    return into(books).insert(entry);
  }

  Future<bool> updateBook(Book entry) {
    return update(books).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(books)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countAll() async => books.count().getSingle();
}
