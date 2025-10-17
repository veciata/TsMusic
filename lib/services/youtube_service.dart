// Export all YouTube related services
export 'youtube/youtube_search_service.dart';
export 'youtube/youtube_download_service.dart';
export 'youtube/youtube_player_service.dart';

// Import and re-export the main YouTube service classes
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../models/youtube_audio.dart';
import '../models/youtube_audio.dart';
import 'youtube/youtube_search_service.dart';
import 'youtube/youtube_download_service.dart';
import 'youtube/youtube_player_service.dart' as yt_player;

export 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Main YouTube service that provides access to all YouTube related functionality.
class YouTubeService extends ChangeNotifier {
  final YoutubeSearchService _searchService;
  final YoutubeDownloadService _downloadService;
  final yt_player.YoutubePlayerService _playerService;
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  YouTubeService()
      : _searchService = YoutubeSearchService(),
        _downloadService = YoutubeDownloadService(),
        _playerService = yt_player.YoutubePlayerService() {
    // Forward notifications from child services
    _searchService.addListener(notifyListeners);
    _downloadService.addListener(notifyListeners);
    _playerService.addListener(notifyListeners);
  }

  // Getters

  YouTubeAudio? get currentAudio => _playerService.currentAudio;
  bool get isPlaying => _playerService.isPlaying;
  Duration get position => _playerService.position;
  Duration get duration => _playerService.duration;
  List<YTDownloadProgress> get activeDownloads =>
      _downloadService.activeDownloads;

  // Search methods
  Future<List<YouTubeAudio>> searchAudio(String query,
      {int maxResults = 10}) async {
    isLoading.value = true;
    notifyListeners();
    try {
      final results =
          await _searchService.search(query, maxResults: maxResults);
      return results;
    } catch (e) {
      rethrow;
    } finally {
      isLoading.value = false;
      notifyListeners();
    }
  }

  Future<List<YouTubeAudio>> searchNextPage() async {
    if (!_searchService.hasMoreResults) return [];
    return await _searchService.searchNextPage();
  }

  // Player methods
  Future<void> playAudio(YouTubeAudio audio) async {
    await _playerService.playAudio(audio);
    notifyListeners();
  }

  Future<void> pauseAudio() async {
    await _playerService.pause();
    notifyListeners();
  }

  Future<void> stopAudio() async {
    await _playerService.stop();
    notifyListeners();
  }

  Future<void> seekAudio(Duration position) async {
    await _playerService.seek(position);
    notifyListeners();
  }

  // Download methods
  Future<void> downloadAudio(YouTubeAudio audio, BuildContext context) async {
    await _downloadService.downloadAudio(
      videoId: audio.id,
      context: context,
      onProgress: (progress) {
        // Update progress
        notifyListeners();
      },
    );
  }

  // Add a method to get the next page of search results
  Future<List<YouTubeAudio>> searchAudioNextPage() async {
    return await _searchService.searchNextPage();
  }

  Future<void> cancelDownload(String videoId) async {
    await _downloadService.cancelDownload(videoId);
    notifyListeners();
  }

  // Cleanup
  @override
  Future<void> dispose() async {
    _searchService.removeListener(notifyListeners);
    _downloadService.removeListener(notifyListeners);
    _playerService.removeListener(notifyListeners);

    // Dispose all services
    (_searchService as ChangeNotifier).dispose();

    (_downloadService as ChangeNotifier).dispose();

    (_playerService as ChangeNotifier).dispose();

    super.dispose();
  }
}
