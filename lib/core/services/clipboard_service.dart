import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class YouTubeLinkResult {
  final String url;
  final String? videoId;
  final String? playlistId;
  final bool isPlaylist;

  const YouTubeLinkResult({
    required this.url,
    this.videoId,
    this.playlistId,
    this.isPlaylist = false,
  });
}

class ClipboardService with WidgetsBindingObserver {
  static final ClipboardService _instance = ClipboardService._();
  factory ClipboardService() => _instance;
  ClipboardService._();

  static final RegExp _youtubeVideoRegExp = RegExp(
    r'^https?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/|youtube\.com/v/|music\.youtube\.com/watch\?v=)([a-zA-Z0-9_-]{11})'
    r'(?:[&?][^"\s]*)?$',
    caseSensitive: false,
  );

  static final RegExp _youtubePlaylistRegExp = RegExp(
    r'^https?://(?:www\.)?(?:youtube\.com|music\.youtube\.com)/playlist\?list=([a-zA-Z0-9_-]+)'
    r'(?:[&?][^"\s]*)?$',
    caseSensitive: false,
  );

  static final RegExp _youtubeVideoInPlaylistRegExp = RegExp(
    r'^https?://(?:www\.)?(?:youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})).*[&?]list=([a-zA-Z0-9_-]+)'
    r'(?:[&?][^"\s]*)?$',
    caseSensitive: false,
  );

  String? _lastCheckedClipboard;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkClipboard();
    }
  }

  YouTubeLinkResult? parseYouTubeLink(String text) {
    final trimmed = text.trim();

    final playlistMatch = _youtubePlaylistRegExp.firstMatch(trimmed);
    if (playlistMatch != null) {
      return YouTubeLinkResult(
        url: trimmed,
        playlistId: playlistMatch.group(1),
        isPlaylist: true,
      );
    }

    final videoInPlaylistMatch = _youtubeVideoInPlaylistRegExp.firstMatch(
      trimmed,
    );
    if (videoInPlaylistMatch != null) {
      return YouTubeLinkResult(
        url: trimmed,
        videoId: videoInPlaylistMatch.group(1),
        playlistId: videoInPlaylistMatch.group(2),
      );
    }

    final videoMatch = _youtubeVideoRegExp.firstMatch(trimmed);
    if (videoMatch != null) {
      return YouTubeLinkResult(url: trimmed, videoId: videoMatch.group(1));
    }

    return null;
  }

  Future<YouTubeLinkResult?> checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return null;

      if (text == _lastCheckedClipboard) return null;
      _lastCheckedClipboard = text;

      final result = parseYouTubeLink(text);
      return result;
    } catch (e) {
      debugPrint('Clipboard check error: $e');
      return null;
    }
  }
}
