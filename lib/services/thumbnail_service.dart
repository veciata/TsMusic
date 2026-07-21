import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:tsmusic/models/song.dart';

class _PriorityItem {
  final Song song;
  final int priority;
  _PriorityItem(this.song, this.priority);
}

class ThumbnailService {
  static ThumbnailService? _instance;

  final http.Client _httpClient;
  final YoutubeExplode _yt;
  Directory? _thumbnailsDir;

  final Set<String> _inProgress = {};
  final Queue<_PriorityItem> _queue = Queue();
  bool _processing = false;

  // Cache for artist thumbnails to avoid repeated lookups
  final Set<String> _artistLookupAttempted = {};

  void Function(Song song, String localPath)? onThumbnailReady;
  void Function(Song song)? onThumbnailFailed;

  ThumbnailService({http.Client? httpClient, YoutubeExplode? yt})
    : _httpClient = httpClient ?? http.Client(),
      _yt = yt ?? YoutubeExplode() {
    _instance = this;
    _initDir();
  }

  static ThumbnailService? get instance => _instance;

  Future<void> _initDir() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _thumbnailsDir = Directory(path.join(appDir.path, 'thumbnails'));
      if (!await _thumbnailsDir!.exists()) {
        await _thumbnailsDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('ThumbnailService: Failed to init dir: $e');
    }
  }

  Future<String?> _getExistingPath(String youtubeId) async {
    if (_thumbnailsDir == null) return null;
    final file = File(
      path.join(_thumbnailsDir!.path, '${youtubeId}_thumb.jpg'),
    );
    if (await file.exists()) return file.path;
    return null;
  }

  Future<String?> _getExistingArtistPath(String artistName) async {
    if (_thumbnailsDir == null) return null;
    final safeName = _safeArtistName(artistName);
    final file = File(
      path.join(_thumbnailsDir!.path, 'artist_${safeName}_thumb.jpg'),
    );
    if (await file.exists()) return file.path;
    return null;
  }

  String _safeArtistName(String name) {
    // Sanitize artist name for use as a filename
    return name.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  void requestThumbnail(Song song, {int priority = 2}) {
    if (song.localThumbnailPath != null) return;

    if (song.youtubeId != null && song.youtubeId!.isNotEmpty) {
      if (_inProgress.contains(song.youtubeId!)) return;
      _queue.add(_PriorityItem(song, priority));
      _sortQueue();
      _processQueue();
    } else {
      // No youtubeId — fall back to artist cover
      if (song.artists.isEmpty) return;
      final artist = song.artists.first;
      final key = 'artist:$artist';
      if (_inProgress.contains(key)) return;
      _queue.add(_PriorityItem(song, priority));
      _sortQueue();
      _processQueue();
    }
  }

  void requestThumbnailForAll(List<Song> songs) {
    for (final song in songs) {
      if (song.localThumbnailPath != null) continue;
      if (song.youtubeId != null &&
          song.youtubeId!.isNotEmpty &&
          _inProgress.contains(song.youtubeId!))
        continue;
      if (song.youtubeId == null || song.youtubeId!.isEmpty) {
        if (song.artists.isNotEmpty) {
          final key = 'artist:${song.artists.first}';
          if (_inProgress.contains(key)) continue;
        }
      }
      _queue.add(_PriorityItem(song, 2));
    }
    _sortQueue();
    _processQueue();
  }

  void _sortQueue() {
    final list = _queue.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    _queue.clear();
    _queue.addAll(list);
  }

  Future<void> _processQueue() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      if (item.song.localThumbnailPath != null) continue;

      if (item.song.youtubeId != null && item.song.youtubeId!.isNotEmpty) {
        await _processVideoThumbnail(item);
      } else if (item.song.artists.isNotEmpty) {
        await _processArtistThumbnail(item);
      }
    }

    _processing = false;
  }

  Future<void> _processVideoThumbnail(_PriorityItem item) async {
    final videoId = item.song.youtubeId!;
    _inProgress.add(videoId);

    try {
      final existing = await _getExistingPath(videoId);
      if (existing != null) {
        onThumbnailReady?.call(item.song, existing);
        _inProgress.remove(videoId);
        return;
      }

      final video = await _yt.videos.get(videoId);
      final thumbUrl = video.thumbnails.mediumResUrl;

      final response = await _httpClient.get(Uri.parse(thumbUrl));
      if (response.statusCode == 200 && _thumbnailsDir != null) {
        final file = File(
          path.join(_thumbnailsDir!.path, '${videoId}_thumb.jpg'),
        );
        await file.writeAsBytes(response.bodyBytes);
        onThumbnailReady?.call(item.song, file.path);
      } else {
        // YouTube thumbnail failed — fall back to artist cover
        await _fallbackToArtistThumbnail(item);
      }
    } catch (e) {
      debugPrint('Thumbnail failed for ${item.song.youtubeId}: $e');
      await _fallbackToArtistThumbnail(item);
    } finally {
      _inProgress.remove(videoId);
    }
  }

  Future<void> _processArtistThumbnail(_PriorityItem item) async {
    final artist = item.song.artists.first;
    final key = 'artist:$artist';
    _inProgress.add(key);

    try {
      await _fetchArtistThumbnail(artist, item.song);
    } catch (e) {
      debugPrint('Artist thumbnail failed for "$artist": $e');
      onThumbnailFailed?.call(item.song);
    } finally {
      _inProgress.remove(key);
    }
  }

  Future<void> _fallbackToArtistThumbnail(_PriorityItem item) async {
    if (item.song.artists.isEmpty) {
      onThumbnailFailed?.call(item.song);
      return;
    }

    final artist = item.song.artists.first;
    final key = 'artist:$artist';
    if (_inProgress.contains(key)) {
      // Already fetching, skip
      return;
    }

    // Check if we already have a cached artist thumbnail
    final existingArtist = await _getExistingArtistPath(artist);
    if (existingArtist != null) {
      onThumbnailReady?.call(item.song, existingArtist);
      return;
    }

    _inProgress.add(key);
    try {
      await _fetchArtistThumbnail(artist, item.song);
    } catch (e) {
      debugPrint('Artist thumbnail fallback failed for "$artist": $e');
      onThumbnailFailed?.call(item.song);
    } finally {
      _inProgress.remove(key);
    }
  }

  Future<void> _fetchArtistThumbnail(String artist, Song originalSong) async {
    if (_artistLookupAttempted.contains(artist.toLowerCase().trim())) {
      final existing = await _getExistingArtistPath(artist);
      if (existing != null) {
        onThumbnailReady?.call(originalSong, existing);
      } else {
        onThumbnailFailed?.call(originalSong);
      }
      return;
    }
    _artistLookupAttempted.add(artist.toLowerCase().trim());

    try {
      final results = await _yt.search.search(artist);
      final videos = results.whereType<Video>().toList();
      if (videos.isEmpty) {
        onThumbnailFailed?.call(originalSong);
        return;
      }

      final thumbUrl = videos.first.thumbnails.mediumResUrl;
      final response = await _httpClient.get(Uri.parse(thumbUrl));
      if (response.statusCode == 200 && _thumbnailsDir != null) {
        final safeName = _safeArtistName(artist);
        final file = File(
          path.join(_thumbnailsDir!.path, 'artist_${safeName}_thumb.jpg'),
        );
        await file.writeAsBytes(response.bodyBytes);
        onThumbnailReady?.call(originalSong, file.path);
      } else {
        onThumbnailFailed?.call(originalSong);
      }
    } catch (e) {
      debugPrint('Artist thumbnail fetch failed for "$artist": $e');
      onThumbnailFailed?.call(originalSong);
    }
  }

  void dispose() {
    _queue.clear();
    _httpClient.close();
  }
}
