import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/book_dao.dart';
import '../../../core/database/daos/course_dao.dart';
import '../../../core/database/daos/study_checkin_dao.dart';
import '../../../core/database/daos/study_goal_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';

/// ---------------------------------------------------------------------------
/// 通用日期工具
/// ---------------------------------------------------------------------------
/// 【为什么统一归一化到「当天 00:00」】
/// 打卡按「天」统计（是否打卡过、连续多少天、当月几天），若 DateTime 里
/// 带着时分秒，同一天的两次记录在 `==` 下不相等，连续天数计算必然出错。
/// 归一化后「同一天」在 `==` 下必然相等，语义也唯一。

/// 把任意时间归一化到当天 00:00
DateTime dayStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 今天 00:00
DateTime today() => dayStart(DateTime.now());

/// 天加减（[delta] 可为负）
DateTime shiftDay(DateTime day, int delta) =>
    DateTime(day.year, day.month, day.day + delta);

/// 是否同一天
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// ---

/// 把任意时间归一化到所在月的 1 号 00:00
DateTime monthStart(DateTime value) => DateTime(value.year, value.month, 1);

/// 当前月
DateTime currentMonth() => monthStart(DateTime.now());

/// 月份加减（[delta] 可为负）
DateTime shiftMonth(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta, 1);

/// 是否当月
bool isCurrentMonth(DateTime month) {
  final now = DateTime.now();
  return month.year == now.year && month.month == now.month;
}

/// ---------------------------------------------------------------------------
/// 连续打卡天数（纯函数，便于单测）
/// ---------------------------------------------------------------------------

/// 根据「已打卡日期集合」与「参考日」计算**截至参考日的连续打卡天数**。
///
/// 【规则】
/// - 从 [reference]（通常是今天）往前逐日回溯；
/// - 当天打卡了 → 计入，继续看前一天；
/// - 当天**没**打卡但**昨天**打卡了 → 从昨天起算（今天还没打不算断签）；
/// - 当天与昨天都没打卡 → 连续天数为 0。
///
/// 【为什么要「今天没打不算断」】
/// 用户早上打开 App 时今天当然还没打卡，此时应显示"昨天为止连续 N 天"，
/// 而不是突然清零 —— 清零会让用户以为 streak 丢了。
///
/// [dates] 可含时分秒，函数内部自行归一化；无需去重（用 Set 处理）。
int computeStreak(Iterable<DateTime> dates, DateTime reference) {
  if (dates.isEmpty) return 0;
  final days = <DateTime>{for (final d in dates) dayStart(d)};
  final ref = dayStart(reference);

  var cursor = ref;
  if (!days.contains(cursor)) {
    // 今天没打卡：看昨天。昨天也没有 → 0
    cursor = shiftDay(cursor, -1);
    if (!days.contains(cursor)) return 0;
  }

  var count = 0;
  while (days.contains(cursor)) {
    count++;
    cursor = shiftDay(cursor, -1);
  }
  return count;
}

/// ---------------------------------------------------------------------------
/// 读书
/// ---------------------------------------------------------------------------

/// 读书列表筛选条件（状态 + 场景无关，只有状态）。
///
/// 【为什么是值对象】`bookListProvider` 靠 `ref.watch(bookFilterProvider)`
/// 触发重查，只有整个值对象 `==` 判为变了才会重跑，故字段都参与 `==`。
class BookFilter {
  const BookFilter({this.status});

  /// 阅读状态筛选；null 表示全部
  final BookStatus? status;

  bool get isUnfiltered => status == null;

  BookFilter copyWith({BookStatus? status, bool clearStatus = false}) {
    return BookFilter(status: clearStatus ? null : (status ?? this.status));
  }

  @override
  bool operator ==(Object other) =>
      other is BookFilter && other.status == status;

