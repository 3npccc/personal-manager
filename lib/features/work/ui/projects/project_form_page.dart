import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/work_providers.dart';
import 'widgets/project_tile.dart';

/// 项目新增 / 编辑表单。
class ProjectFormPage extends ConsumerStatefulWidget {
  const ProjectFormPage({super.key, this.project});

  final Project? project;

  bool get isEditing => project != null;

  @override
  ConsumerState<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends ConsumerState<ProjectFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;

  late ProgressStatus _status;
  late int _priority;
  late double _progress;
  DateTime? _startDate;
  DateTime? _dueDate;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _noteCtrl = TextEditingController(text: p?.note ?? '');
    _status = p == null ? ProgressStatus.ongoing : ProgressStatus.fromCode(p.status);
    _priority = p?.priority ?? 1;
    _progress = (p?.progress ?? 0).toDouble();
    _startDate = p?.startDate;
    _dueDate = p?.dueDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final p = widget.project;
    if (p == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _noteCtrl.text.trim().isNotEmpty ||
          _progress != 0 ||
          _priority != 1 ||
          _status != ProgressStatus.ongoing ||
          _startDate != null ||
          _dueDate != null;
    }
    return _nameCtrl.text.trim() != p.name ||
        _noteCtrl.text.trim() != (p.note ?? '') ||
        _progress.round() != p.progress ||
        _priority != p.priority ||
        _status.code != p.status ||
        !_sameDate(_startDate, p.startDate) ||
        !_sameDate(_dueDate, p.dueDate);
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

    // 【业务规则】截止日期不能早于开始日期。
    // 用表单级校验而不是 assert，因为用户会真的填错，要给出可读提示。
    if (_startDate != null &&
        _dueDate != null &&
        _dueDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('截止日期不能早于开始日期')),
      );
      return;
    }

    setState(() => _saving = true);
    final actions = ref.read(projectActionsProvider);
    final project = widget.project;

    try {
      if (project == null) {
        await actions.create(
          name: _nameCtrl.text,
          status: _status,
          progress: _progress.round(),
          priority: _priority,
          startDate: _startDate,
          dueDate: _dueDate,
          note: _noteCtrl.text,
        );
      } else {
        await actions.update(
          project: project,
          name: _nameCtrl.text,
          status: _status,
          progress: _progress.round(),
          priority: _priority,
          startDate: _startDate,
          dueDate: _dueDate,
          note: _noteCtrl.text,
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
          title: Text(isEditing ? '编辑项目' : '加项目'),
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
                  labelText: '项目名称',
                  hintText: '如：内部管理工具开发',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入项目名称' : null,
              ),
              const SizedBox(height: 20),
              Text(
                '状态',
                style: AppTextStyles.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ProgressStatus.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (selected) {
                        if (selected) setState(() => _status = s);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '优先级',
                style: AppTextStyles.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in const <int>[0, 1, 2])
                    ChoiceChip(
                      label: Text(projectPriorityLabel(p)),
                      selected: _priority == p,
                      onSelected: (selected) {
                        if (selected) setState(() => _priority = p);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '进度',
                      style: AppTextStyles.fieldLabel(context),
                    ),
                  ),
                  Text(
                    '${_progress.round()}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: AppTypography.titleWeight,
                        ),
                  ),
                ],
              ),
              Slider(
                value: _progress,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${_progress.round()}%',
                onChanged: (v) => setState(() => _progress = v),
              ),
              const SizedBox(height: 12),
              DatePickerField(
                label: '开始日期（可选）',
                value: _startDate,
                allowClear: true,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 10),
                onChanged: (d) => setState(() => _startDate = d),
              ),
              const SizedBox(height: 16),
              DatePickerField(
                label: '截止日期（可选）',
                value: _dueDate,
                allowClear: true,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 10),
                onChanged: (d) => setState(() => _dueDate = d),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '项目笔记（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加项目'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
