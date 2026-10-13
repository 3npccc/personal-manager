import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 统一的 loading / error / data 三态视图。
///
/// 用于包装所有 `AsyncValue` 数据源，让"加载中""失败""空列表""有数据"
/// 四种情况在各页面表现一致。
///
/// 用法：
/// ```dart
/// final todos = ref.watch(todoListProvider);
/// AsyncValueView<List<Todo>>(
///   value: todos,
///   emptyBuilder: (list) => list.isEmpty,
///   empty: const EmptyState(icon: Icons.inbox, title: '还没有待办'),
///   data: (list) => ListView(...),
/// )
/// ```
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.empty,
    this.isEmpty,
    this.onRetry,
  });

  /// 要渲染的异步值
  final AsyncValue<T> value;

  /// 有数据时的构建器
  final Widget Function(T data) data;

  /// 自定义加载态（默认居中转圈）
  final Widget? loading;

  /// 自定义错误态；不传则使用内置错误视图
  final Widget? error;

  /// 判断数据为"空"时的视图
  final Widget? empty;

  /// 判定数据是否视为空
  final bool Function(T data)? isEmpty;

  /// 错误态的"重试"回调；不传则不显示重试按钮
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => loading ?? const Center(child: CircularProgressIndicator()),
      error: (err, stack) => error ?? ErrorView(error: err, onRetry: onRetry),
      data: (d) {
        if (empty != null && isEmpty != null && isEmpty!(d)) {
          return empty!;
        }
        return data(d);
      },
    );
  }
}

/// 内置错误视图：图标 + 简短说明 + 可选详情展开 + 重试
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.title = '加载失败',
  });

  final Object error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一的加载视图（局部加载用，例如按钮内、卡片内）
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
