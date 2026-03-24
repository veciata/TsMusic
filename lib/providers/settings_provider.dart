import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_format.dart';

class SettingsProvider with ChangeNotifier {
  static const String _audioFormatKey = 'audioFormat';
  static const String _languageKey = 'language';

  AudioFormat _audioFormat = AudioFormat.auto;
  Locale _locale = const Locale('en', 'US');

  AudioFormat get audioFormat => _audioFormat;
  Locale get locale => _locale;

  SettingsProvider() {
    _loadSettings();
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
    
    // Load language
    final languageCode = prefs.getString(_languageKey);
    if (languageCode != null) {
      _locale = Locale(languageCode);
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
    return 'Unknown Format';
  }

  String getLanguageName(Locale locale) {
    if (locale.languageCode == 'tr') {
      return 'Türkçe';
    } else {
      return 'English';
    }
  }
}
