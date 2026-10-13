import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';

import '../../../core/database/database.dart';

/// 备份文件格式版本（**独立于** 数据库 schemaVersion）。
///
/// 【为什么要两个版本号】
/// - [formatVersion]：备份**文件本身的排版**版本。将来若把 JSON 结构
///   从 `{tables: {...}}` 改成别的形状，靠它识别旧文件。
/// - `schemaVersion`：**数据库表结构**版本（见 `AppDatabase.schemaVersion`）。
///   恢复时必须与当前库一致，否则列对不上。
/// 二者正交：文件格式没变但加了列 → 只有 schemaVersion 变。
const int kBackupFormatVersion = 1;

/// 备份 JSON 里的表清单（**顺序即外键依赖顺序**：父表在前）。
///
/// 【为什么顺序重要】恢复时要在数据上满足外键约束：
/// - `ledger_records.category_id → categories.id`
/// - `work_logs.project_id → projects.id`
/// - `work_journals.project_id → projects.id`（setNull）
/// - `habit_checkins.habit_id → habits.id`
/// 插入按本顺序（父在前）即可；删除按**逆序**（子在前）。
///
/// 【表名为什么用 SQL 名而不是 Dart 类名】
/// 走 SQL 层（`SELECT * FROM <表>` + `insertAll`）可以**一次覆盖 15 张表**
/// 而不用为每张表手写 toJson/fromJson —— 新增表时只要往这个列表里加一行。
/// 表名来自 drift 生成的常量（如 `todos`、`ledgerRecords`），见 database.g.dart。
const List<String> kBackupTableNames = <String>[
  // 通用
  'categories',
  'todos',
  'notes',
  'ledger_records',
  // 学习
  'books',
  'courses',
  'study_goals',
  'study_checkins',
  // 工作
  'projects',
  'work_logs',
  'work_journals',
  // 生活
  'habits',
  'habit_checkins',
  'health_records',
  'life_memos',
];

/// 各表的**日期列**清单（CSV 导出时用于把 Unix 秒渲染成可读时间）。
///
/// 【为什么必须显式声明，不能用启发式】
/// drift 在 SQL 层返回的日期是 **Unix 秒整数**（见
/// `drift/src/runtime/types/mapping.dart:77` → `millisecondsSinceEpoch ~/ 1000`），
/// 与普通整数列在**值类型上完全无法区分**。若靠"数值大小猜日期"，
/// 迟早误伤（例如某笔金额恰好落在 Unix 秒区间）。
/// 显式声明零歧义，代价只是这张小表。
///
/// 【JSON 不需要它】JSON 里日期就存 Unix 秒整数 —— 恢复时原样写回，
/// **完全保真**（不经过任何解析/格式化，无时区与精度损失）。
const Map<String, List<String>> kDateColumnsByTable = <String, List<String>>{
  'todos': <String>['due_date', 'created_at', 'completed_at'],
  'notes': <String>['created_at', 'updated_at'],
  'ledger_records': <String>['record_date', 'created_at'],
  'books': <String>['created_at'],
  'courses': <String>['start_date', 'due_date'],
  'study_checkins': <String>['date', 'created_at'],
  'study_goals': <String>['due_date', 'created_at'],
  'projects': <String>['start_date', 'due_date', 'created_at'],
  'work_logs': <String>['date', 'created_at'],
  'work_journals': <String>['date', 'created_at'],
  'habits': <String>['created_at'],
  'habit_checkins': <String>['date'],
  'health_records': <String>['date'],
  'life_memos': <String>['remind_at', 'created_at'],
};

/// 数据导出服务（阶段 4.8）。
///
/// 【职责边界】
/// - 本类**只负责把库里的数据变成字符串 / 文件**，不含任何交互；
/// - 选文件、弹确认框等交互属于 `backup_page.dart`；
/// - 恢复属于 `backup_service.dart`（它要保证"先自动备份再覆盖"的全流程）。
///
/// 【为什么所有方法都接收 `targetDir` 而不是自己算路径】
/// 方便测试注入临时目录（`Directory.systemTemp`），
/// 也避免把 `path_provider` 的异步路径解析散落在各处。
class ExportService {
  const ExportService(this.db);

  final AppDatabase db;

