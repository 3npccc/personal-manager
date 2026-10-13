import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/todo_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';

/// 待办列表的筛选条件。
///
/// 用不可变值对象 + [copyWith] 表达，便于将来做「重置筛选」等操作。
class TodoFilter {
  const TodoFilter({
    this.scene,
    this.isCompleted,
  });

  /// 场景筛选；null 表示全部
  final Scene? scene;

  /// 完成状态筛选；null 表示全部
  final bool? isCompleted;

  /// 是否处于「无筛选」状态
  bool get isUnfiltered => scene == null && isCompleted == null;

  TodoFilter copyWith({
    Scene? scene,
    bool? isCompleted,
    bool clearScene = false,
    bool clearCompleted = false,
  }) {
    return TodoFilter(
      scene: clearScene ? null : (scene ?? this.scene),
      isCompleted: clearCompleted ? null : (isCompleted ?? this.isCompleted),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoFilter &&
      other.scene == scene &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode => Object.hash(scene, isCompleted);

  @override
  String toString() =>
      'TodoFilter(scene: ${scene?.code}, isCompleted: $isCompleted)';
}

/// 筛选条件（可读写）
class TodoFilterNotifier extends Notifier<TodoFilter> {
  @override
  TodoFilter build() => const TodoFilter();

  void setScene(Scene? scene) {
    state = scene == null
        ? state.copyWith(clearScene: true)
        : state.copyWith(scene: scene);
  }

  void setCompleted(bool? isCompleted) {
    state = isCompleted == null
        ? state.copyWith(clearCompleted: true)
        : state.copyWith(isCompleted: isCompleted);
  }

  void reset() => state = const TodoFilter();
}

final todoFilterProvider = NotifierProvider<TodoFilterNotifier, TodoFilter>(
  TodoFilterNotifier.new,
);

/// 待办列表流（随筛选条件自动重查）。
///
/// 数据库写入后 drift 会自动推送新结果，因此页面无需手动刷新。
final todoListProvider = StreamProvider.autoDispose<List<Todo>>((ref) {
  final filter = ref.watch(todoFilterProvider);
  final dao = ref.watch(todoDaoProvider);
  return dao.watchAll(
    scene: filter.scene?.code,
    isCompleted: filter.isCompleted,
  );
});

/// 单条待办（用于编辑页回填）。
/// 传 null 表示"新增"场景，返回 null。
final todoByIdProvider =
    FutureProvider.autoDispose.family<Todo?, int>((ref, id) async {
  return ref.watch(todoDaoProvider).findById(id);
});

/// 待办写操作集合。
///
/// 单独抽出来是为了让 UI 只依赖这一个入口，避免页面到处 read DAO。
/// 写操作完成后不需要手动刷新 —— drift 的 stream 会自动推送。
class TodoActions {
  TodoActions(this._ref);

  final Ref _ref;

  TodoDao get _dao => _ref.read(todoDaoProvider);

  /// 新增，返回新 id
  Future<int> create({
    required String title,
    required Scene scene,
    TodoPriority priority = TodoPriority.medium,
    String? description,
    DateTime? dueDate,
  }) {
    return _dao.insertTodo(
      TodosCompanion.insert(
        title: title.trim(),
        scene: scene.code,
        priority: Value(priority.value),
        description: Value(
          (description == null || description.trim().isEmpty)
              ? null
              : description.trim(),
        ),
        dueDate: Value(dueDate),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新（整条替换）
  Future<bool> update(Todo todo) => _dao.updateTodo(todo);

  /// 勾选 / 取消完成（同时维护完成时间）
  Future<void> toggle(int id, bool isCompleted) =>
      _dao.toggleCompleted(id, isCompleted);

  /// 删除
  Future<int> remove(int id) => _dao.deleteById(id);
}

final todoActionsProvider = Provider<TodoActions>(TodoActions.new);

/// 某场景下的未完成数量（筛选栏角标用）
final pendingCountProvider =
    FutureProvider.autoDispose.family<int, Scene>((ref, scene) {
  return ref.watch(todoDaoProvider).countPendingByScene(scene.code);
});
