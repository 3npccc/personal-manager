import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/nav_destinations.dart';
import 'core/providers.dart';
import 'features/backup/ui/backup_page.dart';
import 'features/home/ui/home_page.dart';
import 'features/ledger/ui/ledger_page.dart';
import 'features/life/ui/life_page.dart';
import 'features/notes/ui/note_list_page.dart';
import 'features/settings/ui/settings_page.dart';
import 'features/study/ui/study_page.dart';
import 'features/todos/ui/todo_list_page.dart';
import 'features/work/ui/work_page.dart';
import 'shared/widgets/glass_panel.dart';
import 'shared/widgets/motion.dart';
/// 应用外壳：左侧 NavigationRail + 右侧 IndexedStack 内容区。
/// - 当前页索引由 `navIndexProvider` 管理，会持久化到 shared_preferences。
/// - 用 IndexedStack 保留各页面状态，切换不重建。
/// - 导航栏是**真毛玻璃**（`BackdropFilter`），透出的是 [AppBackground]
///   画在 `MaterialApp.builder` 里的柔和品牌色渐变。
///
/// ## 为什么毛玻璃需要 [AppBackground] 配合
///
/// `BackdropFilter` 模糊的是"它背后已经画出来的像素"。如果背后是**纯色**，
/// 模糊前后完全一样，视觉上等于没有玻璃 —— 这是最常见的"毛玻璃做不出来"
/// 的原因。所以磨砂效果需要**有层次、有明暗**的背景才成立。
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  /// 按 kNavDestinations 顺序对应的页面
  static const List<Widget> _pages = <Widget>[
    HomePage(),
    TodoListPage(),
    NoteListPage(),
    LedgerPage(),
    StudyPage(),
    WorkPage(),
    LifePage(),
    BackupPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      _pages.length == kNavDestinations.length,
      '导航项数量必须与页面数量一致',
    );

    final index = ref.watch(navIndexProvider);
    // 兜底：配置里的 index 可能因导航项调整而越界
    final safeIndex = (index >= 0 && index < _pages.length) ? index : 0;

    return Scaffold(
      // 透明：让 MaterialApp.builder 里的 [AppBackground] 一路透上来
      backgroundColor: Colors.transparent,
      body: Row(
        children: <Widget>[
          _GlassNavigationRail(
            selectedIndex: safeIndex,
            onDestinationSelected: ref.read(navIndexProvider.notifier).select,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: safeIndex,
              children: <Widget>[
                for (var i = 0; i < _pages.length; i++)
                  FadeSlideIn(
                    // 只传 `active`：切到第 i 页时它由 false 变 true，
                    // 触发一次入场动画；退到后台的那一页不会播（省 CPU）。
                    active: i == safeIndex,
                    child: _pages[i],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 毛玻璃导航栏。
///
/// 用 [GlassPanel] 包住 `NavigationRail`，并把 Rail 自己的背景设为透明
/// （否则它会在玻璃上又盖一层不透明色，玻璃就白做了）。
class _GlassNavigationRail extends StatelessWidget {
  const _GlassNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      // 导航栏贴着窗口左/上/下边缘，圆角只在右侧 —— 更贴近 iOS 侧边栏观感
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
      blur: 14,
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType: NavigationRailLabelType.all,
        // 关键：Rail 自身背景透明，玻璃才透得出来
        backgroundColor: Colors.transparent,
        indicatorColor: theme.colorScheme.secondaryContainer,
        destinations: <NavigationRailDestination>[
          for (final dest in kNavDestinations)
            NavigationRailDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.selectedIcon),
              label: Text(dest.label),
            ),
        ],
      ),
    );
  }
}
