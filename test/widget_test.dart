import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/app.dart';
import 'package:personal_manager/core/database/database.dart';
import 'package:personal_manager/core/database/database_providers.dart';
import 'package:personal_manager/core/providers.dart';
import 'package:personal_manager/core/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('导航栏 9 项全部渲染，点击可切换', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = await SettingsService.create();

    // 【⚠️ 必须 override appDatabaseProvider】
    // `AppShell` 用 `IndexedStack` **同时构建全部 9 个页面**，
    // 因此 `TodoListPage` 也会被构建并订阅 drift stream。
    // 不 override 就会走生产库（文件库）—— 在 FakeAsync zone 里永不完成，
    // 界面持续调度帧 → `pumpAndSettle timed out`。
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const PersonalManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 9 个导航项全部存在
    for (final label in const <String>[
      '概览',
      '待办',
      '笔记',
      '记账',
      '学习',
      '工作',
      '生活',
      '备份恢复',
      '设置',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少导航项：$label');
    }

    // 点击「记账」后应切到记账页。
    //
    // 【⚠️ 不能用「记账页里的某个 widget 存在」来断言】
    // `AppShell` 用 `IndexedStack(index:, children: _pages)` —— 它会
    // **同时构建全部 9 个页面**（只显示当前项），所以 `LedgerPage` 的
    // FAB「记一笔」**从一开始就在树上**，那种断言无论切没切都成立，等于没测。
    // 真正能验证"切换生效"的是 `IndexedStack.index`（第 4 项 = 索引 3）。
    //
    // 【顺带记录】原来这里写的是 `textContaining('收支记录与月度统计')`，
    // 那是我**凭想象编的文案**，lib/ 里根本不存在（已删）。
    await tester.tap(find.text('记账').first);
    await tester.pumpAndSettle();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 3, reason: '点「记账」后 IndexedStack 应切到第 4 项（索引 3）');
  });
}
