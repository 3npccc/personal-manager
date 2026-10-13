import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/theme/glass_tokens.dart';
import 'glass_panel.dart';

/// 统一的删除 / 危险操作确认弹窗。
/// 返回 true 表示用户确认，false / null 表示取消。
///
/// 【弹窗是真毛玻璃】弹窗同时只会存在一个，数量固定，所以这里用
/// [GlassPanel]（真 `BackdropFilter`）—— 弹出时能透过它看到被模糊的页面，
/// 是 iOS 弹窗最标志性的观感。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool isDanger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Dialog(
        // 去掉 Material 默认的不透明底色，改由 [GlassPanel] 提供
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: GlassPanel(
          borderRadius: GlassTokens.radius,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppDialogText.title(ctx)),
              const SizedBox(height: 10),
              Text(message, style: AppDialogText.body(ctx)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(cancelText),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: isDanger
                        ? FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          )
                        : null,
                    child: Text(confirmText),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// 弹窗内的文字样式。
///
/// 【为什么单独放着而不是直接用 textTheme】
/// 弹窗现在是自己搭的（不再是 `AlertDialog`），`titleMedium` / `bodyMedium`
/// 的字号在 24px 内边距的窄弹窗里偏小，需要比页面正文略微放大一档。
/// 但**字重仍然走全局两级制**（标题 w600 / 正文 w400），不破例。
class AppDialogText {
  AppDialogText._();

  static TextStyle title(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontWeight: AppTypography.titleWeight,
      height: 1.3,
    );
  }

  static TextStyle body(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontWeight: AppTypography.bodyWeight,
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
  }
}
