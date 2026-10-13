import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../providers/life_providers.dart';

/// 生活备忘新增 / 编辑表单。
///
/// 【提醒时间】可选；第一版**仅展示**，不做系统通知（需求说明书范围界定）。
class MemoFormPage extends ConsumerStatefulWidget {
  const MemoFormPage({super.key, this.memo});

  final LifeMemo? memo;

  bool get isEditing => memo != null;

  @override
  ConsumerState<MemoFormPage> createState() => _MemoFormPageState();
}

class _MemoFormPageState extends ConsumerState<MemoFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;

  DateTime? _remindAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.memo;
    _titleCtrl = TextEditingController(text: m?.title ?? '');
    _contentCtrl = TextEditingController(text: m?.content ?? '');
    _remindAt = m?.remindAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final m = widget.memo;
    if (m == null) {
      return _titleCtrl.text.trim().isNotEmpty ||
          _contentCtrl.text.trim().isNotEmpty ||
          _remindAt != null;
    }
    return _titleCtrl.text.trim() != m.title ||
        _contentCtrl.text.trim() != m.content.trim() ||
        !_sameMoment(_remindAt, m.remindAt);
  }

  static bool _sameMoment(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.isAtSameMomentAs(b);
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
    final actions = ref.read(memoActionsProvider);
    final memo = widget.memo;

    try {
      if (memo == null) {
        await actions.create(
          title: _titleCtrl.text,
          content: _contentCtrl.text,
          remindAt: _remindAt,
        );
      } else {
        await actions.update(
          memo: memo,
          title: _titleCtrl.text,
          content: _contentCtrl.text,
          remindAt: _remindAt,
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
          title: Text(isEditing ? '编辑备忘' : '加备忘'),
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
                controller: _titleCtrl,
                autofocus: !isEditing,
                textInputAction: TextInputAction.next,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '如：交物业费 / 买猫粮',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入标题' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentCtrl,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: '内容（可选）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DatePickerField(
                label: '提醒时间（可选，仅展示）',
                value: _remindAt,
                allowClear: true,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
                formatter: FormatUtils.dateTime,
                onChanged: (d) => setState(() => _remindAt = d),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加备忘'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
