import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _key = 'isDarkTheme';
  bool _isDark = false;
  bool _initialized = false;

  ThemeController() {
    _loadTheme();
  }

  bool get isDark => _isDark;
  bool get initialized => _initialized;

  ThemeMode get currentTheme => _isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(_key) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> toggleTheme(bool value) async {
    _isDark = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDark);
  }
}
