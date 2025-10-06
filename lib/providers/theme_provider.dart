import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlayerStyle {
  classic,
  modern,
  compact,
  minimal,
}

class ThemeProvider with ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _primaryColorKey = 'primary_color';
  static const String _playerStyleKey = 'player_style';
  
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDarkMode = false;
  Color _primaryColor = const Color(0xFF1DB954); // Default Spotify green
  PlayerStyle _playerStyle = PlayerStyle.modern;
  
  // Get theme colors
  final List<Color> availableColors = const [
    Color(0xFF1DB954), // Spotify Green
    Color(0xFF1E88E5), // Blue
    Color(0xFF9C27B0), // Purple
    Color(0xFFE91E63), // Pink
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF009688), // Teal
  ];

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _isDarkMode;
  Color get primaryColor => _primaryColor;
  PlayerStyle get playerStyle => _playerStyle;
  
  // Player style names for UI
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

  // Initialize theme from shared preferences
  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    final colorValue = prefs.getInt(_primaryColorKey) ?? 0xFF1DB954;
    final styleIndex = prefs.getInt(_playerStyleKey) ?? PlayerStyle.modern.index;
    
    _themeMode = ThemeMode.values[themeIndex];
    _primaryColor = Color(colorValue);
    _playerStyle = PlayerStyle.values[styleIndex];
    _updateDarkMode();
    notifyListeners();
  }

  void _updateDarkMode() {
    _isDarkMode = _themeMode == ThemeMode.dark || 
                 (_themeMode == ThemeMode.system && 
                  WidgetsBinding.instance.window.platformBrightness == Brightness.dark);
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
  
  // Get the current theme data
  ThemeData getLightTheme() {
    final baseTheme = ThemeData.light();
    final colorScheme = ColorScheme.light(
      primary: _primaryColor,
      primaryContainer: _primaryColor.withOpacity(0.8),
      secondary: _primaryColor.withOpacity(0.6),
      surface: Colors.white,
      background: Colors.grey[50]!,
      onPrimary: Colors.white,
      onSurface: Colors.black87,
      brightness: Brightness.light,
    );

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: colorScheme.background,
      cardColor: colorScheme.surface,
      dividerColor: Colors.grey[300],
      
      // Text Themes
      textTheme: TextTheme(
        titleLarge: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
        bodyLarge: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
        bodyMedium: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
      ),
      
      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: colorScheme.onPrimary,
          backgroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      iconTheme: IconThemeData(
        color: colorScheme.onSurface.withOpacity(0.8),
      ),
      
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
    );
  }
  
  ThemeData getDarkTheme() {
    final baseTheme = ThemeData.dark();
    final colorScheme = ColorScheme.dark(
      primary: _primaryColor,
      primaryContainer: _primaryColor.withOpacity(0.8),
      secondary: _primaryColor.withOpacity(0.6),
      surface: Colors.grey[850]!,
      background: Colors.grey[900]!,
      onPrimary: Colors.white,
      onSurface: Colors.white,
      brightness: Brightness.dark,
    );

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: colorScheme.background,
      cardColor: colorScheme.surface,
      dividerColor: Colors.grey[700],
      
      // Text Themes
      textTheme: TextTheme(
        titleLarge: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
        bodyLarge: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
        bodyMedium: TextStyle(color: colorScheme.onSurface.withOpacity(0.9)),
      ),
      
      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: colorScheme.onPrimary,
          backgroundColor: colorScheme.primary,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      
      iconTheme: IconThemeData(
        color: colorScheme.onSurface.withOpacity(0.9),
      ),
      
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      
      // Using copyWith to ensure we're working with the correct CardThemeData type
      cardTheme: baseTheme.cardTheme.copyWith(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shadowColor: Colors.black.withOpacity(0.1),
      ),
    );
  }
}
