import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/work_providers.dart';

/// 工时新增 / 编辑表单。
class WorkLogFormPage extends ConsumerStatefulWidget {
  const WorkLogFormPage({super.key, this.log, this.initialProjectId});

  /// 编辑时传入；新增时为 null
  final WorkLog? log;

  /// 新增时预选的项目（从项目卡片"记工时"进入时用）
  final int? initialProjectId;

  bool get isEditing => log != null;

  @override
  ConsumerState<WorkLogFormPage> createState() => _WorkLogFormPageState();
}

class _WorkLogFormPageState extends ConsumerState<WorkLogFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _summaryCtrl;

  int? _projectId;
  DateTime? _date;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final log = widget.log;
    _minutesCtrl = TextEditingController(
      text: log == null ? '' : '${log.minutes}',
    );
    _summaryCtrl = TextEditingController(text: log?.summary ?? '');
    _projectId = log?.projectId ?? widget.initialProjectId;
    _date = log?.date ?? workToday();
  }

  @override
  void dispose() {
    _minutesCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final log = widget.log;
    if (log == null) {
      return _minutesCtrl.text.trim().isNotEmpty ||
          _summaryCtrl.text.trim().isNotEmpty ||
          (_projectId != null && _projectId != widget.initialProjectId) ||
          !_isToday(_date);
    }
    return _minutesCtrl.text.trim() != '${log.minutes}' ||
        _summaryCtrl.text.trim() != log.summary ||
        _projectId != log.projectId ||
        !_sameDate(_date, log.date);
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
    if (_projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择项目')),
      );
      return;
    }

    setState(() => _saving = true);
    final actions = ref.read(workLogActionsProvider);
    final log = widget.log;
    final minutes = int.parse(_minutesCtrl.text.trim());

    try {
      if (log == null) {
        await actions.create(
          projectId: _projectId!,
          date: _date,
          minutes: minutes,
          summary: _summaryCtrl.text,
        );
      } else {
        await actions.update(
          entry: log,
          projectId: _projectId!,
          date: _date,
          minutes: minutes,
          summary: _summaryCtrl.text,
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
          title: Text(isEditing ? '编辑工时' : '记工时'),
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
              asyncProjects.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('项目加载失败：$e'),
                data: (projects) {
                  if (projects.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '还没有项目，请先到「项目」页新建一个项目。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    );
                  }
                  return DropdownField<int>(
                    label: '所属项目',
                    value: _projectId,
                    hintText: '请选择项目',
                    items: [
                      for (final p in projects)
                        (value: p.id, label: p.name),
                    ],
                    onChanged: (v) => setState(() => _projectId = v),
                  );
                },
              ),
              const SizedBox(height: 20),
              DatePickerField(
                label: '工作日期',
                value: _date,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
                onChanged: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _minutesCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: '时长（分钟）',
                  hintText: '如：120',
                  suffixText: '分钟',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) {
                  final text = (raw ?? '').trim();
                  if (text.isEmpty) return '请输入时长';
                  final v = int.tryParse(text);
                  if (v == null) return '时长必须是整数';
                  if (v <= 0) return '时长必须大于 0';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _summaryCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '工作内容摘要（可选）',
                  hintText: '如：完成登录模块联调',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '记工时'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
