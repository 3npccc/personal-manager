import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../providers/study_providers.dart';

/// 图书新增 / 编辑表单。
///
/// [book] 为 null 时是新增，否则是编辑。
/// 保存成功后 `pop()` 返回；列表无需手动刷新（drift stream 自动推送）。
class BookFormPage extends ConsumerStatefulWidget {
  const BookFormPage({super.key, this.book});

  final Book? book;

  bool get isEditing => book != null;

  @override
  ConsumerState<BookFormPage> createState() => _BookFormPageState();
}

class _BookFormPageState extends ConsumerState<BookFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _currentPageCtrl;
  late final TextEditingController _totalPagesCtrl;
  late final TextEditingController _noteCtrl;

  late BookStatus _status;
  int? _rating;

  bool _saving = false;

  /// 【为什么页数用 TextEditingController 而不是 int 状态】
  /// 用户可能留空（表示未填）；空字符串与 0 语义不同 ——
  /// 空 → 存 0（未填），但输入框要能"空着"而不是显示 "0"。
  @override
  void initState() {
    super.initState();
    final book = widget.book;
    _titleCtrl = TextEditingController(text: book?.title ?? '');
    _authorCtrl = TextEditingController(text: book?.author ?? '');
    _currentPageCtrl = TextEditingController(
      text: (book == null || book.currentPage == 0)
          ? ''
          : '${book.currentPage}',
    );
    _totalPagesCtrl = TextEditingController(
      text: (book == null || book.totalPages == 0) ? '' : '${book.totalPages}',
    );
    _noteCtrl = TextEditingController(text: book?.note ?? '');
    _status = book == null ? BookStatus.reading : BookStatus.fromCode(book.status);
    _rating = book?.rating;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _currentPageCtrl.dispose();
    _totalPagesCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 解析页数输入；空串 → 0（未填）
  static int _parsePages(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  bool get _isDirty {
    final book = widget.book;
    final current = _parsePages(_currentPageCtrl.text);
    final total = _parsePages(_totalPagesCtrl.text);
    if (book == null) {
      return _titleCtrl.text.trim().isNotEmpty ||
          _authorCtrl.text.trim().isNotEmpty ||
          current != 0 ||
          total != 0 ||
          _status != BookStatus.reading ||
          _rating != null ||
          _noteCtrl.text.trim().isNotEmpty;
    }
    return _titleCtrl.text.trim() != book.title ||
        _authorCtrl.text.trim() != (book.author ?? '') ||
        current != book.currentPage ||
        total != book.totalPages ||
        _status.code != book.status ||
        _rating != book.rating ||
        _noteCtrl.text.trim() != (book.note ?? '');
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
    final actions = ref.read(bookActionsProvider);
    final book = widget.book;

    try {
      if (book == null) {
        await actions.create(
          title: _titleCtrl.text,
          author: _authorCtrl.text,
          currentPage: _parsePages(_currentPageCtrl.text),
          totalPages: _parsePages(_totalPagesCtrl.text),
          status: _status,
          rating: _rating,
          note: _noteCtrl.text,
        );
      } else {
        await actions.update(
          book: book,
          title: _titleCtrl.text,
          author: _authorCtrl.text,
          currentPage: _parsePages(_currentPageCtrl.text),
          totalPages: _parsePages(_totalPagesCtrl.text),
          status: _status,
          rating: _rating,
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

  /// 【联动】切换阅读状态时，若非「读完」则清空评分 ——
  /// 未读完却有星级是矛盾状态（见 BookActions._normalizeRating）。
  void _onStatusChanged(BookStatus status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      if (status != BookStatus.finished) _rating = null;
    });
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
          title: Text(isEditing ? '编辑书籍' : '加本书'),
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
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '书名',
                  border: OutlineInputBorder(),
                ),
                validator: (raw) =>
                    (raw ?? '').trim().isEmpty ? '请输入书名' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _authorCtrl,
                textInputAction: TextInputAction.next,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '作者（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _currentPageCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '当前页',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalPagesCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '总页数',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Label('阅读状态'),
              const SizedBox(height: 8),
              SegmentedButton<BookStatus>(
                segments: [
                  for (final s in BookStatus.values)
                    ButtonSegment<BookStatus>(
                      value: s,
                      label: Text(s.label),
                    ),
                ],
                selected: <BookStatus>{_status},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  _onStatusChanged(s.first);
                },
              ),
              const SizedBox(height: 20),
              // 评分只在「读完」时有意义
              if (_status == BookStatus.finished) ...[
                _Label('评分'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        tooltip: '$i 星',
                        onPressed: () => setState(
                          () => _rating = _rating == i ? null : i,
                        ),
                        icon: Icon(
                          (_rating ?? 0) >= i ? Icons.star : Icons.star_border,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _noteCtrl,
                maxLines: 4,
                minLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '读书笔记（可选）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '加本书'),
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
