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
    final baseDir = await getApplicationDocumentsDirectory();
    _thumbnailsDir = Directory(path.join(baseDir.path, 'thumbnails'));
    if (!await _thumbnailsDir!.exists()) {
      await _thumbnailsDir!.create(recursive: true);
    }
  }

  Future<String?> _getExistingPath(String youtubeId) async {
    if (_thumbnailsDir == null) return null;
    final file = File(path.join(_thumbnailsDir!.path, '${youtubeId}_thumb.jpg'));
    if (await file.exists()) return file.path;
    return null;
  }

  void requestThumbnail(Song song, {int priority = 2}) {
    if (song.youtubeId == null || song.youtubeId!.isEmpty) return;
    if (song.localThumbnailPath != null) return;
    if (_inProgress.contains(song.youtubeId!)) return;

    _queue.add(_PriorityItem(song, priority));
    _sortQueue();
    _processQueue();
  }

  void requestThumbnailForAll(List<Song> songs) {
    for (final song in songs) {
      if (song.youtubeId != null &&
          song.youtubeId!.isNotEmpty &&
          song.localThumbnailPath == null &&
          !_inProgress.contains(song.youtubeId!)) {
        _queue.add(_PriorityItem(song, 2));
      }
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
      if (item.song.youtubeId == null) continue;
      if (item.song.localThumbnailPath != null) continue;

      final videoId = item.song.youtubeId!;
      _inProgress.add(videoId);

      try {
        final existing = await _getExistingPath(videoId);
        if (existing != null) {
          onThumbnailReady?.call(item.song, existing);
          _inProgress.remove(videoId);
          continue;
        }

        final video = await _yt.videos.get(videoId);
        final thumbUrl = video.thumbnails.mediumResUrl;

        final response = await _httpClient.get(Uri.parse(thumbUrl));
        if (response.statusCode == 200 && _thumbnailsDir != null) {
          final file = File(path.join(_thumbnailsDir!.path, '${videoId}_thumb.jpg'));
          await file.writeAsBytes(response.bodyBytes);
          onThumbnailReady?.call(item.song, file.path);
        } else {
          onThumbnailFailed?.call(item.song);
        }
      } catch (e) {
        debugPrint('Thumbnail failed for ${item.song.youtubeId}: $e');
        onThumbnailFailed?.call(item.song);
      } finally {
        _inProgress.remove(videoId);
      }
    }

    _processing = false;
  }

  void dispose() {
    _queue.clear();
    _inProgress.clear();
    _httpClient.close();
  }
}
