import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/models/enums.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:personal_manager/features/notes/providers/note_providers.dart';
import 'package:personal_manager/features/notes/ui/note_editor_page.dart';
import 'package:personal_manager/features/notes/ui/note_list_page.dart';
import 'package:personal_manager/features/notes/ui/widgets/note_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.2 笔记模块测试。
///
/// 覆盖验收要求（开发计划）：
///   「写 3 篇笔记，搜索正文关键字能命中。」
///
/// 另外覆盖：
/// - NoteActions 增删改（含 updatedAt 刷新）
/// - 按场景筛选、按更新时间倒序
/// - 列表页 UI（搜索 → 结果变化、场景筛选、删除确认）
/// - 编辑器页（新建、编辑、校验、脏数据拦截）
void main() {
  late AppDatabase db;

  /// 编辑器页的正文输入框。
  ///
  /// 【为什么不直接 find.byType(TextFormField) 再读 decoration】
  /// `TextFormField` **没有 `decoration` 字段** —— 它只是构造函数参数
  /// （`text_form_field.dart:115` `InputDecoration? decoration`），
  /// 并没有暴露成 getter，所以 `w.decoration` 编译不过（undefined_getter）。
  ///
  /// 【正确链路】
  /// `TextFormField` 内部真实构建的是 `TextField`
  /// （`text_form_field.dart:121,143`：`effectiveDecoration` → `TextField(decoration: ...)`），
  /// 而 `TextField.decoration` 是**真实公开字段**（`text_field.dart:429`），
  /// `InputDecoration.hintText` 也是真实字段（`input_decorator.dart:3145`）。
  /// 因此按「TextField 且 decoration.hintText 匹配」定位，最可靠。
  final bodyField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == '写点什么…',
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一个带内存库 override 的容器。
  ///
  /// 【清理顺序】`addTearDown` 后进先出，因此 `container.dispose()`
  /// 会先于 `setUp` 注册的 `db.close()` 执行 —— 先取消 drift 订阅再关库。
  ///
  /// 【⚠️ 绝不要在这里写 `await Future.delayed(...)`】详见 stage4_todos_test
  /// 同名 helper 的注释：`test()` 跑在 FakeAsync zone，delayed 不会自行推进。
  Future<ProviderContainer> makeContainer() async {
    final settings = await SettingsService.create();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsServiceProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 直接往库里塞一条笔记。
  ///
  /// [updatedAt] 显式传入可用于构造"更新时间顺序"的确定性场景。
  Future<int> seed({
    required String title,
    String content = '',
    Scene scene = Scene.life,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final ts = createdAt ?? DateTime.now();
    return db.noteDao.insertNote(
      NotesCompanion.insert(
        title: title,
        content: Value(content),
        scene: scene.code,
        createdAt: ts,
        updatedAt: updatedAt ?? ts,
      ),
    );
  }

  /// 读取当前筛选条件下的笔记列表。
  ///
  /// 同 stage4_todos_test 的 readList：
  /// `noteListProvider` 是 autoDispose StreamProvider，裸 `read(.future)`
  /// 会因无订阅者而在 loading 阶段被销毁；这里先 listen 占住订阅。
  Future<List<Note>> readList(ProviderContainer c) async {
    final sub = c.listen(noteListProvider, (_, _) {});
    try {
      for (var i = 0; i < 5; i++) {
        await null;
      }
      return await c.read(noteListProvider.future);
    } finally {
      sub.close();
    }
  }

  // =========================================================================
  // Actions（写操作）
  // =========================================================================
  group('NoteActions 写操作', () {
    test('create 写入并裁剪标题与正文空格', () async {
      final c = await makeContainer();
      final actions = c.read(noteActionsProvider);

      final id = await actions.create(
        title: '  读书笔记  ',
        content: '  今天读了三章  ',
        scene: Scene.study,
      );

      final note = await db.noteDao.findById(id);
      expect(note, isNotNull);
      expect(note!.title, '读书笔记', reason: '首尾空格应被裁剪');
      expect(note.content, '今天读了三章', reason: '正文首尾空格应被裁剪');
      expect(note.scene, 'study');
    });

    test('create 时 createdAt 与 updatedAt 相等', () async {
      final c = await makeContainer();
      final ts = DateTime(2026, 3, 1, 10, 30);

      final id = await c.read(noteActionsProvider).create(
            title: '时间戳检查',
            now: ts,
          );

      final note = (await db.noteDao.findById(id))!;
      expect(note.createdAt, ts);
      expect(note.updatedAt, ts, reason: '新建时两个时间应一致');
    });

    test('update 修改内容并刷新 updatedAt', () async {
      final c = await makeContainer();
      final actions = c.read(noteActionsProvider);
      final created = DateTime(2026, 1, 1, 9);
      final id = await seed(
        title: '原标题',
        content: '原正文',
        createdAt: created,
      );
      final note = (await db.noteDao.findById(id))!;

      final later = DateTime(2026, 5, 20, 18);
      final ok = await actions.update(
        note: note,
        title: '新标题',
        content: '新正文',
        scene: Scene.work,
        now: later,
      );

      expect(ok, isTrue);
      final updated = (await db.noteDao.findById(id))!;
      expect(updated.title, '新标题');
      expect(updated.content, '新正文');
      expect(updated.scene, 'work');
      expect(updated.createdAt, created, reason: '创建时间不应被改动');
      expect(
        updated.updatedAt,
        later,
        reason: '更新时间必须刷新，否则列表排序不动',
      );
      expect(updated.updatedAt.isAfter(updated.createdAt), isTrue);
    });

    test('remove 删除指定笔记', () async {
      final c = await makeContainer();
      final actions = c.read(noteActionsProvider);
      final id = await seed(title: '待删除');
      await seed(title: '保留');

      expect(await actions.remove(id), 1);
      final rest = await db.noteDao.findAll();
      expect(rest.length, 1);
      expect(rest.single.title, '保留');
    });
  });

  // =========================================================================
  // 筛选与搜索
  // =========================================================================
  group('NoteFilter 筛选条件', () {
    test('默认无筛选', () async {
      final c = await makeContainer();
      expect(c.read(noteFilterProvider).isUnfiltered, isTrue);
      expect(c.read(noteFilterProvider).scene, isNull);
      expect(c.read(noteFilterProvider).normalizedKeyword, isNull);
    });

    test('setKeyword 空白视为清空搜索', () async {
      final c = await makeContainer();
      final n = c.read(noteFilterProvider.notifier);

      n.setKeyword('dart');
      expect(c.read(noteFilterProvider).normalizedKeyword, 'dart');

      n.setKeyword('   ');
      expect(c.read(noteFilterProvider).normalizedKeyword, isNull);

      n.setKeyword(null);
      expect(c.read(noteFilterProvider).normalizedKeyword, isNull);
    });

    test('相等性：归一化后相同的关键字视为同一 filter', () {
      const a = NoteFilter(keyword: 'dart');
      const b = NoteFilter(keyword: '  dart  ');
      const c = NoteFilter(keyword: 'Dart');
      const d = NoteFilter(keyword: 'dart', scene: Scene.work);

      expect(a, b, reason: '首尾空白不影响相等性');
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse, reason: '大小写不同不应视为相同');
      expect(a == d, isFalse, reason: '场景不同不应视为相同');
    });

    test('按场景筛选列表', () async {
      final c = await makeContainer();
      await seed(title: '学习笔记', scene: Scene.study);
      await seed(title: '工作笔记', scene: Scene.work);
      await seed(title: '生活笔记', scene: Scene.life);

      c.read(noteFilterProvider.notifier).setScene(Scene.work);
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, '工作笔记');
    });

    test('关键字命中标题', () async {
      final c = await makeContainer();
      await seed(title: 'Flutter 状态管理', content: '无关正文');
      await seed(title: '买菜清单', content: '土豆 西红柿');

      c.read(noteFilterProvider.notifier).setKeyword('flutter');
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, 'Flutter 状态管理');
    });

    // ---- 核心验收：搜索正文关键字能命中 ----
    test('关键字命中正文（核心验收点）', () async {
      final c = await makeContainer();
      await seed(title: '第一篇', content: '今天学习了 Riverpod 的用法');
      await seed(title: '第二篇', content: '关于数据库索引的思考');
      await seed(title: '第三篇', content: '周末去爬山，天气很好');

      // "Riverpod" 只出现在第一篇的**正文**里，标题里没有
      c.read(noteFilterProvider.notifier).setKeyword('Riverpod');
      final list = await readList(c);

      expect(list.length, 1, reason: '应只命中正文含 Riverpod 的那篇');
      expect(list.single.title, '第一篇');
      expect(list.single.content, contains('Riverpod'));
    });

    test('搜索大小写不敏感', () async {
      final c = await makeContainer();
      await seed(title: 'A', content: 'Dart 语言特性');

      c.read(noteFilterProvider.notifier).setKeyword('dart');
      expect((await readList(c)).length, 1);

      c.read(noteFilterProvider.notifier).setKeyword('DART');
      expect((await readList(c)).length, 1);
    });

    test('场景 + 关键字组合筛选', () async {
      final c = await makeContainer();
      await seed(title: '学习A', content: 'flutter', scene: Scene.study);
      await seed(title: '工作A', content: 'flutter', scene: Scene.work);
      await seed(title: '学习B', content: '其他', scene: Scene.study);

      final n = c.read(noteFilterProvider.notifier);
      n.setScene(Scene.study);
      n.setKeyword('flutter');

      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, '学习A');
    });

    test('搜不到时返回空列表', () async {
      final c = await makeContainer();
      await seed(title: '只有这篇', content: '一些内容');

      c.read(noteFilterProvider.notifier).setKeyword('不存在的关键字');
      expect(await readList(c), isEmpty);
    });
  });

  // =========================================================================
  // 排序
  // =========================================================================
  group('列表排序', () {
    test('按 updatedAt 倒序，最新更新的在最前', () async {
      final c = await makeContainer();
      // 故意乱序插入
      await seed(
        title: '中间',
        updatedAt: DateTime(2026, 6, 10),
      );
      await seed(
        title: '最旧',
        updatedAt: DateTime(2026, 6, 1),
      );
      await seed(
        title: '最新',
        updatedAt: DateTime(2026, 6, 20),
      );

      final list = await readList(c);
      expect(list.map((n) => n.title).toList(), ['最新', '中间', '最旧']);
    });

    test('更新一条笔记后它应排到最前', () async {
      final c = await makeContainer();
      final old = await seed(
        title: '早先写的',
        updatedAt: DateTime(2026, 6, 1),
      );
      await seed(title: '较新写的', updatedAt: DateTime(2026, 6, 10));

      expect((await readList(c)).first.title, '较新写的');

      final note = (await db.noteDao.findById(old))!;
      await c.read(noteActionsProvider).update(
            note: note,
            title: note.title,
            content: note.content,
            scene: Scene.fromCode(note.scene),
            now: DateTime(2026, 6, 30),
          );

      expect(
        (await readList(c)).first.title,
        '早先写的',
        reason: '更新后更新时间最新，应排到最前',
      );
    });
  });

  // =========================================================================
  // 列表页 UI
  // =========================================================================
  group('笔记列表页 UI', () {
    /// 同 stage4_todos_test 的 settleAfterWrite：写库 → stream 推送 →
    /// 原地重建 → 动画重启，会让 `pumpAndSettle` 不收敛，改用有限次 pump。
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> pumpPage(WidgetTester tester) async {
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: NoteListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态与新建引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有笔记'), findsOneWidget);
      expect(find.text('点右下角「新建笔记」开始记录'), findsOneWidget);
    });

    testWidgets('渲染笔记条目：标题、正文摘要、场景', (tester) async {
      await seed(
        title: 'Flutter 学习',
        content: '今天研究了 Riverpod',
        scene: Scene.study,
      );
      await pumpPage(tester);

      expect(find.text('Flutter 学习'), findsOneWidget);
      expect(find.text('今天研究了 Riverpod'), findsOneWidget);
      expect(find.text('学习'), findsWidgets);
    });

    testWidgets('搜索正文关键字后列表只剩命中项', (tester) async {
      await seed(title: '第一篇', content: '今天学习了 Riverpod 的用法');
      await seed(title: '第二篇', content: '关于数据库索引的思考');
      await seed(title: '第三篇', content: '周末去爬山');
      await pumpPage(tester);

      expect(find.byType(NoteTile), findsNWidgets(3));

      await tester.enterText(find.byType(TextField), 'Riverpod');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(NoteTile), findsOneWidget);
      expect(find.text('第一篇'), findsOneWidget);
      expect(find.text('第二篇'), findsNothing);
    });

    testWidgets('搜索无结果时显示"没有符合条件的笔记"', (tester) async {
      await seed(title: '只有这篇', content: '一些内容');
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'zzz不存在');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('没有符合条件的笔记'), findsOneWidget);
      expect(find.byType(NoteTile), findsNothing);
    });

    testWidgets('清除搜索后恢复完整列表', (tester) async {
      await seed(title: '甲', content: 'aaa');
      await seed(title: '乙', content: 'bbb');
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'aaa');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byType(NoteTile), findsOneWidget);

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteTile), findsNWidgets(2));
    });

    testWidgets('切换场景筛选后列表同步更新', (tester) async {
      await seed(title: '学习笔记', content: 'x', scene: Scene.study);
      await seed(title: '工作笔记', content: 'y', scene: Scene.work);
      await pumpPage(tester);

      expect(find.byType(NoteTile), findsNWidgets(2));

      await tester.tap(find.widgetWithText(ChoiceChip, '学习'));
      await tester.pumpAndSettle();

      expect(find.byType(NoteTile), findsOneWidget);
      expect(find.text('学习笔记'), findsOneWidget);
      expect(find.text('工作笔记'), findsNothing);
    });

    testWidgets('长按弹出删除确认，确认后删除', (tester) async {
      await seed(title: '要删除的笔记', content: 'xx');
      await pumpPage(tester);

      await tester.longPress(find.byType(NoteTile));
      await tester.pumpAndSettle();

      expect(find.text('删除笔记'), findsOneWidget);
      expect(find.textContaining('要删除的笔记'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settleAfterWrite(tester);

      expect(await db.noteDao.countAll(), 0);
      expect(find.text('要删除的笔记'), findsNothing);
    });

    testWidgets('长按后取消删除，数据保留', (tester) async {
      await seed(title: '不该删的笔记', content: 'xx');
      await pumpPage(tester);

      await tester.longPress(find.byType(NoteTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(await db.noteDao.countAll(), 1);
      expect(find.text('不该删的笔记'), findsOneWidget);
    });

    testWidgets('点「新建笔记」打开编辑器，保存后回列表并显示新项', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有笔记'), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, '新建笔记'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPage), findsOneWidget);
      expect(find.text('新建笔记'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '从列表页新建的笔记',
      );
      await tester.enterText(bodyField, '正文内容');
      await tester.tap(find.widgetWithText(FilledButton, '创建笔记'));
      await settleAfterWrite(tester);

      expect(find.byType(NoteEditorPage), findsNothing);
      expect(find.text('从列表页新建的笔记'), findsOneWidget);
    });

    testWidgets('点条目打开编辑页并回填', (tester) async {
      final id = await seed(
        title: '点击编辑我',
        content: '原来的正文',
        scene: Scene.work,
      );
      await pumpPage(tester);

      await tester.tap(find.byType(NoteTile));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorPage), findsOneWidget);
      expect(find.text('编辑笔记'), findsOneWidget);
      expect(find.text('点击编辑我'), findsWidgets);
      expect(find.text('原来的正文'), findsWidgets);

      // 编辑页的标题/正文应已回填
      final titleField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '标题'),
      );
      expect(titleField.controller?.text, '点击编辑我');

      // 收尾：避免未保存脏数据弹窗影响后续（此处测试结束，widget 树销毁）
      expect(id, isPositive);
    });
  });

  // =========================================================================
  // 编辑器页 UI
  // =========================================================================
  group('笔记编辑器页', () {
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 把编辑器 push 到真实导航栈上，使保存后的 pop 行为与线上一致。
    Future<void> pumpEditor(WidgetTester tester, {Note? note}) async {
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => NoteEditorPage(note: note),
                      ),
                    ),
                    child: const Text('打开编辑器'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开编辑器'));
      await tester.pumpAndSettle();
    }

    testWidgets('新建：标题为空时保存被拦截并提示', (tester) async {
      await pumpEditor(tester);
      expect(find.text('新建笔记'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '创建笔记'));
      await tester.pumpAndSettle();

      expect(find.text('请输入标题'), findsOneWidget);
      expect(await db.noteDao.countAll(), 0, reason: '校验失败不应写库');
    });

    testWidgets('新建：填标题与正文后保存成功并写库', (tester) async {
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '我的第一篇笔记',
      );
      await tester.enterText(bodyField, '这是正文，包含关键字 Flutter');
      await tester.tap(find.text('工作'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '创建笔记'));
      await settleAfterWrite(tester);

      final list = await db.noteDao.findAll();
      expect(list.length, 1);
      expect(list.single.title, '我的第一篇笔记');
      expect(list.single.content, '这是正文，包含关键字 Flutter');
      expect(list.single.scene, 'work');
    });

    testWidgets('编辑：回填原值，修改后保存并刷新 updatedAt', (tester) async {
      final created = DateTime(2026, 2, 1, 8);
      final id = await seed(
        title: '原标题',
        content: '原正文',
        scene: Scene.study,
        createdAt: created,
      );
      final note = (await db.noteDao.findById(id))!;

      await pumpEditor(tester, note: note);
      expect(find.text('编辑笔记'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '改后标题',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await settleAfterWrite(tester);

      final updated = (await db.noteDao.findById(id))!;
      expect(updated.title, '改后标题');
      expect(updated.content, '原正文', reason: '未改动的字段应保持');
      expect(updated.scene, 'study');
      expect(updated.createdAt, created, reason: '创建时间不应变');
      expect(
        updated.updatedAt.isAfter(created),
        isTrue,
        reason: '保存应刷新 updatedAt',
      );
    });

    testWidgets('编辑：标题清空后保存被拦截，库中数据不变', (tester) async {
      final id = await seed(title: '原标题', content: '原正文');
      final note = (await db.noteDao.findById(id))!;

      await pumpEditor(tester, note: note);
      await tester.enterText(find.widgetWithText(TextFormField, '标题'), '');
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await tester.pumpAndSettle();

      expect(find.text('请输入标题'), findsOneWidget);
      final unchanged = (await db.noteDao.findById(id))!;
      expect(unchanged.title, '原标题', reason: '校验失败不应改库');
    });

    testWidgets('脏数据拦截：修改后点返回会弹确认框', (tester) async {
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '改了一半',
      );
      await tester.pump();

      // 触发 maybePop（等价于点 AppBar 返回箭头）
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('放弃修改'), findsOneWidget);
      expect(find.text('有未保存的修改，确定离开吗？'), findsOneWidget);

      // 选「取消」应留在编辑页
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPage), findsOneWidget);

      // 再点返回并选「离开」应真正返回
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '离开'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPage), findsNothing);
    });

    testWidgets('未修改时点返回直接退出，不弹确认框', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('放弃修改'), findsNothing);
      expect(find.byType(NoteEditorPage), findsNothing);
    });
  });
}
