import 'package:flutter/material.dart';

import 'habits/habit_list_page.dart';
import 'health/health_list_page.dart';
import 'memos/memo_list_page.dart';

/// 生活管理（阶段 4.6）。
/// 内部 3 个 Tab：习惯 / 健康 / 备忘。
///
/// 【为什么每个 Tab 自带 `Scaffold` + FAB】
/// `TabBarView` 的每个子页需要一个自己的 `Scaffold` 才能浮起 FAB；
/// 若共用一个外层 `Scaffold`，三个页面的 FAB 会互相打架。
/// 外层这个 `Scaffold` 只负责 `TabBar`（AppBar）—— 与 `StudyPage` 同构。
class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('生活管理'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '习惯', icon: Icon(Icons.repeat, size: 20)),
              Tab(text: '健康', icon: Icon(Icons.monitor_heart, size: 20)),
              Tab(text: '备忘', icon: Icon(Icons.push_pin, size: 20)),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            HabitListPage(),
            HealthListPage(),
            MemoListPage(),
          ],
        ),
      ),
    );
  }
}
