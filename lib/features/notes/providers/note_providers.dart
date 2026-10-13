import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/note_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';

/// 笔记列表的筛选条件。
///
/// 用不可变值对象 + [copyWith] 表达，便于做「重置筛选」等操作。
///
/// 【为什么 keyword 也放进这个值对象，而不是单独一个 StateProvider】
/// `noteListProvider` 靠 `ref.watch(noteFilterProvider)` 触发重查。
/// 只有当 filter 发生变化（`==` 判定为不同）时 watch 才会重跑。
/// 因此 keyword 必须参与 `==` / `hashCode`，改关键字才能真正触发重查。
///
/// 【为什么搜索是"提交式"而不是逐字符实时】
/// 逐字符搜索会让每次按键都重建一条 drift stream（旧流被取消、新流建立），
/// 在弱机器上会造成明显卡顿与闪烁。这里让 UI 在"提交"（回车 / 点搜索）
/// 时才 `setKeyword`，把 stream 重建收敛到明确的用户动作上。
class NoteFilter {
  const NoteFilter({
    this.scene,
    this.keyword,
  });

  /// 场景筛选；null 表示全部
  final Scene? scene;

  /// 关键字（标题或正文包含）；null / 空白表示不搜索
  final String? keyword;

  /// 是否处于「无筛选」状态
  bool get isUnfiltered => scene == null && (keyword?.trim().isEmpty ?? true);

  /// 归一化后的关键字（去首尾空白；空白则视为 null）
  String? get normalizedKeyword {
    final kw = keyword?.trim();
    return (kw == null || kw.isEmpty) ? null : kw;
  }

  NoteFilter copyWith({
    Scene? scene,
    String? keyword,
    bool clearScene = false,
    bool clearKeyword = false,
  }) {
    return NoteFilter(
      scene: clearScene ? null : (scene ?? this.scene),
      keyword: clearKeyword ? null : (keyword ?? this.keyword),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteFilter &&
      other.scene == scene &&
      other.normalizedKeyword == normalizedKeyword;

  @override
  int get hashCode => Object.hash(scene, normalizedKeyword);

  @override
  String toString() =>
      'NoteFilter(scene: ${scene?.code}, keyword: $normalizedKeyword)';
}

/// 筛选条件（可读写）
class NoteFilterNotifier extends Notifier<NoteFilter> {
  @override
  NoteFilter build() => const NoteFilter();

  void setScene(Scene? scene) {
    state = scene == null
        ? state.copyWith(clearScene: true)
        : state.copyWith(scene: scene);
  }

  /// 设置搜索关键字。传 null / 空白表示清空搜索。
  void setKeyword(String? keyword) {
    final kw = keyword?.trim();
    state = (kw == null || kw.isEmpty)
        ? state.copyWith(clearKeyword: true)
        : state.copyWith(keyword: kw);
  }

  void reset() => state = const NoteFilter();
}

final noteFilterProvider = NotifierProvider<NoteFilterNotifier, NoteFilter>(
  NoteFilterNotifier.new,
);

/// 笔记列表流（随筛选条件自动重查）。
///
/// 数据库写入后 drift 会自动推送新结果，因此页面无需手动刷新。
final noteListProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final filter = ref.watch(noteFilterProvider);
  final dao = ref.watch(noteDaoProvider);
  return dao.watchAll(
    scene: filter.scene?.code,
    keyword: filter.normalizedKeyword,
  );
});

/// 单条笔记（用于编辑页回填）。
/// 传 null 表示"新增"场景，返回 null。
final noteByIdProvider =
    FutureProvider.autoDispose.family<Note?, int>((ref, id) async {
  return ref.watch(noteDaoProvider).findById(id);
});

/// 笔记写操作集合。
///
/// 单独抽出来是为了让 UI 只依赖这一个入口，避免页面到处 read DAO。
/// 写操作完成后不需要手动刷新 —— drift 的 stream 会自动推送。
class NoteActions {
  NoteActions(this._ref);

  final Ref _ref;

  NoteDao get _dao => _ref.read(noteDaoProvider);

  /// 新增，返回新 id。
  ///
  /// 【关键】`createdAt` 与 `updatedAt` 同时置为 now ——
  /// 列表按 `updatedAt DESC` 排序，新建的笔记必须处在最前。
  Future<int> create({
    required String title,
    String content = '',
    Scene scene = Scene.life,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    return _dao.insertNote(
      NotesCompanion.insert(
        title: title.trim(),
        content: Value(content.trim()),
        scene: scene.code,
        createdAt: ts,
        updatedAt: ts,
      ),
    );
  }

  /// 更新一条笔记。
  ///
  /// 【关键】必须刷新 `updatedAt`，否则列表排序不会把这条挪到前面
  /// （drift 的 stream 会推送新值，但排序键没变 → 位置不动，用户以为没生效）。
  Future<bool> update({
    required Note note,
    required String title,
    required String content,
    required Scene scene,
    DateTime? now,
  }) {
    return _dao.updateNote(
      note.copyWith(
        title: title.trim(),
        content: content.trim(),
        scene: scene.code,
        updatedAt: now ?? DateTime.now(),
      ),
    );
  }

  /// 删除
  Future<int> remove(int id) => _dao.deleteById(id);
}

final noteActionsProvider = Provider<NoteActions>(NoteActions.new);

/// 各场景笔记数量统计（概览页用）
final noteCountBySceneProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
  return ref.watch(noteDaoProvider).countByScene();
});

/// 笔记总数（概览页用）
final noteCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(noteDaoProvider).countAll();
});
