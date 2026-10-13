import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/shared/widgets/motion.dart';

/// 全局测试配置 —— Flutter 会自动加载 `test/flutter_test_config.dart`
/// 并用它的 `testExecutable` 包裹**每一个**测试文件。
///
/// ## 这里做了一件关键的事：关掉入场动效
///
/// 项目在 UI 里引入了错峰入场 / 页面切换动效（见 `shared/widgets/motion.dart`）。
/// 这些动画会让首帧处于"透明度 0、位置偏移"的中间态，对测试有两个坏处：
///
/// 1. 断言会读到过渡值，而不是最终值；
/// 2. `tester.tap()` 命中已偏移 / 不可见的区域时会报警甚至点不到。
///
/// 逐个测试文件去加 `await tester.pumpAndSettle()` 是不可行的：
/// 既有用例大量刻意用 `pump()` + 精确帧数来控制状态（比如验证
/// "第 N 帧还在 loading"），强行改成 `pumpAndSettle` 会**抹掉这些用例的
/// 精确性**，属于降低验收标准。
///
/// 所以这里统一把 [debugMotionEnabled] 置为 false：此时动效组件
/// （`FadeSlideIn` / `StaggeredListItem`）**直接返回 child，不包任何
/// `Opacity` / `Transform`** —— widget 树结构与"没有动效"的版本逐字节
/// 一致，全部既有用例照常工作。
///
/// 动效本身由 `test/motion_test.dart` 显式打开开关后专门验证。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() {
    // 全局关掉；个别用例可自行暂时打开（见 motion_test.dart）
    debugMotionEnabled = false;
  });
  await testMain();
}
