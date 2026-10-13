import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/settings/settings_service.dart';
import 'features/backup/backup_providers.dart';

/// 程序入口。
///
/// 先把 SettingsService 初始化好（含数据库路径），再用 override 注入到
/// ProviderScope，这样所有页面都能同步读到设置，不需要在各处 await。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final documentsDir = await _resolveDocumentsDir();
  final databasePath =
      documentsDir == null ? null : p.join(documentsDir.path, 'personal_manager.sqlite');
  final settings = await SettingsService.create(databasePath: databasePath);

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settings),
        // 恢复前的自动兜底备份与数据库同目录，方便用户一起备份走。
        autoBackupBaseDirProvider.overrideWithValue(
          documentsDir ?? Directory.systemTemp,
        ),
      ],
      child: const PersonalManagerApp(),
    ),
  );
}

/// 解析「用户文档目录」。
///
/// 数据库（drift_flutter 默认）与恢复前的自动兜底备份都放在这里；
/// 若路径解析失败（极少数环境问题），返回 null —— 展示层会隐藏数据库路径，
/// 自动备份退到临时目录，绝不让它的失败阻断应用启动。
Future<Directory?> _resolveDocumentsDir() async {
  try {
    return await getApplicationDocumentsDirectory();
  } on Object catch (e) {
    debugPrint('解析文档目录失败（不影响启动）：$e');
    return null;
  }
}
