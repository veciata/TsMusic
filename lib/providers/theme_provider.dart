import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';

enum PlayerStyle {
  classic,
  modern,
  compact,
  minimal,
}

class ThemeProvider with ChangeNotifier {
  static const _themeModeKey = 'theme_mode';
  static const _primaryColorKey = 'primary_color';
  static const _playerStyleKey = 'player_style';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isDarkMode = false;
  Color _primaryColor = const Color(0xFF1DB954);
  PlayerStyle _playerStyle = PlayerStyle.modern;

  final List<Color> availableColors = const [
    Color(0xFF1DB954),
    Color(0xFF1E88E5),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFFFF5722),
    Color(0xFF009688),
  ];

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _isDarkMode;
  Color get primaryColor => _primaryColor;
  PlayerStyle get playerStyle => _playerStyle;

  String getPlayerStyleName(PlayerStyle style) {
    switch (style) {
      case PlayerStyle.classic:
        return 'Classic';
      case PlayerStyle.modern:
        return 'Modern';
      case PlayerStyle.compact:
        return 'Compact';
      case PlayerStyle.minimal:
        return 'Minimal';
    }
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[prefs.getInt(_themeModeKey) ?? 0];
    _primaryColor = Color(prefs.getInt(_primaryColorKey) ?? 0xFF1DB954);
    _playerStyle =
        PlayerStyle.values[prefs.getInt(_playerStyleKey) ?? PlayerStyle.modern.index];
    _updateDarkMode();
    notifyListeners();
  }

  void _updateDarkMode() {
    if (_themeMode == ThemeMode.system) {
      _isDarkMode = SchedulerBinding.instance.window.platformBrightness == Brightness.dark;
    } else {
      _isDarkMode = _themeMode == ThemeMode.dark;
    }
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _updateDarkMode();
    await _saveInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;
    await _saveInt(_primaryColorKey, color.value);
    notifyListeners();
  }

  Future<void> setPlayerStyle(PlayerStyle style) async {
    _playerStyle = style;
    await _saveInt(_playerStyleKey, style.index);
    notifyListeners();
  }

  ThemeData get lightTheme {
    final base = ThemeData.light();
    return base.copyWith(
      colorScheme: ColorScheme.light(
        primary: _primaryColor,
        secondary: _primaryColor.withOpacity(0.8),
      ),
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: Colors.grey[50],
      cardColor: Colors.white,
      dividerColor: Colors.grey[300],
    );
  }

  ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      colorScheme: ColorScheme.dark(
        primary: _primaryColor,
        secondary: _primaryColor.withOpacity(0.8),
      ),
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: Colors.grey[900],
      cardColor: Colors.grey[850],
      dividerColor: Colors.grey[700],
    );
  }
}
