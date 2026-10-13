import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/form_fields.dart';
import '../providers/todo_providers.dart';
import 'widgets/todo_priority_chip.dart';

/// 待办新增 / 编辑表单。
///
/// [todo] 为 null 时是新增，否则是编辑。
/// 保存成功后 `pop()` 返回；调用方无需手动刷新列表（drift stream 会自动推送）。
class TodoFormPage extends ConsumerStatefulWidget {
  const TodoFormPage({super.key, this.todo});

  final Todo? todo;

  /// 是否处于编辑模式
  bool get isEditing => todo != null;

  @override
  ConsumerState<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends ConsumerState<TodoFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  late Scene _scene;
  late TodoPriority _priority;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final todo = widget.todo;
    _titleCtrl = TextEditingController(text: todo?.title ?? '');
    _descCtrl = TextEditingController(text: todo?.description ?? '');
    _scene = todo == null ? Scene.life : Scene.fromCode(todo.scene);
    _priority = todo == null
        ? TodoPriority.medium
        : TodoPriority.fromValue(todo.priority);
    _dueDate = todo?.dueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// 是否有未保存的修改
  bool get _isDirty {
    final todo = widget.todo;
    if (todo == null) {
      return _titleCtrl.text.trim().isNotEmpty ||
          _descCtrl.text.trim().isNotEmpty ||
          _scene != Scene.life ||
          _priority != TodoPriority.medium ||
          _dueDate != null;
    }
    return _titleCtrl.text.trim() != todo.title ||
        _descCtrl.text.trim() != (todo.description ?? '') ||
        _scene.code != todo.scene ||
        _priority.value != todo.priority ||
        _dueDate != todo.dueDate;
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return showConfirmDialog(
      context,
      title: '放弃修改',
      message: '有未保存的修改，确定离开吗？',
      confirmText: '离开',
      isDanger: true,
    );
  }

  /// 返回前询问是否放弃未保存的修改
  Future<void> _handleBack() async {
    if (await _confirmDiscard() && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final actions = ref.read(todoActionsProvider);
    final todo = widget.todo;

    try {
      if (todo == null) {
        await actions.create(
          title: _titleCtrl.text,
          scene: _scene,
          priority: _priority,
          description: _descCtrl.text,
          dueDate: _dueDate,
        );
      } else {
        await actions.update(
          todo.copyWith(
            title: _titleCtrl.text.trim(),
            description: Value(
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            ),
            scene: _scene.code,
            priority: _priority.value,
            dueDate: Value(_dueDate),
          ),
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
          title: Text(isEditing ? '编辑待办' : '新增待办'),
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
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '要做什么？',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return '请输入标题';
                  if (text.length > 200) return '标题不能超过 200 字';
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: '详细说明（可选）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _Label('场景'),
              const SizedBox(height: 8),
              SegmentedButton<Scene>(
                segments: [
                  for (final scene in Scene.values)
                    ButtonSegment<Scene>(
                      value: scene,
                      label: Text(scene.label),
                    ),
                ],
                selected: <Scene>{_scene},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _scene = s.first);
                },
              ),
              const SizedBox(height: 20),
              _Label('优先级'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in TodoPriority.values)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.label),
                          const SizedBox(width: 4),
                          if (_priority == p)
                            Icon(
                              Icons.check,
                              size: 14,
                              color: TodoPriorityChip.colorOf(context, p),
                            ),
                        ],
                      ),
                      selected: _priority == p,
                      onSelected: _priority == p
                          ? null
                          : (_) => setState(() => _priority = p),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DatePickerField(
                label: '截止日期（可选）',
                value: _dueDate,
                allowClear: true,
                onChanged: (d) => setState(() => _dueDate = d),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '创建待办'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表单小标题
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.fieldLabel(context));
  }
}
