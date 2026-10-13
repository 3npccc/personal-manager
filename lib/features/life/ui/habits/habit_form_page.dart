import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../providers/life_providers.dart';

/// 习惯新增 / 编辑表单。
class HabitFormPage extends ConsumerStatefulWidget {
  const HabitFormPage({super.key, this.habit});

  final Habit? habit;

  bool get isEditing => habit != null;

  @override
  ConsumerState<HabitFormPage> createState() => _HabitFormPageState();
}

class _HabitFormPageState extends ConsumerState<HabitFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  late HabitFrequency _frequency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _nameCtrl = TextEditingController(text: h?.name ?? '');
    _frequency = h == null
        ? HabitFrequency.daily
        : HabitFrequency.fromCode(h.frequency);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final h = widget.habit;
    if (h == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _frequency != HabitFrequency.daily;
    }
    return _nameCtrl.text.trim() != h.name ||
        _frequency.code != h.frequency;
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
    final actions = ref.read(habitActionsProvider);
    final habit = widget.habit;

    try {
      if (habit == null) {
        await actions.create(name: _nameCtrl.text, frequency: _frequency);
      } else {
        await actions.update(
          habit: habit,
          name: _nameCtrl.text,
          frequency: _frequency,
        );
      }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑习惯' : '加习惯'),
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
              TextFormField(
                controller: _nameCtrl,
                autofocus: !isEditing,
                textInputAction: TextInputAction.done,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '习惯名称',
                  hintText: '如：早睡 / 跑步 / 阅读',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入习惯名称' : null,
              ),
              const SizedBox(height: 20),
              Text(
                '频率',
                style: AppTextStyles.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in HabitFrequency.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _frequency == f,
                      onSelected: (selected) {
                        if (selected) setState(() => _frequency = f);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加习惯'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
