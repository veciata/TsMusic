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
  final YoutubeExplode _yt;
  final YoutubeSearchService _searchService;
  final YoutubeDownloadService _downloadService;
  final yt_player.YoutubePlayerService _playerService;
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  YouTubeService()
      : _yt = YoutubeExplode(),
        _searchService = YoutubeSearchService(),
        _downloadService = YoutubeDownloadService(),
        _playerService = yt_player.YoutubePlayerService() {
    // Initialize services with the shared YoutubeExplode instance
    _searchService.setYoutubeExplode(_yt);
    _downloadService.setYoutubeExplode(_yt);
    
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
  List<DownloadProgress> get activeDownloads =>
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
      audio.id,
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
  void dispose() {
    try {
      // Remove listeners first
      _searchService.removeListener(notifyListeners);
      _downloadService.removeListener(notifyListeners);
      _playerService.removeListener(notifyListeners);

      // Close the YouTube client
      _yt.close();
      
      // Dispose all services
      _searchService.dispose();
      _downloadService.dispose();
      _playerService.dispose();
    } catch (e) {
      debugPrint('Error disposing YouTubeService: $e');
    } finally {
      super.dispose();
    }
  }
}
