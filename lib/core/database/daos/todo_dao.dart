import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'todo_dao.g.dart';

/// 待办数据访问对象
@DriftAccessor(tables: [Todos])
class TodoDao extends DatabaseAccessor<AppDatabase> with _$TodoDaoMixin {
  TodoDao(super.db);

  /// 监听全部待办，可按场景 / 完成状态筛选，按「未完成优先 + 截止时间 + 优先级」排序
  Stream<List<Todo>> watchAll({
    String? scene,
    bool? isCompleted,
  }) {
    final query = select(todos);
    if (scene != null) {
      query.where((t) => t.scene.equals(scene));
    }
    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([
      // 未完成排前面
      (t) => OrderingTerm(expression: t.isCompleted, mode: OrderingMode.asc),
      // 有截止时间的排前面，且越近越靠前
      (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      // 优先级高的排前面
      (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// 查询单条
  Future<Todo?> findById(int id) {
    return (select(todos)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 一次性查询全部（可按场景 / 完成状态筛选，排序同 [watchAll]）。
  ///
  /// 与 [watchAll] 的区别：这是**一次性 Future**，不建立 stream 订阅。
  /// 在 `testWidgets`（FakeAsync zone）里做断言时应当用它 ——
  /// `watchAll().first` 的首值要经过「订阅 → fetchAndEmitData → await 查询
  /// → listener.add」一串 await，**需要 tester.pump 驱动时钟**才会到达；
  /// 测试体里没有 pump 去推它，会永久挂起。
  Future<List<Todo>> findAll({String? scene, bool? isCompleted}) {
    final query = select(todos);
    if (scene != null) {
      query.where((t) => t.scene.equals(scene));
    }
    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.isCompleted, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  /// 新增，返回新记录 id
  Future<int> insertTodo(TodosCompanion entry) {
    return into(todos).insert(entry);
  }

  /// 更新
  Future<bool> updateTodo(Todo entry) {
    return update(todos).replace(entry);
  }

  /// 删除
  Future<int> deleteById(int id) {
    return (delete(todos)..where((t) => t.id.equals(id))).go();
  }

  /// 勾选 / 取消完成，同时维护 completedAt
  Future<void> toggleCompleted(int id, bool isCompleted) async {
    await (update(todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(
        isCompleted: Value(isCompleted),
        completedAt: Value(isCompleted ? DateTime.now() : null),
      ),
    );
  }

  /// 统计：指定范围内完成的待办数量
  Future<int> countCompletedBetween(DateTime start, DateTime end) async {
    final count = todos.id.count();
    final query = selectOnly(todos)
      ..addColumns([count])
      ..where(todos.isCompleted.equals(true) &
          todos.completedAt.isBiggerOrEqualValue(start) &
          todos.completedAt.isSmallerThanValue(end));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// 统计：按场景统计未完成待办数量
  Future<int> countPendingByScene(String scene) async {
    final count = todos.id.count();
    final query = selectOnly(todos)
      ..addColumns([count])
      ..where(todos.scene.equals(scene) & todos.isCompleted.equals(false));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// 今日待办（截止日期在今日内，或今日创建且未完成）
  Stream<List<Todo>> watchToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final query = select(todos)
      ..where((t) =>
          t.isCompleted.equals(false) &
          (t.dueDate.isNull() |
              (t.dueDate.isBiggerOrEqualValue(startOfDay) &
                  t.dueDate.isSmallerThanValue(endOfDay))))
      ..orderBy([
        (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      ]);
    return query.watch();
  }

  /// 全部待办总数
  Future<int> countAll() async {
    final count = todos.id.count();
    final query = selectOnly(todos)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
