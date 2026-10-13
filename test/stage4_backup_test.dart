import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/models/enums.dart';
import 'package:personal_manager/features/backup/backup_providers.dart';
import 'package:personal_manager/features/backup/services/backup_service.dart';
import 'package:personal_manager/features/backup/services/export_service.dart';
import 'package:personal_manager/features/backup/ui/backup_page.dart';

/// 阶段 4.8 备份恢复测试。
///
/// 覆盖范围（`开发计划.md §4.8` 原文）：
///   - JSON：含格式版本 / schemaVersion / 导出时间 / **全部 15 张表**；
///   - CSV：15 个文件、UTF-8 BOM、Excel/WPS 可打开（此处断字节与内容）；
///   - 恢复：**先自动备份当前库 → 校验版本 → 写回**，失败不覆盖；
///   - 全程不联网、不静默覆盖。
///
/// 验收路径（§4.8 原文）：
///   备份 → 删除一条记录 → 恢复 → 数据还原。
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发 onCreate（建表 + 内置分类）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // 公共物料
  // ---------------------------------------------------------------------------

  /// 临时目录（每个用例独立，用完删）。
  Directory makeTempDir(String tag) {
    final dir = Directory.systemTemp.createTempSync('pm_backup_$tag');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// 插入一条待办，返回其 id。
  ///
  /// 【签名依据】`TodosCompanion.insert` 的必填项是
  /// `title` / `scene` / `createdAt`（裸值），`priority` 走 `Value`；
  /// 详见 database.g.dart:478 与 C43（Value 三族）。
  Future<int> seedTodo({
    required String title,
    DateTime? createdAt,
    DateTime? dueDate,
  }) async {
    return db.todoDao.insertTodo(
      TodosCompanion.insert(
        title: title,
        scene: Scene.life.code,
        createdAt: createdAt ?? DateTime(2026, 1, 1, 8),
        priority: Value(TodoPriority.medium.value),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate),
      ),
    );
  }

  Future<int> seedNote({required String title}) async {
    final now = DateTime(2026, 1, 1, 9);
    return db.noteDao.insertNote(
      NotesCompanion.insert(
        title: title,
        content: const Value('正文'),
        scene: Scene.study.code,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 找一条内置分类 id。
  Future<int> firstCategoryId() async {
    final row = await db
        .customSelect('SELECT id FROM categories ORDER BY id LIMIT 1')
        .getSingle();
    return row.data['id'] as int;
  }

  Future<int> todoCount() async {
    final rows = await db.customSelect('SELECT COUNT(*) AS c FROM todos').get();
    return rows.first.data['c'] as int;
  }

  // ---------------------------------------------------------------------------
  // 1. 导出 JSON
  // ---------------------------------------------------------------------------

  group('ExportService JSON', () {
    test('包含 formatVersion / schemaVersion / exportedAt / 全部 15 张表', () async {
      final exporter = ExportService(db);
      final text = await exporter.exportJsonText();
      final decoded = jsonDecode(text) as Map<String, Object?>;

      expect(decoded['formatVersion'], kBackupFormatVersion);
      expect(decoded['schemaVersion'], db.schemaVersion);
      expect(decoded['exportedAt'], isA<String>());

      final tables = decoded['tables'] as Map<String, Object?>;
      expect(tables.keys.toSet(), kBackupTableNames.toSet());
      expect(tables.length, 15);
    });

    test('空库导出：15 张表都在，用户表为空、categories 有内置 12 条', () async {
      final exporter = ExportService(db);
      final decoded =
          jsonDecode(await exporter.exportJsonText()) as Map<String, Object?>;
      final tables = decoded['tables'] as Map<String, Object?>;

      // 「空库」= 用户没录任何数据。但 `categories` 不是用户数据：
      // `AppDatabase.onCreate` 会写入 4 条收入 + 8 条支出内置分类，
      // 所以它**必须非空**（下面单独强断言 12 条），不参与「应为空」循环。
      // 【为什么不对全部 15 张表都断言 isEmpty】那样会与业务事实矛盾：
      // 内置分类是产品行为，不是"测试没清干净"。
      const builtInCategoryTable = 'categories';
      final userTables = kBackupTableNames
          .where((name) => name != builtInCategoryTable)
          .toList();
      expect(userTables.length, 14);

      for (final name in userTables) {
        expect(tables[name], isEmpty, reason: '空库下用户表 $name 应为空');
      }

      // 内置分类必须存在且恰好 12 条（4 收入 + 8 支出）——
      // 这条比"非空"更严，能抓住"内置分类被误删/重复初始化"。
      final categories = tables[builtInCategoryTable] as List<Object?>;
      expect(categories.length, 12, reason: '内置分类应为 4 收入 + 8 支出');

      final types = <Object?>[
        for (final c in categories) (c as Map<Object?, Object?>)['type'],
      ];
      expect(types.where((t) => t == 'income').length, 4);
      expect(types.where((t) => t == 'expense').length, 8);
    });

    test('写入文件后可读回，且文件名带时间戳', () async {
      await seedTodo(title: '交周报');
      final dir = makeTempDir('json_file');
      final exporter = ExportService(db);

      final path = await exporter.exportJsonToFile(
        dir,
        now: DateTime(2026, 10, 12, 0, 30, 5),
      );

      expect(File(path).existsSync(), isTrue);
      expect(path, contains('personal_manager_backup_20261012_003005.json'));

      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      final todos = (decoded['tables'] as Map<String, Object?>)['todos'] as List;
      expect(todos.single['title'], '交周报');
    });
  });

  // ---------------------------------------------------------------------------
  // 2. 导出 CSV
  // ---------------------------------------------------------------------------

  group('ExportService CSV', () {
    test('带 UTF-8 BOM 且首行是列名', () async {
      await seedTodo(title: '写测试');
      final exporter = ExportService(db);
      final text = await exporter.exportTableCsvText('todos');

      expect(text.codeUnitAt(0), 0xFEFF, reason: '首字符必须是 BOM');
      final firstLine = text.substring(1).split('\r\n').first;
      expect(firstLine, contains('title'));
      expect(firstLine, contains('priority'));
      // 第二行是数据
      expect(text.substring(1).split('\r\n')[1], contains('写测试'));
    });

    test('日期列渲染为可读时间，而非 Unix 秒', () async {
      final due = DateTime(2026, 3, 15, 9, 30, 0);
      await seedTodo(title: '带截止日期', dueDate: due);

      final exporter = ExportService(db);
      final text = await exporter.exportTableCsvText('todos');
      final header = text.substring(1).split('\r\n').first.split(',');
      final dataRow = text.substring(1).split('\r\n')[1].split(',');
      final dueIdx = header.indexOf('due_date');

      expect(dueIdx, greaterThanOrEqualTo(0));
      expect(dataRow[dueIdx], '2026-03-15 09:30:00');
    });

    test('空表：只有 BOM，不崩', () async {
      final exporter = ExportService(db);
      final text = await exporter.exportTableCsvText('health_records');
      expect(text, '\uFEFF');
    });

    test('exportAllCsvToDir 写出 15 个文件，每个文件名即表名', () async {
      final dir = makeTempDir('csv_dir');
      final exporter = ExportService(db);
      final written = await exporter.exportAllCsvToDir(dir);

      expect(written.length, 15);
      for (final name in kBackupTableNames) {
        expect(File('${dir.path}${Platform.pathSeparator}$name.csv').existsSync(),
            isTrue, reason: '缺少 $name.csv');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 3. 恢复（服务层）
  // ---------------------------------------------------------------------------

  group('BackupService 恢复', () {
    test('备份 → 删记录 → 恢复 → 数据还原', () async {
      await seedTodo(title: '待办A');
      await seedTodo(title: '待办B');
      final dir = makeTempDir('roundtrip');
      final backupDir = makeTempDir('roundtrip_auto');

      final service = BackupService(db);
      final backupPath = await service.backupToDirectory(dir);

      // 故意破坏：删掉所有待办
      await db.customStatement('DELETE FROM todos');
      expect(await todoCount(), 0);

      final result = await service.restoreFromJsonFile(
        backupPath,
        autoBackupBaseDir: backupDir,
      );

      expect(result.isOk, isTrue, reason: result.message ?? '');
      expect(await todoCount(), 2);
      // 自动兜底备份一定生成
      expect(result.autoBackupPath, isNotNull);
      expect(File(result.autoBackupPath!).existsSync(), isTrue);
    });

    test('文件不存在 → fileUnreadable，且不写库', () async {
      await seedTodo(title: '保留');
      final dir = makeTempDir('missing');
      final service = BackupService(db);

      final result = await service.restoreFromJsonFile(
        '${dir.path}${Platform.pathSeparator}nope.json',
        autoBackupBaseDir: dir,
      );

      expect(result.isOk, isFalse);
      expect(result.failure, RestoreFailure.fileUnreadable);
      expect(await todoCount(), 1, reason: '失败不得改动数据');
    });

    test('非法 JSON → malformedJson', () async {
      final dir = makeTempDir('badjson');
      final file = File('${dir.path}${Platform.pathSeparator}bad.json');
      await file.writeAsString('{ this is not json');

      final result = await BackupService(db).restoreFromJsonFile(
        file.path,
        autoBackupBaseDir: dir,
      );
      expect(result.failure, RestoreFailure.malformedJson);
    });

    test('JSON 顶层不是对象 → malformedJson', () async {
      final dir = makeTempDir('arrayjson');
      final file = File('${dir.path}${Platform.pathSeparator}arr.json');
      await file.writeAsString('[1, 2, 3]');

      final result = await BackupService(db).restoreFromJsonFile(
        file.path,
        autoBackupBaseDir: dir,
      );
      expect(result.failure, RestoreFailure.malformedJson);
    });

    test('缺字段 → missingFields', () async {
      final dir = makeTempDir('missingfields');
      final file = File('${dir.path}${Platform.pathSeparator}mf.json');
      await file.writeAsString(jsonEncode(<String, Object?>{'foo': 'bar'}));

      final result = await BackupService(db).restoreFromJsonFile(
        file.path,
        autoBackupBaseDir: dir,
      );
      expect(result.failure, RestoreFailure.missingFields);
    });

    test('formatVersion 不认识 → unsupportedFormatVersion', () async {
      final dir = makeTempDir('badformat');
      final file = File('${dir.path}${Platform.pathSeparator}bf.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'formatVersion': 999,
          'schemaVersion': db.schemaVersion,
          'tables': <String, Object?>{},
        }),
      );

      final result = await BackupService(db).restoreFromJsonFile(
        file.path,
        autoBackupBaseDir: dir,
      );
      expect(result.failure, RestoreFailure.unsupportedFormatVersion);
    });

    test('schemaVersion 不一致 → schemaVersionMismatch，且不写库', () async {
      await seedTodo(title: '保留');
      final dir = makeTempDir('badschema');
      final file = File('${dir.path}${Platform.pathSeparator}bs.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'formatVersion': kBackupFormatVersion,
          'schemaVersion': 999,
          'tables': <String, Object?>{},
        }),
      );

      final result = await BackupService(db).restoreFromJsonFile(
        file.path,
        autoBackupBaseDir: dir,
      );
      expect(result.failure, RestoreFailure.schemaVersionMismatch);
      expect(await todoCount(), 1, reason: '版本不符不得写库');
    });

    test('版本校验全部在写库之前：失败时不会产生自动备份目录', () async {
      final dir = makeTempDir('nobackup');
      final file = File('${dir.path}${Platform.pathSeparator}bs.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'formatVersion': 999,
          'schemaVersion': db.schemaVersion,
          'tables': <String, Object?>{},
        }),
      );

      final service = BackupService(db);
      await service.restoreFromJsonFile(file.path, autoBackupBaseDir: dir);

      expect(service.autoBackupDir(dir).existsSync(), isFalse,
          reason: '校验未通过就不该做自动备份，更不该写库');
    });

    test('恢复后外键关系保持（ledger → category）', () async {
      final catId = await firstCategoryId();
      final ledgerId = await db.ledgerDao.insertRecord(
        LedgerRecordsCompanion.insert(
          type: LedgerType.expense.code,
          amountCents: 1250,
          categoryId: catId,
          recordDate: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1, 10),
        ),
      );
      expect(ledgerId, greaterThan(0));

      final dir = makeTempDir('fk');
      final backupDir = makeTempDir('fk_auto');
      final service = BackupService(db);
      final path = await service.backupToDirectory(dir);

      await db.customStatement('DELETE FROM ledger_records');
      await db.customStatement('DELETE FROM categories');

      final result =
          await service.restoreFromJsonFile(path, autoBackupBaseDir: backupDir);
      expect(result.isOk, isTrue, reason: result.message ?? '');

      // 分类与账目都要回来
      final cats =
          await db.customSelect('SELECT COUNT(*) AS c FROM categories').get();
      expect(cats.first.data['c'], greaterThan(0));
      final ledgers =
          await db.customSelect('SELECT COUNT(*) AS c FROM ledger_records').get();
      expect(ledgers.first.data['c'], 1);
    });

    test('恢复结果里的行数与备份一致', () async {
      await seedTodo(title: 'A');
      await seedTodo(title: 'B');
      await seedNote(title: 'N');
      final dir = makeTempDir('count');
      final backupDir = makeTempDir('count_auto');
      final service = BackupService(db);
      final path = await service.backupToDirectory(dir);

      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      final tables = decoded['tables'] as Map<String, Object?>;
      var expected = 0;
      for (final name in kBackupTableNames) {
        expected += (tables[name] as List).length;
      }

      await db.customStatement('DELETE FROM todos');
      await db.customStatement('DELETE FROM notes');
      final result =
          await service.restoreFromJsonFile(path, autoBackupBaseDir: backupDir);
      expect(result.restoredRowCount, expected);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. 页面（UI 编排）
  // ---------------------------------------------------------------------------
  //
  // 【为什么这一组全部注入假服务，不碰真实文件 IO】
  // `testWidgets` 默认跑在 **FakeAsync zone**：`pumpAndSettle` 只推进**假的**
  // 时钟，而 `File.readAsString()` 这类**真实 IO** 的 Future 要靠**真实事件
  // 循环**轮次才会完成 —— 两者不同步，点击后 `await` 会永远等不到，
  // 用例超时失败（本项目 C7 同类坑）。
  //
  // 因此职责这样切：
  //   - **服务层**（上面三个 group，用 `test()`，跑在真实事件循环）负责验证
  //     「真实 IO 正确性」：JSON 往返、CSV 字节、版本校验、回滚；
  //   - **页面层**（本 group）只验证「交互编排」：点哪个按钮、调了哪个服务、
  //     用户取消/确认时分别显示什么。用假服务即可，且**更精确**。
  group('BackupPage', () {
    late _FakePicker picker;
    late _FakeExporter exporter;
    late _FakeBackup backup;

    /// 挂载页面（全部外部依赖注入假实现）。
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            backupFilePickerProvider.overrideWithValue(picker),
            exportServiceProvider.overrideWithValue(exporter),
            backupServiceProvider.overrideWithValue(backup),
            autoBackupBaseDirProvider.overrideWithValue(
              Directory.systemTemp,
            ),
          ],
          child: const MaterialApp(home: BackupPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      picker = _FakePicker();
      exporter = _FakeExporter(db);
      backup = _FakeBackup(db);
    });

    testWidgets('三张操作卡片都渲染', (tester) async {
      await pumpPage(tester);

      expect(find.byKey(backupJsonCardKey), findsOneWidget);
      expect(find.byKey(backupCsvCardKey), findsOneWidget);
      expect(find.byKey(backupRestoreCardKey), findsOneWidget);
      // 初始没有结果横幅
      expect(find.byKey(backupResultBannerKey), findsNothing);
      // 安全说明文案在
      expect(find.textContaining('不联网'), findsWidgets);
    });

    testWidgets('导出 JSON：点了就调 exporter + picker.saveFile，并显示成功', (tester) async {
      picker.nextSavePath = 'C:/tmp/out.json';
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupJsonCardKey),
          matching: find.text('导出 JSON'),
        ),
      );
      await tester.pumpAndSettle();

      expect(exporter.jsonTextCalls, 1);
      expect(picker.saveCalls, 1);
      // 传给 picker 的文件名带 .json 后缀
      expect(picker.lastSavedFileName, endsWith('.json'));

      final banner = find.byKey(backupResultBannerKey);
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.textContaining('已导出 JSON')),
        findsOneWidget,
      );
    });

    testWidgets('导出 JSON：用户取消 → 不显示横幅', (tester) async {
      picker.nextSavePath = null; // 取消
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupJsonCardKey),
          matching: find.text('导出 JSON'),
        ),
      );
      await tester.pumpAndSettle();

      // 已调用 exporter，但 picker 返回 null → 无成功提示
      expect(exporter.jsonTextCalls, 1);
      expect(find.byKey(backupResultBannerKey), findsNothing);
    });

    testWidgets('导出 CSV：点了就调 exporter 并显示 15 个文件', (tester) async {
      picker.nextDirectory = 'C:/tmp/csv';
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupCsvCardKey),
          matching: find.text('选择目录并导出'),
        ),
      );
      await tester.pumpAndSettle();

      expect(exporter.csvAllCalls, 1);
      final banner = find.byKey(backupResultBannerKey);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('已导出 15 个 CSV'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('导出 CSV：用户取消选目录 → 不调导出、无横幅', (tester) async {
      picker.nextDirectory = null;
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupCsvCardKey),
          matching: find.text('选择目录并导出'),
        ),
      );
      await tester.pumpAndSettle();

      expect(exporter.csvAllCalls, 0);
      expect(find.byKey(backupResultBannerKey), findsNothing);
    });

    testWidgets('恢复：弹出覆盖警告，确认后调服务并显示成功', (tester) async {
      picker.nextOpenPath = 'C:/tmp/backup.json';
      backup.nextResult = const RestoreResult.ok(
        restoredRowCount: 7,
        autoBackupPath: 'C:/tmp/auto_backup_before_restore/x.json',
      );
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupRestoreCardKey),
          matching: find.text('选择文件并恢复'),
        ),
      );
      await tester.pumpAndSettle();

      // 覆盖警告弹窗必须出现（且是危险样式）
      expect(find.text('确认恢复数据？'), findsOneWidget);
      expect(backup.restoreCalls, 0, reason: '未确认前不得调恢复');

      await tester.tap(find.text('覆盖并恢复'));
      await tester.pumpAndSettle();

      expect(backup.restoreCalls, 1);
      final banner = find.byKey(backupResultBannerKey);
      expect(
        find.descendant(of: banner, matching: find.textContaining('恢复完成')),
        findsOneWidget,
      );
      // 提示里带上写入行数
      expect(
        find.descendant(of: banner, matching: find.textContaining('7 行数据')),
        findsOneWidget,
      );
    });

    testWidgets('恢复：在警告框点取消 → 不调服务、无横幅', (tester) async {
      picker.nextOpenPath = 'C:/tmp/backup.json';
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupRestoreCardKey),
          matching: find.text('选择文件并恢复'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('确认恢复数据？'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(backup.restoreCalls, 0, reason: '取消后不得调服务');
      expect(find.byKey(backupResultBannerKey), findsNothing);
    });

    testWidgets('恢复：用户取消选文件 → 连警告框都不弹', (tester) async {
      picker.nextOpenPath = null;
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupRestoreCardKey),
          matching: find.text('选择文件并恢复'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('确认恢复数据？'), findsNothing);
      expect(backup.restoreCalls, 0);
    });

    testWidgets('恢复失败：服务返回失败 → 显示失败原因', (tester) async {
      picker.nextOpenPath = 'C:/tmp/wrong.json';
      backup.nextResult = const RestoreResult.failed(
        RestoreFailure.unsupportedFormatVersion,
        '备份文件格式版本为 999，当前程序支持 1',
      );
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(backupRestoreCardKey),
          matching: find.text('选择文件并恢复'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('覆盖并恢复'));
      await tester.pumpAndSettle();

      final banner = find.byKey(backupResultBannerKey);
      expect(
        find.descendant(of: banner, matching: find.textContaining('恢复失败')),
        findsOneWidget,
      );
    });
  });
}

