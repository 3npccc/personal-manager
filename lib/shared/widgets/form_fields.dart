import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/format_utils.dart';

/// 金额输入框：对外始终以「分」为单位的整数（int?），内部按「元」显示。
///
/// 【为什么不用 TextEditingController.value 直接读 double】
/// 浮点数会有精度问题（如 0.1+0.2），本项目铁律是金额一律整数分。
/// 因此这里让用户输入"元"的文本，交给 [yuanToCents] 做一次精确解析。
///
/// 校验：允许数字与至多一个小数点，最多两位小数。
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = '金额',
    this.currencySymbol = '¥',
    this.helperText,
    this.autofocus = false,
    this.enabled = true,
    this.validator,
  });

  /// 外部持有的控制器。文本形如 `12.50`（元）
  final TextEditingController controller;
  final String label;
  final String currencySymbol;
  final String? helperText;
  final bool autofocus;
  final bool enabled;

  /// 额外校验；返回 null 表示通过。非空时不再做内置的"金额格式"校验，
  /// 由调用方自行决定。
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: <TextInputFormatter>[
        // 只允许 数字 + 至多一个小数点 + 至多两位小数
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        DecimalLimitFormatter(),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '$currencySymbol ',
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      validator: validator ?? _defaultValidator,
    );
  }

  String? _defaultValidator(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '请输入金额';
    final cents = FormatUtils.yuanToCents(text);
    if (cents == null) return '金额格式不正确（最多两位小数）';
    if (cents <= 0) return '金额必须大于 0';
    return null;
  }
}

/// 把「元」文本转成「分」整数。返回 null 表示格式非法。
///
/// 复用 [FormatUtils.yuanToCents]，保证全项目只有一处解析逻辑。
int? amountTextToCents(String text) => FormatUtils.yuanToCents(text);

/// 限制小数位数与点号的输入格式化器。
///
/// 规则：
/// - 至多一个小数点
/// - 小数部分至多两位
/// - 整数部分不允许前导 0（`0` 与 `0.5` 合法，`01` / `00` 不合法）
///
/// 公开为顶层类，便于直接单元测试（`TextInputFormatter` 的行为
/// 用 `tester.enterText` 测不稳 —— 那是一次性整体替换，与逐字符敲键不同）。
class DecimalLimitFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // 只允许一个点
    if ('.'.allMatches(text).length > 1) return oldValue;

    // 小数部分最多两位
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot - 1 > 2) return oldValue;

    // 整数部分不允许前导 0
    final intPart = dot >= 0 ? text.substring(0, dot) : text;
    if (intPart.length > 1 && intPart.startsWith('0')) return oldValue;

    return newValue;
  }
}

/// 日期选择字段：只读输入框 + 点击弹日期选择器。
///
/// 不直接用 `showDatePicker` 暴露给页面，是为了统一各处的日期交互
/// （含「清除」能力与中文格式）。
class DatePickerField extends StatelessWidget {
  const DatePickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '日期',
    this.allowClear = false,
    this.firstDate,
    this.lastDate,
    this.formatter,
  });

  /// 当前值；null 表示"未选择"
  final DateTime? value;

  /// 选择回调；清除时传 null
  final ValueChanged<DateTime?> onChanged;

  final String label;
  final bool allowClear;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// 展示格式化函数，默认 `yyyy-MM-dd`
  final String Function(DateTime)? formatter;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(now.year - 5);
    final last = lastDate ?? DateTime(now.year + 5);
    final initial = value ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '未选择'
        : (formatter ?? FormatUtils.date)(value!);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: allowClear && value != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: '清除',
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          text,
          style: value == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}

/// 下拉选择字段：统一 `DropdownButtonFormField` 的样式。
///
/// [T] 为选项值类型，必须可比较（用在 `value == item` 上）。
class DropdownField<T> extends StatelessWidget {
  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
  });

  final String label;
  final T? value;

  /// 选项：(值, 显示文本)
  final List<({T value, String label})> items;
  final ValueChanged<T?> onChanged;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<T>>[
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            child: Text(item.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

