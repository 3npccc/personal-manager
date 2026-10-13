import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/life_providers.dart';

/// 健康记录新增 / 编辑表单。
///
/// 【三个数值全部可选】允许只录其中一项或几项（表里三列都可空）。
/// 日期默认今天；编辑时回填原值。
class HealthFormPage extends ConsumerStatefulWidget {
  const HealthFormPage({super.key, this.record});

  final HealthRecord? record;

  bool get isEditing => record != null;

  @override
  ConsumerState<HealthFormPage> createState() => _HealthFormPageState();
}

class _HealthFormPageState extends ConsumerState<HealthFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sleepCtrl;
  late final TextEditingController _exerciseCtrl;
  late final TextEditingController _weightCtrl;

  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _sleepCtrl = TextEditingController(text: _numText(r?.sleepHours));
    _exerciseCtrl = TextEditingController(
      text: r?.exerciseMinutes == null ? '' : '${r!.exerciseMinutes}',
    );
    _weightCtrl = TextEditingController(text: _numText(r?.weightKg));
    _date = r == null ? lifeToday() : lifeDay(r.date);
  }

  /// double → 输入框文本（去掉尾随 `.0`）
  static String _numText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }

  @override
  void dispose() {
    _sleepCtrl.dispose();
    _exerciseCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final r = widget.record;
    if (r == null) {
      return _sleepCtrl.text.trim().isNotEmpty ||
          _exerciseCtrl.text.trim().isNotEmpty ||
          _weightCtrl.text.trim().isNotEmpty ||
          !_sameDay(_date, lifeToday());
    }
    return _sleepCtrl.text.trim() != _numText(r.sleepHours) ||
        _exerciseCtrl.text.trim() !=
            (r.exerciseMinutes == null ? '' : '${r.exerciseMinutes}') ||
        _weightCtrl.text.trim() != _numText(r.weightKg) ||
        !_sameDay(_date, r.date);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _handleBack() async {
    if (_isDirty) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃修改',
        message: '有未保存的修改，确定离开吗？',
        confirmText: '离开',
        isDanger: true,
      );
      if (!ok) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// 解析可空的非负数（小数允许）。空 → null；非法 → 抛 `FormatException`。
  static double? _parseNum(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 0) {
      throw const FormatException('请输入不小于 0 的数字');
    }
    return v;
  }

  /// 解析可空的非负整数。空 → null；非法 → 抛 `FormatException`。
  static int? _parseInt(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0) {
      throw const FormatException('请输入不小于 0 的整数');
    }
    return v;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    double? sleep;
    int? exercise;
    double? weight;
    try {
      sleep = _parseNum(_sleepCtrl.text);
      exercise = _parseInt(_exerciseCtrl.text);
      weight = _parseNum(_weightCtrl.text);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(healthActionsProvider).upsert(
            date: _date,
            sleepHours: sleep,
            exerciseMinutes: exercise,
            weightKg: weight,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.isEditing;
    final now = DateTime.now();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑健康记录' : '记健康'),
          actions: [
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              DatePickerField(
                label: '日期',
                value: _date,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
                onChanged: (d) {
                  if (d != null) setState(() => _date = lifeDay(d));
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _sleepCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '睡眠时长（小时，可选）',
                  hintText: '如 7.5',
                  border: OutlineInputBorder(),
                ),
                validator: _numValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _exerciseCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '运动时长（分钟，可选）',
                  hintText: '如 30',
                  border: OutlineInputBorder(),
                ),
                validator: _intValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _weightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '体重（公斤，可选）',
                  hintText: '如 65.5',
                  border: OutlineInputBorder(),
                ),
                validator: _numValidator,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '记健康'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小数输入校验：空通过；负数 / 非数字 → 提示。
  String? _numValidator(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '请输入数字';
    if (v < 0) return '不能为负数';
    return null;
  }

  /// 整数输入校验：空通过；负数 / 非整数 → 提示。
  String? _intValidator(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return '请输入整数';
    if (v < 0) return '不能为负数';
    return null;
  }
}