/// 测试用假文件选择器：所有"用户选择"都由测试预设。
class _FakePicker implements BackupFilePicker {
  String? nextDirectory;
  String? nextOpenPath;
  String? nextSavePath;

  int saveCalls = 0;
  String? lastSavedFileName;

  @override
  Future<String?> pickDirectory({String? dialogTitle}) async => nextDirectory;

  @override
  Future<String?> pickJsonFile({String? dialogTitle}) async => nextOpenPath;

  @override
  Future<String?> saveFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    saveCalls++;
    lastSavedFileName = fileName;
    return nextSavePath;
  }
}

/// 测试用假导出服务：只记录"被调了几次"，不碰真实文件。
class _FakeExporter extends ExportService {
  _FakeExporter(super.db);

  int jsonTextCalls = 0;
  int csvAllCalls = 0;

  @override
  Future<String> exportJsonText() async {
    jsonTextCalls++;
    return '{"formatVersion":1,"schemaVersion":1,"tables":{}}';
  }

  @override
  Future<List<String>> exportAllCsvToDir(Directory targetDir) async {
    csvAllCalls++;
    return <String>[for (final n in kBackupTableNames) '${targetDir.path}/$n.csv'];
  }
}

/// 测试用假恢复服务：返回测试预设的结果，不碰真实文件与数据库。
class _FakeBackup extends BackupService {
  _FakeBackup(super.db);

  int restoreCalls = 0;
  RestoreResult nextResult = const RestoreResult.ok(
    restoredRowCount: 0,
    autoBackupPath: null,
  );

  @override
  Future<RestoreResult> restoreFromJsonFile(
    String filePath, {
    required Directory autoBackupBaseDir,
    DateTime? now,
  }) async {
    restoreCalls++;
    return nextResult;
  }
}
