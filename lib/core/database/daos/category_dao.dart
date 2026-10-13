import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'category_dao.g.dart';

/// 分类数据访问对象。
/// 注意：isReferenced 需要查询 ledger_records，故必须在此显式声明该表，
/// drift 不会自动纳入仅被引用的表。
@DriftAccessor(tables: [Categories, LedgerRecords])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// 监听分类，可按类型筛选，按 sortOrder 排序
  Stream<List<Category>> watchAll({String? type}) {
    final query = select(categories);
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
    ]);
    return query.watch();
  }

  Future<List<Category>> findAll({String? type}) {
    final query = select(categories);
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
    ]);
    return query.get();
  }

  Future<Category?> findById(int id) {
    return (select(categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<bool> updateCategory(Category entry) {
    return update(categories).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(categories)..where((t) => t.id.equals(id))).go();
  }

  /// 该分类是否已被记账记录引用
  Future<bool> isReferenced(int categoryId) async {
    final count = ledgerRecords.id.count();
    final query = selectOnly(ledgerRecords)
      ..addColumns([count])
      ..where(ledgerRecords.categoryId.equals(categoryId));
    final row = await query.getSingle();
    return (row.read(count) ?? 0) > 0;
  }
  /// 批量插入（用于初始化内置分类，幂等：仅当无数据时插入）
  Future<void> ensureBuiltInCategories() async {
    final existing = await categories.count().getSingle();
    if (existing > 0) return;

    const incomeNames = ['工资', '奖金', '理财', '其他收入'];
    const expenseNames = ['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '学习', '其他支出'];

    await batch((b) {
      b.insertAll(
        categories,
        [
          for (var i = 0; i < incomeNames.length; i++)
            CategoriesCompanion.insert(
              type: 'income',
              name: incomeNames[i],
              isCustom: const Value(false),
              sortOrder: Value(i),
            ),
        ],
      );
      b.insertAll(
        categories,
        [
          for (var i = 0; i < expenseNames.length; i++)
            CategoriesCompanion.insert(
              type: 'expense',
              name: expenseNames[i],
              isCustom: const Value(false),
              sortOrder: Value(i),
            ),
        ],
      );
    });
  }
}
