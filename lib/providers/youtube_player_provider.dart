import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/services/youtube_service.dart';

/// Separate provider for YouTube audio playback
/// This keeps YouTube music separate from the main music player
/// YouTube audio only exists in search and artist screens and is killed when leaving
class YouTubePlayerProvider extends ChangeNotifier {
  final YouTubeService _youTubeService;
  bool _isLoading = false;
  String? _loadingVideoId;
  Timer? _debounceTimer;
  
  // Active screen tracking for lifecycle management
  final Set<String> _activeScreens = <String>{};

  YouTubePlayerProvider(this._youTubeService) {
    // Listen to YouTubeService state changes
    _youTubeService.addListener(_onYouTubeServiceChanged);
  }

  // Getters that delegate to YouTubeService
  YouTubeAudio? get currentAudio => _youTubeService.currentAudio;
  bool get isPlaying => _youTubeService.isPlaying;
  bool get isLoading => _isLoading;
  String? get loadingVideoId => _loadingVideoId;

  void _onYouTubeServiceChanged() {
    // Sync with YouTubeService state changes
    notifyListeners();
  }

  /// Register a screen as active (for lifecycle management)
  void registerScreen(String screenName) {
    _activeScreens.add(screenName);
    debugPrint('YouTube: Screen registered: $screenName, active screens: $_activeScreens');
  }

  /// Unregister a screen (called when screen is disposed/navigated away)
  void unregisterScreen(String screenName) {
    _activeScreens.remove(screenName);
    debugPrint('YouTube: Screen unregistered: $screenName, active screens: $_activeScreens');
    
    // Auto-stop YouTube audio when no active screens remain
    if (_activeScreens.isEmpty) {
      debugPrint('YouTube: No active screens, stopping playback');
      stop();
    }
  }

  /// Play YouTube audio (only if there's at least one active screen)
  Future<void> playAudio(YouTubeAudio audio) async {
    if (_activeScreens.isEmpty) {
      debugPrint('YouTube: Cannot play - no active screens');
      throw Exception('YouTube playback not available - no active screens');
    }
    
    if (_loadingVideoId == audio.id) return;
    
    _setLoading(audio.id);
    
    try {
      await _youTubeService.playAudio(audio).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timeout');
        },
      );
    } catch (e) {
      debugPrint('Error playing YouTube audio: $e');
      rethrow;
    } finally {
      _clearLoading();
    }
  }

  /// Pause current YouTube audio
  Future<void> pause() async {
    if (isPlaying) {
      try {
        await _youTubeService.pause();
      } catch (e) {
        debugPrint('Error pausing YouTube audio: $e');
      }
    }
  }

  /// Resume current YouTube audio
  Future<void> play() async {
    if (!isPlaying && currentAudio != null) {
      try {
        await _youTubeService.play();
      } catch (e) {
        debugPrint('Error resuming YouTube audio: $e');
      }
    }
  }

  /// Stop YouTube audio
  Future<void> stop() async {
    try {
      await _youTubeService.stop();
    } catch (e) {
      debugPrint('Error stopping YouTube audio: $e');
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Check if a specific audio is currently playing
  bool isCurrentAudio(String videoId) {
    return currentAudio?.id == videoId;
  }

  /// Check if a specific audio is currently loading
  bool isLoadingAudio(String videoId) {
    return _loadingVideoId == videoId;
  }

  /// Set loading state
  void _setLoading(String videoId) {
    _isLoading = true;
    _loadingVideoId = videoId;
    notifyListeners();
  }

  /// Clear loading state
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

  bool get mounted => true; // Simple check for this provider
}
