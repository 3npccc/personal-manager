import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/category_dao.dart';
import '../../../core/database/daos/ledger_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';

/// ---------------------------------------------------------------------------
/// 月份工具
/// ---------------------------------------------------------------------------
/// 【为什么月份只保留「年 + 月」】
/// 本项目所有月度查询（`summaryOfMonth` / `dailyExpenseOfMonth`）都只读
/// `year` 与 `month`。把 DateTime 归一化到当月 1 号 00:00，
/// 可以让「同一个月」在 `==` 下必然相等 —— provider 的 `watch` 才有意义
/// （含日/时/分的 DateTime 每次 now 都不同，会导致 stream 无限重建）。

/// 把任意时间归一化到所在月的 1 号 00:00
DateTime monthStart(DateTime value) => DateTime(value.year, value.month, 1);

/// 当前月
DateTime currentMonth() => monthStart(DateTime.now());

/// 月份加减（[delta] 可为负）
DateTime shiftMonth(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta, 1);

/// 是否当月（用户本地时区）
bool isCurrentMonth(DateTime month) {
  final now = DateTime.now();
  return month.year == now.year && month.month == now.month;
}

/// ---------------------------------------------------------------------------
/// 筛选条件
/// ---------------------------------------------------------------------------

/// 记账列表的筛选条件。
///
/// 【为什么是值对象而不是几个独立的 StateProvider】
/// `ledgerListProvider` 靠 `ref.watch(ledgerFilterProvider)` 触发重查。
/// 只有整个值对象 `==` 判定为「变了」时 watch 才会重跑，
/// 因此每个字段都必须参与 `==` / `hashCode`。
class LedgerFilter {
  /// 【ignore 注释的位置很讲究】lint 报的位置是 `}) : _month = month;`
  /// 这一行（不是 `const LedgerFilter({` 那一行），而 `// ignore:` 必须
  /// 紧邻被忽略的代码行 —— 挂在构造函数声明上方**不生效**。
  /// 这里作为**行尾注释**贴在目标行末尾，是唯一可靠的位置。
  const LedgerFilter({
    DateTime? month,
    this.type,
    this.categoryId,
  }) : _month = month; // ignore: prefer_initializing_formals

  final DateTime? _month;

  /// 类型筛选；null 表示全部
  final LedgerType? type;

  /// 分类筛选；null 表示全部分类
  final int? categoryId;

  /// 生效月份。未显式设置时取「当前月」。
  ///
  /// 【为什么用 getter 延迟求值】
  /// 若在构造函数里写 `month ?? currentMonth()`，`const LedgerFilter()`
  /// 就不成立了，且构造时刻被冻结。用 getter 保证每次读取都是最新月份，
  /// 同时 `==` 里两端都走同一个 getter，比较仍然稳定。
  DateTime get month => monthStart(_month ?? DateTime.now());

  /// 是否处于「无筛选」（仅看月份，不含类型/分类筛选）
  bool get isUnfiltered => type == null && categoryId == null;

  LedgerFilter copyWith({
    DateTime? month,
    LedgerType? type,
    int? categoryId,
    bool clearMonth = false,
    bool clearType = false,
    bool clearCategory = false,
  }) {
    return LedgerFilter(
      month: clearMonth ? null : monthStart(month ?? this.month),
      type: clearType ? null : (type ?? this.type),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    );
  }

  /// 切到上一个月 / 下一个月（同时保留类型与分类筛选）
  LedgerFilter previousMonth() => copyWith(month: shiftMonth(month, -1));

  LedgerFilter nextMonth() => copyWith(month: shiftMonth(month, 1));

  @override
  bool operator ==(Object other) =>
      other is LedgerFilter &&
      other.month == month &&
      other.type == type &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(month, type, categoryId);

  @override
  String toString() =>
      'LedgerFilter(month: ${month.year}-${month.month}, '
      'type: ${type?.code}, categoryId: $categoryId)';
}

/// 筛选条件（可读写）
class LedgerFilterNotifier extends Notifier<LedgerFilter> {
  @override
  LedgerFilter build() => LedgerFilter(month: currentMonth());

