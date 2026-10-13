import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/section_header.dart';
import '../backup_providers.dart';
import '../services/backup_service.dart';

/// 备份页面的定位键（供测试精确限定作用域）。
///
/// 【为什么要有 Key】本页有多个按钮 + 多段结果文本，测试若用裸文本断言，
/// 很容易命中别处同款文案（见规则 22 与 C48）。用 key 锚定到区块，
/// 断言才不"碰运气"，同时让页面结构自描述。
const Key backupJsonCardKey = ValueKey('backup-card-json');
const Key backupCsvCardKey = ValueKey('backup-card-csv');
const Key backupRestoreCardKey = ValueKey('backup-card-restore');
const Key backupResultBannerKey = ValueKey('backup-result-banner');

/// 备份恢复页（阶段 4.8）。
///
/// 【能力】
/// - 一键导出 JSON（含版本号 / 导出时间 / 全部 15 张表）
/// - 选目录批量导出 CSV（UTF-8 BOM，Excel / WPS 直接打开）
/// - 从 JSON 恢复：**先显示覆盖警告 → 二次确认 → 自动兜底备份 → 校验 → 写回**
///
/// 【安全底线】全程不联网；恢复前一定先自动备份当前库；
/// 任何一步失败都**不覆盖**任何数据，并把具体原因显示给用户。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  /// 防重入：导出 / 恢复进行中时禁用按钮，避免并发写同一目录。
  bool _busy = false;

  /// 最近一次操作结果（成功 / 失败），用于页面顶部横幅。
  _OpResult? _last;

  Future<void> _run(Future<_OpResult> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    _OpResult result;
    try {
      result = await action();
    } on Object catch (e) {
      // 【为什么要兜底】任何未预期异常都要变成用户可读的结果，
      // 否则页面会停在 _busy=true 且毫无提示（比报错更糟）。
      result = _OpResult.failure('操作失败：$e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
  }

  /// 一键导出 JSON：选保存位置 → 写文件。
  Future<void> _exportJson() async {
    await _run(() async {
      final picker = ref.read(backupFilePickerProvider);
      final exporter = ref.read(exportServiceProvider);
      final text = await exporter.exportJsonText();
      final fileName = 'personal_manager_backup_${_stamp(DateTime.now())}.json';
      final path = await picker.saveFile(
        fileName: fileName,
        bytes: utf8.encode(text),
      );
      if (path == null) return const _OpResult.cancelled();
      return _OpResult.success('已导出 JSON：$path');
    });
  }

  /// 导出 CSV：选目录 → 写 15 个 csv 文件。
  Future<void> _exportCsv() async {
    await _run(() async {
      final picker = ref.read(backupFilePickerProvider);
      final exporter = ref.read(exportServiceProvider);
      final dir = await picker.pickDirectory(dialogTitle: '选择 CSV 导出目录');
      if (dir == null) return const _OpResult.cancelled();
      final written = await exporter.exportAllCsvToDir(Directory(dir));
      return _OpResult.success('已导出 ${written.length} 个 CSV 到：$dir');
    });
  }

  /// 从 JSON 恢复（覆盖警告 → 确认 → 执行）。
  Future<void> _restore() async {
    await _run(() async {
      final picker = ref.read(backupFilePickerProvider);
      final path = await picker.pickJsonFile(dialogTitle: '选择备份 JSON 文件');
      if (path == null) return const _OpResult.cancelled();
      if (!mounted) return const _OpResult.cancelled();

      // ---- 覆盖警告：必须由用户显式确认 ----
      final confirmed = await showConfirmDialog(
        context,
        title: '确认恢复数据？',
        message: '恢复会用备份文件里的内容**完全替换**当前全部数据。\n\n'
            '为了安全，恢复前会自动在当前数据目录下生成一份兜底备份；'
            '但请仍然确认：你真的想用所选文件覆盖现在的数据吗？',
        confirmText: '覆盖并恢复',
        isDanger: true,
      );
      if (!confirmed || !mounted) return const _OpResult.cancelled();

      final service = ref.read(backupServiceProvider);
      final baseDir = ref.read(autoBackupBaseDirProvider);
      final result = await service.restoreFromJsonFile(
        path,
        autoBackupBaseDir: baseDir,
      );
      if (!mounted) return const _OpResult.cancelled();
      return _fromRestore(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          const SectionHeader(title: '数据安全', icon: Icons.shield_outlined),
          const _SafetyNote(),
          const SizedBox(height: 20),
          if (_last != null) ...<Widget>[
            _ResultBanner(result: _last!),
            const SizedBox(height: 20),
          ],
          _ActionCard(
            key: backupJsonCardKey,
            icon: Icons.description_outlined,
            title: '导出 JSON 备份',
            subtitle: '包含格式版本、导出时间与全部 15 张表数据，最适合整库还原',
            buttonLabel: '导出 JSON',
            busy: _busy,
            onPressed: _exportJson,
          ),
          const SizedBox(height: 16),
          _ActionCard(
            key: backupCsvCardKey,
            icon: Icons.table_chart_outlined,
            title: '导出 CSV（按表分文件）',
            subtitle: '每张表一个 .csv，带 UTF-8 BOM，Excel / WPS 可直接打开',
            buttonLabel: '选择目录并导出',
            busy: _busy,
            onPressed: _exportCsv,
          ),
          const SizedBox(height: 16),
          _ActionCard(
            key: backupRestoreCardKey,
            icon: Icons.restore_outlined,
            title: '从 JSON 备份恢复',
            subtitle: '先还原前自动兜底备份，再校验版本；失败绝不覆盖当前数据',
            buttonLabel: '选择文件并恢复',
            busy: _busy,
            isDanger: true,
            onPressed: _restore,
          ),
        ],
      ),
    );
  }
}

/// 操作结果（成功 / 取消 / 失败）。
class _OpResult {
  const _OpResult.success(this.message) : isSuccess = true, isCancelled = false;

  const _OpResult.cancelled()
      : message = null,
        isSuccess = false,
        isCancelled = true;

  const _OpResult.failure(this.message)
      : isSuccess = false,
        isCancelled = false;

  final String? message;
  final bool isSuccess;
  final bool isCancelled;
}

/// 把 [RestoreResult] 翻译成页面结果。
_OpResult _fromRestore(RestoreResult result) {
  if (result.isOk) {
    final backup = result.autoBackupPath;
    final extra = backup == null ? '' : '\n兜底备份：$backup';
    return _OpResult.success('恢复完成，共写入 ${result.restoredRowCount} 行数据。$extra');
  }
  return _OpResult.failure('恢复失败：${result.message ?? '未知原因'}');
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}'
      '_${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// 顶部安全说明块。
class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.lock_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '所有备份与恢复都在本机完成，程序不联网、不上传任何数据。'
                '恢复是覆盖操作，请先确认备份文件来源可靠。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个操作卡片：图标 + 标题 + 说明 + 按钮。
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.onPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool isDanger;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: isDanger
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: isDanger
                  ? FilledButton.icon(
                      onPressed: busy ? null : onPressed,
                      icon: const Icon(Icons.warning_amber_outlined, size: 18),
                      label: Text(buttonLabel),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: busy ? null : onPressed,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(buttonLabel),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果横幅：失败红、成功绿（此处沿用前景色语义而非涨跌色）。
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final _OpResult result;

  @override
  Widget build(BuildContext context) {
    // 取消不显示横幅（用户主动放弃，不需要提示）。
    if (result.isCancelled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final ok = result.isSuccess;
    final bg = ok
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.errorContainer;
    final fg = ok
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onErrorContainer;

    return Card(
      key: backupResultBannerKey,
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 20,
              color: fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.message ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
