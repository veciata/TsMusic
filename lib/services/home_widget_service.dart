import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:home_widget/home_widget.dart';
import 'package:tsmusic/models/song.dart';

class HomeWidgetService {
  static const String _playerWidgetClass =
      'com.veciata.tsmusic.SimplePlayerWidgetProvider';
  static const String _searchWidgetClass =
      'com.veciata.tsmusic.SearchWidgetProvider';

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId('group.com.veciata.tsmusic');
    } catch (_) {}
  }

  static Future<void> updateSearchWidget({
    bool isDarkMode = false,
    Color? primaryColor,
  }) async {
    try {
      await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);
      await HomeWidget.saveWidgetData<int>(
        'widget_primary_color',
        primaryColor?.value ?? 0xFF1DB954,
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: _searchWidgetClass);
    } catch (_) {}
  }

  static Future<void> updatePlayerWidget({
    required Song? currentSong,
    required bool isPlaying,
    required bool isOnlinePlaying,
    String? onlineTitle,
    String? onlineAuthor,
    bool isDarkMode = false,
    Color? primaryColor,
    List<Song>? queue,
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
        thumbnailPath =
            currentSong.localThumbnailPath ?? currentSong.albumArtUrl;
      } else {
        title = 'TS Music';
        artist = 'Not playing';
        thumbnailPath = null;
      }

      await HomeWidget.saveWidgetData<String>('widget_title', title);
      await HomeWidget.saveWidgetData<String>('widget_artist', artist);
      await HomeWidget.saveWidgetData<bool>(
        'widget_is_playing',
        isPlaying || isOnlinePlaying,
      );
      await HomeWidget.saveWidgetData<bool>(
        'widget_is_online',
        isOnlinePlaying,
      );
      await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);
      await HomeWidget.saveWidgetData<String?>(
        'widget_thumbnail',
        thumbnailPath,
      );
      await HomeWidget.saveWidgetData<int>(
        'widget_primary_color',
        primaryColor?.value ?? 0xFF1DB954,
      );

      final queueItems = (queue ?? [])
          .take(10)
          .map((s) => {'title': s.title, 'artists': s.artists.join(', ')})
          .toList();
      await HomeWidget.saveWidgetData<String>(
        'widget_queue',
        jsonEncode(queueItems),
      );

      await HomeWidget.updateWidget(qualifiedAndroidName: _playerWidgetClass);
    } catch (_) {}
  }
}
