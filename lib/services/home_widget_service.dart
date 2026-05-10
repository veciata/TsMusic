import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:tsmusic/models/song.dart';

class HomeWidgetService {
  static const String _playerWidgetClass = 'com.veciata.tsmusic.SimplePlayerWidgetProvider';
  static const String _playlistWidgetClass = 'com.veciata.tsmusic.NowPlayingPlaylistWidgetProvider';

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId('group.com.veciata.tsmusic');
    } catch (e) {
      debugPrint('HomeWidgetService.init error: $e');
    }
  }

  static Future<void> updatePlayerWidget({
    required Song? currentSong,
    required bool isPlaying,
    required bool isOnlinePlaying,
    String? onlineTitle,
    String? onlineAuthor,
    bool isDarkMode = false,
  }) async {
    try {
      final String title;
      final String artist;
      final String? thumbnailPath;

      if (isOnlinePlaying && onlineTitle != null) {
        title = onlineTitle;
        artist = onlineAuthor ?? '';
        thumbnailPath = null;
      } else if (currentSong != null) {
        title = currentSong.title;
        artist = currentSong.artists.isNotEmpty
            ? currentSong.artists.join(' & ')
            : '';
        thumbnailPath = currentSong.localThumbnailPath ?? currentSong.albumArtUrl;
      } else {
        title = 'TS Music';
        artist = 'Not playing';
        thumbnailPath = null;
      }

      await HomeWidget.saveWidgetData<String>('widget_title', title);
      await HomeWidget.saveWidgetData<String>('widget_artist', artist);
      await HomeWidget.saveWidgetData<bool>(
          'widget_is_playing', isPlaying || isOnlinePlaying);
      await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);
      await HomeWidget.saveWidgetData<String?>('widget_thumbnail', thumbnailPath);

      await HomeWidget.updateWidget(qualifiedAndroidName: _playerWidgetClass);
    } catch (e) {
      debugPrint('HomeWidgetService.updatePlayerWidget error: $e');
    }
  }

  static Future<void> updatePlaylistWidget({
    required Song? currentSong,
    required List<Song> queue,
    required bool isPlaying,
    required bool isDarkMode,
  }) async {
    try {
      final String title;
      final String artist;

      if (currentSong != null) {
        title = currentSong.title;
        artist = currentSong.artists.isNotEmpty
            ? currentSong.artists.join(' & ')
            : '';
      } else {
        title = 'TS Music';
        artist = 'Not playing';
      }

      final int currentIndex = currentSong != null
          ? queue.indexOf(currentSong)
          : 0;
      final list = <Map<String, dynamic>>[];
      for (var i = 0; i < queue.length; i++) {
        final song = queue[i];
        list.add({
          'title': song.title,
          'artist': song.artists.isNotEmpty ? song.artists.join(' & ') : '',
          'isCurrent': i == currentIndex,
        });
      }
      final playlistJson = jsonEncode(list);

      await HomeWidget.saveWidgetData<String>('widget_title', title);
      await HomeWidget.saveWidgetData<String>('widget_artist', artist);
      await HomeWidget.saveWidgetData<bool>(
          'widget_is_playing', isPlaying);
      await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);
      await HomeWidget.saveWidgetData<String>('playlist_json', playlistJson);

      await HomeWidget.updateWidget(qualifiedAndroidName: _playlistWidgetClass);
    } catch (e) {
      debugPrint('HomeWidgetService.updatePlaylistWidget error: $e');
    }
  }
}
