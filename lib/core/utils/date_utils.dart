/// 日期辅助工具：统一处理"按天比较"与"连续天数计算"，避免时区与时分秒干扰。
class DateUtils2 {
  DateUtils2._();

  /// 归一化到当天 00:00（消除时分秒）
  static DateTime dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 是否同一天
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 计算连续打卡天数。
  ///
  /// [dates] 为打卡日期集合（顺序不限，可含重复）。
  /// 规则：
  /// - 从最近一次打卡日往前连续推算，遇到断档即停止。
  /// - 若最近一次打卡既不是今天也不是昨天，则认为连续性已断，返回 0。
  ///   （这样"昨天打过、今天还没打"仍能正确显示昨天的连续数）
  static int calculateStreak(Iterable<DateTime> dates, {DateTime? today}) {
    final normalized = dates.map(dayOf).toSet();
    if (normalized.isEmpty) return 0;

    final base = dayOf(today ?? DateTime.now());
    final sortedDesc = normalized.toList()..sort((a, b) => b.compareTo(a));
    final latest = sortedDesc.first;

    final diffFromToday = base.difference(latest).inDays;
    // 最近一次打卡超过 1 天前，连续性已断
    if (diffFromToday > 1) return 0;

    var streak = 0;
    var cursor = latest;
    while (normalized.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 生成从 start 到 end（含）的每一天，用于日历视图
  static List<DateTime> daysBetween(DateTime start, DateTime end) {
    final result = <DateTime>[];
    var cursor = dayOf(start);
    final last = dayOf(end);
    while (!cursor.isAfter(last)) {
      result.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  /// 本周范围（周一 00:00 ~ 下周一 00:00）
  static ({DateTime start, DateTime end}) thisWeek({DateTime? today}) {
    final base = dayOf(today ?? DateTime.now());
    // weekday: 周一=1 ... 周日=7
    final start = base.subtract(Duration(days: base.weekday - 1));
    return (start: start, end: start.add(const Duration(days: 7)));
  }

  /// 本月范围（1 号 00:00 ~ 下月 1 号 00:00）
  static ({DateTime start, DateTime end}) thisMonth({DateTime? today}) {
    final base = today ?? DateTime.now();
    final start = DateTime(base.year, base.month, 1);
    final end = DateTime(base.year, base.month + 1, 1);
    return (start: start, end: end);
  }
}
