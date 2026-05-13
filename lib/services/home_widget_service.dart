import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:tsmusic/models/song.dart';

class HomeWidgetService {
  static const String _playerWidgetClass = 'com.veciata.tsmusic.SimplePlayerWidgetProvider';
  static const String _searchWidgetClass = 'com.veciata.tsmusic.SearchWidgetProvider';

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId('group.com.veciata.tsmusic');
    } catch (e) {
      debugPrint('HomeWidgetService.init error: $e');
    }
  }

  static Future<void> updateSearchWidget({bool isDarkMode = false}) async {
    try {
      const width = 300.0;
      const height = 56.0;
      final widget = _SearchBarPreview(isDarkMode: isDarkMode);

      final path = await HomeWidget.renderFlutterWidget(
        SizedBox(width: width, height: height, child: widget),
        key: 'search_widget_image',
        logicalSize: const Size(width, height),
      );

      await HomeWidget.saveWidgetData<String>('search_widget_image', path);
      await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);
      await HomeWidget.updateWidget(qualifiedAndroidName: _searchWidgetClass);
    } catch (e) {
      debugPrint('HomeWidgetService.updateSearchWidget error: $e');
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
}

class _SearchBarPreview extends StatelessWidget {
  final bool isDarkMode;

  const _SearchBarPreview({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final iconColor = isDarkMode ? Colors.white70 : Colors.black54;
    final hintColor = isDarkMode ? Colors.white38 : Colors.black38;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? Colors.white24 : Colors.black12,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Search songs...',
            style: TextStyle(color: hintColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
