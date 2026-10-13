import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/work_providers.dart';

/// 工作日志新增 / 编辑表单。
class JournalFormPage extends ConsumerStatefulWidget {
  const JournalFormPage({super.key, this.journal});

  final WorkJournal? journal;

  bool get isEditing => journal != null;

  @override
  ConsumerState<JournalFormPage> createState() => _JournalFormPageState();
}

class _JournalFormPageState extends ConsumerState<JournalFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contentCtrl;
  late final TextEditingController _achievementCtrl;
  late final TextEditingController _problemCtrl;

  int? _projectId;
  DateTime? _date;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final j = widget.journal;
    _contentCtrl = TextEditingController(text: j?.content ?? '');
    _achievementCtrl = TextEditingController(text: j?.achievement ?? '');
    _problemCtrl = TextEditingController(text: j?.problem ?? '');
    _projectId = j?.projectId;
    _date = j?.date ?? workToday();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _achievementCtrl.dispose();
    _problemCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final j = widget.journal;
    if (j == null) {
      return _contentCtrl.text.trim().isNotEmpty ||
          _achievementCtrl.text.trim().isNotEmpty ||
          _problemCtrl.text.trim().isNotEmpty ||
          _projectId != null ||
          !_isToday(_date);
    }
    return _contentCtrl.text.trim() != j.content ||
        _achievementCtrl.text.trim() != (j.achievement ?? '') ||
        _problemCtrl.text.trim() != (j.problem ?? '') ||
        _projectId != j.projectId ||
        !_sameDate(_date, j.date);
  }

  static bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
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
    final actions = ref.read(journalActionsProvider);
    final journal = widget.journal;

    try {
      if (journal == null) {
        await actions.create(
          date: _date,
          projectId: _projectId,
          content: _contentCtrl.text,
          achievement: _achievementCtrl.text,
          problem: _problemCtrl.text,
        );
      } else {
        await actions.update(
          entry: journal,
          date: _date,
          projectId: _projectId,
          content: _contentCtrl.text,
          achievement: _achievementCtrl.text,
          problem: _problemCtrl.text,
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
    final asyncProjects = ref.watch(projectListProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑日志' : '写日志'),
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
                onChanged: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: 20),
              asyncProjects.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('项目加载失败：$e'),
                data: (projects) {
                  if (projects.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: DropdownField<int>(
                      label: '关联项目（可选）',
                      value: _projectId,
                      hintText: '不关联',
                      items: [
                        for (final p in projects)
                          (value: p.id, label: p.name),
                      ],
                      onChanged: (v) => setState(() => _projectId = v),
                    ),
                  );
                },
              ),
              TextFormField(
                controller: _contentCtrl,
                autofocus: !isEditing,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '工作内容',
                  hintText: '今天做了什么？',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入工作内容' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _achievementCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '今日成果（可选）',
                  hintText: '完成了什么、有什么进展',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _problemCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '遇到的问题（可选）',
                  hintText: '卡在哪里、需要什么支持',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '写日志'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
