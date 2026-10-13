import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/app_background.dart';

/// 根组件：MaterialApp + 主题 + 中文 locale
class PersonalManagerApp extends ConsumerWidget {
  const PersonalManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: '个人管理',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      // 【为什么背景放在这里，而不是放在 AppShell 里】
      // `builder` 包裹的是**整个 Navigator**，所以每一层路由（push 出来的
      // 新增/编辑表单页、分类管理页…）都在它上面。放这里能保证：
      //   ① 所有页面的 Scaffold 背景都透明时，背后始终有渐变底兜着；
      //   ② 不会出现"从主页 push 到表单页后渐变底消失、背景变纯色"的跳变。
      builder: (context, child) {
        return Stack(
          children: <Widget>[
            const Positioned.fill(child: AppBackground()),
            ?child,
          ],
        );
      },
      home: const AppShell(),
    );
  }
}
