import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/study_providers.dart';

/// 学习目标新增 / 编辑表单。
class GoalFormPage extends ConsumerStatefulWidget {
  const GoalFormPage({super.key, this.goal});

  final StudyGoal? goal;

  bool get isEditing => goal != null;

  @override
  ConsumerState<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends ConsumerState<GoalFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  late StudyGoalType _type;
  DateTime? _dueDate;
  late bool _isCompleted;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _nameCtrl = TextEditingController(text: goal?.name ?? '');
    _type = goal == null ? StudyGoalType.other : StudyGoalType.fromCode(goal.type);
    _dueDate = goal?.dueDate;
    _isCompleted = goal?.isCompleted ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final goal = widget.goal;
    if (goal == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _type != StudyGoalType.other ||
          _dueDate != null ||
          _isCompleted;
    }
    return _nameCtrl.text.trim() != goal.name ||
        _type.code != goal.type ||
        !_sameDate(_dueDate, goal.dueDate) ||
        _isCompleted != goal.isCompleted;
  }

  static bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
    final actions = ref.read(studyGoalActionsProvider);
    final goal = widget.goal;

    try {
      if (goal == null) {
        await actions.create(
          name: _nameCtrl.text,
          type: _type,
          dueDate: _dueDate,
          isCompleted: _isCompleted,
        );
      } else {
        await actions.update(
          goal: goal,
          name: _nameCtrl.text,
          type: _type,
          dueDate: _dueDate,
          isCompleted: _isCompleted,
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
    final now = DateTime.now();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑目标' : '加目标'),
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
                textInputAction: TextInputAction.next,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '目标名称',
                  hintText: '如：读完《分布式系统》',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入目标名称' : null,
              ),
              const SizedBox(height: 20),
              Text(
                '目标类型',
                style: AppTextStyles.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in StudyGoalType.values)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (selected) {
                        if (selected) setState(() => _type = t);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DatePickerField(
                label: '截止日期（可选）',
                value: _dueDate,
                allowClear: true,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 10),
                onChanged: (d) => setState(() => _dueDate = d),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已完成'),
                value: _isCompleted,
                onChanged: (v) => setState(() => _isCompleted = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加目标'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
