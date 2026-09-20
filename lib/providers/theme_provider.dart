import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/flow_colors.dart';

enum DensityMode {
  comfortable,
  compact,
  minimal;

  String get label {
    switch (this) {
      case DensityMode.comfortable:
        return 'Comfortable';
      case DensityMode.compact:
        return 'Compact';
      case DensityMode.minimal:
        return 'Minimal';
    }
  }

  static DensityMode fromString(String? name) {
    switch (name?.toLowerCase()) {
      case 'compact':
        return DensityMode.compact;
      case 'minimal':
        return DensityMode.minimal;
      case 'comfortable':
      default:
        return DensityMode.comfortable;
    }
  }
}

class ThemeProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'flowstate_theme_mode';
  static const String _keyAccent = 'flowstate_accent_color';
  static const String _keyDensity = 'flowstate_density_mode';

  ThemeMode _themeMode = ThemeMode.light; // White/Light default identity
  FlowAccent _selectedAccent = FlowAccent.cyan;
  DensityMode _densityMode = DensityMode.comfortable;
  bool _isInitialized = false;

  ThemeProvider() {
    _loadPreferences();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  FlowAccent get selectedAccent => _selectedAccent;
  Color get accentColor => _selectedAccent.color;
  Color get lightAccentColor => _selectedAccent.lightColor;
  Color get darkAccentColor => _selectedAccent.darkColor;
  DensityMode get densityMode => _densityMode;
  bool get isInitialized => _isInitialized;

  /// Check whether the active effective brightness is dark
  bool isDark(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  Color resolveAccent(BuildContext context) => _selectedAccent.resolve(context);

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_keyThemeMode);
      if (modeStr == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (modeStr == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light; // Default
      }
      final accentStr = prefs.getString(_keyAccent);
      if (accentStr != null) {
        _selectedAccent = FlowAccent.fromString(accentStr);
      }
      final densityStr = prefs.getString(_keyDensity);
      if (densityStr != null) {
        _densityMode = DensityMode.fromString(densityStr);
      }
    } catch (_) {
      // Fallback gracefully in test / offline environments
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setAccent(FlowAccent accent) async {
    _selectedAccent = accent;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccent, accent.name);
    } catch (_) {}
  }

  Future<void> setDensityMode(DensityMode mode) async {
    _densityMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDensity, mode.name);
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, isDarkMode ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'light';
      if (mode == ThemeMode.dark) {
        modeStr = 'dark';
      } else if (mode == ThemeMode.system) {
        modeStr = 'system';
      }
      await prefs.setString(_keyThemeMode, modeStr);
    } catch (_) {}
  }
}
