import 'package:flutter/material.dart';
import 'app_en.dart';
import 'app_tr.dart';

class AppLocalizations {
  static const supportedLocales = [
    Locale('en', 'US'),
    Locale('tr', 'TR'),
  ];

  static const Locale fallbackLocale = Locale('en', 'US');

  static AppLocalizations of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return _getLocalizedValues(locale);
  }

  static AppLocalizations _getLocalizedValues(Locale locale) {
    switch (locale.languageCode) {
      case 'tr':
        return AppLocalizationsTr();
      case 'en':
      default:
        return AppLocalizationsEn();
    }
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // Navigation
  String get home => throw UnimplementedError();
  String get downloads => throw UnimplementedError();
  String get settings => throw UnimplementedError();
  String get search => throw UnimplementedError();
  String get sql => throw UnimplementedError();

  // Music Player
  String get notPlaying => throw UnimplementedError();
  String get selectSongToPlay => throw UnimplementedError();
  String get tsMusic => throw UnimplementedError();

  // Settings
  String get appearance => throw UnimplementedError();
  String get about => throw UnimplementedError();
  String get language => throw UnimplementedError();
  String get darkMode => throw UnimplementedError();
  String get playerStyle => throw UnimplementedError();
  String get accentColor => throw UnimplementedError();
  String get audioDownloadFormat => throw UnimplementedError();
  String get version => throw UnimplementedError();
  String get helpSupport => throw UnimplementedError();
  String get selectPlayerStyle => throw UnimplementedError();
  String get selectAudioFormat => throw UnimplementedError();
  String get cancel => throw UnimplementedError();
  String get selectLanguage => throw UnimplementedError();
  String get debug => throw UnimplementedError();
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((supportedLocale) => supportedLocale.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations._getLocalizedValues(locale);
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizations> old) => false;
}
