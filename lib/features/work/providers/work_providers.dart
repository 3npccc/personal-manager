import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/project_dao.dart';
import '../../../core/database/daos/work_journal_dao.dart';
import '../../../core/database/daos/work_log_dao.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/format_utils.dart';

/// ---------------------------------------------------------------------------
/// 阶段 4.5 工作管理
/// ---------------------------------------------------------------------------
/// 四个 Tab：项目 / 工时 / 周报 / 日志。
///
/// 【数据层现状】阶段 2 已把三个 DAO 建好（`ProjectDao` / `WorkLogDao` /
/// `WorkJournalDao`），本文件只补业务规则与 provider，**不动 DAO 的既有查询**。
/// 唯一例外见 [WorkLogDao] 的 `summaryByProject` —— 已在阶段 2 就绪，直接用。
///
/// 【为什么日期统一归一化】工时按「天」统计、周报按「周一~下周一」聚合，
/// 若 DateTime 带时分秒，同一天两个值在 `==` 下不相等，聚合必然错。
/// 这里统一用 `DateUtils2.dayOf`（项目已有的公共工具），不重复造。

/// 把任意时间归一化到当天 00:00
DateTime workDay(DateTime value) => DateUtils2.dayOf(value);

/// 今天 00:00
DateTime workToday() => workDay(DateTime.now());

/// ---------------------------------------------------------------------------
/// 项目
/// ---------------------------------------------------------------------------

/// 项目列表筛选条件（状态 + 优先级）。
///
/// 【为什么是值对象】`projectListProvider` 靠 `ref.watch(projectFilterProvider)`
/// 触发重查 —— 只有整个值对象 `==` 判为变了才重跑，故字段都参与 `==`。
///
/// 【⚠️ 两个字段 → 可以用 `Object.hash`】`Object.hash` 要求**至少 2 个**
/// 位置参数（C33）。本类恰好两个字段，安全；若将来删到只剩一个，
/// 必须改成 `x.hashCode`。
class ProjectFilter {
  const ProjectFilter({this.status, this.priority});

  /// 项目状态筛选；null 表示全部
  final ProgressStatus? status;

  /// 优先级筛选（0 低 / 1 中 / 2 高）；null 表示全部
  final int? priority;

  bool get isUnfiltered => status == null && priority == null;

  ProjectFilter copyWith({
    ProgressStatus? status,
    int? priority,
    bool clearStatus = false,
    bool clearPriority = false,
  }) {
    return ProjectFilter(
      status: clearStatus ? null : (status ?? this.status),
      priority: clearPriority ? null : (priority ?? this.priority),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectFilter &&
      other.status == status &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(status, priority);

  @override
  String toString() =>
      'ProjectFilter(status: ${status?.code}, priority: $priority)';
}

class ProjectFilterNotifier extends Notifier<ProjectFilter> {
  @override
  ProjectFilter build() => const ProjectFilter();

  void setStatus(ProgressStatus? status) {
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
  }

  void setPriority(int? priority) {
    state = priority == null
        ? state.copyWith(clearPriority: true)
        : state.copyWith(priority: priority);
  }

  void reset() => state = const ProjectFilter();
}

final projectFilterProvider =
    NotifierProvider<ProjectFilterNotifier, ProjectFilter>(
  ProjectFilterNotifier.new,
);

/// 项目列表流（随筛选自动重查）。
///
/// 【为什么优先级筛选在内存里做】`ProjectDao.watchAll` 只支持按 `status`
/// 过滤（阶段 2 定的接口）。为优先级再开一个 DAO 方法属于改数据层，
/// 且优先级过滤是"在已加载列表上挑子集"，数据量小，内存过滤足够。
/// **不去改 DAO**，避免影响已验收的 4.1~4.4 及阶段 2 的测试。
final projectListProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final filter = ref.watch(projectFilterProvider);
  final dao = ref.watch(projectDaoProvider);
  return dao.watchAll(status: filter.status?.code).map((list) {
    final p = filter.priority;
    if (p == null) return list;
    return list.where((x) => x.priority == p).toList();
  });
});

/// 单个项目（编辑页回填 / 工时页下拉用）
final projectByIdProvider = FutureProvider.autoDispose.family<Project?, int>(
  (ref, id) => ref.watch(projectDaoProvider).findById(id),
);

/// 项目总数
final projectCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(projectDaoProvider).countAll(),
);

