import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfigViewModel extends ChangeNotifier {
  final SharedPreferences _prefs;

  AppConfigViewModel(this._prefs) {
    _loadSettings();
  }

  int _themeIndex = 0;
  int _gridColumns = 3;
  String _apiRemaining = 'Đang kiểm tra...';

  int get themeIndex => _themeIndex;
  bool get hapticsEnabled =>
      true; // Constant true if needed by other files, or remove fully if possible
  int get gridColumns => _gridColumns;
  String get apiRemaining => _apiRemaining;

  void updateApiRemaining(String value) {
    _apiRemaining = value;
    notifyListeners();
  }

  ThemeMode get themeMode {
    if (_themeIndex == 1) return ThemeMode.light;
    if (_themeIndex == 2) return ThemeMode.dark;
    return ThemeMode.system;
  }

  void _loadSettings() {
    _themeIndex = _prefs.getInt('themeMode') ?? 0;
    if (_themeIndex == 3) _themeIndex = 2; // Migrate legacy OLED mode
    _gridColumns = _prefs.getInt('gridColumns') ?? 3;
    notifyListeners();
  }

  Future<void> setThemeIndex(int index) async {
    _themeIndex = index;
    await _prefs.setInt('themeMode', index);
    notifyListeners();
  }

  Future<void> setGridColumns(int columns) async {
    _gridColumns = columns;
    await _prefs.setInt('gridColumns', columns);
    notifyListeners();
  }
}
