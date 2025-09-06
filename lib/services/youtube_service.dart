import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/new_music_provider.dart';
import 'package:tsmusic/models/song.dart';

class YouTubeAudio {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? audioUrl;

  YouTubeAudio({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    this.thumbnailUrl,
    this.audioUrl,
  });

  factory YouTubeAudio.fromVideo(Video video) {
    Duration? safeDuration;
    try {
      safeDuration =
          video.duration != null && video.duration!.inMilliseconds > 0
              ? video.duration
              : null;
    } catch (e) {
      print('Error parsing video duration: $e');
      safeDuration = null;
    }

    return YouTubeAudio(
      id: video.id.value,
      title: video.title,
      author: video.author,
      duration: safeDuration,
      thumbnailUrl: video.thumbnails.mediumResUrl,
    );
  }
}

class DownloadProgress {
  final String videoId;
  final String title;
  double progress;
  bool isDownloading;
  String? error;
  bool cancelRequested;
  StreamSubscription<List<int>>? subscription;
  final Completer<void>? completer;

  DownloadProgress({
    required this.videoId,
    required this.title,
    this.progress = 0.0,
    this.isDownloading = true,
    this.error,
    this.cancelRequested = false,
    this.subscription,
    this.completer,
  });
}

class YouTubeService extends ChangeNotifier {
  static final YoutubeExplode _yt = YoutubeExplode();
  static final http.Client _httpClient = http.Client();
  static bool _isDisposed = false;

  YouTubeService._internal() {
    _isDisposed = false;
  }

  static final YouTubeService _instance = YouTubeService._internal();

  factory YouTubeService() {
    if (_isDisposed) {
      throw StateError('YouTubeService was disposed and cannot be used again');
    }
    return _instance;
  }

  final Map<String, DownloadProgress> _activeDownloads = {};

  // Static method to close all resources (call this from main.dart on app shutdown)
  static Future<void> close() async {
    if (_isDisposed) return;

    try {
      // Wait for all downloads to complete or timeout after 5 seconds
      await Future.any([
        Future.delayed(const Duration(seconds: 5)),
        Future.wait(_instance._activeDownloads.keys.map((id) =>
            _instance._activeDownloads[id]?.completer?.future ??
            Future.value()))
      ]);

      _yt.close();
    } catch (e) {
      debugPrint('Error closing YouTube client: $e');
    }

    try {
      _httpClient.close();
    } catch (e) {
      debugPrint('Error closing HTTP client: $e');
    } finally {
      _isDisposed = true;
    }
  }

  List<DownloadProgress> get activeDownloads =>
      _activeDownloads.values.toList();

  // Cache search pages per query for pagination
  final Map<String, VideoSearchList> _searchPages = {};

  void _notifyProgressUpdate() {
    notifyListeners();
  }

  void _addActiveDownload(String videoId, String title) {
    _activeDownloads[videoId] = DownloadProgress(
      videoId: videoId,
      title: title,
      progress: 0.0,
      isDownloading: true,
      completer: Completer<void>(),
    );
    _notifyProgressUpdate();
  }

  void _updateDownloadProgress(String videoId, double progress) {
    if (_activeDownloads.containsKey(videoId)) {
      _activeDownloads[videoId]!.progress = progress;
      _activeDownloads[videoId]!.isDownloading = progress < 1.0;
      _notifyProgressUpdate();
    }
  }

