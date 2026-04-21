import 'package:flutter/material.dart';
import 'package:tsmusic/localization/app_en.dart';
import 'package:tsmusic/localization/app_tr.dart';

class AppLocalizations {
  static const supportedLocales = [Locale('en', 'US'), Locale('tr', 'TR')];

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
  String get nowPlaying => throw UnimplementedError();
  String get songs => throw UnimplementedError();
  String get music => throw UnimplementedError();
  String get artists => throw UnimplementedError();
  String get playlists => throw UnimplementedError();
  String get localSongs => throw UnimplementedError();
  String get online => throw UnimplementedError();
  String get downloaded => throw UnimplementedError();
  String get unknownTitle => throw UnimplementedError();
  String get unknownArtist => throw UnimplementedError();
  String get unknownAlbum => throw UnimplementedError();
  String get playAll => throw UnimplementedError();

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
  String get createdBy => throw UnimplementedError();
  String get supportFeedback => throw UnimplementedError();
  String get openGitHub => throw UnimplementedError();

  // Sorting & Filtering
  String get sortByTitle => throw UnimplementedError();
  String get sortByArtist => throw UnimplementedError();
  String get sortByDate => throw UnimplementedError();
  String get ascending => throw UnimplementedError();
  String get descending => throw UnimplementedError();
  String get refresh => throw UnimplementedError();

  // Song Actions
  String get move => throw UnimplementedError();
  String get delete => throw UnimplementedError();
  String get addToPlaylist => throw UnimplementedError();
  String get deleteSong => throw UnimplementedError();
  String get confirmDelete => throw UnimplementedError();
  String get songDeleted => throw UnimplementedError();
  String get errorMovingFile => throw UnimplementedError();

  // Move Dialog
  String get moveTo => throw UnimplementedError();
  String get internalStorage => throw UnimplementedError();
  String get musicFolder => throw UnimplementedError();

  // Playlist
  String get createPlaylist => throw UnimplementedError();
  String get deletePlaylist => throw UnimplementedError();
  String get playlistName => throw UnimplementedError();
  String get playlistCreated => throw UnimplementedError();
  String get playlistDeleted => throw UnimplementedError();
  String get noPlaylists => throw UnimplementedError();
  String get addSongs => throw UnimplementedError();
  String get add => throw UnimplementedError();
  String get removeFromPlaylist => throw UnimplementedError();
  String get remove => throw UnimplementedError();
  String get play => throw UnimplementedError();
  String get done => throw UnimplementedError();
  String get edit => throw UnimplementedError();
  String get noArtists => throw UnimplementedError();

  // Common
  String get create => throw UnimplementedError();
  String get save => throw UnimplementedError();
  String get ok => throw UnimplementedError();
  String get retry => throw UnimplementedError();
  String get skip => throw UnimplementedError();
  String get error => throw UnimplementedError();

  // Home Screen
  String get noMusicFound => throw UnimplementedError();
  String get addMusicToDevice => throw UnimplementedError();
  String get searchAndDownload => throw UnimplementedError();
  String get errorLoadingMusic => throw UnimplementedError();
  String get tryAgain => throw UnimplementedError();
  String get loading => throw UnimplementedError();
  String get scanning => throw UnimplementedError();
  String get scanningForMusic => throw UnimplementedError();

  // Artist/Follow
  String get follow => throw UnimplementedError();
  String get following => throw UnimplementedError();
  String get noLocalSongsForArtist => throw UnimplementedError();
  String get noOnlineSongsFound => throw UnimplementedError();

  // Queue
  String get queue => throw UnimplementedError();
  String get clearQueue => throw UnimplementedError();
  String get queueCleared => throw UnimplementedError();

  // Downloads
  String get downloading => throw UnimplementedError();
  String get downloadStarted => throw UnimplementedError();
  String get downloadFailed => throw UnimplementedError();
  String get downloadComplete => throw UnimplementedError();
  String get noDownloads => throw UnimplementedError();
  String get downloadingMusic => throw UnimplementedError();

  // Introduction
  String get introWelcomeTitle => throw UnimplementedError();
  String get introWelcomeDesc => throw UnimplementedError();
  String get introStorageTitle => throw UnimplementedError();
  String get introStorageDesc => throw UnimplementedError();
  String get introSearchTitle => throw UnimplementedError();
  String get introSearchDesc => throw UnimplementedError();
  String get introDownloadTitle => throw UnimplementedError();
  String get introDownloadDesc => throw UnimplementedError();
  String get introQueueTitle => throw UnimplementedError();
  String get introQueueDesc => throw UnimplementedError();
  String get getStarted => throw UnimplementedError();
  String get next => throw UnimplementedError();
  String get permissionRequired => throw UnimplementedError();
  String get grantPermission => throw UnimplementedError();
  String get permissionGranted => throw UnimplementedError();
  String get permissionGrantedDesc => throw UnimplementedError();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations._getLocalizedValues(locale);
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizations> old) => false;
}
