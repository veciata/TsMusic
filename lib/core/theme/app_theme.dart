import 'package:flutter/material.dart';

const List<Color> availableColors = [
  Color(0xFF1DB954),
  Color(0xFF1E88E5),
  Color(0xFF9C27B0),
  Color(0xFFE91E63),
  Color(0xFFFF5722),
  Color(0xFF009688),
];

ThemeData buildLightTheme(Color primaryColor) {
  final colorScheme = ColorScheme.light(
    primary: primaryColor,
    primaryContainer: primaryColor.withValues(alpha: 0.8),
    secondary: primaryColor.withValues(alpha: 0.6),
    onSurface: Colors.black87,
  );

  return ThemeData.light().copyWith(
    colorScheme: colorScheme,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: colorScheme.surface,
    cardColor: colorScheme.surface,
    dividerColor: Colors.grey[300],
    textTheme: TextTheme(
      titleLarge:
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
      bodyLarge: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
      bodyMedium: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
    ),
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
      color: colorScheme.onSurface.withValues(alpha: 0.8),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surface,
      contentTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      actionTextColor: colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      closeIconColor: colorScheme.onSurfaceVariant,
      elevation: 4,
    ),
  );
}

ThemeData buildDarkTheme(Color primaryColor) {
  final colorScheme = ColorScheme.dark(
    primary: primaryColor,
    primaryContainer: primaryColor.withValues(alpha: 0.8),
    secondary: primaryColor.withValues(alpha: 0.6),
    surface: Colors.grey[850]!,
    onPrimary: Colors.white,
  );

  return ThemeData.dark().copyWith(
    colorScheme: colorScheme,
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: colorScheme.surface,
    cardColor: colorScheme.surface,
    dividerColor: Colors.grey[700],
    textTheme: TextTheme(
      titleLarge:
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.9)),
      bodyLarge: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.9)),
      bodyMedium: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.9)),
    ),
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
      color: colorScheme.onSurface.withValues(alpha: 0.9),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
    cardTheme: ThemeData.dark().cardTheme.copyWith(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      shadowColor: Colors.black.withValues(alpha: 0.1),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surface,
      contentTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      actionTextColor: colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      closeIconColor: colorScheme.onSurfaceVariant,
      elevation: 4,
    ),
  );
}