  /// 设置月份（会归一化到当月 1 号）
  void setMonth(DateTime month) {
    state = state.copyWith(month: monthStart(month));
  }

  void previousMonth() => state = state.previousMonth();

  void nextMonth() => state = state.nextMonth();

  /// 回到当前月
  void resetMonth() => setMonth(currentMonth());

  /// 设置类型筛选；null = 全部。
  ///
  /// 【联动】类型变化时清掉分类筛选 —— 分类是按类型划分的
  /// （income 分类不可能出现在 expense 记录上），不清会得到空列表。
  void setType(LedgerType? type) {
    state = type == null
        ? state.copyWith(clearType: true, clearCategory: true)
        : state.copyWith(type: type, clearCategory: true);
  }

  /// 设置分类筛选；null = 全部分类
  void setCategory(int? categoryId) {
    state = categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId);
  }

  /// 清空类型与分类筛选，保留月份
  void resetFilters() {
    state = LedgerFilter(month: state.month);
  }

  /// 全部重置（含月份回到当前月）
  void reset() => state = LedgerFilter(month: currentMonth());
}

final ledgerFilterProvider =
    NotifierProvider<LedgerFilterNotifier, LedgerFilter>(
  LedgerFilterNotifier.new,
);

/// ---------------------------------------------------------------------------
/// 列表 / 统计
/// ---------------------------------------------------------------------------

/// 记账列表流（随筛选条件自动重查）。
/// 数据库写入后 drift 自动推送新结果，页面无需手动刷新。
final ledgerListProvider = StreamProvider.autoDispose<List<LedgerRecord>>((ref) {
  final filter = ref.watch(ledgerFilterProvider);
  final dao = ref.watch(ledgerDaoProvider);
  return dao.watchAll(
    month: filter.month,
    type: filter.type?.code,
    categoryId: filter.categoryId,
  );
});

/// 当前月份的收入 / 支出 / 结余统计（单位：分）。
///
/// 【为什么用 StreamProvider 而不是 FutureProvider】
/// 新增 / 删除一笔账后统计卡片必须立刻跟着变。若用 FutureProvider，
/// 需要手动 `ref.invalidate` 才刷新，容易漏。这里复用 drift 的
/// `watchAll` 流自行聚合，保证「写库 → 自动重算」。
final monthlySummaryProvider =
    StreamProvider.autoDispose<LedgerSummary>((ref) {
  final month = ref.watch(ledgerFilterProvider).month;
  final dao = ref.watch(ledgerDaoProvider);
  return dao.watchAll(month: month).map((records) {
    var income = 0;
    var expense = 0;
    for (final r in records) {
      switch (r.type) {
        case 'income':
          income += r.amountCents;
        case 'expense':
          expense += r.amountCents;
      }
    }
    return LedgerSummary(
      incomeCents: income,
      expenseCents: expense,
      balanceCents: income - expense,
    );
  });
});

/// 单条记录（编辑页回填用）。id 不存在时返回 null。
final ledgerRecordByIdProvider =
    FutureProvider.autoDispose.family<LedgerRecord?, int>((ref, id) async {
  return ref.watch(ledgerDaoProvider).findById(id);
});

/// ---------------------------------------------------------------------------
/// 分类
/// ---------------------------------------------------------------------------

/// 分类列表流；不传 [type] 返回全部。
final categoryListProvider =
    StreamProvider.autoDispose.family<List<Category>, String?>((ref, type) {
  return ref.watch(categoryDaoProvider).watchAll(type: type);
});

/// 仅某类型的分类（表单里的下拉选项用）
final categoriesOfTypeProvider =
    StreamProvider.autoDispose.family<List<Category>, LedgerType>((ref, type) {
  return ref.watch(categoryDaoProvider).watchAll(type: type.code);
});

/// 分类写操作集合。
///
/// 【关键业务规则】被记账记录引用的分类禁止删除 —— 见 [remove]。
class CategoryActions {
  CategoryActions(this._ref);

  final Ref _ref;

  CategoryDao get _dao => _ref.read(categoryDaoProvider);

  /// 该分类是否已被记账记录引用
  Future<bool> isReferenced(int categoryId) => _dao.isReferenced(categoryId);

