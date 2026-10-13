import 'package:flutter/material.dart';

import 'journals/journal_list_page.dart';
import 'logs/work_log_list_page.dart';
import 'projects/project_list_page.dart';
import 'reports/report_page.dart';

/// 工作管理（阶段 4.5）。
/// 内部 4 个 Tab：项目 / 工时 / 周报 / 日志。
///
/// 【为什么每个 Tab 自带 `Scaffold` + FAB】
/// 与 4.4 学习管理同构：`TabBarView` 的每个子页需要自己的 `Scaffold`
/// 才能浮起各自的 FAB；若共用一个外层 `Scaffold`，四个页面的 FAB
/// 会互相打架。外层这个 `Scaffold` 只负责 `TabBar`（AppBar）。
class WorkPage extends StatelessWidget {
  const WorkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('工作管理'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '项目', icon: Icon(Icons.folder_special, size: 20)),
              Tab(text: '工时', icon: Icon(Icons.timer, size: 20)),
              Tab(text: '周报', icon: Icon(Icons.description, size: 20)),
              Tab(text: '日志', icon: Icon(Icons.edit_note, size: 20)),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            ProjectListPage(),
            WorkLogListPage(),
            ReportPage(),
            JournalListPage(),
          ],
        ),
      ),
    );
  }
}
