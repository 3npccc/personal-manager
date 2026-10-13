import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'ledger_dao.g.dart';

/// 记账数据访问对象
@DriftAccessor(tables: [LedgerRecords, Categories])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(super.db);

  /// 监听记录，可按月份 / 类型 / 分类筛选，按日期倒序
  Stream<List<LedgerRecord>> watchAll({
    DateTime? month,
    String? type,
    int? categoryId,
  }) {
    final query = select(ledgerRecords);
    if (month != null) {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      query.where((t) =>
          t.recordDate.isBiggerOrEqualValue(start) &
          t.recordDate.isSmallerThanValue(end));
    }
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.recordDate, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// 一次性查询全部（排序同 [watchAll]）。
  ///
  /// 【为什么需要它】在 `testWidgets`（FakeAsync zone）里做断言时应当用它 ——
  /// `watchAll().first` 的首值需要 `tester.pump` 驱动时钟才会到达，
  /// 测试体里没有 pump 就会**永久挂起**（10 分钟后被测试级超时杀掉）。
  /// `findAll` 走 `get()`，microtask 即可完成，不依赖时钟。
  Future<List<LedgerRecord>> findAll({
    DateTime? month,
    String? type,
    int? categoryId,
  }) {
    final query = select(ledgerRecords);
    if (month != null) {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      query.where((t) =>
          t.recordDate.isBiggerOrEqualValue(start) &
          t.recordDate.isSmallerThanValue(end));
    }
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.recordDate, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<LedgerRecord?> findById(int id) {
    return (select(ledgerRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertRecord(LedgerRecordsCompanion entry) {
    return into(ledgerRecords).insert(entry);
  }

  Future<bool> updateRecord(LedgerRecord entry) {
    return update(ledgerRecords).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(ledgerRecords)..where((t) => t.id.equals(id))).go();
  }

  /// 月度统计：收入合计、支出合计、结余（单位：分）
  Future<LedgerSummary> summaryOfMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final query = selectOnly(ledgerRecords)
      ..addColumns([ledgerRecords.amountCents.sum(), ledgerRecords.type])
      ..where(ledgerRecords.recordDate
              .isBiggerOrEqualValue(start) &
          ledgerRecords.recordDate.isSmallerThanValue(end))
      ..groupBy([ledgerRecords.type]);

    final rows = await query.get();
    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final sum = row.read(ledgerRecords.amountCents.sum()) ?? 0;
      switch (row.read(ledgerRecords.type)) {
        case 'income':
          income = sum;
        case 'expense':
          expense = sum;
      }
    }
    return LedgerSummary(
      incomeCents: income,
      expenseCents: expense,
      balanceCents: income - expense,
    );
  }

  /// 按月统计每日支出（用于图表或列表分组）
  Future<List<DailyAmount>> dailyExpenseOfMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final query = selectOnly(ledgerRecords)
      ..addColumns([ledgerRecords.amountCents.sum(), ledgerRecords.recordDate])
      ..where(ledgerRecords.recordDate
              .isBiggerOrEqualValue(start) &
          ledgerRecords.recordDate.isSmallerThanValue(end) &
          ledgerRecords.type.equals('expense'))
      ..groupBy([ledgerRecords.recordDate])
      ..orderBy([
        OrderingTerm(
          expression: ledgerRecords.recordDate,
          mode: OrderingMode.asc,
        ),
      ]);

    final rows = await query.get();
    return [
      for (final row in rows)
        DailyAmount(
          date: row.read(ledgerRecords.recordDate)!,
          amountCents: row.read(ledgerRecords.amountCents.sum()) ?? 0,
        ),
    ];
  }

  Future<int> countAll() async {
    return ledgerRecords.count().getSingle();
  }
}

/// 月度收支统计结果
class LedgerSummary {
  const LedgerSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceCents,
  });

  final int incomeCents;
  final int expenseCents;
  final int balanceCents;
}

/// 单日金额
class DailyAmount {
  const DailyAmount({required this.date, required this.amountCents});

  final DateTime date;
  final int amountCents;
}
