import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_format.dart';

class SettingsProvider with ChangeNotifier {
  static const String _audioFormatKey = 'audioFormat';

  AudioFormat _audioFormat = AudioFormat.auto; // Default value

  AudioFormat get audioFormat => _audioFormat;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final audioFormatString = prefs.getString(_audioFormatKey);
    if (audioFormatString != null) {
      _audioFormat = AudioFormat.values.firstWhere(
        (e) => e.toString() == 'AudioFormat.$audioFormatString',
        orElse: () => AudioFormat.auto,
      );
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
    return 'Unknown Format'; // Should not happen
  }
}
