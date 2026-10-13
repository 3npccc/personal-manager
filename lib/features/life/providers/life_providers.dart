import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/habit_checkin_dao.dart';
import '../../../core/database/daos/habit_dao.dart';
import '../../../core/database/daos/health_record_dao.dart';
import '../../../core/database/daos/life_memo_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/utils/date_utils.dart';

/// ---------------------------------------------------------------------------
/// 阶段 4.6 生活管理
/// ---------------------------------------------------------------------------
/// 三个 Tab：习惯 / 健康 / 备忘。
///
/// 【数据层现状】阶段 2 已把四个 DAO 建好
/// （`HabitDao` / `HabitCheckinDao` / `HealthRecordDao` / `LifeMemoDao`），
/// 本文件只补业务规则与 provider，**不动 DAO 的既有查询**。
///
/// 【⚠️ drift `Value` 判据（C43，改本文件前必读）】
/// 本文件用到 4 个 Companion，实测签名如下（`database.g.dart`）：
/// | Companion.insert | 可选列（必须 `Value(x)`） | 必填列（必须裸值） |
/// | -- | -- | -- |
/// | `HabitsCompanion` | `id` | `name` / `frequency` / `createdAt` |
/// | `HabitCheckinsCompanion` | `id` / `note` | `habitId` / `date` |
/// | `HealthRecordsCompanion` | `id` / `sleepHours` / `exerciseMinutes` / `weightKg` | `date` |
/// | `LifeMemosCompanion` | `id` / `content` / `remindAt` / `isCompleted` | `title` / `createdAt` |
/// data class `copyWith` 则相反：**必填列裸值、可空列 `Value`**，例如
/// `HabitCheckin.copyWith({int? habitId, DateTime? date, Value note})`、
/// `HealthRecord.copyWith({DateTime? date, Value sleepHours, ...})`、
/// `LifeMemo.copyWith({String? title, String? content, Value remindAt,`
/// `bool? isCompleted, ...})`（`note` / `sleepHours` / `remindAt` 的实参类型
/// 都是 `Value&lt;T&gt;`，此处为避开 doc 注释的 HTML 解析故不写尖括号）。
/// 📌 **不要凭印象** —— 改前先 `Grep` 一遍 `database.g.dart`。

/// 把任意时间归一化到当天 00:00。
///
/// 【为什么必须归一化】打卡按「天」判定（同一天重复打卡算一次）、
/// 连续天数按「天」逐日比对。若 `DateTime` 带时分秒，同一天的两个值在 `==`
/// 下不相等，去重与连续性判断必然出错。
DateTime lifeDay(DateTime value) => DateUtils2.dayOf(value);

/// 今天 00:00
DateTime lifeToday() => lifeDay(DateTime.now());

/// ---------------------------------------------------------------------------
/// 习惯
/// ---------------------------------------------------------------------------

/// 习惯列表（按创建时间倒序）。
final habitListProvider = StreamProvider.autoDispose<List<Habit>>(
  (ref) => ref.watch(habitDaoProvider).watchAll(),
);

/// 单个习惯（编辑表单回填用）。
final habitByIdProvider = FutureProvider.autoDispose.family<Habit?, int>(
  (ref, id) => ref.watch(habitDaoProvider).findById(id),
);

/// 某习惯的全部打卡日期（升序、去重），连续天数由它算出。
///
/// 【为什么用 FutureProvider 而不是 Stream】连续天数需要在「打卡/取消打卡」后
/// 重新计算 —— 直接用 `FutureProvider` + `ref.invalidate` 就够了，
/// 且测试里可以用一次性 `findAll` 类方法（C7）。
final habitCheckinDatesProvider =
    FutureProvider.autoDispose.family<List<DateTime>, int>(
  (ref, habitId) => ref.watch(habitCheckinDaoProvider).checkinDatesOfHabit(
        habitId,
      ),
);

/// 某习惯的连续打卡天数（含今天；今天没打则从昨天起算，见 [computeHabitStreak]）。
final habitStreakProvider = FutureProvider.autoDispose.family<int, int>(
  (ref, habitId) async {
    final dates = await ref.watch(habitCheckinDatesProvider(habitId).future);
    return computeHabitStreak(dates, today: lifeToday());
  },
);

