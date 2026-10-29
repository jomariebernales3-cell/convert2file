import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeChoice { day, night, dbz }

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._();
  ThemeService._();

  static const _themeKey = 'app_theme_mode';
  static const _defaultThemeChoice = AppThemeChoice.night;

  int? _currentUserId;
  AppThemeChoice _themeChoice = _defaultThemeChoice;

  AppThemeChoice get themeChoice => _themeChoice;
  bool get isDbzTheme => _themeChoice == AppThemeChoice.dbz;
  ThemeMode get themeMode =>
      _themeChoice == AppThemeChoice.day ? ThemeMode.light : ThemeMode.dark;

  Future<void> init({int? userId}) async {
    _currentUserId = userId;
    await _loadThemeForCurrentUser(notify: false);
  }

  Future<void> loadForUser(int? userId) async {
    _currentUserId = userId;
    await _loadThemeForCurrentUser();
  }

  Future<void> resetToDefaultGuestTheme() async {
    _currentUserId = null;
    _themeChoice = _defaultThemeChoice;
    notifyListeners();
  }

  Future<void> _loadThemeForCurrentUser({bool notify = true}) async {
    if (_currentUserId == null) {
      _themeChoice = _defaultThemeChoice;
      if (notify) notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _themeChoice = _themeFromName(prefs.getString(_userThemeKey));
    if (notify) notifyListeners();
  }

  Future<void> setThemeChoice(AppThemeChoice choice) async {
    if (_themeChoice == choice) return;
    _themeChoice = choice;
    notifyListeners();

    if (_currentUserId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userThemeKey, choice.name);
    }
  }

  String get _userThemeKey => '${_themeKey}_user_$_currentUserId';

  AppThemeChoice _themeFromName(String? name) {
    return switch (name) {
      'day' || 'light' => AppThemeChoice.day,
      'dbz' => AppThemeChoice.dbz,
      _ => AppThemeChoice.night,
    };
  }
}
