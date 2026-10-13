import 'package:intl/intl.dart';

/// 通用格式化工具
class FormatUtils {
  FormatUtils._();

  static final DateFormat _date = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _month = DateFormat('yyyy-MM');
  static final DateFormat _time = DateFormat('HH:mm');

  /// 2026-10-10
  static String date(DateTime? value) => value == null ? '' : _date.format(value);

  /// 2026-10-10 21:30
  static String dateTime(DateTime? value) =>
      value == null ? '' : _dateTime.format(value);

  /// 2026-10
  static String month(DateTime value) => _month.format(value);

  /// 21:30
  static String time(DateTime value) => _time.format(value);

  /// 相对日期描述：今天 / 明天 / 昨天 / 具体日期
  static String friendlyDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day);
    final diff = target.difference(today).inDays;
    return switch (diff) {
      0 => '今天',
      1 => '明天',
      -1 => '昨天',
      _ when diff < 0 => '已逾期 ${date(value)}',
      _ => date(value),
    };
  }

  /// 金额：分 → 元，如 1250 → "12.50"
  ///
  /// 【实现说明】不使用 `cents / 100` 这样的浮点除法 ——
  /// 大额（如 1 亿元 = 10^10 分）在 double 下会丢精度。
  /// 这里用整数除法与取余拼字符串，任意大小都精确。
  static String centsToYuan(
    int cents, {
    bool withSymbol = false,
    String symbol = '¥',
  }) {
    final negative = cents < 0;
    final abs = negative ? -cents : cents;
    final yuan = abs ~/ 100;
    final frac = abs % 100;
    final text = '$yuan.${frac.toString().padLeft(2, '0')}';
    final signed = negative ? '-$text' : text;
    return withSymbol ? '$symbol$signed' : signed;
  }

  /// 金额：元文本 → 分，**严格解析**。解析失败或超过两位小数都返回 null。
  /// 如 "12.50" → 1250、"12.505" → null
  ///
  /// 【为什么不用 double】
  /// `double.tryParse('12.1') * 100` 会得到 1209.9999...，round 后虽正确，
  /// 但一旦涉及多位小数或极端值就可能出错。本项目铁律是「金额零 double」，
  /// 因此这里做纯字符串解析：
  ///   1. 拆出整数部分与小数部分
  ///   2. 校验两边都是纯数字
  ///   3. 小数部分右补零到两位，整数部分左补零，拼成整数
  ///
  /// 支持：`12` / `12.5` / `12.50` / `.5` / `0.05` / `-3.2`
  /// 拒绝：`12.345`（超两位）/ `1.2.3` / `abc` / 空串
  ///
  /// 【与 [yuanToCentsRounded] 的分工】
  /// 本方法用于**用户手动输入**：金额最小单位是分，输入三位小数属于错误输入，
  /// 应当明确拒绝而不是悄悄改数。导入外部数据请用 [yuanToCentsRounded]。
  static int? yuanToCents(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 允许一个可选正负号
    var body = trimmed;
    var negative = false;
    if (body.startsWith('-')) {
      negative = true;
      body = body.substring(1);
    } else if (body.startsWith('+')) {
      body = body.substring(1);
    }
    if (body.isEmpty) return null;

    final parts = body.split('.');
    if (parts.length > 2) return null;

    final intRaw = parts[0];
    final fracRaw = parts.length == 2 ? parts[1] : '';

    // 至少要有整数位或小数位之一
    if (intRaw.isEmpty && fracRaw.isEmpty) return null;
    // 小数部分最多两位
    if (fracRaw.length > 2) return null;
    // 两边都必须是纯数字
    if (intRaw.isNotEmpty && !_isDigits(intRaw)) return null;
    if (fracRaw.isNotEmpty && !_isDigits(fracRaw)) return null;

    final intPart = intRaw.isEmpty ? 0 : int.parse(intRaw);
    final fracPart = fracRaw.isEmpty ? 0 : int.parse(fracRaw.padRight(2, '0'));

    final cents = intPart * 100 + fracPart;
    return negative ? -cents : cents;
  }

  /// 金额：元文本 → 分，**宽容解析**（超过两位小数按四舍五入到分）。
  /// 用于导入外部数据（CSV/JSON）等"数值可能不规范"的场景。
  /// 如 "12.505" → 1251、"0.004" → 0
  ///
  /// 同样不使用 double：对多余的小数位按"看下一位决定进位"的整数方式处理。
  /// 解析失败返回 null。
  static int? yuanToCentsRounded(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    var body = trimmed;
    var negative = false;
    if (body.startsWith('-')) {
      negative = true;
      body = body.substring(1);
    } else if (body.startsWith('+')) {
      body = body.substring(1);
    }
    if (body.isEmpty) return null;

    final parts = body.split('.');
    if (parts.length > 2) return null;

    final intRaw = parts[0];
    final fracRaw = parts.length == 2 ? parts[1] : '';

    if (intRaw.isEmpty && fracRaw.isEmpty) return null;
    if (intRaw.isNotEmpty && !_isDigits(intRaw)) return null;
    if (fracRaw.isNotEmpty && !_isDigits(fracRaw)) return null;

    final intPart = intRaw.isEmpty ? 0 : int.parse(intRaw);

    // 取小数前两位作为"分"
    final firstTwo = fracRaw.length >= 2 ? fracRaw.substring(0, 2) : fracRaw;
    var fracCents =
        firstTwo.isEmpty ? 0 : int.parse(firstTwo.padRight(2, '0'));

    // 第三位 >= 5 时进一分
    if (fracRaw.length > 2) {
      final third = fracRaw.codeUnitAt(2) - 0x30;
      if (third >= 5) fracCents += 1;
    }

    final cents = intPart * 100 + fracCents;
    return negative ? -cents : cents;
  }

  /// 是否全为 ASCII 数字
  static bool _isDigits(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  /// 分钟 → "1小时30分" / "45分钟"
  static String minutes(int total) {
    if (total < 60) return '$total分钟';
    final hours = total ~/ 60;
    final mins = total % 60;
    return mins == 0 ? '$hours小时' : '$hours小时$mins分';
  }

  /// 进度百分比文本，0.0~1.0 → "75%"
  static String percent(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    return '${(clamped * 100).round()}%';
  }

  /// 安全除法，分母为 0 时返回 0
  static double safeRatio(num part, num total) {
    if (total <= 0) return 0;
    return (part / total).clamp(0.0, 1.0).toDouble();
  }
}
