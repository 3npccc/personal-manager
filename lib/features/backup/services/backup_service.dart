import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import 'export_service.dart';

/// 恢复失败的原因（用于给 UI 精确提示，而不是一句"失败了"）。
enum RestoreFailure {
  /// 文件不存在 / 无法读取
  fileUnreadable,

  /// 不是合法 JSON
  malformedJson,

  /// JSON 里缺少备份所需的字段（不是本程序导出的文件）
  missingFields,

  /// 备份文件格式版本不认识（比如来自更新的程序）
  unsupportedFormatVersion,

  /// 数据库表结构版本与当前程序不一致
  schemaVersionMismatch,

  /// 写入数据库过程中出错（数据已回滚）
  writeFailed,
}

/// 恢复结果。
///
/// 【为什么用结果对象而不是抛异常】恢复失败是**可预期的用户操作结果**
/// （选了错文件等），页面要把具体原因显示给人看。用返回值比 try/catch
/// 更能强制调用方处理每一种情况。
class RestoreResult {
  const RestoreResult.ok({
    required this.restoredRowCount,
    required this.autoBackupPath,
  })  : failure = null,
        message = null;

  const RestoreResult.failed(RestoreFailure this.failure, this.message)
      : restoredRowCount = 0,
        autoBackupPath = null;

  /// 成功时的字段
  final int restoredRowCount;
  final String? autoBackupPath;

  /// 失败时的字段
  final RestoreFailure? failure;
  final String? message;

  bool get isOk => failure == null;
}

/// 备份与恢复服务（阶段 4.8）。
///
/// 【设计要点】
/// 1. **导出复用** [ExportService]，不重复实现序列化；
/// 2. **恢复强制先自动备份**当前库 —— 用户点"恢复"后即使选错文件，
///    旧数据也一定能找回来（"不允许静默覆盖"的落地方式）；
/// 3. **版本校验在写库之前** —— 校验不过绝不碰数据库；
/// 4. **恢复在单个事务里** —— 中途失败整体回滚，不会留下半截数据。
class BackupService {
  BackupService(this.db, {ExportService? exportService})
      : exportService = exportService ?? ExportService(db);

  final AppDatabase db;
  final ExportService exportService;

  /// 备份到 `targetDir`，返回写出的文件路径。
  Future<String> backupToDirectory(Directory targetDir, {DateTime? now}) {
    return exportService.exportJsonToFile(targetDir, now: now);
  }

  /// 自动备份目录名：`auto_backup_before_restore`。
  ///
  /// 【为什么单独一个子目录】用户原始导出与"恢复前的自动兜底"分开存放，
  /// 避免手工整理时误删兜底文件。
  Directory autoBackupDir(Directory baseDir) =>
      Directory(_join(baseDir.path, 'auto_backup_before_restore'));

