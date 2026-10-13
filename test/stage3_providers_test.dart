import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/app.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:personal_manager/core/utils/format_utils.dart';
import 'package:personal_manager/features/settings/ui/settings_page.dart';
import 'package:personal_manager/shared/widgets/form_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 3 测试：状态层（Riverpod）+ 设置服务 + 公共组件。
///
/// 覆盖验收要求：
/// - provider 能注入内存数据库，DAO 经 provider 可用
/// - DAO 的 stream 查询在数据变化后自动推送（页面自动刷新能力）
/// - 设置（主题 / 货币符号 / 导航位置）能写能读、能持久化
/// - 设置页 UI 能通过 provider 读写并即时反映到全应用主题
/// - 金额输入组件保证「分」的整数语义
void main() {
  // =========================================================================
  // Provider 注入与 stream 自动刷新
  // =========================================================================
  group('Provider 层', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('appDatabaseProvider 被 override 后，DAO provider 返回可用实例', () async {
      final container = makeContainer();

      final todoDao = container.read(todoDaoProvider);
      final id = await todoDao.insertTodo(
        TodosCompanion.insert(
          title: '经 provider 写入的待办',
          scene: 'life',
          createdAt: DateTime.now(),
        ),
      );
      expect(id, greaterThan(0));

      // 换一个 DAO provider 读同一份数据，验证它们指向同一个库
      final all = await container.read(todoDaoProvider).watchAll().first;
      expect(all.length, 1);
      expect(all.first.title, '经 provider 写入的待办');
    });

    test('所有 DAO provider 都能解析且非空', () {
      final container = makeContainer();
      expect(container.read(todoDaoProvider), isNotNull);
      expect(container.read(noteDaoProvider), isNotNull);
      expect(container.read(ledgerDaoProvider), isNotNull);
      expect(container.read(categoryDaoProvider), isNotNull);
      expect(container.read(bookDaoProvider), isNotNull);
      expect(container.read(courseDaoProvider), isNotNull);
      expect(container.read(studyCheckinDaoProvider), isNotNull);
      expect(container.read(studyGoalDaoProvider), isNotNull);
      expect(container.read(projectDaoProvider), isNotNull);
      expect(container.read(workLogDaoProvider), isNotNull);
      expect(container.read(workJournalDaoProvider), isNotNull);
      expect(container.read(habitDaoProvider), isNotNull);
      expect(container.read(habitCheckinDaoProvider), isNotNull);
      expect(container.read(healthRecordDaoProvider), isNotNull);
      expect(container.read(lifeMemoDaoProvider), isNotNull);
    });

    test('DAO 的 watch 流在数据变化后自动推送（页面自动刷新的基础）', () async {
      final container = makeContainer();
      final dao = container.read(todoDaoProvider);

      final snapshots = <int>[];
      final sub = dao.watchAll().listen((rows) => snapshots.add(rows.length));

      // 等首个快照
      await Future<void>.delayed(Duration.zero);

      await dao.insertTodo(TodosCompanion.insert(
        title: '第一条',
        scene: 'study',
        createdAt: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await dao.insertTodo(TodosCompanion.insert(
        title: '第二条',
        scene: 'work',
        createdAt: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await sub.cancel();

      // 至少收到 0 → 1 → 2 三次推送（首帧可能因调度差异略多）
      expect(snapshots.first, 0);
      expect(snapshots, contains(1));
      expect(snapshots, contains(2));
    });
  });

  // =========================================================================
  // 设置服务
  // =========================================================================
  group('SettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('默认值：主题跟随系统、货币 ¥、导航 home', () async {
      final settings = await SettingsService.create();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.currencySymbol, '¥');
      expect(settings.lastNavId, 'home');
    });

    test('主题模式可写可读，重启后保留', () async {
      final settings = await SettingsService.create();
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);

      await settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);

      // 模拟"重启"：重新从同一份 prefs 创建实例
      final reopened = await SettingsService.create();
      expect(reopened.themeMode, ThemeMode.light);
    });

    test('货币符号：空值回退为 ¥，前后空格被裁剪', () async {
      final settings = await SettingsService.create();

      await settings.setCurrencySymbol('   ');
      expect(settings.currencySymbol, '¥');

      await settings.setCurrencySymbol('  \$  ');
      expect(settings.currencySymbol, '\$');
    });

    test('导航位置可持久化', () async {
      final settings = await SettingsService.create();
      await settings.setLastNavId('ledger');
      expect((await SettingsService.create()).lastNavId, 'ledger');
    });

    test('未知的导航 id 原样返回，由 provider 层兜底', () async {
      final settings = await SettingsService.create();
      await settings.setLastNavId('not-a-real-page');
      expect(settings.lastNavId, 'not-a-real-page');
    });
  });

  // =========================================================================
  // Provider 层的设置读写
  // =========================================================================
  group('设置 Provider', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings = await SettingsService.create();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [settingsServiceProvider.overrideWithValue(settings)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('themeModeProvider 初始值来自设置服务，set 后同步持久化', () async {
      final container = makeContainer();
      expect(container.read(themeModeProvider), ThemeMode.system);

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('currencySymbolProvider 空白输入回退为 ¥ 并同步状态', () async {
      final container = makeContainer();
      await container.read(currencySymbolProvider.notifier).set('   ');
      expect(container.read(currencySymbolProvider), '¥');
      expect(settings.currencySymbol, '¥');
    });

    test('navIndexProvider 初始值来自持久化的 id', () async {
      await settings.setLastNavId('study');
      final container = makeContainer();
      // kNavDestinations 顺序：home/todos/notes/ledger/study/...
      expect(container.read(navIndexProvider), 4);
    });

    test('navIndexProvider 遇到非法 id 回退到 0', () async {
      await settings.setLastNavId('not-a-page');
      final container = makeContainer();
      expect(container.read(navIndexProvider), 0);
    });

    test('navIndexProvider.select 越界时忽略，合法时切换并持久化', () async {
      final container = makeContainer();
      final notifier = container.read(navIndexProvider.notifier);

      notifier.select(-1);
      expect(container.read(navIndexProvider), 0);
      notifier.select(999);
      expect(container.read(navIndexProvider), 0);

      notifier.select(7);
      expect(container.read(navIndexProvider), 7);
      // 持久化是 fire-and-forget，等一拍再断言
      await Future<void>.delayed(Duration.zero);
      expect(settings.lastNavId, 'backup');
    });

    test('navIndexProvider.selectById 按 id 定位，未知 id 忽略', () async {
      final container = makeContainer();
      final notifier = container.read(navIndexProvider.notifier);

      notifier.selectById('ledger');
      expect(container.read(navIndexProvider), 3);

      notifier.selectById('nope');
      expect(container.read(navIndexProvider), 3);
    });
  });

  // =========================================================================
  // 设置页 UI（验证"UI 可通过 provider 读写数据"）
  // =========================================================================
  group('设置页', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
    });

    /// 【⚠️ 必须 override appDatabaseProvider】
    /// `PersonalManagerApp` → `AppShell` 用 `IndexedStack` **同时构建全部 9 个页面**，
    /// 因此 `TodoListPage` 也会被构建并 `ref.watch(todoListProvider)`
    /// → 订阅 drift stream。
    /// 若不 override，就会走**生产库**（`driftDatabase`，文件库 +
    /// `closeStreamsSynchronously: false`）：在 FakeAsync zone 里它永远不完成，
    /// 界面持续调度帧 → `pumpAndSettle timed out`。
    /// （阶段 3 验收时 TodoListPage 还是占位页故无恙；阶段 4.1 换成真实实现后暴露。）
    Future<Widget> buildApp() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = await SettingsService.create();
      return ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const PersonalManagerApp(),
      );
    }

    /// IndexedStack 会同时构建所有页面，因此不能用裸的 `find.text('设置')`
    /// 去点导航项 —— 它会同时命中导航栏标签与设置页标题。
    /// 这里限定只在 NavigationRail 内点击。
    Future<void> tapNav(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('切到设置页并切换主题为深色，全应用主题随之变化', (tester) async {
      await tester.pumpWidget(await buildApp());
      await tester.pumpAndSettle();

      await tapNav(tester, '设置');

      // 默认跟随系统；点「深色」
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Scaffold).first);
      // 验证 themeMode=dark 确实生效
      expect(
        Theme.of(ctx).brightness,
        Brightness.dark,
        reason: '选深色后当前主题应为暗色',
      );
    });

    testWidgets('货币符号快捷选择会即时更新"当前"显示', (tester) async {
      await tester.pumpWidget(await buildApp());
      await tester.pumpAndSettle();

      await tapNav(tester, '设置');

      expect(find.text('当前：¥'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '\$'));
      await tester.pumpAndSettle();

      expect(find.text('当前：\$'), findsOneWidget);
    });

    testWidgets('设置页展示隐私提示与版本信息', (tester) async {
      await tester.pumpWidget(await buildApp());
      await tester.pumpAndSettle();

      await tapNav(tester, '设置');

      // 「数据」区块在首屏
      expect(find.text('数据全部保存在本机'), findsOneWidget);

      // 「关于」区块可能在 ListView 视口之外，需滚动到可见
      await tester.scrollUntilVisible(
        find.text('版本 1.0.0（第一版）'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('版本 1.0.0（第一版）'), findsOneWidget);
    });
  });

  // =========================================================================
  // 公共组件：金额输入
  // =========================================================================
  group('AmountField 金额输入', () {
    /// 挂载一个最小表单，返回 (controller, formKey)
    Future<GlobalKey<FormState>> pumpForm(
      WidgetTester tester, {
      String initial = '',
      TextEditingController? controller,
    }) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AmountField(
              controller: controller ?? TextEditingController(text: initial),
            ),
          ),
        ),
      ));
      return formKey;
    }

    testWidgets('空输入时校验失败并显示提示', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final formKey = await pumpForm(tester, controller: controller);

      // 触发校验后必须 pump 才会渲染出错误文本
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      expect(find.text('请输入金额'), findsOneWidget);
      expect(controller.text, '');
    });

    testWidgets('合法金额通过校验，不显示错误', (tester) async {
      final formKey = await pumpForm(tester, initial: '12.50');
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('请输入金额'), findsNothing);
    });

    testWidgets('零金额被拒绝（金额必须大于 0）', (tester) async {
      final formKey = await pumpForm(tester, initial: '0');
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('金额必须大于 0'), findsOneWidget);
    });

    testWidgets('三位小数被拒绝', (tester) async {
      final formKey = await pumpForm(tester, initial: '12.505');
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('金额格式不正确（最多两位小数）'), findsOneWidget);
    });
  });

  // =========================================================================
  // 输入格式化器（逐字符，模拟真实敲键）
  // =========================================================================
  group('DecimalLimitFormatter 输入约束', () {
    /// 模拟用户逐字符敲入 text（每一步都经过 formatter），
    /// 返回最终被接受的文本。
    ///
    /// 【语义】某一步被 formatter 拒绝时，该字符被丢弃，`value` 保持上一次的
    /// 合法值；下一次敲键在此基础上继续拼接。这与真实输入法行为一致 ——
    /// 用户敲了非法字符，字符没进去，但不会"锁死"后续输入。
    ///
    /// 用逐字符而非 `tester.enterText` 的原因：后者是一次性整体替换，
    /// 与真实输入路径不同，会把"逐步接受"误判为"整体拒绝"。
    String typeCharByChar(TextInputFormatter formatter, String text) {
      var value = TextEditingValue.empty;
      for (var i = 0; i < text.length; i++) {
        final next = value.copyWith(
          text: value.text + text[i],
          selection: TextSelection.collapsed(offset: value.text.length + 1),
        );
        value = formatter.formatEditUpdate(value, next);
      }
      return value.text;
    }

    final formatter = DecimalLimitFormatter();

    test('正常金额逐字符输入全部通过', () {
      expect(typeCharByChar(formatter, '12.50'), '12.50');
      expect(typeCharByChar(formatter, '0.05'), '0.05');
      expect(typeCharByChar(formatter, '100'), '100');
    });

    test('第三位小数被拒绝（停在两位）', () {
      expect(typeCharByChar(formatter, '1.234'), '1.23');
      expect(typeCharByChar(formatter, '12.999'), '12.99');
    });

    test('第二个小数点被拒绝（该字符被丢弃，后续字符继续进入）', () {
      // 逐字符敲 `1.2.3` 的真实过程：
      //   敲 '1' → '1'；敲 '.' → '1.'；敲 '2' → '1.2'
      //   敲 '.' → 形成 '1.2.'（两个点）→ 被拒，输入框仍是 '1.2'
      //   敲 '3' → 形成 '1.23' → 合法，进入
      // 结论：非法字符被丢弃，而不是"从此拒绝后续所有输入"。
      final result = typeCharByChar(formatter, '1.2.3');
      expect(result, '1.23');
      expect('.'.allMatches(result).length, 1, reason: '只应有一个小数点');
    });

    test('整数部分前导 0 被拒绝', () {
      // 敲 `0` 合法，再敲 `1` 形成 `01` 被拒 → 仍是 `0`
      expect(typeCharByChar(formatter, '01'), '0');
    });

    test('0.5 这类小数合法（前导 0 后面跟点）', () {
      expect(typeCharByChar(formatter, '0.5'), '0.5');
    });

    test('输入结束后可以正常退格回退', () {
      // 从 '12.50' 退到 '12.5'
      const old = TextEditingValue(
        text: '12.50',
        selection: TextSelection.collapsed(offset: 5),
      );
      final next = old.copyWith(
        text: '12.5',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(formatter.formatEditUpdate(old, next).text, '12.5');
    });
  });

  // =========================================================================
  // 金额解析（"分"整数语义的兜底保障）
  // =========================================================================
  group('yuanToCents 纯字符串解析', () {
    test('常见写法', () {
      expect(FormatUtils.yuanToCents('12'), 1200);
      expect(FormatUtils.yuanToCents('12.5'), 1250);
      expect(FormatUtils.yuanToCents('12.50'), 1250);
      expect(FormatUtils.yuanToCents('0.05'), 5);
      expect(FormatUtils.yuanToCents('.5'), 50);
      expect(FormatUtils.yuanToCents('  8.88  '), 888);
    });

    test('零与负数', () {
      expect(FormatUtils.yuanToCents('0'), 0);
      expect(FormatUtils.yuanToCents('0.00'), 0);
      expect(FormatUtils.yuanToCents('-3.20'), -320);
      expect(FormatUtils.yuanToCents('+3.20'), 320);
    });

    test('非法输入返回 null', () {
      expect(FormatUtils.yuanToCents(''), isNull);
      expect(FormatUtils.yuanToCents('   '), isNull);
      expect(FormatUtils.yuanToCents('abc'), isNull);
      expect(FormatUtils.yuanToCents('1.2.3'), isNull);
      expect(FormatUtils.yuanToCents('1.'), 100);
      expect(FormatUtils.yuanToCents('1.234'), isNull);
      expect(FormatUtils.yuanToCents('-'), isNull);
      expect(FormatUtils.yuanToCents('.'), isNull);
      expect(FormatUtils.yuanToCents('1e3'), isNull);
    });

    test('往返：分 → 元 → 分 不失真', () {
      for (final cents in <int>[0, 1, 5, 99, 100, 1250, 999999, 123456789]) {
        final yuan = FormatUtils.centsToYuan(cents);
        expect(FormatUtils.yuanToCents(yuan), cents, reason: '$cents → $yuan');
      }
    });

    test('负数金额往返不失真', () {
      for (final cents in <int>[-1, -5, -100, -1250, -999999]) {
        final yuan = FormatUtils.centsToYuan(cents);
        expect(yuan.startsWith('-'), isTrue, reason: '$cents → $yuan 应带负号');
        expect(FormatUtils.yuanToCents(yuan), cents, reason: '$cents → $yuan');
      }
    });

    test('大额不丢精度（旧 double 实现的隐患点）', () {
      // 1 亿元 = 10^10 分，double 实现下 toStringAsFixed 可能失真
      const big = 10000000000;
      final yuan = FormatUtils.centsToYuan(big);
      expect(yuan, '100000000.00');
      expect(FormatUtils.yuanToCents(yuan), big);
    });

    test('避免 double 精度陷阱（旧实现的隐患）', () {
      // double 实现下常见误差点
      expect(FormatUtils.yuanToCents('1.005'), isNull); // 三位小数直接拒绝
      expect(FormatUtils.yuanToCents('2.675'), isNull);
      // 两位小数一律精确
      expect(FormatUtils.yuanToCents('2.67'), 267);
      expect(FormatUtils.yuanToCents('8.29'), 829);
    });
  });
}
