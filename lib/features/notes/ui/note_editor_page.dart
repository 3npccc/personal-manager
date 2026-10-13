import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../providers/note_providers.dart';

/// 笔记新建 / 编辑页。
///
/// [note] 为 null 时是新建，否则是编辑。
/// 保存成功后 `pop()` 返回；调用方无需手动刷新列表（drift stream 自动推送）。
///
/// 【脏数据拦截】离开前若内容有改动，弹确认框。用
/// `PopScope(canPop: false)` + `onPopInvokedWithResult` 实现 ——
/// 注意它**只拦截 `maybePop()`（物理返回键 / AppBar 返回箭头）**，
/// 代码里显式调用 `Navigator.pop()` 不会走 `canPop` 检查。
/// 因此「保存成功」那条路径必须用无参 `pop()`（见 `_save`）。
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final Note? note;

  /// 是否处于编辑模式
  bool get isEditing => note != null;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;

  late Scene _scene;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleCtrl = TextEditingController(text: note?.title ?? '');
    _contentCtrl = TextEditingController(text: note?.content ?? '');
    _scene = note == null ? Scene.life : Scene.fromCode(note.scene);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  /// 是否有未保存的修改
  bool get _isDirty {
    final note = widget.note;
    if (note == null) {
      return _titleCtrl.text.trim().isNotEmpty ||
          _contentCtrl.text.trim().isNotEmpty ||
          _scene != Scene.life;
    }
    return _titleCtrl.text.trim() != note.title ||
        _contentCtrl.text.trim() != note.content.trim() ||
        _scene.code != note.scene;
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
    final actions = ref.read(noteActionsProvider);
    final note = widget.note;

    try {
      if (note == null) {
        await actions.create(
          title: _titleCtrl.text,
          content: _contentCtrl.text,
          scene: _scene,
        );
      } else {
        await actions.update(
          note: note,
          title: _titleCtrl.text,
          content: _contentCtrl.text,
          scene: _scene,
        );
      }
      if (!mounted) return;
      // 无参 pop()：泛型为 void，与路由 MaterialPageRoute<void> 匹配。
      // 不要写成 pop(true) —— 泛型不匹配会运行时崩（见断点文档踩坑 #7）。
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
          title: Text(isEditing ? '编辑笔记' : '新建笔记'),
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
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      autofocus: !isEditing,
                      maxLength: 200,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '给这篇笔记起个名字',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return '请输入标题';
                        if (text.length > 200) return '标题不能超过 200 字';
                        return null;
                      },
                    ),
                    const SizedBox(height: 4),
                    _Label('正文'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentCtrl,
                      maxLines: null,
                      minLines: 12,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: '写点什么…',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(isEditing ? '保存修改' : '创建笔记'),
                        ),
                      ),
                    ],
                  ),
                ),
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
