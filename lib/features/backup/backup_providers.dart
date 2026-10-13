import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import 'services/backup_service.dart';
import 'services/export_service.dart';

/// 备份 = JSON / CSV 导出的出口。
final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(appDatabaseProvider)),
);

/// 恢复 = 校验 + 自动兜底备份 + 事务写回。
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(appDatabaseProvider),
    exportService: ref.watch(exportServiceProvider),
  ),
);

/// 「选目录 / 选文件 / 保存文件」这类**系统对话框**的抽象。
///
/// 【为什么必须抽成接口】
/// 1. **可测试性**：`FilePicker` 会弹出真实的 Windows 文件对话框，
///    widget 测试里没法点（会挂住）。注入假实现后，测试可以精确控制
///    "用户选了哪个目录 / 点了取消"两条路径，把页面逻辑测干净。
/// 2. **可替换性**：将来若要换成"最近使用目录"记忆、或换成拖拽入，
///    只改这一个实现，页面不动。
///
/// 约定：所有方法**返回 null 表示用户取消**（不抛异常），
/// 让调用方统一按"取消 = 什么都不做"处理。
abstract class BackupFilePicker {
  /// 选一个目录（备份导出用）。
  Future<String?> pickDirectory({String? dialogTitle});

  /// 选一个已存在的文件（恢复用）。
  Future<String?> pickJsonFile({String? dialogTitle});

  /// 让用户选保存位置并写出文件（一键保存 JSON 到任意位置）。
  Future<String?> saveFile({
    required String fileName,
    required List<int> bytes,
  });
}

/// 生产实现：走 [FilePicker]。
class SystemBackupFilePicker implements BackupFilePicker {
  const SystemBackupFilePicker();

  @override
  Future<String?> pickDirectory({String? dialogTitle}) {
    return FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
  }

  @override
  Future<String?> pickJsonFile({String? dialogTitle}) async {
    // 【注意】file_picker 13.x 的 `FilePicker` 是 `abstract final class`，
    // 方法**全部是 static**（没有 `FilePicker.platform` 这个实例 getter ——
    // 那是 8.x 之前的旧 API）。`pickFiles` 返回 `List<PlatformFile>`
    // （用户取消时是**空列表**，不是 null）。
    final files = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (files.isEmpty) return null;
    return files.first.path;
  }

  @override
  Future<String?> saveFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );
    return uri?.toFilePath();
  }
}

/// 可被测试 override 的文件选择器。
final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => const SystemBackupFilePicker(),
);

/// 自动兜底备份的根目录（恢复前的自动备份写到这里）。
///
/// 【为什么要单独一个 provider】测试里要把它指到临时目录，
/// 避免污染用户真实的「文档」目录。
final autoBackupBaseDirProvider = Provider<Directory>((ref) {
  throw UnimplementedError(
    'autoBackupBaseDirProvider 必须 override（生产在 main() 注入文档目录）',
  );
});