  /// 新增自定义分类，返回新 id。
  ///
  /// 【重名校验】同名分类在**同一类型下**不允许重复 ——
  /// 下拉里出现两个「餐饮」会让用户无法分辨。跨类型同名是允许的。
  Future<int> create({
    required LedgerType type,
    required String name,
  }) async {
    final trimmed = name.trim();
    final siblings = await _dao.findAll(type: type.code);
    if (siblings.any((c) => c.name == trimmed)) {
      throw ArgumentError('该类型下已存在分类「$trimmed」');
    }
    final maxOrder = siblings.isEmpty
        ? -1
        : siblings.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    return _dao.insertCategory(
      CategoriesCompanion.insert(
        type: type.code,
        name: trimmed,
        isCustom: const Value(true),
        sortOrder: Value(maxOrder + 1),
      ),
    );
  }

  /// 重命名分类（只改名字，不动 sortOrder / isCustom）
  Future<bool> rename({required Category category, required String name}) {
    return _dao.updateCategory(category.copyWith(name: name.trim()));
  }

  /// 删除分类。
  ///
  /// 返回 false 表示「被记录引用，拒绝删除」——调用方据此提示用户。
  /// 【为什么在应用层先查 isReferenced】
  /// 表上虽然有 `onDelete: KeyAction.restrict` 兜底，但外键违规抛的是
  /// 底层 `SqliteException`，语义不清晰且错误文案对用户不可读。
  /// 这里先显式查询，给出明确结果，外键约束仅作为最后一道防线。
  Future<bool> remove(int categoryId) async {
    if (await _dao.isReferenced(categoryId)) return false;
    await _dao.deleteById(categoryId);
    return true;
  }
}

final categoryActionsProvider =
    Provider<CategoryActions>(CategoryActions.new);

/// ---------------------------------------------------------------------------
/// 记账写操作
/// ---------------------------------------------------------------------------

/// 记账写操作集合。UI 只依赖这一个入口，不直接 read DAO。
/// 写操作完成后无需手动刷新 —— drift 的 stream 会推送。
class LedgerActions {
  LedgerActions(this._ref);

  final Ref _ref;

  LedgerDao get _dao => _ref.read(ledgerDaoProvider);

  /// 新增一条收支记录，返回新 id。
  ///
  /// 【金额铁律】[amountCents] 必须是**正整数**（分）。
  /// 负数用 `type` 表达（income / expense），不能靠符号区分 ——
  /// 否则统计求和时正负混在一起，无法拆分收入与支出。
  Future<int> create({
    required LedgerType type,
    required int amountCents,
    required int categoryId,
    required DateTime recordDate,
    Scene? scene,
    String? note,
  }) {
    _assertAmount(amountCents);
    return _dao.insertRecord(
      LedgerRecordsCompanion.insert(
        type: type.code,
        amountCents: amountCents,
        categoryId: categoryId,
        recordDate: recordDate,
        scene: Value(scene?.code),
        note: _normalizeNote(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新一条记录（整条替换）。
  Future<bool> update({
    required LedgerRecord record,
    required LedgerType type,
    required int amountCents,
    required int categoryId,
    required DateTime recordDate,
    Scene? scene,
    String? note,
  }) {
    _assertAmount(amountCents);
    return _dao.updateRecord(
      record.copyWith(
        type: type.code,
        amountCents: amountCents,
        categoryId: categoryId,
        recordDate: recordDate,
        scene: Value(scene?.code),
        note: _normalizeNote(note),
      ),
    );
  }

  /// 删除
  Future<int> remove(int id) => _dao.deleteById(id);

  /// 当月统计（一次性查询，供概览页等使用）
  Future<LedgerSummary> summaryOfMonth(DateTime month) =>
      _dao.summaryOfMonth(month);

  void _assertAmount(int amountCents) {
    assert(amountCents > 0, '金额必须为正整数分（用 type 区分收入/支出）');
  }

  Value<String?> _normalizeNote(String? note) {
    final trimmed = note?.trim();
    return Value(
      (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
  }
}

final ledgerActionsProvider = Provider<LedgerActions>(LedgerActions.new);

/// 记录总数（概览页用）
final ledgerCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(ledgerDaoProvider).countAll();
});
