import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/music_provider.dart';
import 'package:tsmusic/models/song.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/database/database_helper.dart';

// Audio quality enum
enum AudioQuality {
  high,
  medium,
  low,
}

class YouTubeAudio {
  final String id;
  final String title;
  final String author;
  final List<String> artists;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? audioUrl;

  YouTubeAudio({
    required this.id,
    required this.title,
    required this.author,
    required this.artists,
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
      safeDuration = null;
    }

    final authors = video.author.split(',').map((a) => a.trim()).toList();

    return YouTubeAudio(
      id: video.id.value,
      title: video.title,
      author: video.author,
      artists: authors.isNotEmpty ? authors : ['Unknown Artist'],
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

class YouTubeService with ChangeNotifier {
  static final YoutubeExplode _yt = YoutubeExplode();
  static final http.Client _httpClient = http.Client();
  static bool _isDisposed = false;
  static final YouTubeService _instance = YouTubeService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;
  bool _isPlaying = false;
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final Map<String, VideoSearchList> _searchPages = {};

  // Getters
  List<DownloadProgress> get activeDownloads => _activeDownloads.values.toList();
  YouTubeAudio? get currentAudio => _currentAudio;
  bool get isPlaying => _audioPlayer.playing;

  // Factory constructor
  factory YouTubeService() {
    if (_isDisposed) {
      throw StateError('YouTubeService was disposed and cannot be used again');
    }
    return _instance;
  }

  // Private constructor
  YouTubeService._internal() {
    _isDisposed = false;
    _init();
  }

  void _init() {
    // Initialize audio player
    _audioPlayer.playbackEventStream.listen((event) {
      _isPlaying = _audioPlayer.playing;
      notifyListeners();
    }, onError: (e, stackTrace) {
      debugPrint('Audio player error: $e\n$stackTrace');
      _isPlaying = false;
      notifyListeners();
    });
  }

  // Play audio from YouTube
  
Future<void> playAudio(YouTubeAudio audio) async {
  try {
    _currentAudio = audio;
    isLoading.value = true;
    await _audioPlayer.stop();

    final audioUrl = await _getExplodeAudioStream(audio.id);
    if (audioUrl == null) throw Exception('Audio stream not found');

    await _audioPlayer.setAudioSource(
      AudioSource.uri(
        Uri.parse(audioUrl),
        tag: MediaItem(
          id: audio.id,
          title: audio.title,
          artist: audio.author,
          artUri: audio.thumbnailUrl != null ? Uri.parse(audio.thumbnailUrl!) : null,
        ),
      ),
    );

    await _audioPlayer.play();
    _isPlaying = true;
    notifyListeners();
  } catch (e) {
    debugPrint('Error streaming audio: $e');
  } finally {
    isLoading.value = false;
  }
}


  // Get audio stream using YouTube Explode
  Future<String?> _getAudioStream(String videoId) async {
    try {
      final url = await _getExplodeAudioStream(videoId);
      if (url != null) return url;
      debugPrint('No audio stream found for video $videoId');
      return null;
    } catch (e, stackTrace) {
      debugPrint('YouTube Explode failed: $e\n$stackTrace');
      return null;
    }
  }

  // Get audio stream using YouTube Explode with retry logic
  Future<String?> _getExplodeAudioStream(String videoId, {int retryCount = 3}) async {
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        debugPrint('Attempt $attempt to get stream for video $videoId');
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);

        // Önce audio-only stream'leri dene
        final audioOnly = manifest.audioOnly;
        if (audioOnly.isNotEmpty) {
          final bestAudio = audioOnly.withHighestBitrate();
          debugPrint('Found audio-only stream: ${bestAudio.url} (${bestAudio.bitrate} bps)');
          return bestAudio.url.toString();
        }

        // Audio-only yoksa, muxed stream'leri dene
        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          final sortedMuxed = muxed.toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
          final bestMuxed = sortedMuxed.first;
          debugPrint('Fallback to muxed stream: ${bestMuxed.url} (${bestMuxed.bitrate} bps)');
          return bestMuxed.url.toString();
        }

        debugPrint('No suitable stream found in attempt $attempt');
      } catch (e, stackTrace) {
        debugPrint('Error in YouTube Explode (attempt $attempt): $e\n$stackTrace');
        if (attempt == retryCount) {
          return null;
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  // Pause audio
  Future<void> pause() async {
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  // Stop audio
  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentAudio = null;
    _isPlaying = false;
    notifyListeners();
  }

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
        if (error == 'Canceled by user') {
          download.completer?.complete();
        } else {
          download.completer?.completeError(error);
        }
      } else {
        download.completer?.complete();
      }
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
      await d.subscription?.cancel();
    } catch (_) {}
    return true;
  }