/// 进行中的项目数（首页提醒用）
final ongoingProjectCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(projectDaoProvider).countOngoing(),
);

/// 项目进度（0.0~1.0）。纯函数，无状态、易测。
double projectProgress(Project project) =>
    (project.progress / 100).clamp(0.0, 1.0).toDouble();

/// 项目写操作集合
class ProjectActions {
  ProjectActions(this._ref);

  final Ref _ref;

  ProjectDao get _dao => _ref.read(projectDaoProvider);

  /// 新增项目。
  ///
  /// 【校验】名称必填（trim 后非空）；截止日期不得早于开始日期（都填了才校验）。
  /// 【⚠️ 进度/优先级越界是「clamp」而不是「拒绝」】与 DAO 层
  /// `ProjectDao.updateProgress`（`progress.clamp(0, 100)`）语义保持一致；
  /// `database_test.dart` 的「进度超界被裁剪到 0-100」也验证了这个约定。
  /// **不要在这里加 `assert(progress >= 0 && ...)`** —— 那会与紧随其后的
  /// `clamp` 自相矛盾（第 3 轮验证实测：传 500 时 assert 先炸，
  /// 测试「进度越界被 clamp 到 0~100」直接失败）。
  Future<int> create({
    required String name,
    ProgressStatus status = ProgressStatus.ongoing,
    int progress = 0,
    int priority = 1,
    DateTime? startDate,
    DateTime? dueDate,
    String? note,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('项目名称不能为空');
    }
    _assertDates(startDate: startDate, dueDate: dueDate);
    return _dao.insertProject(
      ProjectsCompanion.insert(
        name: trimmed,
        status: status.code,
        progress: Value(progress.clamp(0, 100)),
        priority: Value(priority.clamp(0, 2)),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        note: _optional(note),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新整个项目
  Future<bool> update({
    required Project project,
    required String name,
    required ProgressStatus status,
    required int progress,
    required int priority,
    DateTime? startDate,
    DateTime? dueDate,
    String? note,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('项目名称不能为空');
    }
    _assertDates(startDate: startDate, dueDate: dueDate);
    return _dao.updateProject(
      project.copyWith(
        name: trimmed,
        status: status.code,
        progress: progress.clamp(0, 100),
        priority: priority.clamp(0, 2),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        note: Value(_plain(note)),
      ),
    );
  }

  /// 只更新进度（列表页拖动条用）。
  ///
  /// 【业务规则在 DAO】`ProjectDao.updateProgress` 已实现：
  /// ① 进度 `clamp(0, 100)`；② 到 100% 自动置 completed。
  /// 这里只做参数透传，不重复实现，避免两处规则分歧。
  /// ⚠️ **不要在这里加 `assert`** —— DAO 层是 clamp 语义（见 `create` 的注释）。
  Future<void> updateProgress({required int id, required int progress}) {
    return _dao.updateProgress(id, progress);
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  /// 【业务规则】起止日期只允许"截止 ≥ 开始"。只填一个时不校验。
  void _assertDates({DateTime? startDate, DateTime? dueDate}) {
    if (startDate == null || dueDate == null) return;
    assert(
      !dueDate.isBefore(startDate),
      '截止日期不能早于开始日期',
    );
  }

  Value<String?> _optional(String? text) {
    final trimmed = text?.trim();
    return Value((trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }

  /// 更新时用：空串归一化成 null（表里 note 可空，空串没意义）
  String? _plain(String? text) {
    final trimmed = text?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

final projectActionsProvider = Provider<ProjectActions>(ProjectActions.new);

/// ---------------------------------------------------------------------------
/// 工时记录
/// ---------------------------------------------------------------------------

/// 工时列表筛选条件（项目 + 日期范围）。
class WorkLogFilter {
  const WorkLogFilter({this.projectId, this.start, this.end});

  /// 项目筛选；null 表示全部项目
  final int? projectId;

  /// 起始日期（含）；null 表示不限
  final DateTime? start;

  /// 结束日期（不含）；null 表示不限
  final DateTime? end;

  bool get isUnfiltered => projectId == null && start == null && end == null;

  WorkLogFilter copyWith({
    int? projectId,
    DateTime? start,
    DateTime? end,
    bool clearProject = false,
    bool clearRange = false,
  }) {
    return WorkLogFilter(
      projectId: clearProject ? null : (projectId ?? this.projectId),
      start: clearRange ? null : (start ?? this.start),
      end: clearRange ? null : (end ?? this.end),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkLogFilter &&
      other.projectId == projectId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(projectId, start, end);

  @override
  String toString() =>
      'WorkLogFilter(projectId: $projectId, start: $start, end: $end)';
}

class WorkLogFilterNotifier extends Notifier<WorkLogFilter> {
  @override
  WorkLogFilter build() => const WorkLogFilter();

  void setProject(int? projectId) {
    state = projectId == null
        ? state.copyWith(clearProject: true)
        : state.copyWith(projectId: projectId);
  }

  /// 设置日期范围（[start] 含、[end] 不含）。两者都传 null 表示清空。
  void setRange({DateTime? start, DateTime? end}) {
    if (start == null && end == null) {
      state = state.copyWith(clearRange: true);
      return;
    }
    state = WorkLogFilter(
      projectId: state.projectId,
      start: start == null ? null : workDay(start),
      end: end == null ? null : workDay(end),
    );
  }

  void reset() => state = const WorkLogFilter();
}

final workLogFilterProvider =
    NotifierProvider<WorkLogFilterNotifier, WorkLogFilter>(
  WorkLogFilterNotifier.new,
);

/// 工时列表流（随筛选自动重查）
final workLogListProvider = StreamProvider.autoDispose<List<WorkLog>>((ref) {
  final filter = ref.watch(workLogFilterProvider);
  final dao = ref.watch(workLogDaoProvider);
  return dao.watchAll(
    projectId: filter.projectId,
    start: filter.start,
    end: filter.end,
  );
});

/// 单条工时记录
final workLogByIdProvider = FutureProvider.autoDispose.family<WorkLog?, int>(
  (ref, id) => ref.watch(workLogDaoProvider).findById(id),
);

/// 工时记录总数
final workLogCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(workLogDaoProvider).countAll(),
);

/// 按项目分组的工时合计（工时 Tab 顶部统计条用，基于当前筛选）。
///
/// 【为什么从同一个 stream 聚合】`workLogListProvider` 已按筛选过滤，
/// 再额外查一次 DAO 会多开订阅且时序不同步。直接复用同一份数据，
/// 与 4.4 `monthCheckinSummaryProvider` 同构。
final workLogGroupedProvider =
    StreamProvider.autoDispose<List<WorkLogGroup>>((ref) {
  final logs = ref.watch(workLogListProvider);
  final projects = ref.watch(projectListProvider);

  // 两个流任一未就绪就等（AsyncValue 组合，避免"半份数据"）
  if (logs.isLoading || projects.isLoading) {
    return const Stream<List<WorkLogGroup>>.empty();
  }

  final nameMap = {
    for (final p in projects.value ?? const <Project>[]) p.id: p.name,
  };
  final list = logs.value ?? const <WorkLog>[];

  final totals = <int, int>{};
  final counts = <int, int>{};
  for (final log in list) {
    totals[log.projectId] = (totals[log.projectId] ?? 0) + log.minutes;
    counts[log.projectId] = (counts[log.projectId] ?? 0) + 1;
  }

  final groups = <WorkLogGroup>[
    for (final entry in totals.entries)
      WorkLogGroup(
        projectId: entry.key,
        projectName: nameMap[entry.key] ?? '（已删除项目）',
        totalMinutes: entry.value,
        logCount: counts[entry.key] ?? 0,
      ),
  ]..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));

  return Stream<List<WorkLogGroup>>.value(groups);
});

/// 单组工时汇总（项目 + 合计分钟 + 条数）
class WorkLogGroup {
  const WorkLogGroup({
    required this.projectId,
    required this.projectName,
    required this.totalMinutes,
    required this.logCount,
  });

  final int projectId;
  final String projectName;
  final int totalMinutes;
  final int logCount;

  /// 人类可读时长，如「1小时30分」
  String get durationText => FormatUtils.minutes(totalMinutes);

  @override
  bool operator ==(Object other) =>
      other is WorkLogGroup &&
      other.projectId == projectId &&
      other.projectName == projectName &&
      other.totalMinutes == totalMinutes &&
      other.logCount == logCount;

  @override
  int get hashCode =>
      Object.hash(projectId, projectName, totalMinutes, logCount);

  @override
  String toString() =>
      'WorkLogGroup($projectName, $totalMinutes min, $logCount logs)';
}

/// 工时写操作集合
class WorkLogActions {
  WorkLogActions(this._ref);

  final Ref _ref;

  WorkLogDao get _dao => _ref.read(workLogDaoProvider);

  /// 新增工时记录。
  ///
  /// 【校验】项目必填（外键）；时长必须 > 0（0 分钟的记录没有意义）；
  /// 日期归一化到当天。
  Future<int> create({
    required int projectId,
    DateTime? date,
    required int minutes,
    String summary = '',
  }) {
    assert(minutes > 0, '工时必须大于 0 分钟');
    final day = workDay(date ?? DateTime.now());
    return _dao.insertLog(
      WorkLogsCompanion.insert(
        projectId: projectId,
        date: day,
        minutes: minutes,
        summary: Value(summary.trim()),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新一条工时记录
  Future<bool> update({
    required WorkLog entry,
    required int projectId,
    DateTime? date,
    required int minutes,
    String summary = '',
  }) {
    assert(minutes > 0, '工时必须大于 0 分钟');
    return _dao.updateLog(
      entry.copyWith(
        projectId: projectId,
        date: workDay(date ?? entry.date),
        minutes: minutes,
        summary: summary.trim(),
      ),
    );
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  /// 指定范围内按项目聚合（周报用，直接透传 DAO 的阶段 2 实现）
  Future<List<ProjectWorkSummary>> summaryBetween(
    DateTime start,
    DateTime end,
  ) =>
      _dao.summaryByProject(start, end);

  /// 某项目累计工时（分钟）
  Future<int> totalMinutesOfProject(int projectId) =>
      _dao.totalMinutesOfProject(projectId);
}

final workLogActionsProvider = Provider<WorkLogActions>(WorkLogActions.new);

/// ---------------------------------------------------------------------------
/// 周报
/// ---------------------------------------------------------------------------

/// 周报时间范围（含起始日、不含结束日）。
///
/// 【为什么只有两个日期而不是"第几周"】用户可能想看"上周""本月""自定义"，
/// 统一收敛成 `[start, end)` 区间，生成逻辑就只需处理一种输入。
class ReportRange {
  const ReportRange({required this.start, required this.end});

  /// 起始日（含）
  final DateTime start;

  /// 结束日（不含）
  final DateTime end;

  /// 本周（周一 00:00 ~ 下周一 00:00）
  factory ReportRange.thisWeek({DateTime? today}) {
    final r = DateUtils2.thisWeek(today: today);
    return ReportRange(start: r.start, end: r.end);
  }

  /// 上周
  factory ReportRange.lastWeek({DateTime? today}) {
    final base = DateUtils2.dayOf(today ?? DateTime.now());
    final thisStart = base.subtract(Duration(days: base.weekday - 1));
    final lastStart = thisStart.subtract(const Duration(days: 7));
    return ReportRange(
      start: lastStart,
      end: lastStart.add(const Duration(days: 7)),
    );
  }

  /// 本月（1 号 ~ 下月 1 号）
  factory ReportRange.thisMonth({DateTime? today}) {
    final r = DateUtils2.thisMonth(today: today);
    return ReportRange(start: r.start, end: r.end);
  }

  /// 天数（end 不含，故为 end-start）
  int get days => end.difference(start).inDays;

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ReportRange($start ~ $end)';
}

/// 当前选中的周报范围（周报页用）
class ReportRangeNotifier extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.thisWeek();

  void set(ReportRange range) => state = range;

  void thisWeek() => state = ReportRange.thisWeek();

  void lastWeek() => state = ReportRange.lastWeek();

  void thisMonth() => state = ReportRange.thisMonth();

  /// 自定义（起止都归一化到当天）
  void setCustom({required DateTime start, required DateTime end}) {
    final s = workDay(start);
    // 用户选的"结束日"含当天 → 内部区间右开，故 +1 天
    final e = workDay(end).add(const Duration(days: 1));
    state = ReportRange(start: s, end: e);
  }
}

final reportRangeProvider =
    NotifierProvider<ReportRangeNotifier, ReportRange>(
  ReportRangeNotifier.new,
);

/// 周报数据：范围内按项目分组 + 明细 + 总工时。
class WeeklyReportData {
  const WeeklyReportData({
    required this.range,
    required this.groups,
    required this.logs,
    required this.totalMinutes,
  });

  final ReportRange range;

  /// 按项目分组的合计（按工时降序）
  final List<ProjectWorkSummary> groups;

  /// 范围内的明细（按日期升序）
  final List<WorkLog> logs;

  /// 总工时（分钟）
  final int totalMinutes;

  bool get isEmpty => logs.isEmpty;

  @override
  String toString() =>
      'WeeklyReportData(${groups.length} projects, $totalMinutes min)';
}

/// 周报聚合数据（范围变 → 重跑）
final weeklyReportProvider =
    FutureProvider.autoDispose<WeeklyReportData>((ref) async {
  final range = ref.watch(reportRangeProvider);
  final dao = ref.watch(workLogDaoProvider);

  final groups = await dao.summaryByProject(range.start, range.end);
  final logs = await dao.findBetween(range.start, range.end);

  var total = 0;
  for (final log in logs) {
    total += log.minutes;
  }

  // 按工时降序（DAO 返回顺序未定义，这里明确排序，保证文本稳定）
  final sorted = [...groups]
    ..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));

  return WeeklyReportData(
    range: range,
    groups: sorted,
    logs: logs,
    totalMinutes: total,
  );
});

/// 生成周报的**可复制文本**。
///
/// 【为什么是纯函数】文本生成要能被单测直接断言（不依赖 widget），
/// 且周报页要能"编辑后实时重新生成"。纯函数最省、最好测。
///
/// 【输出结构】
/// ```
/// 工作周报（2026-10-05 ~ 2026-10-11）
///
/// 一、工时汇总（共 12 小时30分）
///   · 项目 A：8 小时
///   · 项目 B：4 小时30分
///
/// 二、本周重点
/// （用户填写）
///
/// 三、下周计划
/// （用户填写）
/// ```
/// [highlights] / [plans] 为空时该段显示占位提示，不会留空段。
String buildReportText({
  required WeeklyReportData data,
  String highlights = '',
  String plans = '',
}) {
  final buffer = StringBuffer();
  final start = FormatUtils.date(data.range.start);
  // range.end 是右开区间，展示时减一天才对得上用户认知
  final endDate = data.range.end.subtract(const Duration(days: 1));
  final end = FormatUtils.date(endDate);

  buffer.writeln('工作周报（$start ~ $end）');
  buffer.writeln();

  buffer.writeln('一、工时汇总（共 ${FormatUtils.minutes(data.totalMinutes)}）');
  if (data.groups.isEmpty) {
    buffer.writeln('  本期间没有工时记录');
  } else {
    for (final g in data.groups) {
      buffer.writeln('  · ${g.projectName}：${FormatUtils.minutes(g.totalMinutes)}');
    }
  }
  buffer.writeln();

  buffer.writeln('二、本周重点');
  final h = highlights.trim();
  buffer.writeln(h.isEmpty ? '（待补充）' : h);
  buffer.writeln();

  buffer.writeln('三、下周计划');
  final p = plans.trim();
  buffer.writeln(p.isEmpty ? '（待补充）' : p);

  return buffer.toString();
}

/// ---------------------------------------------------------------------------
/// 工作日志
/// ---------------------------------------------------------------------------

/// 日志筛选条件（关键字 + 可选项目）
class JournalFilter {
  const JournalFilter({this.keyword = '', this.projectId});

  /// 关键字（匹配内容 / 成果 / 问题）
  final String keyword;

  /// 项目筛选；null 表示全部。DAO 不支持按项目过滤，故在内存里筛。
  final int? projectId;

  bool get isUnfiltered => keyword.trim().isEmpty && projectId == null;

  /// 送去 DAO 的关键字（空串 → null，避免 `like '%%'`）
  String? get daoKeyword {
    final k = keyword.trim();
    return k.isEmpty ? null : k;
  }

  JournalFilter copyWith({
    String? keyword,
    int? projectId,
    bool clearProject = false,
  }) {
    return JournalFilter(
      keyword: keyword ?? this.keyword,
      projectId: clearProject ? null : (projectId ?? this.projectId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JournalFilter &&
      other.keyword == keyword &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(keyword, projectId);

  @override
  String toString() => 'JournalFilter(keyword: $keyword, project: $projectId)';
}

class JournalFilterNotifier extends Notifier<JournalFilter> {
  @override
  JournalFilter build() => const JournalFilter();

  void setKeyword(String keyword) => state = state.copyWith(keyword: keyword);

  void setProject(int? projectId) {
    state = projectId == null
        ? state.copyWith(clearProject: true)
        : state.copyWith(projectId: projectId);
  }

  void reset() => state = const JournalFilter();
}

final journalFilterProvider =
    NotifierProvider<JournalFilterNotifier, JournalFilter>(
  JournalFilterNotifier.new,
);

/// 日志列表流。
///
/// 【为什么按项目过滤放在内存】`WorkJournalDao.watchAll` 只接受 `keyword`
/// （阶段 2 定的接口，且注释明确"可按关键字搜索内容/成果/问题"）。
/// 项目过滤是在已加载结果上挑子集，数据量小；**不改 DAO**，
/// 避免影响阶段 2 已验收的测试。
final journalListProvider =
    StreamProvider.autoDispose<List<WorkJournal>>((ref) {
  final filter = ref.watch(journalFilterProvider);
  final dao = ref.watch(workJournalDaoProvider);
  return dao.watchAll(keyword: filter.daoKeyword).map((list) {
    final p = filter.projectId;
    if (p == null) return list;
    return list.where((j) => j.projectId == p).toList();
  });
});

/// 单条日志
final journalByIdProvider = FutureProvider.autoDispose.family<WorkJournal?, int>(
  (ref, id) => ref.watch(workJournalDaoProvider).findById(id),
);

/// 日志总数
final journalCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(workJournalDaoProvider).countAll(),
);

/// 日志写操作集合
class JournalActions {
  JournalActions(this._ref);

  final Ref _ref;

  WorkJournalDao get _dao => _ref.read(workJournalDaoProvider);

  /// 新增日志。
  ///
  /// 【校验】内容必填（trim 后非空）—— 一条"什么都没有"的日志没有价值。
  Future<int> create({
    DateTime? date,
    int? projectId,
    required String content,
    String? achievement,
    String? problem,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('工作内容不能为空');
    }
    return _dao.insertJournal(
      WorkJournalsCompanion.insert(
        date: workDay(date ?? DateTime.now()),
        projectId: Value(projectId),
        // 【⚠️ 为什么包 `Value(...)`】`WorkJournals` 表里 `content` 声明为
        // `text().withDefault(const Constant(''))` —— 有默认值 → drift 把它
        // 归为**可选列**，`WorkJournalsCompanion.insert` 的形参类型因此是
        // `Value<String>` 而**不是** `String`（与同一文件的 `WorkLogsCompanion`
        // 的 `summary` 一致）。传裸 `String` 会报
        // `argument_type_not_assignable`（阶段 4.5 第 1 轮 analyze 实测）。
        content: Value(trimmed),
        achievement: _optional(achievement),
        problem: _optional(problem),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 更新日志
  Future<bool> update({
    required WorkJournal entry,
    DateTime? date,
    int? projectId,
    required String content,
    String? achievement,
    String? problem,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('工作内容不能为空');
    }
    return _dao.updateJournal(
      entry.copyWith(
        date: workDay(date ?? entry.date),
        projectId: Value(projectId),
        // 【⚠️ 这里**必须**传裸 `String?`，不要包 `Value`】
        // 接收者是 **data class `WorkJournal`**（`entry`），走的是
        // `WorkJournal.copyWith`。drift 里 `copyWith` 有**两族**，形参类型不同：
        //   - `WorkJournalsCompanion.copyWith({Value<String>? content, ...})`
        //   - `WorkJournal.copyWith({String? content, ...})`  ← 我们走的是这个
        // 实测（`database.g.dart:5007`）真签名：
        //   `WorkJournal copyWith({int? id, DateTime? date,
        //     Value<int?> projectId = const Value.absent(),
        //     String? content,                       ← 裸 `String?`！
        //     Value<String?> achievement = ..., Value<String?> problem = ...,
        //     DateTime? createdAt})`
        // 规律：`copyWith` 里**必填列是裸 `T?`**，**可空/带默认值的列才是
        // `Value<T>`**（与 `Companion.insert` 的判据同源，但结论相反！）。
        // 包成 `Value(trimmed)` 会报
        // `The argument type 'Value<String>' can't be assigned to the
        //  parameter type 'String?'`（第 1 轮验证实测，见 §C43）。
        content: trimmed,
        achievement: _optional(achievement),
        problem: _optional(problem),
      ),
    );
  }

  Future<int> remove(int id) => _dao.deleteById(id);

  Value<String?> _optional(String? text) {
    final trimmed = text?.trim();
    return Value((trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }
}

final journalActionsProvider = Provider<JournalActions>(JournalActions.new);