  /// 【⚠️ 单字段不要写 `Object.hash(status)`】
  /// `Object.hash` 要求**至少 2 个**参数（`hash(a, b, [c, ...])`），
  /// 传 1 个会编译错 `not_enough_positional_arguments`。
  /// 本文件里其它值对象都是 2~4 个字段（如 `monthCheckinSummary`
  /// 的 `Object.hash(days, totalMinutes)`），所以一直没暴露这个限制。
  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'BookFilter(status: ${status?.code})';
}

class BookFilterNotifier extends Notifier<BookFilter> {
  @override
  BookFilter build() => const BookFilter();

  /// 设置状态筛选；null = 全部
  void setStatus(BookStatus? status) {
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
  }

  void reset() => state = const BookFilter();
}

final bookFilterProvider = NotifierProvider<BookFilterNotifier, BookFilter>(
  BookFilterNotifier.new,
);

/// 图书列表流（随筛选条件自动重查）
final bookListProvider = StreamProvider.autoDispose<List<Book>>((ref) {
  final filter = ref.watch(bookFilterProvider);
  final dao = ref.watch(bookDaoProvider);
  return dao.watchAll(status: filter.status?.code);
});

/// 单本书（编辑页回填用）
final bookByIdProvider = FutureProvider.autoDispose.family<Book?, int>(
  (ref, id) => ref.watch(bookDaoProvider).findById(id),
);

/// 【⚠️ 为什么不提供 `bookCountByStatusProvider`】
/// 曾经写过 `dao.watchAll(status: x).first.then(...)`。这有致命问题：
/// `testWidgets` 跑在 FakeAsync zone，drift 的 `watch()` **首值必须由
/// `tester.pump` 驱动**才会到达，单纯 `await ... .first` 会**永久挂起**
/// （阶段 4.1 踩过，见 C22 / 复盘规则 7）。
/// 统计各状态数量在当前 UI 里是**从已加载的列表本地数**（`list.where(...).length`），
/// 不需要额外的流查询，所以这里干脆不提供，免留埋雷。

/// 图书总数（一次性查询，无 FakeAsync 陷阱）
final bookCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(bookDaoProvider).countAll(),
);

/// 一本书的阅读进度（0.0~1.0）。
///
/// 【为什么是纯函数而不是 provider】列表项每本书都要算，做成 provider
/// 会产生 N 个 family 实例；纯函数最省，且无状态、易测。
/// 总页数为 0（未填）时返回 0，避免除零。
double bookProgress(Book book) {
  if (book.totalPages <= 0) return 0;
  return (book.currentPage / book.totalPages).clamp(0.0, 1.0).toDouble();
}

/// 读书写操作集合
class BookActions {
  BookActions(this._ref);

  final Ref _ref;

  BookDao get _dao => _ref.read(bookDaoProvider);

