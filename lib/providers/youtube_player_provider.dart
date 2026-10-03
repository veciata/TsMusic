import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/core/services/error_tracking_service.dart';

class YouTubePlayerProvider extends ChangeNotifier {
  final YouTubeService _youTubeService;
  bool _isLoading = false;
  String? _loadingVideoId;
  Timer? _debounceTimer;
  final Set<String> _activeScreens = <String>{};
  YouTubePlayerProvider(this._youTubeService) {
    _youTubeService.addListener(_onYouTubeServiceChanged);
  }
  YouTubeAudio? get currentAudio => _youTubeService.currentAudio;
  bool get isPlaying => _youTubeService.isPlaying;
  bool get isLoading => _isLoading;
  String? get loadingVideoId => _loadingVideoId;
  void _onYouTubeServiceChanged() {
    notifyListeners();
  }

  void registerScreen(String screenName) {
    _activeScreens.add(screenName);
  }

  void unregisterScreen(String screenName) {
    _activeScreens.remove(screenName);
    if (_activeScreens.isEmpty) {
      stop();
    }
  }

  Future<void> playAudio(YouTubeAudio audio) async {
    if (_activeScreens.isEmpty) {
      throw Exception('YouTube playback not available - no active screens');
    }
    if (_loadingVideoId == audio.id) return;
    _setLoading(audio.id);
    try {
      await _youTubeService
          .playAudio(audio)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Connection timeout');
            },
          );
    } catch (e) {
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'YouTube online playback failed',
        extras: {'videoId': audio.id, 'title': audio.title},
      );
      rethrow;
    } finally {
      _clearLoading();
    }
  }

  Future<void> pause() async {
    if (isPlaying) {
      try {
        await _youTubeService.pause();
      } catch (e) {
        ErrorTrackingService().recordError(
          e,
          StackTrace.current,
          context: 'YouTubePlayerProvider.pause',
        );
      }
    }
  }

  Future<void> play() async {
    if (!isPlaying && currentAudio != null) {
      try {
        await _youTubeService.play();
      } catch (e) {
        ErrorTrackingService().recordError(
          e,
          StackTrace.current,
          context: 'YouTubePlayerProvider.play',
        );
      }
    }
  }

  Future<void> stop() async {
    try {
      await _youTubeService.stop();
    } catch (e) {
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'YouTubePlayerProvider.stop',
      );
    }
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  bool isCurrentAudio(String videoId) => currentAudio?.id == videoId;
  bool isLoadingAudio(String videoId) => _loadingVideoId == videoId;
  void _setLoading(String videoId) {
    _isLoading = true;
    _loadingVideoId = videoId;
    notifyListeners();
  }

  void _clearLoading() {
    _isLoading = false;
    _loadingVideoId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _youTubeService.removeListener(_onYouTubeServiceChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  bool get mounted => true;
}
