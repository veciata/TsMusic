import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/audio_format.dart';

class SettingsProvider with ChangeNotifier {
  static const String _audioFormatKey = 'audioFormat';
  static const String _languageKey = 'language';
  static const String _downloadLocationKey = 'downloadLocation';
  static const String _firstLaunchKey = 'first_launch';

  AudioFormat _audioFormat = AudioFormat.auto;
  Locale _locale = const Locale('en', 'US');
  String _downloadLocation = 'internal';

  AudioFormat get audioFormat => _audioFormat;
  Locale get locale => _locale;
  String get downloadLocation => _downloadLocation;

  SettingsProvider() {
    _loadSettings();
  }

  /// Get supported locales
  static const List<Locale> _supportedLocales = [
    Locale('en', 'US'),
    Locale('tr', 'TR'),
  ];

  /// Get device locale and check if supported
  Locale _getDeviceLocale() {
    try {
      final deviceLocale = Platform.localeName;
      debugPrint('Device locale: $deviceLocale');

      // Parse platform locale (e.g., "en_US", "tr_TR")
      final languageCode = deviceLocale.split('_').first.split('-').first.toLowerCase();

      // Check if language is supported
      for (final locale in _supportedLocales) {
        if (locale.languageCode == languageCode) {
          debugPrint('Using supported locale: ${locale.languageCode}');
          return locale;
        }
      }

      // Default to English if not supported
      debugPrint('Locale not supported, defaulting to English');
      return const Locale('en', 'US');
    } catch (e) {
      debugPrint('Error getting device locale: $e');
      return const Locale('en', 'US');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load audio format
    final audioFormatString = prefs.getString(_audioFormatKey);
    if (audioFormatString != null) {
      _audioFormat = AudioFormat.values.firstWhere(
        (e) => e.toString() == 'AudioFormat.$audioFormatString',
        orElse: () => AudioFormat.auto,
      );
    }

    // Load language or use device locale on first launch
    final languageCode = prefs.getString(_languageKey);
    final isFirstLaunch = prefs.getBool(_firstLaunchKey) ?? true;

    if (languageCode != null) {
      // User has manually selected a language before
      _locale = Locale(languageCode);
    } else if (isFirstLaunch) {
      // First launch - use device locale
      _locale = _getDeviceLocale();
      // Save the detected locale
      await prefs.setString(_languageKey, _locale.languageCode);
      await prefs.setBool(_firstLaunchKey, false);
      debugPrint('First launch: set locale to ${_locale.languageCode}');
    }

    notifyListeners();
  }

  Future<void> setAudioFormat(AudioFormat format) async {
    if (_audioFormat != format) {
      _audioFormat = format;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_audioFormatKey, format.name);
      notifyListeners();
    }
  }

  Future<void> setLanguage(Locale locale) async {
    if (_locale != locale) {
      _locale = locale;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, locale.languageCode);
      notifyListeners();
    }
  }

  String getAudioFormatName(AudioFormat format) {
    if (format == AudioFormat.mp3) {
      return 'MP3 (Best available audio)';
    } else if (format == AudioFormat.opus) {
      return 'Opus (High quality, small size)';
    } else if (format == AudioFormat.m4a) {
      return 'M4A (High quality)';
    } else if (format == AudioFormat.auto) {
      return 'Auto (App decides)';
    }
    return 'Best available audio';
  }

  Future<void> setDownloadLocation(String location) async {
    if (_downloadLocation != location) {
      _downloadLocation = location;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_downloadLocationKey, location);
      notifyListeners();
    }
  }

  String getDownloadLocationName(String location) {
    if (location == 'internal') {
      return 'Internal Storage (App folder)';
    } else if (location == 'downloads') {
      return 'Downloads folder';
    } else if (location == 'music') {
      return 'Music folder';
    }
    return 'Internal Storage (App folder)';
  }

  String getLanguageName(Locale locale) {
    if (locale.languageCode == 'tr') {
      return 'Türkçe';
    } else {
      return 'English';
    }
  }
}