/// 今天已打卡的习惯 id 集合（首页提醒 / 列表勾选态用）。
final todayCheckedHabitIdsProvider =
    FutureProvider.autoDispose<Set<int>>((ref) async {
  final all = await ref.watch(habitDaoProvider).findAll();
  final today = lifeToday();
  final result = <int>{};
  for (final h in all) {
    final hit =
        await ref.watch(habitCheckinDaoProvider).findByHabitAndDate(h.id, today);
    if (hit != null) result.add(h.id);
  }
  return result;
});

/// 今日已打卡的习惯数（首页提醒用）。
final todayCheckedHabitCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(habitCheckinDaoProvider).countToday(),
);

/// 习惯总数
final habitCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(habitDaoProvider).countAll(),
);

/// 计算「连续打卡天数」（纯函数，无状态、易测）。
///
/// 【规则（与阶段 4.5 的 `computeHabitStreak` 同源，勿改）】
/// - `dates` 会被归一化到「天」并**去重**（同一天多条只算 1 天）。
/// - 从 `today` 起往回逐日检查：
///   - 若今天已打卡 → 从今天起算；
///   - 若今天未打卡但**昨天**已打卡 → 从昨天起算（**不清零**，当天还没打不算断签）；
///   - 若昨天也未打卡 → 返回 0（连续性已断）。
/// - 逐日递减，直到某天没有打卡记录为止。
int computeHabitStreak(Iterable<DateTime> dates, {required DateTime today}) {
  final days = <DateTime>{
    for (final d in dates) DateTime(d.year, d.month, d.day),
  };
  if (days.isEmpty) return 0;

  final start = DateTime(today.year, today.month, today.day);
  var cursor = start;

  // 今天没打：若昨天打了就从昨天起算，否则断签
  if (!days.contains(cursor)) {
    final yesterday = DateTime(cursor.year, cursor.month, cursor.day - 1);
    if (!days.contains(yesterday)) return 0;
    cursor = yesterday;
  }

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return streak;
}

/// 习惯频率枚举：每天 / 每周。
enum HabitFrequency {
  daily('daily', '每天'),
  weekly('weekly', '每周');

  const HabitFrequency(this.code, this.label);

  /// 存库用的字符串
  final String code;

  /// 界面展示的中文
  final String label;

  /// 由存库字符串解析；未知值兜底为「每天」。
  static HabitFrequency fromCode(String? code) {
    for (final f in HabitFrequency.values) {
      if (f.code == code) return f;
    }
    return HabitFrequency.daily;
  }
}

/// 习惯写操作集合。
class HabitActions {
  HabitActions(this._ref);

  final Ref _ref;

  HabitDao get _dao => _ref.read(habitDaoProvider);
  HabitCheckinDao get _checkinDao => _ref.read(habitCheckinDaoProvider);

