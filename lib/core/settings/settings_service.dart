import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量设置服务：只存主题模式、货币符号等偏好。
/// 业务数据一律走数据库（drift），不使用本服务。
///
/// 【为什么不做成 Provider 可变的】
/// SharedPreferences 的读写是同步的内存操作（首次加载后已在内存中），
/// 因此 getter 可以同步返回；写入是异步落盘，失败也不该打断交互。
class SettingsService {
  SettingsService(this._prefs, {this.databasePath});

  final SharedPreferences _prefs;

  /// 数据库文件的绝对路径（仅用于「设置 - 数据存储位置」展示）。
  /// 由 main() 通过 path_provider 求出后注入；测试环境可为 null。
  final String? databasePath;

  static const String _kThemeMode = 'settings.theme_mode';
  static const String _kCurrencySymbol = 'settings.currency_symbol';
  static const String _kLastNavId = 'settings.last_nav_id';

  /// 默认货币符号
  static const String defaultCurrencySymbol = '¥';

  /// 异步创建实例（供 Provider 使用）
  static Future<SettingsService> create({String? databasePath}) async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs, databasePath: databasePath);
  }

  // -------------------------------------------------------------------------
  // 主题模式
  // -------------------------------------------------------------------------

  /// 主题模式：system / light / dark
  ThemeMode get themeMode {
    final raw = _prefs.getString(_kThemeMode) ?? 'system';
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) {
    return _prefs.setString(_kThemeMode, mode.name);
  }

  // -------------------------------------------------------------------------
  // 货币符号
  // -------------------------------------------------------------------------

  /// 货币符号，默认人民币
  String get currencySymbol {
    final raw = _prefs.getString(_kCurrencySymbol);
    if (raw == null || raw.trim().isEmpty) return defaultCurrencySymbol;
    return raw.trim();
  }

  Future<void> setCurrencySymbol(String symbol) {
    final value = symbol.trim().isEmpty ? defaultCurrencySymbol : symbol.trim();
    return _prefs.setString(_kCurrencySymbol, value);
  }

  // -------------------------------------------------------------------------
  // 导航位置
  // -------------------------------------------------------------------------

  /// 上次停留的导航页 id（重启后恢复）
  String get lastNavId => _prefs.getString(_kLastNavId) ?? 'home';

  Future<void> setLastNavId(String id) {
    return _prefs.setString(_kLastNavId, id);
  }
}