  /// 新增一本书，返回新 id。
  ///
  /// 【校验】书名必填（trim 后非空）；页数非负；当前页不得超过总页数
  /// （总页数为 0 表示未填，此时不做上限约束）。
  Future<int> create({
    required String title,
    String? author,
    int currentPage = 0,
    int totalPages = 0,
    BookStatus status = BookStatus.reading,
    int? rating,
    String? note,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('书名不能为空');
    }
    _assertPages(currentPage: currentPage, totalPages: totalPages);
    return _dao.insertBook(
      BooksCompanion.insert(
        title: trimmed,
        author: _optional(author),
        currentPage: Value(currentPage),
        totalPages: Value(totalPages),
        status: status.code,
        rating: Value(_normalizeRating(rating, status)),
        note: _optional(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新整本书
  Future<bool> update({
    required Book book,
    required String title,
    String? author,
    required int currentPage,
    required int totalPages,
    required BookStatus status,
    int? rating,
    String? note,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('书名不能为空');
    }
    _assertPages(currentPage: currentPage, totalPages: totalPages);
    return _dao.updateBook(
      book.copyWith(
        title: trimmed,
        author: _optional(author),
        currentPage: currentPage,
        totalPages: totalPages,
        status: status.code,
        rating: Value(_normalizeRating(rating, status)),
        note: _optional(note),
      ),
    );
  }

  /// 【业务规则】只有「读完」的书才保留评分。
  ///
  /// 未读完时评分没有意义（还在读怎么评分），若保留会在列表上显示
  /// 一个"未读完却有 4 星"的矛盾状态。因此非 finished 一律清空评分。
  int? _normalizeRating(int? rating, BookStatus status) {
    if (status != BookStatus.finished) return null;
    if (rating == null) return null;
    return rating.clamp(1, 5);
  }

  /// 【业务规则】只在「总页数 > 0」时才校验当前页不超过总页数。
  /// 总页数为 0 表示用户还没填，此时当前页可以是任意非负数。
  void _assertPages({required int currentPage, required int totalPages}) {
    assert(currentPage >= 0, '当前页不能为负');
    assert(totalPages >= 0, '总页数不能为负');
    assert(
      totalPages <= 0 || currentPage <= totalPages,
      '当前页不能超过总页数',
    );
  }

  /// 只更新阅读进度（列表页快捷「+1 页」用）
  Future<bool> updateProgress({required Book book, required int currentPage}) {
    _assertPages(currentPage: currentPage, totalPages: book.totalPages);
    return _dao.updateBook(book.copyWith(currentPage: currentPage));
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  Value<String?> _optional(String? text) {
    final trimmed = text?.trim();
    return Value((trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }
}

final bookActionsProvider = Provider<BookActions>(BookActions.new);

/// ---------------------------------------------------------------------------
/// 课程
/// ---------------------------------------------------------------------------

/// 课程状态筛选值对象
class CourseFilter {
  const CourseFilter({this.status});

  final ProgressStatus? status;

  bool get isUnfiltered => status == null;

  CourseFilter copyWith({ProgressStatus? status, bool clearStatus = false}) {
    return CourseFilter(
      status: clearStatus ? null : (status ?? this.status),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CourseFilter && other.status == status;

  /// 单字段 → 用 `status.hashCode`（`Object.hash` 至少要 2 个参数，
  /// 见 `BookFilter.hashCode` 处的说明）。
  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'CourseFilter(status: ${status?.code})';
}

class CourseFilterNotifier extends Notifier<CourseFilter> {
  @override
  CourseFilter build() => const CourseFilter();

  void setStatus(ProgressStatus? status) {
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
  }

  void reset() => state = const CourseFilter();
}

final courseFilterProvider =
    NotifierProvider<CourseFilterNotifier, CourseFilter>(
  CourseFilterNotifier.new,
);

/// 课程列表流
final courseListProvider = StreamProvider.autoDispose<List<Course>>((ref) {
  final filter = ref.watch(courseFilterProvider);
  final dao = ref.watch(courseDaoProvider);
  return dao.watchAll(status: filter.status?.code);
});

/// 单门课程
final courseByIdProvider = FutureProvider.autoDispose.family<Course?, int>(
  (ref, id) => ref.watch(courseDaoProvider).findById(id),
);

/// 课程总数
final courseCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(courseDaoProvider).countAll(),
);

/// 一门课程的完成进度（0.0~1.0）。总章节为 0 时返回 0（避免除零）。
double courseProgress(Course course) {
  if (course.totalChapters <= 0) return 0;
  return (course.completedChapters / course.totalChapters)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// 课程写操作集合
class CourseActions {
  CourseActions(this._ref);

  final Ref _ref;

  CourseDao get _dao => _ref.read(courseDaoProvider);

  Future<int> create({
    required String name,
    String? platform,
    int totalChapters = 0,
    int completedChapters = 0,
    DateTime? startDate,
    DateTime? dueDate,
    ProgressStatus status = ProgressStatus.ongoing,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('课程名不能为空');
    }
    _assertChapters(
      completed: completedChapters,
      total: totalChapters,
    );
    return _dao.insertCourse(
      CoursesCompanion.insert(
        name: trimmed,
        platform: _optional(platform),
        totalChapters: Value(totalChapters),
        completedChapters: Value(completedChapters),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        status: _normalizeStatus(totalChapters, completedChapters, status),
      ),
    );
  }

  Future<bool> update({
    required Course course,
    required String name,
    String? platform,
    required int totalChapters,
    required int completedChapters,
    DateTime? startDate,
    DateTime? dueDate,
    required ProgressStatus status,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('课程名不能为空');
    }
    _assertChapters(completed: completedChapters, total: totalChapters);
    return _dao.updateCourse(
      course.copyWith(
        name: trimmed,
        platform: _optional(platform),
        totalChapters: totalChapters,
        completedChapters: completedChapters,
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        status: _normalizeStatus(totalChapters, completedChapters, status),
      ),
    );
  }

  /// 更新已完成章节数（DAO 内部会在全部完成时自动置为 completed）。
  ///
  /// 【为什么这里也要校验】DAO 的 `updateProgress` 直接写库，
  /// 若传入超过总章节的数会存进一个非法状态。这里先拦。
  Future<void> updateProgress({
    required Course course,
    required int completedChapters,
  }) async {
    assert(completedChapters >= 0, '已完成章节不能为负');
    assert(
      course.totalChapters <= 0 || completedChapters <= course.totalChapters,
      '已完成章节不能超过总章节',
    );
    await _dao.updateProgress(course.id, completedChapters);
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  /// 【业务规则】总章节 > 0 且已完成 >= 总章节 → 强制 completed。
  /// 用户手动选了 ongoing 也不能让"100% 却进行中"的矛盾状态入库。
  String _normalizeStatus(int total, int completed, ProgressStatus status) {
    if (total > 0 && completed >= total) return ProgressStatus.completed.code;
    return status.code;
  }

  void _assertChapters({required int completed, required int total}) {
    assert(completed >= 0, '已完成章节不能为负');
    assert(total >= 0, '总章节不能为负');
    assert(total <= 0 || completed <= total, '已完成章节不能超过总章节');
  }

  Value<String?> _optional(String? text) {
    final trimmed = text?.trim();
    return Value((trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }
}

final courseActionsProvider = Provider<CourseActions>(CourseActions.new);

/// ---------------------------------------------------------------------------
/// 学习打卡
/// ---------------------------------------------------------------------------

/// 当前查看的月份（打卡页日历用）
class CheckinMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => currentMonth();

  void setMonth(DateTime month) => state = monthStart(month);

  void previousMonth() => state = shiftMonth(state, -1);

  void nextMonth() => state = shiftMonth(state, 1);

  void reset() => state = currentMonth();
}

final checkinMonthProvider =
    NotifierProvider<CheckinMonthNotifier, DateTime>(
  CheckinMonthNotifier.new,
);

/// 当前月份内的打卡记录（日历打点用）
final checkinMonthListProvider =
    StreamProvider.autoDispose<List<StudyCheckin>>((ref) {
  final month = ref.watch(checkinMonthProvider);
  final dao = ref.watch(studyCheckinDaoProvider);
  return dao.watchMonth(month);
});

/// 全部打卡记录（列表用，按日期倒序）
final checkinListProvider =
    StreamProvider.autoDispose<List<StudyCheckin>>((ref) {
  return ref.watch(studyCheckinDaoProvider).watchAll();
});

/// 连续打卡天数。以「全部打卡日期」为输入，参考日 = 今天。
final checkinStreakProvider = FutureProvider.autoDispose<int>((ref) async {
  final dates = await ref.watch(studyCheckinDaoProvider).allCheckinDates();
  return computeStreak(dates, today());
});

/// 今天是否已打卡
final checkinTodayProvider = FutureProvider.autoDispose<bool>((ref) async {
  final record = await ref.watch(studyCheckinDaoProvider).findByDate(today());
  return record != null;
});

/// 当月打卡天数 + 当月总时长（分钟）的聚合
class MonthCheckinSummary {
  const MonthCheckinSummary({
    required this.days,
    required this.totalMinutes,
  });

  /// 打卡天数（去重后的天数）
  final int days;

  /// 总学习时长（分钟）
  final int totalMinutes;

  @override
  bool operator ==(Object other) =>
      other is MonthCheckinSummary &&
      other.days == days &&
      other.totalMinutes == totalMinutes;

  @override
  int get hashCode => Object.hash(days, totalMinutes);

  @override
  String toString() =>
      'MonthCheckinSummary(days: $days, totalMinutes: $totalMinutes)';
}

/// 当月打卡聚合（天数 + 总时长）。
///
/// 【为什么复用一个 stream 做两种聚合】`watchMonth` 已经按月份过滤，
/// 再额外查一次 `totalMinutesOfMonth` 会多开一个订阅且时序不同步。
/// 直接从同一份记录里聚合，天数与时长必然一致。
final monthCheckinSummaryProvider =
    StreamProvider.autoDispose<MonthCheckinSummary>((ref) {
  final month = ref.watch(checkinMonthProvider);
  final dao = ref.watch(studyCheckinDaoProvider);
  return dao.watchMonth(month).map((list) {
    final dayKeys = <DateTime>{for (final r in list) dayStart(r.date)};
    var minutes = 0;
    for (final r in list) {
      minutes += r.minutes;
    }
    return MonthCheckinSummary(days: dayKeys.length, totalMinutes: minutes);
  });
});

/// 打卡写操作集合
class StudyCheckinActions {
  StudyCheckinActions(this._ref);

  final Ref _ref;

  StudyCheckinDao get _dao => _ref.read(studyCheckinDaoProvider);

  /// 新增一条打卡。
  ///
  /// 【校验】时长非负。内容可空（有些用户只想要"打过卡"的记录）。
  Future<int> create({
    DateTime? date,
    String content = '',
    int minutes = 0,
    bool goalMet = false,
  }) {
    assert(minutes >= 0, '学习时长不能为负');
    final day = dayStart(date ?? DateTime.now());
    return _dao.insertCheckin(
      StudyCheckinsCompanion.insert(
        date: day,
        content: Value(content.trim()),
        minutes: Value(minutes),
        goalMet: Value(goalMet),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新一条打卡
  Future<bool> update({
    required StudyCheckin entry,
    DateTime? date,
    String content = '',
    int minutes = 0,
    bool goalMet = false,
  }) {
    assert(minutes >= 0, '学习时长不能为负');
    return _dao.updateCheckin(
      entry.copyWith(
        date: dayStart(date ?? entry.date),
        content: content.trim(),
        minutes: minutes,
        goalMet: goalMet,
      ),
    );
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  /// 今天是否已打卡（一次性查询）
  Future<bool> hasCheckedInToday() async {
    return await _dao.findByDate(today()) != null;
  }

  /// 连续打卡天数（一次性查询）
  Future<int> streak() async {
    return computeStreak(await _dao.allCheckinDates(), today());
  }
}

final studyCheckinActionsProvider =
    Provider<StudyCheckinActions>(StudyCheckinActions.new);

/// ---------------------------------------------------------------------------
/// 学习目标
/// ---------------------------------------------------------------------------

/// 目标筛选条件（完成状态 + 类型）
class StudyGoalFilter {
  const StudyGoalFilter({this.isCompleted, this.type});

  /// 完成状态筛选；null 表示全部
  final bool? isCompleted;

  /// 类型筛选；null 表示全部类型
  final StudyGoalType? type;

  bool get isUnfiltered => isCompleted == null && type == null;

  StudyGoalFilter copyWith({
    bool? isCompleted,
    StudyGoalType? type,
    bool clearCompleted = false,
    bool clearType = false,
  }) {
    return StudyGoalFilter(
      isCompleted: clearCompleted ? null : (isCompleted ?? this.isCompleted),
      type: clearType ? null : (type ?? this.type),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StudyGoalFilter &&
      other.isCompleted == isCompleted &&
      other.type == type;

  @override
  int get hashCode => Object.hash(isCompleted, type);

  @override
  String toString() =>
      'StudyGoalFilter(isCompleted: $isCompleted, type: ${type?.code})';
}

class StudyGoalFilterNotifier extends Notifier<StudyGoalFilter> {
  @override
  StudyGoalFilter build() => const StudyGoalFilter();

  void setCompleted(bool? isCompleted) {
    state = isCompleted == null
        ? state.copyWith(clearCompleted: true)
        : state.copyWith(isCompleted: isCompleted);
  }

  void setType(StudyGoalType? type) {
    state = type == null
        ? state.copyWith(clearType: true)
        : state.copyWith(type: type);
  }

  void reset() => state = const StudyGoalFilter();
}

final studyGoalFilterProvider =
    NotifierProvider<StudyGoalFilterNotifier, StudyGoalFilter>(
  StudyGoalFilterNotifier.new,
);

/// 学习目标列表流。
///
/// 【为什么在 provider 里按 type 过滤】DAO 的 `watchAll` 只支持
/// `isCompleted` 过滤，类型过滤放在这里做，避免改 DAO 影响已有测试。
final studyGoalListProvider = StreamProvider.autoDispose<List<StudyGoal>>((ref) {
  final filter = ref.watch(studyGoalFilterProvider);
  final dao = ref.watch(studyGoalDaoProvider);
  return dao.watchAll(isCompleted: filter.isCompleted).map((list) {
    final type = filter.type;
    if (type == null) return list;
    return list.where((g) => g.type == type.code).toList();
  });
});

/// 单条目标
final studyGoalByIdProvider =
    FutureProvider.autoDispose.family<StudyGoal?, int>(
  (ref, id) => ref.watch(studyGoalDaoProvider).findById(id),
);

/// 未完成目标数（概览用）
final pendingStudyGoalCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(studyGoalDaoProvider).countPending(),
);

/// 目标总数
final studyGoalCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(studyGoalDaoProvider).countAll(),
);

/// 目标是否已逾期（有截止日期、未完成、截止日早于今天）
bool isGoalOverdue(StudyGoal goal, DateTime reference) {
  if (goal.isCompleted) return false;
  final due = goal.dueDate;
  if (due == null) return false;
  return dayStart(due).isBefore(dayStart(reference));
}

/// 学习目标写操作集合
class StudyGoalActions {
  StudyGoalActions(this._ref);

  final Ref _ref;

  StudyGoalDao get _dao => _ref.read(studyGoalDaoProvider);

  Future<int> create({
    required String name,
    StudyGoalType type = StudyGoalType.other,
    DateTime? dueDate,
    bool isCompleted = false,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('目标名不能为空');
    }
    return _dao.insertGoal(
      StudyGoalsCompanion.insert(
        name: trimmed,
        type: type.code,
        dueDate: Value(dueDate),
        isCompleted: Value(isCompleted),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<bool> update({
    required StudyGoal goal,
    required String name,
    required StudyGoalType type,
    DateTime? dueDate,
    required bool isCompleted,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('目标名不能为空');
    }
    return _dao.updateGoal(
      goal.copyWith(
        name: trimmed,
        type: type.code,
        dueDate: Value(dueDate),
        isCompleted: isCompleted,
      ),
    );
  }

  Future<void> toggleCompleted({required int id, required bool isCompleted}) {
    return _dao.toggleCompleted(id, isCompleted);
  }

  Future<int> remove(int id) => _dao.deleteById(id);
}

final studyGoalActionsProvider =
    Provider<StudyGoalActions>(StudyGoalActions.new);