  /// 新增习惯。
  ///
  /// 【校验】名称必填（trim 后非空）。
  Future<int> create({
    required String name,
    HabitFrequency frequency = HabitFrequency.daily,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('习惯名称不能为空');
    }
    return _dao.insertHabit(
      HabitsCompanion.insert(
        // 必填列 → 裸值
        name: trimmed,
        frequency: frequency.code,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 修改习惯（名称 + 频率）。
  ///
  /// 【⚠️ 这里是 data class `Habit.copyWith`】其 4 个字段**全是必填列**
  /// （`int? id` / `String? name` / `String? frequency` / `DateTime? createdAt`）
  /// → **一律传裸值**，不要包 `Value`（C43）。
  Future<bool> update({
    required Habit habit,
    required String name,
    required HabitFrequency frequency,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('习惯名称不能为空');
    }
    return _dao.updateHabit(
      habit.copyWith(name: trimmed, frequency: frequency.code),
    );
  }

  /// 删除习惯。
  ///
  /// 【级联】表定义里 `habit_checkins.habit_id` 是
  /// `references(Habits, #id, onDelete: cascade)` → 打卡记录会一起删。
  Future<int> remove(int id) => _dao.deleteById(id);

  /// 切换「某天」的打卡状态，返回切换后是否已打卡。
  ///
  /// 【业务规则在 DAO】`HabitCheckinDao.toggleCheckin` 已实现
  /// 「未打则插入 / 已打则删除」，且插入时归一化到当天 00:00、保证幂等。
  /// 这里只做透传，不重复实现（避免两处规则分歧）。
  ///
  /// ⚠️ **不要在这里加 `assert`** —— DAO 层已用 `insertCheckin` 的
  /// 「同一天重复打卡直接返回已有 id」做幂等兜底；加断言会与「幂等」矛盾
  /// （第 26 次失误的同型问题）。
  Future<bool> toggleCheckin(int habitId, DateTime day) =>
      _checkinDao.toggleCheckin(habitId, day);

  /// 今日是否已打卡。
  Future<bool> isCheckedOn(int habitId, DateTime day) async {
    final hit = await _checkinDao.findByHabitAndDate(habitId, day);
    return hit != null;
  }
}

final habitActionsProvider = Provider<HabitActions>(HabitActions.new);

/// ---------------------------------------------------------------------------
/// 健康记录
/// ---------------------------------------------------------------------------

/// 健康记录流（按日期倒序）。
final healthRecordListProvider =
    StreamProvider.autoDispose<List<HealthRecord>>(
  (ref) => ref.watch(healthRecordDaoProvider).watchAll(),
);

/// 按日期查健康记录（同一天至多一条）。
final healthRecordByDateProvider =
    FutureProvider.autoDispose.family<HealthRecord?, DateTime>(
  (ref, day) => ref.watch(healthRecordDaoProvider).findByDate(day),
);

/// 健康记录条数（首页 / 概览用）。
final healthRecordCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(healthRecordDaoProvider).countAll(),
);

/// 睡眠时长展示文本（如 `7.5 小时`）；未填返回 `—`。纯函数，易测。
String sleepHoursText(double? hours) {
  if (hours == null) return '—';
  // 去掉无意义的尾随 0：7.0 → 7，7.5 → 7.5
  final s = hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toString();
  return '$s 小时';
}

/// 运动时长展示文本（如 `30 分钟`）；未填返回 `—`。纯函数，易测。
String exerciseText(int? minutes) {
  if (minutes == null) return '—';
  return '$minutes 分钟';
}

/// 体重展示文本（如 `65.5 kg`）；未填返回 `—`。纯函数，易测。
String weightText(double? kg) {
  if (kg == null) return '—';
  final s = kg == kg.roundToDouble() ? kg.round().toString() : kg.toString();
  return '$s kg';
}

/// 健康记录写操作集合。
class HealthActions {
  HealthActions(this._ref);

  final Ref _ref;

  HealthRecordDao get _dao => _ref.read(healthRecordDaoProvider);

  /// 新增 / 覆盖某天的健康记录（同一天只保留一条）。
  ///
  /// 【规则】同一天已有记录则**更新**它，否则新增。
  /// 三个数值都可空（`sleepHours` / `exerciseMinutes` / `weightKg`），
  /// 允许只填其中一项或几项 —— 未填的存 `null`。
  /// 日期归一化到当天 00:00。
  ///
  /// 【⚠️ 不校验数值范围】`sleepHours` / `weightKg` 允许小数；
  /// 负数在物理上无意义，但**不做 assert 拒绝**，
  /// 由表单层（`TextInputType.number` + 非负校验）拦住即可 ——
  /// 与 C26 的「assert 与业务语义别打架」教训一致。
  Future<int> upsert({
    required DateTime date,
    double? sleepHours,
    int? exerciseMinutes,
    double? weightKg,
  }) async {
    final day = lifeDay(date);
    final existing = await _dao.findByDate(day);
    if (existing != null) {
      await _dao.updateRecord(
        existing.copyWith(
          // 【data class copyWith】`date` 是必填列 → 裸值；
          // 三个数值列是可空列 → `Value(x)`（C43）
          date: day,
          sleepHours: Value(sleepHours),
          exerciseMinutes: Value(exerciseMinutes),
          weightKg: Value(weightKg),
        ),
      );
      return existing.id;
    }
    return _dao.insertRecord(
      HealthRecordsCompanion.insert(
        // 【Companion.insert】`date` 必填 → 裸值；
        // 三个数值列有默认值 → `Value(x)`（C43）
        date: day,
        sleepHours: Value(sleepHours),
        exerciseMinutes: Value(exerciseMinutes),
        weightKg: Value(weightKg),
      ),
    );
  }

  Future<int> remove(int id) => _dao.deleteById(id);
}

final healthActionsProvider = Provider<HealthActions>(HealthActions.new);

/// ---------------------------------------------------------------------------
/// 生活备忘
/// ---------------------------------------------------------------------------

/// 备忘列表筛选条件（完成状态）。
///
/// 【为什么是值对象】`memoListProvider` 靠 `ref.watch(memoFilterProvider)`
/// 触发重查 —— 只有整个值对象 `==` 判为变了才重跑。
///
/// 【⚠️ 只有一个字段 → 必须用 `x.hashCode`】
/// `Object.hash` 要求**至少 2 个**位置参数（C33）。
class MemoFilter {
  const MemoFilter({this.isCompleted});

  /// 完成状态筛选；null 表示全部
  final bool? isCompleted;

  bool get isUnfiltered => isCompleted == null;

  MemoFilter copyWith({bool? isCompleted, bool clearCompleted = false}) {
    return MemoFilter(
      isCompleted: clearCompleted ? null : (isCompleted ?? this.isCompleted),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MemoFilter && other.isCompleted == isCompleted;

  // 单字段 → `hashCode`，不能用 `Object.hash`（C33）
  @override
  int get hashCode => isCompleted.hashCode;

  @override
  String toString() => 'MemoFilter(isCompleted: $isCompleted)';
}

class MemoFilterNotifier extends Notifier<MemoFilter> {
  @override
  MemoFilter build() => const MemoFilter();

  void setCompleted(bool? isCompleted) {
    state = isCompleted == null
        ? state.copyWith(clearCompleted: true)
        : state.copyWith(isCompleted: isCompleted);
  }

  void reset() => state = const MemoFilter();
}

final memoFilterProvider = NotifierProvider<MemoFilterNotifier, MemoFilter>(
  MemoFilterNotifier.new,
);

/// 备忘列表流（随筛选自动重查）。
final memoListProvider = StreamProvider.autoDispose<List<LifeMemo>>((ref) {
  final filter = ref.watch(memoFilterProvider);
  return ref.watch(lifeMemoDaoProvider).watchAll(
        isCompleted: filter.isCompleted,
      );
});

/// 未完成的备忘数（首页提醒用）。
final pendingMemoCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(lifeMemoDaoProvider).countPending(),
);

/// 备忘写操作集合。
class MemoActions {
  MemoActions(this._ref);

  final Ref _ref;

  LifeMemoDao get _dao => _ref.read(lifeMemoDaoProvider);

  /// 新增备忘。
  ///
  /// 【校验】标题必填（trim 后非空）。
  /// 【内容】trim 后为空则存空串（表默认值），不存 null。
  Future<int> create({
    required String title,
    String content = '',
    DateTime? remindAt,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('备忘标题不能为空');
    }
    return _dao.insertMemo(
      LifeMemosCompanion.insert(
        // 必填列 → 裸值
        title: trimmed,
        createdAt: DateTime.now(),
        // 有默认值 / 可空列 → Value(x)
        content: Value(content.trim()),
        remindAt: Value(remindAt),
      ),
    );
  }

  /// 修改备忘（标题 + 内容 + 提醒时间）。
  ///
  /// 【⚠️ 这里是 data class `LifeMemo.copyWith`】
  /// `title` / `content` / `isCompleted` 是**必填列 → 裸值**；
  /// `remindAt` 是可空列 → **`Value(x)`**（C43）。
  Future<bool> update({
    required LifeMemo memo,
    required String title,
    required String content,
    DateTime? remindAt,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('备忘标题不能为空');
    }
    return _dao.updateMemo(
      memo.copyWith(
        title: trimmed,
        content: content.trim(),
        remindAt: Value(remindAt),
      ),
    );
  }

  /// 切换完成状态。
  ///
  /// 【业务规则在 DAO】`LifeMemoDao.toggleCompleted` 只写 `is_completed` 一列。
  Future<void> toggleCompleted(int id, bool isCompleted) =>
      _dao.toggleCompleted(id, isCompleted);

  Future<int> remove(int id) => _dao.deleteById(id);
}

final memoActionsProvider = Provider<MemoActions>(MemoActions.new);
