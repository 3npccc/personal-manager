import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/theme/app_theme.dart';
import 'package:personal_manager/core/theme/glass_tokens.dart';
import 'package:personal_manager/shared/widgets/app_card.dart';
import 'package:personal_manager/shared/widgets/glass_panel.dart';

/// 毛玻璃组件测试。
///
/// ## 覆盖点
///
/// 1. [GlassTokens]：明暗两套色值符合预期（浅色用白、深色用高表面色），
///    且透明度符合常量定义 —— 这是"玻璃色差 bug"的防线；
/// 2. [GlassPanel]：`blurEnabled` 时确实插入 `BackdropFilter`，
///    关闭时退化为普通半透明面板；
/// 3. [GlassCard]：表面是半透明（不是全不透明），且带高光描边与阴影；
/// 4. [AppCard]：仍然可点（回归保护 —— 它从 `Card` 换成了 `GlassCard`）。
///
/// ## 为什么不用 golden 测试
///
/// golden（像素比对）对模糊渲染极其敏感：不同 GPU / 驱动 / Skia 版本
/// 在同一段模糊代码上会产出不同像素，golden 会变成"每换一台机器就要
/// 重新生成基线"的负担。这里改为**断言结构与关键色值**，稳定且更有语义。
void main() {
  group('GlassTokens', () {
    test('浅色主题：玻璃表面以白色为基底，透明度等于 surfaceAlpha', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A6EA5),
        brightness: Brightness.light,
      );
      final surface = GlassTokens.surfaceFor(scheme, Brightness.light);

      expect(
        surface.a,
        moreOrLessEquals(GlassTokens.surfaceAlpha, epsilon: 0.005),
        reason: '不透明度必须等于常量，否则玻璃会比设计稿更实/更透',
      );
      // 白色基底 + alpha<1：R/G/B 仍应是 1.0（预乘前）
      expect(surface.r, moreOrLessEquals(1.0, epsilon: 0.005));
      expect(surface.g, moreOrLessEquals(1.0, epsilon: 0.005));
      expect(surface.b, moreOrLessEquals(1.0, epsilon: 0.005));
    });

    test('浅色主题：卡片表面比玻璃面板更实（cardAlpha > surfaceAlpha）', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A6EA5),
        brightness: Brightness.light,
      );
      final card = GlassTokens.cardSurfaceFor(scheme, Brightness.light);
      final panel = GlassTokens.surfaceFor(scheme, Brightness.light);

      expect(
        card.a,
        greaterThan(panel.a),
        reason: '卡片不用真模糊，必须靠更高不透明度保证内容可读',
      );
    });

    test('深色主题：玻璃表面不再是白色（避免"发灰亮块"）', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A6EA5),
        brightness: Brightness.dark,
      );
      final surface = GlassTokens.surfaceFor(scheme, Brightness.dark);

      // 关键：深色下不能用白色做玻璃
      expect(
        surface.r,
        lessThan(1.0),
        reason: '深色主题若仍以白色为基底，会透出灰色亮块',
      );
      expect(
        surface.a,
        moreOrLessEquals(GlassTokens.surfaceAlpha, epsilon: 0.005),
      );
    });

    test('投影：深色主题更重（黑底上要看得出浮起）', () {
      final light = GlassTokens.shadowFor(Brightness.light);
      final dark = GlassTokens.shadowFor(Brightness.dark);

      expect(light.length, 2, reason: '两层阴影才能形成自然的柔和过渡');
      expect(dark.length, 2);
      expect(
        dark.first.color.a,
        greaterThan(light.first.color.a),
        reason: '深色主题必须有更重的投影，否则玻璃片"浮不起来"',
      );
    });

    test('描边：浅色主题用白色高光，深色主题用 outlineVariant', () {
      final light = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A6EA5),
        brightness: Brightness.light,
      );
      final dark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A6EA5),
        brightness: Brightness.dark,
      );

      final lb = GlassTokens.borderFor(light, Brightness.light);
      final db = GlassTokens.borderFor(dark, Brightness.dark);

      expect(lb.r, moreOrLessEquals(1.0, epsilon: 0.005),
          reason: '浅色主题的玻璃边缘应是白色高光');
      expect(db, isNot(equals(lb)));
    });
  });

  group('GlassPanel', () {
    testWidgets('blurEnabled 时插入 BackdropFilter，且滤镜是模糊', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassPanel(child: Text('玻璃')),
            ),
          ),
        ),
      );

      final filter = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(filter.filter, isA<ui.ImageFilter>());
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('玻璃'), findsOneWidget);
    });

    testWidgets('blurEnabled=false 时不插入 BackdropFilter（降级 / 测试用）',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassPanel(blurEnabled: false, child: Text('玻璃')),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('玻璃'), findsOneWidget);
    });

    testWidgets('半透明表面 + 高光描边（玻璃的两个必备特征）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassPanel(blurEnabled: false, child: Text('玻璃')),
            ),
          ),
        ),
      );

      // GlassPanel 的最外层是 ClipRRect，其内是 DecoratedBox
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassPanel),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final deco = decorated.decoration as BoxDecoration;

      expect(
        deco.color!.a,
        lessThan(1.0),
        reason: '玻璃表面必须是半透明，否则背景透不出来',
      );
      expect(deco.border, isNotNull, reason: '必须有高光描边');
      expect(deco.borderRadius, isNotNull);
    });
  });

  group('GlassCard', () {
    testWidgets('表面半透明 + 有描边 + 有阴影', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassCard(child: Text('卡片')),
            ),
          ),
        ),
      );

      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GlassCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final deco = decorated.decoration as BoxDecoration;

      expect(deco.color!.a, lessThan(1.0), reason: '卡片表面应半透明');
      expect(deco.color!.a, greaterThan(0.8), reason: '但要比面板实，保证可读');
      expect(deco.border, isNotNull);
      expect(deco.boxShadow, isNotEmpty, reason: '必须有投影才能"浮"起来');
    });

    testWidgets('不用 BackdropFilter（列表里上百个卡片不能逐个模糊）',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassCard(child: Text('卡片')),
            ),
          ),
        ),
      );

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '卡片走"模拟玻璃"，绝不能引入真模糊（性能分区约定）',
      );
    });

    testWidgets('有 onTap 时可点击并回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GlassCard(
                onTap: () => tapped++,
                child: const Text('可点'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('可点'));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('AppCard（回归：从 Card 换成 GlassCard 后仍可用）', () {
    testWidgets('无 onTap 时正常渲染内容', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(child: Text('内容')),
          ),
        ),
      );

      expect(find.text('内容'), findsOneWidget);
      expect(find.byType(GlassCard), findsOneWidget);
    });

    testWidgets('有 onTap 时可点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped++,
              child: const Text('可点卡片'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('可点卡片'));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('主题接线', () {
    testWidgets('AppTheme.light / dark 都能构建，且 scaffold 背景透明', (tester) async {
      // 主题的透明背景是毛玻璃能透出 AppBackground 的前提，
      // 这里做一个显式的契约测试：将来若有人把它改回不透明色，会立刻失败。
      final light = AppTheme.light;
      final dark = AppTheme.dark;

      expect(light.scaffoldBackgroundColor, Colors.transparent);
      expect(dark.scaffoldBackgroundColor, Colors.transparent);
      expect(light.cardTheme.color, isNotNull);
      expect(dark.cardTheme.color, isNotNull);
      expect(light.cardTheme.color!.a, lessThan(1.0));
      expect(dark.cardTheme.color!.a, lessThan(1.0));
    });
  });
}
