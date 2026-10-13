import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/models/enums.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/form_fields.dart';
import '../providers/ledger_providers.dart';

/// 记账新增 / 编辑表单。
///
/// [record] 为 null 时是新增，否则是编辑。
/// 保存成功后 `pop()` 返回；调用方无需手动刷新列表（drift stream 自动推送）。
///
/// 【脏数据拦截】用 `PopScope(canPop: false)` + `onPopInvokedWithResult`
/// 实现。它**只拦截 `maybePop()`**（物理返回键 / AppBar 返回箭头），
/// 代码里显式 `Navigator.pop()` 不走该检查，因此保存成功那条路径用无参 `pop()`。
class LedgerFormPage extends ConsumerStatefulWidget {
  const LedgerFormPage({super.key, this.record});

  final LedgerRecord? record;

  /// 是否处于编辑模式
  bool get isEditing => record != null;

  @override
  ConsumerState<LedgerFormPage> createState() => _LedgerFormPageState();
}

class _LedgerFormPageState extends ConsumerState<LedgerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;

  late LedgerType _type;
  late DateTime _recordDate;
  Scene? _scene;

  /// 当前选中的分类 id。
  ///
  /// 【为什么要额外存一份 id，而不只是让下拉自己管】
  /// 分类是异步流加载的，首次构建时列表可能还是空的；此时
  /// `DropdownButtonFormField.value` 若指向一个不在 items 里的值，
  /// Flutter 会断言失败。因此 [build] 里先判 `containsKey` 再传 value。
  int? _categoryId;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _amountCtrl = TextEditingController(
      // 回填时把「分」还原成「元」文本（1250 → "12.50"）
      text: record == null ? '' : FormatUtils.centsToYuan(record.amountCents),
    );
    _noteCtrl = TextEditingController(text: record?.note ?? '');
    _type = record == null
        ? LedgerType.expense
        : LedgerType.fromCode(record.type);
    _recordDate = record?.recordDate ?? _todayOnly();
    // 【为什么要先取到局部变量】Dart 的流分析不会把 `record?.scene == null`
    // 这个判定「传递」到三元表达式另一分支里的 `record.scene`，
    // 直接写 `record?.scene == null ? null : Scene.fromCode(record.scene)`
    // 会报 unchecked_use_of_nullable_value。先落到局部变量再判空最稳。
    final sceneCode = record?.scene;
    _scene = sceneCode == null ? null : Scene.fromCode(sceneCode);
    _categoryId = record?.categoryId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 今天的 00:00
  ///
  /// 【为什么去掉时分秒】列表按月区间查询（>= 1 号 00:00 且 < 下月 1 号 00:00），
  /// 保留时分秒会让 31 日 23:59 之外的边界情况难以推理；
  /// 记账的语义粒度本来就是「哪一天」，故统一存当天 00:00。
  static DateTime _todayOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// 是否有未保存的修改
  bool get _isDirty {
    final record = widget.record;
    if (record == null) {
      return _amountCtrl.text.trim().isNotEmpty ||
          _noteCtrl.text.trim().isNotEmpty ||
          _type != LedgerType.expense ||
          _scene != null ||
          _categoryId != null;
    }
    return _amountCtrl.text.trim() !=
            FormatUtils.centsToYuan(record.amountCents) ||
        _noteCtrl.text.trim() != (record.note ?? '') ||
        _type.code != record.type ||
        _scene?.code != record.scene ||
        _categoryId != record.categoryId ||
        !DateUtilsSameDay.isSame(_recordDate, record.recordDate);
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
    final categoryId = _categoryId;
    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }

    // 金额解析走全项目唯一的 FormatUtils.yuanToCents（整数分，零 double）。
    final cents = FormatUtils.yuanToCents(_amountCtrl.text);
    if (cents == null || cents <= 0) return; // validator 已拦，这里兜底

    setState(() => _saving = true);
    final actions = ref.read(ledgerActionsProvider);
    final record = widget.record;

    try {
      if (record == null) {
        await actions.create(
          type: _type,
          amountCents: cents,
          categoryId: categoryId,
          recordDate: _recordDate,
          scene: _scene,
          note: _noteCtrl.text,
        );
      } else {
        await actions.update(
          record: record,
          type: _type,
          amountCents: cents,
          categoryId: categoryId,
          recordDate: _recordDate,
          scene: _scene,
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

  /// 切换收入 / 支出时，分类列表整体换掉，原选中项必然失效
  void _onTypeChanged(LedgerType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _categoryId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.isEditing;
    final asyncCategories = ref.watch(categoriesOfTypeProvider(_type));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑记录' : '记一笔'),
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
              _Label('类型'),
              const SizedBox(height: 8),
              SegmentedButton<LedgerType>(
                segments: [
                  for (final t in LedgerType.values)
                    ButtonSegment<LedgerType>(
                      value: t,
                      label: Text(t.label),
                    ),
                ],
                selected: <LedgerType>{_type},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  _onTypeChanged(s.first);
                },
              ),
              const SizedBox(height: 20),
              AmountField(
                controller: _amountCtrl,
                label: '金额（元）',
                autofocus: !isEditing,
              ),
              const SizedBox(height: 20),
              asyncCategories.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text('分类加载失败：$e'),
                data: (categories) {
                  // 选中的分类可能已被删除 → 先判存在再传给下拉，避免断言崩溃
                  final ids = categories.map((c) => c.id).toSet();
                  final safeValue =
                      (_categoryId != null && ids.contains(_categoryId))
                          ? _categoryId
                          : null;
                  return DropdownField<int>(
                    label: '分类',
                    value: safeValue,
                    hintText: categories.isEmpty ? '请先添加分类' : '请选择分类',
                    items: [
                      for (final c in categories)
                        (value: c.id, label: c.name),
                    ],
                    onChanged: (id) => setState(() => _categoryId = id),
                  );
                },
              ),
              const SizedBox(height: 20),
              DatePickerField(
                label: '日期',
                value: _recordDate,
                onChanged: (d) {
                  if (d != null) setState(() => _recordDate = d);
                },
              ),
              const SizedBox(height: 20),
              _Label('场景（可选）'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('不指定'),
                    selected: _scene == null,
                    onSelected: (_) => setState(() => _scene = null),
                  ),
                  for (final scene in Scene.values)
                    ChoiceChip(
                      label: Text(scene.label),
                      selected: _scene == scene,
                      onSelected: (selected) => setState(
                        () => _scene = selected ? scene : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                minLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isEditing ? '保存修改' : '记一笔'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 只比较「年月日」的辅助类。
///
/// 【为什么不用 `DateUtils2.isSameDay`】本页只需要一个纯函数，
/// 且不想让 UI 依赖 core/utils；两行实现就地放置、语义明确。
class DateUtilsSameDay {
  DateUtilsSameDay._();

  static bool isSame(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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