  Future<List<YouTubeAudio>> searchAudio(String query) async {
    try {
      final searchResults = await _yt.search.search(query);
      _searchPages[query] = searchResults;
      final videos = searchResults.whereType<Video>().toList();
      return videos.map((video) => YouTubeAudio.fromVideo(video)).toList();
    } catch (e) {
      debugPrint('Error searching YouTube: $e');
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
      debugPrint('Error loading next page for "$query": $e');
      return [];
    }
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final url = await _getExplodeAudioStream(videoId);
      if (url != null) return url;
      return null;
    } catch (e) {
      debugPrint('Error getting audio stream URL: $e');
      rethrow;
    }
  }

  Future<String?> downloadAudio(
    String videoId, {
    void Function(double)? onProgress,
    required BuildContext context,
  }) async {
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
      final safeTitle =
          '${video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.opus';
      _addActiveDownload(videoId, video.title);
      if (onProgress != null) onProgress(0.0);
      _updateDownloadProgress(videoId, 0.0);

      Directory? musicDir;
      if (kIsWeb) return null;
      else if (Platform.isAndroid || Platform.isIOS) {
        try {
          musicDir = Directory('/storage/emulated/0/Music/tsmusic');
          if (!await musicDir.exists()) await musicDir.create(recursive: true);
        } catch (e) {
          final appDocDir = await getApplicationDocumentsDirectory();
          musicDir = Directory('${appDocDir.path}/tsmusic');
          if (!await musicDir.exists()) await musicDir.create(recursive: true);
        }
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        musicDir = Directory('${appDocDir.path}/tsmusic');
        if (!await musicDir.exists()) await musicDir.create(recursive: true);
      }

      final file = File('${musicDir!.path}/$safeTitle');
      if (await file.exists()) {
        await _addDownloadedSongToLibrary(
          videoId: videoId,
          filePath: file.path,
          context: context,
        );
        _updateDownloadProgress(videoId, 1.0);
        _removeDownload(videoId);
        return file.path;
      }

      final audioUrl = await getAudioStreamUrl(videoId);
      if (audioUrl == null) {
        _updateDownloadProgress(videoId, 0.0);
        _removeDownload(videoId, error: 'Failed to get audio stream');
        return null;
      }

      final request = http.Request('GET', Uri.parse(audioUrl));
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        _updateDownloadProgress(videoId, 0.0);
        _removeDownload(videoId, error: 'Download failed with status ${response.statusCode}');
        return null;
      }

      final contentLength = response.contentLength ?? 0;
      int receivedLength = 0;
      final bytes = <int>[];
      final done = Completer<void>();

      final sub = response.stream.listen((chunk) {
        if (_activeDownloads[videoId]?.cancelRequested == true) return;
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

      _activeDownloads[videoId]?.subscription = sub;

      try {
        await done.future;
      } catch (e) {
        if (_activeDownloads[videoId]?.cancelRequested == true) {
          _removeDownload(videoId, error: 'Canceled by user');
          return null;
        }
        rethrow;
      } finally {
        try {
          await sub.cancel();
        } catch (_) {}
      }

      if (_activeDownloads[videoId]?.cancelRequested == true) return null;

      await file.writeAsBytes(bytes);
      await _addDownloadedSongToLibrary(
        videoId: videoId,
        filePath: file.path,
        context: context,
      );
      _updateDownloadProgress(videoId, 1.0);
      _removeDownload(videoId);
      return file.path;
    } catch (e) {
      _removeDownload(videoId, error: 'Download failed: $e');
      return null;
    }
  }

  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    return status.isGranted;
  }

  int _createYouTubeSongId(String videoId, String filePath) {
    final uniqueString = '${videoId}_$filePath';
    return uniqueString.hashCode & 0x7FFFFFFF;
  }

  Future<void> _addDownloadedSongToLibrary({
    required String videoId,
    required String filePath,
    required BuildContext context,
  }) async {
    try {
      final video = await _yt.videos.get(videoId);
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      await db.transaction((txn) async {
        final existingSongs = await txn.query(
          DatabaseHelper.tableSongs,
          where: 'file_path = ?',
          whereArgs: [filePath],
        );

        if (existingSongs.isNotEmpty) {
          return;
        }

        final songMap = {
          'title': video.title,
          'file_path': filePath,
          'duration': video.duration?.inMilliseconds ?? 0,
          'is_downloaded': 1,
          'created_at': DateTime.now().toIso8601String(),
        };

        final songId = await txn.insert(
          DatabaseHelper.tableSongs,
          songMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final artistId = await _getOrCreateArtist(txn, video.author.isNotEmpty ? video.author : 'Unknown Artist');

        await txn.insert(
          DatabaseHelper.tableSongArtist,
          {
            'song_id': songId,
            'artist_id': artistId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        await txn.insert(
          DatabaseHelper.tableSongGenre,
          {
            'song_id': songId,
            'genre_id': await _getOrCreateGenre(txn, 'tsmusic'),
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });

      if (context.mounted) {
        final musicProvider = Provider.of<MusicProvider>(context, listen: false);
        await musicProvider.loadLocalMusic();
      }
    } catch (e) {
      debugPrint('Error adding downloaded song to library: $e');
      rethrow;
    }
  }

  Future<int> _getOrCreateArtist(DatabaseExecutor db, String name) async {
    final result = await db.query(
      DatabaseHelper.tableArtists,
      where: '${DatabaseHelper.columnName} = ?',
      whereArgs: [name],
    );

    if (result.isNotEmpty) return result.first[DatabaseHelper.columnId] as int;

    return await db.insert(
      DatabaseHelper.tableArtists,
      {
        DatabaseHelper.columnName: name,
        DatabaseHelper.columnCreatedAt: DateTime.now().toIso8601String(),
      },
    );
  }

  Future<int> _getOrCreateGenre(DatabaseExecutor db, String name) async {
    final result = await db.query(
      DatabaseHelper.tableGenres,
      where: '${DatabaseHelper.columnName} = ?',
      whereArgs: [name],
    );

    if (result.isNotEmpty) return result.first[DatabaseHelper.columnId] as int;

    return await db.insert(
      DatabaseHelper.tableGenres,
      {
        DatabaseHelper.columnName: name,
        DatabaseHelper.columnCreatedAt: DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  void dispose() {
    for (final download in _activeDownloads.values) {
      download.completer?.completeError('Service disposed');
    }
    _activeDownloads.clear();
    _audioPlayer.dispose();
    isLoading.dispose();
    _yt.close();
    super.dispose();
  }
}
