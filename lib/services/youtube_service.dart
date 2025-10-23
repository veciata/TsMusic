import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'package:tsmusic/models/song.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/database/database_helper.dart';

// YouTube API anahtarı (güvenlik için daha sonra saklanmalıdır)
const String _youtubeApiKey = 'YOUR_YOUTUBE_API_KEY';

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
  
  // Audio quality preferences
  static const List<AudioQuality> _audioQualityPreference = [
    AudioQuality.high,
    AudioQuality.medium,
    AudioQuality.low,
  ];

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
    }, onError: (e) {
      debugPrint('Audio player error: $e');
      _isPlaying = false;
      notifyListeners();
    });
  }

  // Play audio from YouTube
  Future<void> playAudio(YouTubeAudio audio) async {
    try {
      _currentAudio = audio;
      isLoading.value = true;
      notifyListeners();

      // Clear any previous errors
      _audioPlayer.stop();
      
      // Try different methods to get the audio stream
      String? audioUrl = await _getAudioStream(audio.id);
      
      if (audioUrl == null) {
        throw Exception('Ses akışı alınamadı. Lütfen daha sonra tekrar deneyin.');
      }

      debugPrint('Playing audio from URL: $audioUrl');
      
      // Set audio source with better error handling
      try {
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
          preload: true, // Preload the audio for better performance
        );

        // Wait for the audio to be ready
        await _audioPlayer.load();
        
        // Start playing
        await _audioPlayer.play();
        _isPlaying = true;
        
        debugPrint('Audio playback started successfully');
      } catch (e) {
        debugPrint('Error setting audio source: $e');
        throw Exception('Ses çalınamadı: ${e.toString()}');
      }
      
      // Update the current audio with the latest info
      _currentAudio = YouTubeAudio(
        id: audio.id,
        title: audio.title,
        author: audio.author,
        artists: audio.artists,
        duration: audio.duration,
        thumbnailUrl: audio.thumbnailUrl,
        audioUrl: audioUrl,
      );
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing YouTube audio: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }
  
  // Try different methods to get the audio stream
  Future<String?> _getAudioStream(String videoId) async {
    // Try YouTube Explode first (most reliable method)
    try {
      final url = await _getExplodeAudioStream(videoId);
      if (url != null) return url;
    } catch (e) {
      debugPrint('YouTube Explode method failed: $e');
    }
    
    // Fallback to direct method
    try {
      final url = await _getDirectAudioStream(videoId);
      if (url != null) return url;
    } catch (e) {
      debugPrint('Direct method failed: $e');
    }
    
    // As a last resort, try using yt-dlp/yt-dlp-ffmpeg
    try {
      final url = await _getYtDlpStream(videoId);
      if (url != null) return url;
    } catch (e) {
      debugPrint('yt-dlp method failed: $e');
    }
    
    return null;
  }
  
  // Get audio stream using yt-dlp
  Future<String?> _getYtDlpStream(String videoId) async {
    try {
      final result = await Process.run('yt-dlp', [
        '--format', 'bestaudio/best',
        '--get-url',
        'https://www.youtube.com/watch?v=$videoId'
      ]);
      
      if (result.exitCode == 0) {
        final url = result.stdout.toString().trim();
        if (url.isNotEmpty) {
          debugPrint('Got audio URL from yt-dlp: $url');
          return url;
        }
      } else {
        debugPrint('yt-dlp error: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('Error in yt-dlp: $e');
    }
    return null;
  }
  
  // Get audio stream using direct method
  Future<String?> _getDirectAudioStream(String videoId) async {
    try {
      final response = await http.post(
        Uri.https('www.youtube.com', '/youtubei/v1/player', {'key': _youtubeApiKey}),
        headers: {
          'Content-Type': 'application/json',
        },
        body: '{"videoId":"$videoId","context":{"client":{"clientName":"ANDROID","clientVersion":"17.10.35","androidSdkVersion":30}}}',
      );
      
      if (response.statusCode == 200) {
        // Parse the response to get the streaming URL
        // This is a simplified example - you'll need to parse the actual response
        final regex = RegExp(r'"url"\s*:\s*"(https?://[^"]+mime=audio[^"]+)"');
        final match = regex.firstMatch(response.body);
        if (match != null) {
          return match.group(1)?.replaceAll('\\u0026', '&');
        }
      }
    } catch (e) {
      debugPrint('Error in direct audio stream: $e');
    }
    return null;
  }
  
  // Get audio stream using YouTube Explode with retry logic
  Future<String?> _getExplodeAudioStream(String videoId, {int retryCount = 2}) async {
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        debugPrint('Attempt $attempt to get stream for video $videoId');
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        
        // Try different audio qualities
        for (final quality in _audioQualityPreference) {
          try {
            // Filter streams by codec and sort by bitrate (highest first)
            final streams = manifest.audio
                .where((s) => s.audioCodec == 'mp4' || s.audioCodec == 'm4a' || s.audioCodec == 'webm')
                .toList()
                ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
                
            if (streams.isNotEmpty) {
              final stream = streams.first;
              debugPrint('Found audio stream: ${stream.url} (${stream.bitrate} bps)');
              return stream.url.toString();
            }
          } catch (e) {
            debugPrint('Error processing stream quality: $e');
            continue;
          }
        }
        
        // If no preferred quality found, try any audio stream
        final anyAudio = manifest.audio.firstOrNull;
        if (anyAudio != null) {
          debugPrint('Falling back to any available audio stream: ${anyAudio.url}');
          return anyAudio.url.toString();
        }
      } catch (e) {
        debugPrint('Error in YouTube Explode audio stream (attempt $attempt): $e');
        if (attempt == retryCount) {
          rethrow;
        }
        // Wait a bit before retrying
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

  Future<String?> _getBestAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // Try to get audio-only streams first
      final audioStreams = manifest.audio;
      if (audioStreams.isNotEmpty) {
        return audioStreams.withHighestBitrate().url.toString();
      }
      
      // If no audio-only streams, try muxed streams
      final muxedStreams = manifest.muxed;
      if (muxedStreams.isNotEmpty) {
        // Sort by quality and get the best one
        final sortedStreams = muxedStreams.toList()
          ..sort((a, b) => (b.bitrate.bitsPerSecond).compareTo(a.bitrate.bitsPerSecond));
        return sortedStreams.first.url.toString();
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting audio stream URL: $e');
      return null;
    }
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      // First try to get the manifest
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final audioStream = audioStreams.withHighestBitrate();
          return audioStream.url.toString();
        }
      } catch (e) {
        debugPrint('Error getting stream manifest: $e');
      }

      // If manifest fails, try to get the video details and use the muxed streams
      try {
        final video = await _yt.videos.get(videoId);
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final streams = manifest.muxed;
        if (streams.isNotEmpty) {
          // Try to find a medium quality stream first
          var stream = streams.firstWhere(
            (s) => s.videoQuality.name.contains('medium'),
            orElse: () => streams.first,
          );
          return stream.url.toString();
        }
      } catch (e) {
        debugPrint('Error getting muxed streams: $e');
      }

      // If all else fails, try to get the video URL directly
      try {
        final video = await _yt.videos.get(videoId);
        return 'https://www.youtube.com/watch?v=$videoId';
      } catch (e) {
        debugPrint('Error getting video URL: $e');
      }

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

  /// Creates a unique numeric ID for YouTube songs
  /// Uses the video ID and file path to generate a consistent hash
  int _createYouTubeSongId(String videoId, String filePath) {
    // Combine video ID and file path for uniqueness
    final uniqueString = '${videoId}_$filePath';
    // Generate a positive integer hash
    return uniqueString.hashCode & 0x7FFFFFFF; // Ensure positive integer
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
        // First, check if song already exists by file path
        final existingSongs = await txn.query(
          DatabaseHelper.tableSongs,
          where: 'file_path = ?',
          whereArgs: [filePath],
        );

        if (existingSongs.isNotEmpty) {
          // Song already exists, no need to add it again
          return;
        }
        
        // Create song without specifying ID to let the database auto-generate it
        final songMap = {
          'title': video.title,
          'file_path': filePath,
          'duration': video.duration?.inMilliseconds ?? 0,
          'is_downloaded': 1,
          'created_at': DateTime.now().toIso8601String(),
        };

        // Insert song and get the auto-generated ID
        final songId = await txn.insert(
          DatabaseHelper.tableSongs,
          songMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Get or create artist
        final artistId = await _getOrCreateArtist(txn, video.author.isNotEmpty ? video.author : 'Unknown Artist');
        
        // Link song to artist
        await txn.insert(
          DatabaseHelper.tableSongArtist,
          {
            'song_id': songId,
            'artist_id': artistId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        // Add tags
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

      // Notify the music provider to refresh its data
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
    
    // Insert new artist and return the ID
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
    
    // Insert new genre and return the ID
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
    super.dispose();
  }
}
