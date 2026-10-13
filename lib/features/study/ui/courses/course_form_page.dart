import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/study_providers.dart';

/// 课程新增 / 编辑表单。
class CourseFormPage extends ConsumerStatefulWidget {
  const CourseFormPage({super.key, this.course});

  final Course? course;

  bool get isEditing => course != null;

  @override
  ConsumerState<CourseFormPage> createState() => _CourseFormPageState();
}

class _CourseFormPageState extends ConsumerState<CourseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _platformCtrl;
  late final TextEditingController _totalCtrl;
  late final TextEditingController _completedCtrl;

  late ProgressStatus _status;
  DateTime? _startDate;
  DateTime? _dueDate;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    _nameCtrl = TextEditingController(text: course?.name ?? '');
    _platformCtrl = TextEditingController(text: course?.platform ?? '');
    _totalCtrl = TextEditingController(
      text: (course == null || course.totalChapters == 0)
          ? ''
          : '${course.totalChapters}',
    );
    _completedCtrl = TextEditingController(
      text: (course == null || course.completedChapters == 0)
          ? ''
          : '${course.completedChapters}',
    );
    _status = course == null
        ? ProgressStatus.ongoing
        : ProgressStatus.fromCode(course.status);
    _startDate = course?.startDate;
    _dueDate = course?.dueDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _platformCtrl.dispose();
    _totalCtrl.dispose();
    _completedCtrl.dispose();
    super.dispose();
  }

  static int _parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  bool get _isDirty {
    final course = widget.course;
    final total = _parse(_totalCtrl.text);
    final completed = _parse(_completedCtrl.text);
    if (course == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _platformCtrl.text.trim().isNotEmpty ||
          total != 0 ||
          completed != 0 ||
          _status != ProgressStatus.ongoing ||
          _startDate != null ||
          _dueDate != null;
    }
    return _nameCtrl.text.trim() != course.name ||
        _platformCtrl.text.trim() != (course.platform ?? '') ||
        total != course.totalChapters ||
        completed != course.completedChapters ||
        _status.code != course.status ||
        !_sameDate(_startDate, course.startDate) ||
        !_sameDate(_dueDate, course.dueDate);
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

    final total = _parse(_totalCtrl.text);
    final completed = _parse(_completedCtrl.text);
    // 【校验】已完成章节不能超过总章节（总章节为 0 表示未填，不约束）
    if (total > 0 && completed > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成章节不能超过总章节')),
      );
      return;
    }

    setState(() => _saving = true);
    final actions = ref.read(courseActionsProvider);
    final course = widget.course;

    try {
      if (course == null) {
        await actions.create(
          name: _nameCtrl.text,
          platform: _platformCtrl.text,
          totalChapters: total,
          completedChapters: completed,
          startDate: _startDate,
          dueDate: _dueDate,
          status: _status,
        );
      } else {
        await actions.update(
          course: course,
          name: _nameCtrl.text,
          platform: _platformCtrl.text,
          totalChapters: total,
          completedChapters: completed,
          startDate: _startDate,
          dueDate: _dueDate,
          status: _status,
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
          title: Text(isEditing ? '编辑课程' : '加课程'),
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
                  labelText: '课程名',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入课程名' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _platformCtrl,
                textInputAction: TextInputAction.next,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '学习平台（可选）',
                  hintText: '如 B站 / 慕课',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '总章节数',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _completedCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '已完成章节',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '课程状态',
                style: AppTextStyles.fieldLabel(context),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ProgressStatus>(
                segments: [
                  for (final s in ProgressStatus.values)
                    ButtonSegment<ProgressStatus>(
                      value: s,
                      label: Text(s.label),
                    ),
                ],
                selected: <ProgressStatus>{_status},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _status = s.first);
                },
              ),
              const SizedBox(height: 20),
              DatePickerField(
                label: '开始日期（可选）',
                value: _startDate,
                allowClear: true,
                onChanged: (d) => setState(() => _startDate = d),
              ),
              const SizedBox(height: 16),
              DatePickerField(
                label: '计划完成时间（可选）',
                value: _dueDate,
                allowClear: true,
                onChanged: (d) => setState(() => _dueDate = d),
                formatter: FormatUtils.date,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加课程'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
