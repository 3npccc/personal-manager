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
import 'package:personal_manager/features/todos/providers/todo_providers.dart';
import 'package:personal_manager/features/todos/ui/todo_form_page.dart';
import 'package:personal_manager/features/todos/ui/todo_list_page.dart';
import 'package:personal_manager/features/todos/ui/widgets/todo_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 4.1 待办模块测试。
///
/// 覆盖验收要求：
/// - 新增 / 编辑 / 删除 / 勾选完成（含完成时间）
/// - 按场景与完成状态筛选
/// - 排序：未完成优先，其次优先级高的靠前
/// - 删除前二次确认
/// - 表单校验与保存
void main() {
  late AppDatabase db;

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
  /// 【清理顺序】
  /// `addTearDown` 是后进先出、且在 `setUp` 注册的 `tearDown` 之前执行，
  /// 因此这里的 `container.dispose()` 会**先于** `db.close()` 运行 ——
  /// 正是我们需要的顺序（先取消 drift 的 stream 订阅，再关库）。
  ///
  /// 【⚠️ 绝对不要在这里写 `await Future.delayed(...)`】
  /// `flutter_test` 的 `test()` 会把测试体（含 tearDown 回调）跑在
  /// 一个 `FakeAsync` zone 里。该 zone 内的 `Future.delayed` **不会自行推进**，
  /// 必须有 `tester.pump()` 去驱动时钟。`test()` 里根本没有 tester，
  /// 于是这个 `await` 永远挂起 → 测试不输出结果 → `flutter test` 整体卡死。
  /// `container.dispose()` 本身是同步的，无需等待任何 Future。
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

  /// 直接往库里塞一条待办，返回 id
  Future<int> seed({
    required String title,
    Scene scene = Scene.life,
    TodoPriority priority = TodoPriority.medium,
    DateTime? dueDate,
    bool completed = false,
  }) async {
    final id = await db.todoDao.insertTodo(
      TodosCompanion.insert(
        title: title,
        scene: scene.code,
        priority: Value(priority.value),
        dueDate: Value(dueDate),
        createdAt: DateTime.now(),
      ),
    );
    if (completed) {
      await db.todoDao.toggleCompleted(id, true);
    }
    return id;
  }

  /// 读取当前筛选条件下的待办列表。
  ///
  /// 【为什么是 listen + read，而不是裸 read】
  /// `todoListProvider` 是 `StreamProvider.autoDispose`：
  /// `c.read(provider.future)` 只是取一次 Future，**没有留下任何监听者**，
  /// autoDispose 会立刻调度销毁，流还没吐出第一个值就被 dispose，
  /// 于是抛出「disposed during loading state」。
  /// 先 `c.listen` 占住订阅，provider 才有理由存活到数据到达；
  /// 取到值后立刻关闭订阅。
  ///
  /// 【为什么没有"轮询等待"】
  /// `flutter_test` 的 `test()` 把测试体跑在 `FakeAsync` zone 内，
  /// 其中的 `Future.delayed` 不会自行推进（要有 tester.pump 才行），
  /// 用 `while (DateTime.now()...) { await Future.delayed(...) }` 轮询会
  /// 变成疯狂空转的真实时间死循环。
  /// 好在 drift 对内存库的 stream 在 `await` 之后就能拿到首值，
  /// 单次 `await read(.future)` 已足够，无需轮询。
  Future<List<Todo>> readList(ProviderContainer c) async {
    final sub = c.listen(todoListProvider, (_, _) {});
    try {
      // 让出若干次 microtask，使 filter 变更触发的重查询有机会完成。
      // `await null` 在 FakeAsync 下会正常推进 microtask 队列，
      // 不像 `Future.delayed` 那样依赖时钟。
      for (var i = 0; i < 5; i++) {
        await null;
      }
      return await c.read(todoListProvider.future);
    } finally {
      sub.close();
    }
  }

  // =========================================================================
  // Actions（写操作）
  // =========================================================================
  group('TodoActions 写操作', () {
    test('create 写入并裁剪标题空格，空描述存 null', () async {
      final c = await makeContainer();
      final actions = c.read(todoActionsProvider);

      final id = await actions.create(
        title: '  写周报  ',
        scene: Scene.work,
        description: '   ',
      );

      final todo = await db.todoDao.findById(id);
      expect(todo, isNotNull);
      expect(todo!.title, '写周报', reason: '首尾空格应被裁剪');
      expect(todo.description, isNull, reason: '空白描述应存 null');
      expect(todo.scene, 'work');
      expect(todo.priority, TodoPriority.medium.value);
      expect(todo.isCompleted, isFalse);
      expect(todo.completedAt, isNull);
    });

    test('create 传入描述与截止日期会被保存', () async {
      final c = await makeContainer();
      final due = DateTime(2026, 11, 1);

      final id = await c.read(todoActionsProvider).create(
            title: '交报告',
            scene: Scene.work,
            priority: TodoPriority.high,
            description: '  给甲方  ',
            dueDate: due,
          );

      final todo = await db.todoDao.findById(id);
      expect(todo!.description, '给甲方');
      expect(todo.dueDate, due);
      expect(todo.priority, TodoPriority.high.value);
    });

    test('toggle(true) 记录完成时间，toggle(false) 清空完成时间', () async {
      final c = await makeContainer();
      final actions = c.read(todoActionsProvider);
      final id = await seed(title: '跑步');

      await actions.toggle(id, true);
      var todo = await db.todoDao.findById(id);
      expect(todo!.isCompleted, isTrue);
      expect(todo.completedAt, isNotNull);

      await actions.toggle(id, false);
      todo = await db.todoDao.findById(id);
      expect(todo!.isCompleted, isFalse);
      expect(todo.completedAt, isNull, reason: '取消完成时应清空完成时间');
    });

    test('update 修改标题 / 场景 / 优先级 / 截止日期', () async {
      final c = await makeContainer();
      final actions = c.read(todoActionsProvider);
      final id = await seed(title: '原标题', scene: Scene.life);
      final todo = (await db.todoDao.findById(id))!;

      final ok = await actions.update(
        todo.copyWith(
          title: '新标题',
          scene: Scene.study.code,
          priority: TodoPriority.high.value,
          dueDate: Value(DateTime(2026, 12, 25)),
        ),
      );

      expect(ok, isTrue);
      final updated = (await db.todoDao.findById(id))!;
      expect(updated.title, '新标题');
      expect(updated.scene, 'study');
      expect(updated.priority, TodoPriority.high.value);
      expect(updated.dueDate, DateTime(2026, 12, 25));
    });

    test('remove 删除指定待办', () async {
      final c = await makeContainer();
      final actions = c.read(todoActionsProvider);
      final id = await seed(title: '待删除');
      await seed(title: '保留');

      expect(await actions.remove(id), 1);
      final rest = await db.todoDao.watchAll().first;
      expect(rest.length, 1);
      expect(rest.first.title, '保留');
    });
  });

  // =========================================================================
  // 筛选
  // =========================================================================
  group('TodoFilter 筛选条件', () {
    test('默认无筛选', () async {
      final c = await makeContainer();
      expect(c.read(todoFilterProvider).isUnfiltered, isTrue);
      expect(c.read(todoFilterProvider).scene, isNull);
      expect(c.read(todoFilterProvider).isCompleted, isNull);
    });

    test('setScene / setCompleted，传 null 表示取消该项筛选', () async {
      final c = await makeContainer();
      final n = c.read(todoFilterProvider.notifier);

      n.setScene(Scene.study);
      expect(c.read(todoFilterProvider).scene, Scene.study);
      expect(c.read(todoFilterProvider).isUnfiltered, isFalse);

      n.setCompleted(false);
      expect(c.read(todoFilterProvider).isCompleted, isFalse);

      n.setScene(null);
      expect(c.read(todoFilterProvider).scene, isNull);
      expect(c.read(todoFilterProvider).isCompleted, isFalse,
          reason: '取消场景筛选不应影响状态筛选');

      n.reset();
      expect(c.read(todoFilterProvider).isUnfiltered, isTrue);
    });

    test('相等性：相同条件视为同一个 filter', () {
      const a = TodoFilter(scene: Scene.work, isCompleted: true);
      const b = TodoFilter(scene: Scene.work, isCompleted: true);
      const c = TodoFilter(scene: Scene.work);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('按场景筛选列表', () async {
      final c = await makeContainer();
      await seed(title: '读书', scene: Scene.study);
      await seed(title: '写代码', scene: Scene.work);
      await seed(title: '买菜', scene: Scene.life);

      c.read(todoFilterProvider.notifier).setScene(Scene.work);
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, '写代码');
    });

    test('按完成状态筛选列表', () async {
      final c = await makeContainer();
      await seed(title: '已完成项', completed: true);
      await seed(title: '未完成项');

      c.read(todoFilterProvider.notifier).setCompleted(true);
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, '已完成项');
    });

    test('场景 + 状态组合筛选', () async {
      final c = await makeContainer();
      await seed(title: '学习未完成', scene: Scene.study);
      await seed(title: '学习已完成', scene: Scene.study, completed: true);
      await seed(title: '工作未完成', scene: Scene.work);

      final n = c.read(todoFilterProvider.notifier);
      n.setScene(Scene.study);
      n.setCompleted(false);
      final list = await readList(c);
      expect(list.length, 1);
      expect(list.single.title, '学习未完成');
    });
  });

  // =========================================================================
  // 排序
  // =========================================================================
  group('列表排序', () {
    test('未完成优先，其次优先级高的靠前', () async {
      final c = await makeContainer();
      // 故意打乱插入顺序
      await seed(
        title: '已完成高优先',
        priority: TodoPriority.high,
        completed: true,
      );
      await seed(title: '未完成低优先', priority: TodoPriority.low);
      await seed(title: '未完成高优先', priority: TodoPriority.high);

      final list = await readList(c);
      expect(list.map((t) => t.title).toList(), [
        '未完成高优先',
        '未完成低优先',
        '已完成高优先',
      ]);
    });
  });

  // =========================================================================
  // pendingCountProvider
  // =========================================================================
  group('未完成数量统计', () {
    /// 读一个 autoDispose 的 FutureProvider.family。
    ///
    /// 同 readList 的说明：直接 `read(provider.future)` 时没有订阅者，
    /// autoDispose 会在 loading 阶段就把 provider 销毁掉。
    /// 这里先 listen 占住订阅，取到值后再关闭。
    Future<int> readCount(ProviderContainer c, Scene scene) async {
      final p = pendingCountProvider(scene);
      final sub = c.listen(p, (_, _) {});
      try {
        return await c.read(p.future);
      } finally {
        sub.close();
      }
    }

    test('只统计指定场景的未完成项', () async {
      final c = await makeContainer();
      await seed(title: 's1', scene: Scene.study);
      await seed(title: 's2', scene: Scene.study);
      await seed(title: 's3', scene: Scene.study, completed: true);
      await seed(title: 'w1', scene: Scene.work);

      expect(await readCount(c, Scene.study), 2);
      expect(await readCount(c, Scene.work), 1);
      expect(await readCount(c, Scene.life), 0);
    });
  });

  // =========================================================================
  // 列表页 UI
  // =========================================================================
  group('待办列表页 UI', () {
    /// 【写库后推进界面：为什么不能用 pumpAndSettle】
    ///
    /// 涉及「写数据库 + 界面原地更新（条目仍存在）」的操作，
    /// `pumpAndSettle()` 会**不收敛**，一路泵到 10 分钟超时抛
    /// `TimeoutException`。原因是它的循环：
    /// ```dart
    /// do { await binding.pump(100ms); } while (binding.hasScheduledFrame);
    /// ```
    /// 只看 `hasScheduledFrame`。而「写库 → drift stream 推送 →
    /// todoListProvider 发新值 → TodoListPage 重建 → TodoTile/Checkbox
    /// 重建并重启 Material 涟漪动画」这条链在 fake 时钟下持续调度新帧，
    /// 于是 `hasScheduledFrame` 长期为 true。
    /// （对比：删除会让条目消失、ListView 变空；校验失败不写库 ——
    ///   这两种情况动画会自然结束，故可以正常 settle。）
    ///
    /// 因此改用**有限次 pump**：先小幅多次推进，让 drift 的异步写库与
    /// stream 推送有机会完成；再推进一段时长让收尾动画（页面转场 / 涟漪）
    /// 结束。整个过程最多 12 帧，**不会无限等待**。
    /// 注意：这里**没有**使用任何依赖时钟的轮询，符合本项目测试铁律。
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 【drift 的 pending timer 问题 —— 已在 production 代码层根治】
    /// 早期版本这里放了一个 `unmount` helper，靠 `addTearDown` 里换空 widget
    /// 再 `pump` 去"排干" drift 关闭订阅时排的 0 时长 timer。**那套方案是错的**：
    /// flutter_test 的 `_verifyInvariants`（断言 `!timersPending`）在测试体结束时
    /// **立即**执行，早于任何 `addTearDown`，根本来不及补救。
    ///
    /// 正解写在 `AppDatabase.forTesting`：用
    /// `DatabaseConnection(executor, closeStreamsSynchronously: true)` 构造，
    /// 让 drift 的 `markAsClosed` 走同步分支、**从源头不创建 timer**。
    /// 详见 lib/core/database/database.dart 的注释。
    ///
    /// 因此这里不再需要任何收尾动作，测试保持干净。
    Future<void> pumpPage(WidgetTester tester) async {
      final settings = await SettingsService.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: TodoListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空列表显示空状态与新增引导', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有待办'), findsOneWidget);
      expect(find.text('点右下角「新增待办」开始记录'), findsOneWidget);
    });

    testWidgets('渲染待办条目：标题、场景、优先级', (tester) async {
      await seed(
        title: '完成项目文档',
        scene: Scene.work,
        priority: TodoPriority.high,
      );
      await pumpPage(tester);

      expect(find.text('完成项目文档'), findsOneWidget);
      expect(find.text('工作'), findsWidgets);

      // 优先级标签在 tile 内
      expect(
        find.descendant(
          of: find.byType(TodoTile),
          matching: find.text('高'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('点复选框可勾选完成', (tester) async {
      final id = await seed(title: '可勾选任务');
      await pumpPage(tester);

      final checkbox = find.descendant(
        of: find.byType(TodoTile),
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);

      await tester.tap(checkbox);
      // 写库 + 界面原地更新 → 不能用 pumpAndSettle（见 settleAfterWrite 说明）
      await settleAfterWrite(tester);

      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      // 库里也应为已完成。
      // 【⚠️ 必须用 findById，不能用 watchAll().first】
      // testWidgets 跑在 FakeAsync zone 里：`watchAll()` 的首值要经过
      // 「订阅 → fetchAndEmitData → await 查询 → listener.add」一串 await，
      // 且**需要 tester.pump 驱动时钟**才会到达；测试体里没有 pump 去推它，
      // 于是 `await watchAll().first` **永久挂起**（10 分钟后被测试级超时杀掉）。
      // 而 findById 是一次性查询（getSingleOrNull），microtask 即可完成，不依赖时钟。
      final todo = (await db.todoDao.findById(id))!;
      expect(todo.isCompleted, isTrue);
      expect(todo.completedAt, isNotNull);
    });

    testWidgets('长按弹出删除确认，确认后删除', (tester) async {
      await seed(title: '要删除的任务');
      await pumpPage(tester);

      await tester.longPress(find.byType(TodoTile));
      await tester.pumpAndSettle();

      expect(find.text('删除待办'), findsOneWidget);
      expect(find.textContaining('要删除的任务'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(await db.todoDao.countAll(), 0);
      expect(find.text('要删除的任务'), findsNothing);
    });

    testWidgets('长按后取消删除，数据保留', (tester) async {
      await seed(title: '不该删的任务');
      await pumpPage(tester);

      await tester.longPress(find.byType(TodoTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(await db.todoDao.countAll(), 1);
      expect(find.text('不该删的任务'), findsOneWidget);
    });

    testWidgets('切换场景筛选后列表同步更新', (tester) async {
      await seed(title: '学习任务', scene: Scene.study);
      await seed(title: '工作任务', scene: Scene.work);
      await pumpPage(tester);

      expect(find.byType(TodoTile), findsNWidgets(2));

      // 点筛选栏的「学习」（注意页面还有导航等文本，这里限定在 ChoiceChip 内）
      await tester.tap(
        find.widgetWithText(ChoiceChip, '学习'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TodoTile), findsOneWidget);
      expect(find.text('学习任务'), findsOneWidget);
      expect(find.text('工作任务'), findsNothing);
    });

    testWidgets('筛选后无结果显示"没有符合条件的待办"', (tester) async {
      await seed(title: '只有工作任务', scene: Scene.work);
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '学习'));
      await tester.pumpAndSettle();

      expect(find.text('没有符合条件的待办'), findsOneWidget);
    });

    testWidgets('点「新增待办」打开表单页，保存后回到列表并显示新项', (tester) async {
      await pumpPage(tester);
      expect(find.text('还没有待办'), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, '新增待办'));
      await tester.pumpAndSettle();
      expect(find.text('新增待办'), findsWidgets); // AppBar 标题
      expect(find.byType(TodoFormPage), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '从列表页新建的任务',
      );
      await tester.tap(find.widgetWithText(FilledButton, '创建待办'));
      await tester.pumpAndSettle();

      // 回到列表页，新项出现
      expect(find.byType(TodoFormPage), findsNothing);
      expect(find.text('从列表页新建的任务'), findsOneWidget);
    });

    testWidgets('点条目打开编辑页并回填', (tester) async {
      await seed(title: '点击编辑我');
      await pumpPage(tester);

      await tester.tap(find.byType(TodoTile));
      await tester.pumpAndSettle();

      expect(find.byType(TodoFormPage), findsOneWidget);
      expect(find.text('编辑待办'), findsOneWidget);
      expect(find.text('点击编辑我'), findsWidgets);
    });
  });

  // =========================================================================
  // 表单页 UI
  // =========================================================================
  group('待办表单页', () {
    /// 写库 + `Navigator.pop` 返回列表后，列表 stream 会推送新数据并重建。
    /// 同列表页 group 的 `settleAfterWrite`：用有限次 pump 代替
    /// `pumpAndSettle`，避免「写库 → stream 推送 → 原地重建 → 动画重启」
    /// 使 `hasScheduledFrame` 长期为 true 而导致 pumpAndSettle 超时。
    Future<void> settleAfterWrite(WidgetTester tester) async {
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 把表单页 push 到一个真实导航栈上（而不是当根路由），
    /// 这样保存后的 `Navigator.pop` 行为与线上一致。
    Future<void> pumpForm(WidgetTester tester, {Todo? todo}) async {
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
                        builder: (_) => TodoFormPage(todo: todo),
                      ),
                    ),
                    child: const Text('打开表单'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();
      // 无需收尾：drift 的 pending timer 已在 AppDatabase.forTesting 层根治
      // （closeStreamsSynchronously: true），详见该文件注释。
    }

    testWidgets('新增模式：标题为空时保存被拦截并提示', (tester) async {
      await pumpForm(tester);
      expect(find.text('新增待办'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '创建待办'));
      await tester.pumpAndSettle();

      expect(find.text('请输入标题'), findsOneWidget);
      expect(await db.todoDao.countAll(), 0, reason: '校验失败不应写库');
    });

    testWidgets('新增模式：填标题后保存成功并写库', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '新的一条待办',
      );
      // 选「工作」场景
      await tester.tap(find.text('工作'));
      await tester.pumpAndSettle();
      // 选高优先级
      await tester.tap(find.widgetWithText(ChoiceChip, '高'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '创建待办'));
      // 保存成功会写库并 pop 回列表 → 列表原地重建，不能用 pumpAndSettle
      await settleAfterWrite(tester);

      // 【⚠️ 用 findAll() 而不是 watchAll().first】
      // testWidgets 在 FakeAsync zone 里，`watchAll().first` 的首值需要
      // tester.pump 驱动时钟才会到达，测试体里会永久挂起（详见 findById 处注释）。
      final list = await db.todoDao.findAll();
      expect(list.length, 1);
      expect(list.single.title, '新的一条待办');
      expect(list.single.scene, 'work');
      expect(list.single.priority, TodoPriority.high.value);
    });

    testWidgets('编辑模式：回填原值，修改后保存', (tester) async {
      final id = await seed(
        title: '原标题',
        scene: Scene.study,
        priority: TodoPriority.low,
      );
      final todo = (await db.todoDao.findById(id))!;

      await pumpForm(tester, todo: todo);
      expect(find.text('编辑待办'), findsOneWidget);
      expect(find.text('原标题'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, '标题'),
        '改后标题',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      // 写库 + pop → 同上，用有限 pump 代替 pumpAndSettle
      await settleAfterWrite(tester);

      final updated = (await db.todoDao.findById(id))!;
      expect(updated.title, '改后标题');
      expect(updated.scene, 'study', reason: '未改动的字段应保持');
      expect(updated.priority, TodoPriority.low.value);
    });

    testWidgets('编辑模式：标题清空后保存被拦截', (tester) async {
      final id = await seed(title: '原标题');
      final todo = (await db.todoDao.findById(id))!;

      await pumpForm(tester, todo: todo);
      await tester.enterText(find.widgetWithText(TextFormField, '标题'), '');
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await tester.pumpAndSettle();

      expect(find.text('请输入标题'), findsOneWidget);
      final unchanged = (await db.todoDao.findById(id))!;
      expect(unchanged.title, '原标题', reason: '校验失败不应改库');
    });
  });
}
