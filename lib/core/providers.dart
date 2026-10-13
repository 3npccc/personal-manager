import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation/nav_destinations.dart';
import 'settings/settings_service.dart';

/// 设置服务实例。
/// 在 main() 中通过 override 注入已初始化的实例，
/// 因此这里默认实现用 throw 提示"必须先 override"。
final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError(
    'settingsServiceProvider 必须在 ProviderScope 中用 override 注入',
  );
});

/// 主题模式（跟随设置服务，可读写）
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ref.read(settingsServiceProvider).themeMode;
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(settingsServiceProvider).setThemeMode(mode);
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// 货币符号（跟随设置服务，可读写）
class CurrencySymbolNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.read(settingsServiceProvider).currencySymbol;
  }

  Future<void> set(String symbol) async {
    final value = symbol.trim().isEmpty ? '¥' : symbol.trim();
    await ref.read(settingsServiceProvider).setCurrencySymbol(value);
    state = value;
  }
}

final currencySymbolProvider = NotifierProvider<CurrencySymbolNotifier, String>(
  CurrencySymbolNotifier.new,
);

/// 当前选中的导航页索引（持久化到设置，重启后恢复）。
///
/// 存的是 [NavDestination.id]（如 `home`），不是索引本身 —— 这样将来
/// 调整导航顺序或增删项时，旧配置不会错位到别的页面。
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() {
    final lastId = ref.read(settingsServiceProvider).lastNavId;
    final index = kNavDestinations.indexWhere((d) => d.id == lastId);
    return index >= 0 ? index : 0;
  }

  /// 按索引切换（越界或非法值一律忽略）
  void select(int index) {
    if (index < 0 || index >= kNavDestinations.length) return;
    if (index == state) return;
    state = index;
    // 持久化失败不应影响交互，因此不 await，也不向上抛
    ref
        .read(settingsServiceProvider)
        .setLastNavId(kNavDestinations[index].id)
        .catchError((Object _) {});
  }

  /// 按 id 切换
  void selectById(String id) {
    final index = kNavDestinations.indexWhere((d) => d.id == id);
    if (index >= 0) select(index);
  }
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);
