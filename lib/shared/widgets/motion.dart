import 'package:flutter/material.dart';

/// 动效总开关 —— **widget 测试必须在 setUp 里关掉它**。
///
/// ## 为什么需要这个全局开关
///
/// 错峰入场动画对测试不友好，原因有二：
///
/// 1. **需要等帧**：动画未跑完时 widget 停在中间态（透明度、位移都不是终值），
///    此时断言拿到的是过渡值，`tester.tap()` 打上去也可能因
///    `warnIfMissed` 因可点区域与命中区域偏差而报警。
/// 2. **测试要确定性**：项目里有数百个既有用例，大量刻意用 `pump()` +
///    精确帧数来控制状态。若每个用例都被迫改成 `pumpAndSettle()`，
///    既危险又抹掉了这些用例原有的精确性。
///
/// 所以：**测试里统一关掉动效**（`debugMotionEnabled = false`），
/// 让被测 widget 树回到"无动画"的确定性状态；动效本身另用
/// 少量专门用例（显式打开）来验证。
///
/// 用法（`test/` 里的 `setUp`）：
/// ```dart
/// setUp(() => debugMotionEnabled = false);
/// tearDown(() => debugMotionEnabled = true);
/// ```
bool debugMotionEnabled = true;

/// 入场动效：淡入 + 轻微上移。
///
/// ## 为什么需要它
///
/// `AppShell` 用 `IndexedStack` 保留 9 个页面的状态（切换不重建），
/// 代价是**切换是瞬时的** —— 视觉上像"啪"地换了一屏，缺少空间感。
///
/// 直接在外面套 `AnimatedSwitcher` 是不行的：`IndexedStack` 的 9 个
/// children **始终都被构建**，套在外层只会让"整个 Stack"做一次动画，
/// 切页时反而没有效果。
///
/// ## ⚠️ 为什么用「显式 [active] 标记」而不是 TickerMode
///
/// 一个自然的想法是：`IndexedStack` 的子节点在不可见时会被 `Offstage`
/// 包住，于是可以从 `TickerMode.of(context)` 判断"我是否在前台"。
///
/// **这是错的。** `Offstage`（`IndexedStack` 用的就是它）只是**跳过绘制**，
/// 并不会关闭 `TickerMode`；真正关 `TickerMode` 的是 `TabBarView` /
/// `Navigator` 这类带 `TickerMode` 的容器。所以靠 `TickerMode` 判断
/// 在 `IndexedStack` 场景下**永远为 true**，会导致每次依赖变化都重播动画。
///
/// 结论：由 `AppShell` **显式**把"你是否是当前页"传下来，最可靠。
///
/// 用法：
/// ```dart
/// FadeSlideIn(active: i == currentIndex, child: page)
/// ```
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.active = true,
    this.duration = const Duration(milliseconds: 260),
    this.offset = 12,
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;

  /// 是否处于"前台"。
  ///
  /// **由 false 变为 true** 时重播一次动画 —— 这正是"从别的页切到本页"。
  /// 反向（退到后台）不播：虽然后台重播看不见，却会让 9 个页面同时起
  /// 8 个无用动画，白白吃 CPU。
  final bool active;

  /// 动画时长。260ms：足够被感知，又不会让人等。
  final Duration duration;

  /// 起始位置的下移量（逻辑像素），动画结束时归零。
  final double offset;

  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // 首次挂载就播一次：首次进入也应有入场感。
    // 非活跃页（IndexedStack 里未被选中的那些）先停在起点，等切过去再播。
    if (widget.active && debugMotionEnabled) {
      _c.forward();
    } else {
      // 关掉动效时直接落到终值 —— 测试里就是"没有动画"的普通 widget
      _c.value = debugMotionEnabled ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(covariant FadeSlideIn old) {
    super.didUpdateWidget(old);
    // 只有"从非活跃变为活跃"才播
    if (widget.active && !old.active && debugMotionEnabled) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 动效关闭时**完全不包 Opacity/Transform** —— 让 widget 树结构和
    // "没有动效"的版本逐字节一致，既有测试的 finder 与 tap 全部照常工作。
    if (!debugMotionEnabled) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = widget.curve.transform(_c.value);
        return Opacity(
          opacity: t,
          // 用 Transform 而不是 AnimatedSlide：位移必须是**固定像素**，
          // 而 AnimatedSlide.offset 是相对自身尺寸的比例（见 HoverLift 注释）。
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 列表项错峰入场：每个 item 比前一个晚 [step] 出现。
///
/// ## 为什么需要错峰
///
/// 单纯让整个列表一起淡入，看着像"整块板子"在动；而**逐项依次**出现
/// 会形成从上到下的视线引导，是 iOS / Material 列表的通用做法。
///
/// ## 错峰上限
///
/// 第 [maxStagger] 项之后不再追加延迟 —— 否则长列表滚动到底部时，
/// 第 100 项要等 100×35ms = 3.5 秒才出现，那就变成 bug 了。
class StaggeredListItem extends StatefulWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 35),
    this.maxStagger = 12,
    this.duration = const Duration(milliseconds: 240),
  });

  /// 在列表中的位置（从 0 开始）。
  final int index;

  final Widget child;

  /// 每项之间的间隔。
  final Duration step;

  /// 参与错峰的最大项数，超出后统一用最后一档延迟。
  final int maxStagger;

  final Duration duration;

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// 这一项的实际延迟（已按 [StaggeredListItem.maxStagger] 封顶）。
  late final Duration _delay;

  @override
  void initState() {
    super.initState();
    final capped = widget.index.clamp(0, widget.maxStagger);
    _delay = widget.step * capped;
    // 总时长 = 延迟 + 动画时长，用 Interval 把前段"空转"掉。
    //
    // ⚠️ 【为什么不用 Future.delayed】
    // `Future.delayed` 在 widget 测试里是一颗定时器炸弹：
    //   ① 若测试在延迟结束前结束，会报 "A Timer is still pending"；
    //   ② `pumpAndSettle` 的判定依赖帧调度，挂起的 Future 会让它
    //      要么提前返回、要么空等到超时。
    // 用 `Interval` 让延迟成为**同一条时间轴上的空转段**后，
    // 整条动画就是一个普通 Ticker，`pumpAndSettle` 能精确等到它结束。
    _c = AnimationController(
      vsync: this,
      duration: _delay + widget.duration,
    );
    if (debugMotionEnabled) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!debugMotionEnabled) {
      return widget.child;
    }
    final total = (_delay + widget.duration).inMilliseconds;
    final start = total == 0 ? 0.0 : _delay.inMilliseconds / total;
    final curve = Interval(
      start,
      1,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = curve.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