  void _removeDownload(String videoId, {String? error}) {
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!;
      if (error != null) {
        download.error = error;
        download.isDownloading = false;
        // Avoid throwing for user-initiated cancels; complete gracefully
        if (error == 'Canceled by user') {
          download.completer?.complete();
        } else {
          download.completer?.completeError(error);
        }
      } else {
        download.completer?.complete();
      }
      // Cancel any subscription if still active
      try {
        download.subscription?.cancel();
      } catch (_) {}
      _activeDownloads.remove(videoId);
      _notifyProgressUpdate();
    }
  }

  Future<bool> cancelDownload(String videoId) async {
    final d = _activeDownloads[videoId];
    if (d == null) return false;
    d.cancelRequested = true;
    d.isDownloading = false;
    _notifyProgressUpdate();
    try {
      // Let the streaming loop handle cleanup; just cancel the subscription
      await d.subscription?.cancel();
    } catch (_) {}
    // Do not call _removeDownload here to avoid racing with the download loop
    return true;
  }

  Future<List<YouTubeAudio>> searchAudio(String query) async {
    try {
      final searchResults = await _yt.search.search(query);
      // Cache the first page for pagination
      _searchPages[query] = searchResults;
      final videos = searchResults.whereType<Video>().toList();
      return videos.map((video) => YouTubeAudio.fromVideo(video)).toList();
    } catch (e) {
      print('Error searching YouTube: $e');
      return [];
    }
  }

  Future<List<YouTubeAudio>> searchAudioNextPage(String query) async {
    try {
      final VideoSearchList? current = _searchPages[query];
      if (current == null) return [];
      final VideoSearchList? next = await current.nextPage();
      if (next == null) return [];
      _searchPages[query] = next;
      final videos = next.whereType<Video>().toList();
      return videos.map((video) => YouTubeAudio.fromVideo(video)).toList();
    } catch (e) {
      print('Error loading next page for "$query": $e');
      return [];
    }
  }

  Future<String?> getStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStream = manifest.audioOnly.withHighestBitrate();
      if (audioStream != null) {
        return audioStream.url.toString();
      }
      return null;
    } catch (e) {
      print('Error getting stream URL: $e');
      return null;
    }
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) return null;
      final audioStream = audioStreams.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      print('Error getting audio stream URL: $e');
      return null;
    }
  }

  Future<String?> downloadAudio(
    String videoId, {
    void Function(double)? onProgress,
    required BuildContext context,
  }) async {
    debugPrint('Starting audio download for video: $videoId');

    if (!await _checkStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission required')),
        );
      }
      return null;
    }

    try {
      final video = await _yt.videos.get(videoId);
      debugPrint('Video title: ${video.title}');

      final safeTitle =
          '${video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.mp3';

      _addActiveDownload(videoId, video.title);
      if (onProgress != null) onProgress(0.0);
      _updateDownloadProgress(videoId, 0.0);

      Directory? musicDir;
      if (kIsWeb) {
        debugPrint('Web download not supported yet');
        return null;
      } else if (Platform.isAndroid || Platform.isIOS) {
        try {
          musicDir = Directory('/storage/emulated/0/Music/tsmusic');
          if (!await musicDir.exists()) {
            await musicDir.create(recursive: true);
          }
        } catch (e) {
          final appDocDir = await getApplicationDocumentsDirectory();
          musicDir = Directory('${appDocDir.path}/tsmusic');
          if (!await musicDir.exists()) {
            await musicDir.create(recursive: true);
          }
        }
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        musicDir = Directory('${appDocDir.path}/tsmusic');
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
      }

      final file = File('${musicDir!.path}/$safeTitle');

      if (await file.exists()) {
        debugPrint('File already exists at: ${file.path}');
        await _addDownloadedSongToLibrary(
          context: context,
          filePath: file.path,
          video: video,
        );
        _updateDownloadProgress(videoId, 1.0);
        _removeDownload(videoId);
        return file.path;
      }

      final audioUrl = await getAudioStreamUrl(videoId);
      if (audioUrl == null) {
        debugPrint('Failed to get audio stream URL');
        _updateDownloadProgress(videoId, 0.0);
        _removeDownload(videoId, error: 'Failed to get audio stream');
        return null;
      }

      try {
        final request = http.Request('GET', Uri.parse(audioUrl));
        final response = await _httpClient.send(request);

        if (response.statusCode != 200) {
          debugPrint(
              'Failed to download audio. Status code: ${response.statusCode}');
          _updateDownloadProgress(videoId, 0.0);
          _removeDownload(videoId,
              error: 'Download failed with status ${response.statusCode}');
          return null;
        }

        final contentLength = response.contentLength ?? 0;
        int receivedLength = 0;
        final bytes = <int>[];
        final done = Completer<void>();

        // attach subscription for cancellation
        final sub = response.stream.listen((chunk) {
          if (_activeDownloads[videoId]?.cancelRequested == true) {
            // Ignore further processing; cancellation will be handled
            return;
          }
          bytes.addAll(chunk);
          receivedLength += chunk.length;

          if (contentLength > 0) {
            final progress = receivedLength / contentLength;
            _updateDownloadProgress(videoId, progress);
            onProgress?.call(progress);
          }
        }, onError: (e) {
          if (!done.isCompleted) done.completeError(e);
        }, onDone: () {
          if (!done.isCompleted) done.complete();
        }, cancelOnError: true);

        // store subscription reference
        final progressRef = _activeDownloads[videoId];
        if (progressRef != null) {
          progressRef.subscription = sub;
        }

        try {
          await done.future;
        } catch (e) {
          // If canceled, treat gracefully
          if (_activeDownloads[videoId]?.cancelRequested == true) {
            debugPrint('Download canceled by user for $videoId');
            _removeDownload(videoId, error: 'Canceled by user');
            return null;
          }
          rethrow;
        } finally {
          try {
            await sub.cancel();
          } catch (_) {}
        }

        // If canceled after completion, bail out
        if (_activeDownloads[videoId]?.cancelRequested == true) {
          return null;
        }

        await file.writeAsBytes(bytes);
        debugPrint('File downloaded to: ${file.path}');

        await _addDownloadedSongToLibrary(
          context: context,
          filePath: file.path,
          video: video,
        );

        _updateDownloadProgress(videoId, 1.0);
        _removeDownload(videoId);
        return file.path;
      } catch (e) {
        debugPrint('Error downloading audio: $e');
        _removeDownload(videoId, error: 'Download failed: $e');
        return null;
      }
    } catch (e) {
      debugPrint('Error preparing download: $e');
      _removeDownload(videoId, error: 'Preparation failed: $e');
      return null;
    }
  }

  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    return status.isGranted;
  }

  String _createYouTubeSongId(String videoId, String filePath) {
    final pathHash = filePath.hashCode.toRadixString(16).substring(0, 8);
    return 'yt_${videoId}_$pathHash';
  }

  bool _isDuplicateSong(
    NewMusicProvider musicProvider,
    String title,
    String artist,
  ) {
    final normalizedTitle = title.toLowerCase().trim();
    final normalizedArtist = artist.toLowerCase().trim();
    return musicProvider.songs.any(
      (song) =>
          song.title.toLowerCase().trim() == normalizedTitle &&
          song.artist.toLowerCase().trim() == normalizedArtist,
    );
  }

  Future<void> _addDownloadedSongToLibrary({
    required BuildContext context,
    required String filePath,
    required Video video,
  }) async {
    try {
      final musicProvider =
          Provider.of<NewMusicProvider>(context, listen: false);
      final songId = _createYouTubeSongId(video.id.value, filePath);

      final existingSong = musicProvider.songs.firstWhere(
        (s) => s.id == songId,
        orElse: () => Song(
          id: '',
          title: '',
          artist: '',
          url: '',
          duration: 0,
        ),
      );

      if (existingSong.id.isNotEmpty) {
        if (!existingSong.hasTag('tsmusic')) {
          final updatedTags = List<String>.from(existingSong.tags)
            ..add('tsmusic');
          await musicProvider.updateSong(
            existingSong.copyWith(tags: updatedTags),
          );
        }
        return;
      }

      final song = Song(
        id: songId,
        title: video.title,
        artist: video.author,
        album: 'YouTube Downloads',
        albumArtUrl: video.thumbnails.mediumResUrl,
        url: filePath,
        duration: video.duration?.inMilliseconds ?? 0,
        isFavorite: false,
        tags: ['tsmusic'],
      );

      await musicProvider.addSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to library: ${song.title}')),
        );
      }
    } catch (e) {
      debugPrint('Error adding downloaded song to library: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error adding song to library')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Clear all active downloads and complete their completers with an error
    for (final download in _activeDownloads.values) {
      download.completer?.completeError('Service was disposed');
    }
    _activeDownloads.clear();
    super.dispose();
  }
}