  /// 导出全部 15 张表为 **JSON 文本**（不含文件 I/O）。
  ///
  /// 返回的结构：
  /// ```json
  /// {
  ///   "formatVersion": 1,
  ///   "schemaVersion": 1,
  ///   "exportedAt": "2026-10-12T00:30:00.000",
  ///   "tables": { "todos": [ {..}, .. ], .. }
  /// }
  /// ```
  Future<String> exportJsonText() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final name in kBackupTableNames) {
      tables[name] = await _readTable(name);
    }
    final payload = <String, Object?>{
      'formatVersion': kBackupFormatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    };
    // 【为什么用 JsonEncoder.withIndent】导出文件可能被用户直接打开看，
    // 缩进后可读性好很多；体积对本机备份无所谓。
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 把 JSON 写进 `targetDir`，返回文件路径。
  ///
  /// 文件名形如 `personal_manager_backup_20261012_003000.json`
  /// （时间戳到秒，避免同目录多次导出互相覆盖）。
  Future<String> exportJsonToFile(Directory targetDir, {DateTime? now}) async {
    final text = await exportJsonText();
    final file = File(
      _joinPath(targetDir.path, 'personal_manager_backup_${_stamp(now)}.json'),
    );
    await file.writeAsString(text, flush: true);
    return file.path;
  }

  /// 导出**一张表**为 CSV 文本（带 UTF-8 BOM）。
  ///
  /// 【为什么要 BOM】Excel / WPS 在中文 Windows 上默认按 GBK 解析 CSV，
  /// 没有 BOM 的中文会变乱码。BOM（`\uFEFF`）能强制它们按 UTF-8 打开。
  ///
  /// 【为什么列头取"第一行的键"】drift 的 `SELECT *` 对同一张表每行返回的
  /// 键**完全一致**（都是 SQL 列名），取第一行即可。空表则只输出 BOM。
  Future<String> exportTableCsvText(String tableName) async {
    final rows = await _readTable(tableName);
    final dateCols = kDateColumnsByTable[tableName] ?? const <String>[];
    final buffer = StringBuffer('\uFEFF'); // UTF-8 BOM
    if (rows.isNotEmpty) {
      final headers = rows.first.keys.toList();
      final data = <List<Object?>>[
        headers,
        for (final row in rows)
          <Object?>[for (final h in headers) _csvCell(row[h], dateCols, h)],
      ];
      // csv 8.x 的 API：`Csv` 类（旧的 `ListToCsvConverter` 已被移除）。
      // 默认 `fieldDelimiter: ','` / `lineDelimiter: '\r\n'`，与旧默认一致。
      buffer.write(Csv().encode(data));
    }
    return buffer.toString();
  }

  /// 把所有表导出为 CSV 到 `targetDir`，返回生成的文件路径列表。
  ///
  /// 文件名与规格书一致：`todos.csv`、`notes.csv`、`ledger.csv` …… 
  /// （规格书列的是 `ledger.csv`，这里统一用 `ledger_records.csv`
  /// 与 SQL 表名一致，避免两个名字指同一张表产生歧义）。
  Future<List<String>> exportAllCsvToDir(Directory targetDir) async {
    final written = <String>[];
    for (final name in kBackupTableNames) {
      final text = await exportTableCsvText(name);
      final file = File(_joinPath(targetDir.path, '$name.csv'));
      await file.writeAsString(text, flush: true);
      written.add(file.path);
    }
    return written;
  }

  // -------------------------------------------------------------------------
  // 内部：SQL 层读取
  // -------------------------------------------------------------------------

  /// 读整张表为 `List<Map>`（列名 → 值）。
  ///
  /// 【为什么直接用 customSelect】`db.select(...)` 需要具体的表 getter；
  /// 走字符串 SQL 才能用一个循环覆盖 15 张表。表名来自固定常量列表，
  /// **不是用户输入**，无注入风险。
  Future<List<Map<String, Object?>>> _readTable(String tableName) async {
    final rows = await db.customSelect('SELECT * FROM $tableName').get();
    return <Map<String, Object?>>[
      for (final row in rows) Map<String, Object?>.from(row.data),
    ];
  }

  /// CSV 单元格渲染。
  ///
  /// 【为什么日期要专门处理】drift 在 SQL 层返回的日期是 **Unix 秒整数**
  /// （`int`），直接写进 CSV 在 Excel 里是一串看不懂的数字。
  /// 这里按 [kDateColumnsByTable] **显式声明的列名**（而非猜数值）
  /// 判断是否为日期列，是则渲染为 `yyyy-MM-dd HH:mm:ss`。
  ///
  /// 【为什么不用类型判断】`row.data` 里日期与普通整数**都是 `int`**，
  /// 类型上无法区分（drift 的 `QueryRow.data` 文档明确说"未映射到 Dart 类型"）。
  Object? _csvCell(Object? value, List<String> dateCols, String column) {
    if (value == null) return '';
    if (value is int && dateCols.contains(column)) {
      return _formatUnixSeconds(value);
    }
    return value;
  }

  /// Unix 秒 → `yyyy-MM-dd HH:mm:ss`（本地时区）。
  ///
  /// 手写补齐而不引入 intl，避免为一个格式串增加依赖面；
  /// 输出格式固定、可预测，正好适合 CSV。
  String _formatUnixSeconds(int seconds) {
    final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _stamp(DateTime? now) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// 极简路径拼接（避免为了 `p.join` 引入 path 包到服务层）。
  ///
  /// 【为什么不用字面量判断分隔符】直接用 [Platform.pathSeparator] 比较，
  /// 既跨平台正确，也避免在源码里写反斜杠字面量（工具与 linter 都容易看花眼）。
  String _joinPath(String dir, String name) {
    if (dir.endsWith(Platform.pathSeparator)) return '$dir$name';
    return '$dir${Platform.pathSeparator}$name';
  }
}
