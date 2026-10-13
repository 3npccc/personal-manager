import 'package:flutter/material.dart';

import 'books/book_list_page.dart';
import 'checkins/checkin_page.dart';
import 'courses/course_list_page.dart';
import 'goals/study_goal_page.dart';

/// 学习管理（阶段 4.4）。
/// 内部 4 个 Tab：读书 / 课程 / 打卡 / 目标。
///
/// 【为什么每个 Tab 自带 `Scaffold` + FAB】
/// `TabBarView` 的每个子页需要一个自己的 `Scaffold` 才能浮起 FAB；
/// 若共用一个外层 `Scaffold`，四个页面的 FAB 会互相打架。
/// 外层这个 `Scaffold` 只负责 `TabBar`（AppBar）。
class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('学习管理'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '读书', icon: Icon(Icons.menu_book, size: 20)),
              Tab(text: '课程', icon: Icon(Icons.school, size: 20)),
              Tab(text: '打卡', icon: Icon(Icons.event_available, size: 20)),
              Tab(text: '目标', icon: Icon(Icons.flag, size: 20)),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            BookListPage(),
            CourseListPage(),
            CheckinPage(),
            StudyGoalPage(),
          ],
        ),
      ),
    );
  }
}
