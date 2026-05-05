import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/player_styles.dart';
import 'package:tsmusic/core/theme/app_theme.dart' as app_theme;

class ThemeProvider with ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _primaryColorKey = 'primary_color';
  static const String _playerStyleKey = 'player_style';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isDarkMode = false;
  Color _primaryColor = const Color(0xFF1DB954);
  PlayerStyle _playerStyle = PlayerStyle.modern;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _isDarkMode;
  Color get primaryColor => _primaryColor;
  PlayerStyle get playerStyle => _playerStyle;
  List<Color> get availableColors => app_theme.availableColors;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    final colorValue = prefs.getInt(_primaryColorKey) ?? 0xFF1DB954;
    final styleIndex =
        prefs.getInt(_playerStyleKey) ?? PlayerStyle.modern.index;

    _themeMode = ThemeMode.values[themeIndex];
    _primaryColor = Color(colorValue);
    _playerStyle = PlayerStyle.values[styleIndex];
    _updateDarkMode();
    notifyListeners();
  }

  void _updateDarkMode() {
    _isDarkMode = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.window.platformBrightness ==
                Brightness.dark);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _updateDarkMode();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);

    notifyListeners();
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_primaryColorKey, color.value);

    notifyListeners();
  }

  Future<void> setPlayerStyle(PlayerStyle style) async {
    _playerStyle = style;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playerStyleKey, style.index);

    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  ThemeData getLightTheme() => app_theme.buildLightTheme(_primaryColor);

  ThemeData getDarkTheme() => app_theme.buildDarkTheme(_primaryColor);

  String getPlayerStyleName(PlayerStyle style) => style.displayName;

  String getPlayerStyleDescription(PlayerStyle style) {
    switch (style) {
      case PlayerStyle.classic:
        return 'Traditional layout with large album art';
      case PlayerStyle.modern:
        return 'Full-screen blurred background with glow effects';
      case PlayerStyle.compact:
        return 'Small player with horizontal layout';
      case PlayerStyle.minimal:
        return 'Ultra-minimal with bottom sheet controls';
    }
  }
}