  /// 从 JSON 文件恢复。
  ///
  /// 步骤（严格按顺序，**任一步失败都立即返回**）：
  ///   1. 读文件 + 解析 JSON；
  ///   2. 校验 `formatVersion` 与 `schemaVersion`；
  ///   3. **自动备份当前数据库**到 [autoBackupDir]；
  ///   4. 事务内清空 15 表 + 按外键父先子后重插。
  Future<RestoreResult> restoreFromJsonFile(
    String filePath, {
    required Directory autoBackupBaseDir,
    DateTime? now,
  }) async {
    // ---- 1. 读文件 ----
    final file = File(filePath);
    if (!await file.exists()) {
      return const RestoreResult.failed(
        RestoreFailure.fileUnreadable,
        '文件不存在或无法访问',
      );
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } on Object catch (e) {
      return RestoreResult.failed(
        RestoreFailure.fileUnreadable,
        '读取文件失败：$e',
      );
    }

    // ---- 2. 解析 + 校验 ----
    final Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const RestoreResult.failed(
          RestoreFailure.malformedJson,
          '文件内容不是有效的备份 JSON 对象',
        );
      }
      payload = decoded;
    } on Object catch (e) {
      return RestoreResult.failed(
        RestoreFailure.malformedJson,
        'JSON 解析失败：$e',
      );
    }

    final formatVersion = payload['formatVersion'];
    final schemaVersion = payload['schemaVersion'];
    final tablesRaw = payload['tables'];
    if (formatVersion is! int || schemaVersion is! int || tablesRaw is! Map) {
      return const RestoreResult.failed(
        RestoreFailure.missingFields,
        '这不是本程序导出的备份文件（缺少 formatVersion / schemaVersion / tables）',
      );
    }
    if (formatVersion != kBackupFormatVersion) {
      return RestoreResult.failed(
        RestoreFailure.unsupportedFormatVersion,
        '备份文件格式版本为 $formatVersion，'
            '当前程序支持 $kBackupFormatVersion',
      );
    }
    if (schemaVersion != db.schemaVersion) {
      return RestoreResult.failed(
        RestoreFailure.schemaVersionMismatch,
        '备份来自数据库结构 v$schemaVersion，'
            '当前程序是 v${db.schemaVersion}，无法直接恢复',
      );
    }

    // ---- 3. 自动备份当前库（**必须在任何写库动作之前**）----
    final backupDir = autoBackupDir(autoBackupBaseDir);
    String autoBackupPath;
    try {
      await backupDir.create(recursive: true);
      autoBackupPath = await exportService.exportJsonToFile(
        backupDir,
        now: now,
      );
    } on Object catch (e) {
      // 【为什么要拦】自动备份失败还继续恢复 = 用户失去所有旧数据，
      // 与"不允许静默覆盖"直接冲突 → 宁可拒绝恢复。
      return RestoreResult.failed(
        RestoreFailure.fileUnreadable,
        '恢复前的自动备份失败，已中止（不覆盖任何数据）：$e',
      );
    }

    // ---- 4. 事务内清空 + 重插 ----
    try {
      final inserted = await db.transaction(() async {
        // 4a. 按**逆序**（子表在前）删除，满足外键约束
        for (final name in kBackupTableNames.reversed) {
          await db.customStatement('DELETE FROM $name');
        }
        // 4b. 按**正序**（父表在前）插入
        var count = 0;
        for (final name in kBackupTableNames) {
          final rows = tablesRaw[name];
          if (rows is! List) continue; // 该表在备份里缺失 → 视为空，跳过
          for (final row in rows) {
            if (row is! Map) continue;
            await _insertRow(name, row);
            count++;
          }
        }
        return count;
      });

      return RestoreResult.ok(
        restoredRowCount: inserted,
        autoBackupPath: autoBackupPath,
      );
    } on Object catch (e) {
      return RestoreResult.failed(
        RestoreFailure.writeFailed,
        '写入数据库失败，已回滚（数据未改变）：$e',
      );
    }
  }

  // -------------------------------------------------------------------------
  // 内部：逐行插入
  // -------------------------------------------------------------------------

  /// 把一行 `{列名: 值}` 插入 `tableName`。
  ///
  /// 【为什么按 Dart 类型分派 Value 类型】`SELECT *` 读出的值本来就是
  /// **原始 SQL 值**（drift 文档：dateTime 存为 int、bool 存为 int、
  /// 小数存为 double、文本存为 String、NULL 存为 null）。
  /// 这里反着来一遍即可**无损还原**，无需知道每列的声明类型。
  Future<void> _insertRow(String tableName, Map<Object?, Object?> row) async {
    if (row.isEmpty) return;
    final columns = <String>[];
    final placeholders = <String>[];
    final variables = <Variable>[];
    row.forEach((key, value) {
      if (key is! String) return;
      columns.add(key);
      placeholders.add('?');
      variables.add(_toVariable(value));
    });
    if (columns.isEmpty) return;

    await db.customInsert(
      'INSERT INTO $tableName (${columns.join(', ')}) '
      'VALUES (${placeholders.join(', ')})',
      variables: variables,
    );
  }

  /// Dart 值 → drift [Variable]。
  ///
  /// 【为什么 null 也用 Variable】`INSERT` 里 `?` 占位必须一一对应；
  /// 传 `null` 裸值会让 drift 无法区分"缺参数"与"参数是 NULL"，
  /// 故统一用 `Variable<Object>(null)` 表示 SQL NULL。
  ///
  /// 【为什么没有 blob 分支】本项目 15 张表**没有任何 BLOB 列**
  /// （见 `tables.dart`：只有 int / text / real / bool / dateTime）。
  /// 加一个用不到的分支只会引入 `dart:typed_data` 依赖与假安全感，
  /// 故不加；若将来真加了 BLOB 列，这里 fail-fast 落到兜底转换。
  Variable _toVariable(Object? value) {
    if (value == null) return Variable<Object>(null);
    if (value is int) return Variable.withInt(value);
    if (value is double) return Variable.withReal(value);
    if (value is bool) return Variable.withBool(value);
    if (value is String) return Variable.withString(value);
    // 兜底：转字符串。正常不会走到（见 ExportService._readTable 的返回类型），
    // 万一将来 drift 改了返回形态，这里会以"能看见的错值"暴露而不是崩溃。
    return Variable.withString(value.toString());
  }

  String _join(String dir, String name) {
    if (dir.endsWith(Platform.pathSeparator)) return '$dir$name';
    return '$dir${Platform.pathSeparator}$name';
  }
}
