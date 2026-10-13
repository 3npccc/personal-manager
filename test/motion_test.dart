import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/shared/widgets/glass_panel.dart';
import 'package:personal_manager/shared/widgets/motion.dart';

/// UI 动效组件测试。
///
/// ## 为什么这个文件要**显式打开**动效
///
/// `test/flutter_test_config.dart` 全局把 [debugMotionEnabled] 关掉了
/// （理由见那个文件的注释：既有 470 个用例都依赖"无动画"的确定性行为）。
/// 但动效本身也是功能，不能没人测 —— 所以这里在需要动效的用例里
/// **显式打开**，用完再关回去。
///
/// ## 覆盖点
///
/// 1. 关闭开关时：组件**不包裹任何 Opacity/Transform**，直接透传 child；
/// 2. 打开开关时：初始帧处于"半透明 + 下移"，动画结束后恢复正常；
/// 3. 错峰：index 越大，动画结束得越晚（这是错峰的本质）；
/// 4. 错峰封顶：超过 maxStagger 后延迟不再增加。
void main() {
  tearDown(() {
    // 每个用例结束都恢复"关"（与 flutter_test_config 的全局设置一致），
    // 避免用例之间互相污染。
    debugMotionEnabled = false;
  });

  group('FadeSlideIn', () {
    testWidgets('关闭动效时直接透传 child，不插入 Opacity/Transform', (tester) async {
      debugMotionEnabled = false;

      // 【为什么不用 MaterialApp 包】
      // MaterialApp 内部自带大量 Opacity / Transform（路由过渡、图标、
      // InkWell 等），会让 `find.byType(Opacity)` 命中一堆无关节点，
      // 断言就失去意义（规则 48：多区块页面必须限定作用域）。
      // 这里用最小包裹，让"树里有没有 Opacity"这句话真的只针对被测组件。
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FadeSlideIn(child: Text('内容')),
        ),
      );

      // 关键断言：树里**没有** Opacity / Transform
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Transform), findsNothing);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('打开动效时先半透明，动画结束后完全不透明', (tester) async {
      debugMotionEnabled = true;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FadeSlideIn(
            active: true,
            duration: Duration(milliseconds: 200),
            child: Text('内容'),
          ),
        ),
      );

      // 首帧：动画刚起步，透明度应小于 1
      await tester.pump();
      final first = tester.widget<Opacity>(find.byType(Opacity));
      expect(
        first.opacity,
        lessThan(1.0),
        reason: '首帧应处于动画起点附近，透明度尚未达到 1',
      );

      // 跑完动画
      await tester.pumpAndSettle();
      final last = tester.widget<Opacity>(find.byType(Opacity));
      expect(last.opacity, 1.0, reason: '动画结束后应完全不透明');
    });

    testWidgets('active 由 false 变 true 触发一次动画', (tester) async {
      debugMotionEnabled = true;

      Widget build(bool active) => Directionality(
            textDirection: TextDirection.ltr,
            child: FadeSlideIn(
              active: active,
              duration: const Duration(milliseconds: 200),
              child: const Text('内容'),
            ),
          );

      // 先以 inactive 挂载（透明度停在 0 附近，动画未播）
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      final beforeOpacity =
          tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(beforeOpacity, 0.0, reason: '非活跃页应停在起点（完全透明）');

      // 切为 active -> didUpdateWidget 里 `_c.forward(from: 0)`：
      // 先把 value 拉回**起点**再启动 ticker。此时还没推进时间
      // （`pump()` 不带 duration = elapsed 0），所以应精确停在 0.0。
      //
      // 这里断言的是 **0.0 本身**，而不是"大于 0"：
      // 重播必须从起点开始；若沿用上一帧的残留值，就会出现"闪一下"的跳变。
      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        0.0,
        reason: '重播必须从起点（forward(from: 0)）开始，不允许残留旧值',
      );

      // 推进半程（时长 200ms，走 100ms）-> 应处于"飞行中"：0 < opacity < 1。
      // ⚠️ 必须**带 duration** 的 pump 才会推进时钟；裸 pump() 不推进，
      //    拿到的永远是起点值（这正是本用例最初失败的原因）。
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(mid, greaterThan(0.0), reason: '推进时间后应已开始淡入');
      expect(mid, lessThan(1.0), reason: '半程不应已经完成');

      await tester.pumpAndSettle();
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        1.0,
        reason: '动画结束后应完全不透明',
      );
    });
  });

  group('StaggeredListItem', () {
    testWidgets('关闭动效时直接透传 child', (tester) async {
      debugMotionEnabled = false;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: StaggeredListItem(index: 3, child: Text('第 4 项')),
        ),
      );

      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Transform), findsNothing);
      expect(find.text('第 4 项'), findsOneWidget);
    });

    testWidgets('index 越大越晚开始（错峰的本质）', (tester) async {
      debugMotionEnabled = true;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              StaggeredListItem(
                index: 0,
                step: Duration(milliseconds: 50),
                duration: Duration(milliseconds: 100),
                child: Text('A'),
              ),
              StaggeredListItem(
                index: 2,
                step: Duration(milliseconds: 50),
                duration: Duration(milliseconds: 100),
                child: Text('B'),
              ),
            ],
          ),
        ),
      );

      // 推进 100ms：index=0 的（0 延迟 + 100ms）应已完成；
      // index=2 的（100ms 延迟 + 100ms）才刚开始，透明度仍应明显低于 1。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities.length, 2);
      expect(
        opacities[0],
        greaterThan(opacities[1]),
        reason: 'index=0 应比 index=2 先完成淡入',
      );
    });

    testWidgets('超过 maxStagger 后延迟封顶（长列表不会等到天荒地老）',
        (tester) async {
      debugMotionEnabled = true;

      // index = maxStagger 与 index = maxStagger + 50 的延迟应完全相同。
      // 验证方式：两项同时在 100ms 内完成（延迟都是 maxStagger*step）。
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              StaggeredListItem(
                index: 5,
                step: Duration(milliseconds: 40),
                maxStagger: 5,
                duration: Duration(milliseconds: 80),
                child: Text('P'),
              ),
              StaggeredListItem(
                index: 99,
                step: Duration(milliseconds: 40),
                maxStagger: 5,
                duration: Duration(milliseconds: 80),
                child: Text('Q'),
              ),
            ],
          ),
        ),
      );

      // 5*40 + 80 = 280ms 之后两项都该完成
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities.length, 2);
      expect(
        opacities[0],
        moreOrLessEquals(opacities[1], epsilon: 0.001),
        reason: 'index 超过 maxStagger 后延迟应一致，二者透明度应相同',
      );
      expect(opacities[0], 1.0, reason: '封顶延迟后应在 280ms 内完成');
    });
  });

  group('HoverLift', () {
    testWidgets('鼠标进入时向上位移，离开时复位', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: HoverLift(lift: 2, child: Text('卡片'))),
        ),
      );

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // 移到 widget 上方
      await gesture.moveTo(tester.getCenter(find.text('卡片')));
      await tester.pumpAndSettle();

      final hovered = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      // Matrix4 的平移分量在第 12/13/14 位（列主序）
      expect(
        hovered.transform!.storage[13],
        -2.0,
        reason: '悬停时应向上位移 2 像素',
      );

      // 移开
      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();
      final left = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(left.transform!.storage[13], 0.0, reason: '离开后应复位');
    });
  });
}
