import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/study_providers.dart';

/// 学习打卡新增 / 编辑表单。
///
/// 新增时默认日期为今天；保存后弹出 SnackBar 显示新的连续天数。
class CheckinFormPage extends ConsumerStatefulWidget {
  const CheckinFormPage({super.key, this.entry});

  final StudyCheckin? entry;

  bool get isEditing => entry != null;

  @override
  ConsumerState<CheckinFormPage> createState() => _CheckinFormPageState();
}

class _CheckinFormPageState extends ConsumerState<CheckinFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contentCtrl;
  late final TextEditingController _minutesCtrl;

  late DateTime _date;
  late bool _goalMet;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _contentCtrl = TextEditingController(text: entry?.content ?? '');
    _minutesCtrl = TextEditingController(
      text: (entry == null || entry.minutes == 0) ? '' : '${entry.minutes}',
    );
    _date = entry == null ? today() : dayStart(entry.date);
    _goalMet = entry?.goalMet ?? false;
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  static int _parseMinutes(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  bool get _isDirty {
    final entry = widget.entry;
    final minutes = _parseMinutes(_minutesCtrl.text);
    if (entry == null) {
      return _contentCtrl.text.trim().isNotEmpty ||
          minutes != 0 ||
          _goalMet ||
          !isSameDay(_date, today());
    }
    return _contentCtrl.text.trim() != entry.content ||
        minutes != entry.minutes ||
        _goalMet != entry.goalMet ||
        !isSameDay(_date, entry.date);
  }

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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final actions = ref.read(studyCheckinActionsProvider);
    final entry = widget.entry;

    // 【为什么先取 messenger 再 pop】
    // 保存成功后会 `Navigator.pop()` 把本页移除，本页的 `context` 随之失效；
    // 若 pop 之后再用本页 context 弹 SnackBar，会命中"已卸载的 context"。
    // 这里提前从（仍有效的）本页 context 取到 messenger，pop 之后照常能弹 ——
    // ScaffoldMessenger 挂在祖先 MaterialApp 上，不随本页销毁。
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (entry == null) {
        await actions.create(
          date: _date,
          content: _contentCtrl.text,
          minutes: _parseMinutes(_minutesCtrl.text),
          goalMet: _goalMet,
        );
      } else {
        await actions.update(
          entry: entry,
          date: _date,
          content: _contentCtrl.text,
          minutes: _parseMinutes(_minutesCtrl.text),
          goalMet: _goalMet,
        );
      }
      // 保存后取一次新的连续天数，给用户正反馈
      final streak = await actions.streak();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('打卡成功，已连续 $streak 天'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
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
          title: Text(isEditing ? '编辑打卡' : '今日打卡'),
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
                label: '打卡日期',
                value: _date,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1, 12, 31),
                onChanged: (d) {
                  if (d != null) setState(() => _date = dayStart(d));
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _minutesCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '学习时长（分钟）',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) {
                  final text = (raw ?? '').trim();
                  if (text.isEmpty) return null; // 允许不填，视为 0
                  final v = int.tryParse(text);
                  if (v == null || v < 0) return '请输入非负整数';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 4,
                minLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '学习内容（可选）',
                  hintText: '如：读完《原则》第 3 章',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('完成今日学习目标'),
                subtitle: Text(
                  _goalMet ? '已达成' : '未达成',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _goalMet,
                onChanged: (v) => setState(() => _goalMet = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '打卡'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
