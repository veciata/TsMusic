import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/youtube_audio.dart';

// Import the Video class explicitly
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show Video;

class YoutubeSearchService extends ChangeNotifier {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, List<Video>> _searchPages = {};
  bool _isSearching = false;
  String? _currentQuery;
  bool _hasMoreResults = true;
  List<Video>? _currentSearchResults;
  String? _nextPageToken;

  bool get isSearching => _isSearching;
  bool get hasMoreResults => _hasMoreResults;
  String? get currentQuery => _currentQuery;

  Future<List<YouTubeAudio>> search(String query, {int maxResults = 20}) async {
    _isSearching = true;
    _currentQuery = query;
    _hasMoreResults = true;
    _nextPageToken = null;
    notifyListeners();

    try {

      // Get search results using the search client
      final search = _yt.search;
      final searchResults = await search.search(query);
      final videos = searchResults.take(maxResults).toList();

      _currentSearchResults = videos;
      _searchPages[query] = videos;

      // Convert to YouTubeAudio objects
      final results = <YouTubeAudio>[];
      for (var video in videos) {
        try {
          results.add(YouTubeAudio.fromVideo(video));
        } catch (e) {
          debugPrint('Error processing video ${video.id}: $e');
        }
      }

      _hasMoreResults = videos.length >= maxResults;

      return results;
    } catch (e) {
      debugPrint('Error searching YouTube: $e');
      rethrow;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<List<YouTubeAudio>> searchNextPage() async {
    if (!_hasMoreResults || _currentQuery == null) {
      return [];
    }

    _isSearching = true;
    notifyListeners();

    try {
      final search = _yt.search;
      final searchResults = await search.search(_currentQuery!);

      // Skip the videos we already have
      final existingCount = _currentSearchResults?.length ?? 0;
      final newVideos = searchResults.skip(existingCount).take(20).toList();

      if (newVideos.isEmpty) {
        _hasMoreResults = false;
        return [];
      }

      _currentSearchResults?.addAll(newVideos);
      _searchPages[_currentQuery!] = _currentSearchResults ?? [];

      // Assume there are more results if we got a full page
      _hasMoreResults = newVideos.length == 20;

      return newVideos
          .map((video) {
            try {
              return YouTubeAudio.fromVideo(video);
            } catch (e) {
              debugPrint('Error processing video ${video.id}: $e');
              return null;
            }
          })
          .whereType<YouTubeAudio>()
          .toList();
    } catch (e) {
      debugPrint('Error loading next page: $e');
      rethrow;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    try {
      _yt.close();
    } catch (e) {
      debugPrint('Error disposing YoutubeSearchService: $e');
    }
    super.dispose();
  }

  // Add a method to clear search results
  void clearSearch() {
    _currentQuery = null;
    _currentSearchResults?.clear();
    _searchPages.clear();
    _hasMoreResults = true;
    _isSearching = false;
    notifyListeners();
  }
}
