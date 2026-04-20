import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/audio_format.dart';
import 'package:tsmusic/models/song.dart' as ts;
import 'package:tsmusic/utils/youtube_artist_parser.dart';

/// YouTube googlevideo akışları libmpv'nin varsayılan User-Agent'ı ile 403 döner;
/// tarayıcı benzeri başlıklar ve [Referer] gerekir (youtube_explode ile uyumlu).
Map<String, String> _youtubePlaybackHttpHeaders() => {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.youtube.com/',
      'Origin': 'https://www.youtube.com',
      'Cookie': 'CONSENT=YES+cb',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.5',
    };

class DownloadResult {
  final String filePath;
  final ts.Song song;
  DownloadResult({required this.filePath, required this.song});
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

    final artistList = YouTubeArtistParser.parseArtistName(
      video.title,
      video.author,
    );

    return YouTubeAudio(
      id: video.id.value,
      title: video.title,
      author: artistList.isNotEmpty ? artistList.first : video.author,
      artists: artistList,
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
  static YouTubeService? _instance;

  final YoutubeExplode _yt;
  final http.Client _httpClient;
  final Player _player;

  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final Map<String, VideoSearchList> _searchPages = {};

  Function()? _stopOtherPlayer;

  // Getters
  List<DownloadProgress> get activeDownloads =>
      _activeDownloads.values.toList();
  YouTubeAudio? get currentAudio => _currentAudio;
  bool get isPlaying => _player.state.playing;
  Player get player => _player;

  static YouTubeService? get instance => _instance;

  void setStopOtherPlayerCallback(Function() callback) {
    _stopOtherPlayer = callback;
  }

  // Public constructor
  YouTubeService({YoutubeExplode? yt, http.Client? httpClient, Player? player})
      : _yt = yt ?? YoutubeExplode(),
        _httpClient = httpClient ?? http.Client(),
        _player = player ?? Player() {
    _instance = this;
    _init();
  }

  void _init() {
    // Initialize audio player
    _player.stream.playing.listen((playing) {
      notifyListeners();
    });
  }

  // Play audio from YouTube
  Future<void> playAudio(YouTubeAudio audio) async {
    try {
      _currentAudio = audio;
      isLoading.value = true;
      notifyListeners();

      // Stop local player first to avoid double sound
      _stopOtherPlayer?.call();

      // Clear any previous errors
      await _player.stop();

      final String? audioUrl = await _getAudioStream(audio.id);

      if (audioUrl == null) {
        throw Exception(
            'Ses akışı alınamadı. Lütfen daha sonra tekrar deneyin.');
      }

      debugPrint('Playing audio from URL: $audioUrl');

      try {
        final headers = _youtubePlaybackHttpHeaders();
        await _player.open(Media(audioUrl, httpHeaders: headers));
        await _player.play();
        debugPrint('✅ Audio playback started successfully');
      } catch (e) {
        debugPrint('❌ Error setting audio source: $e');
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

  /// İndirme ile aynı mantık: önce androidVr, sonra varsayılan; mümkünse m4a (mp4).
  Future<String?> _getAudioStream(String videoId) async {
    try {
      debugPrint('🔧 Getting YouTube stream URL: $videoId');

      StreamManifest manifest;
      try {
        manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [YoutubeApiClient.androidVr],
        );
      } catch (e) {
        debugPrint(
            'Manifest androidVr ile alınamadı, varsayılan deneniyor: $e');
        manifest = await _yt.videos.streamsClient.getManifest(videoId);
      }

      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        debugPrint('❌ Ses akışı yok');
        return null;
      }

      final m4aStreams =
          audioStreams.where((s) => s.container.name == 'mp4').toList();
      final StreamInfo streamInfo = m4aStreams.isNotEmpty
          ? m4aStreams.reduce(
              (a, b) =>
                  a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
            )
          : audioStreams.reduce(
              (a, b) =>
                  a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
            );

      final streamUrl = streamInfo.url.toString();
      debugPrint('✅ Got YouTube stream URL (${streamInfo.container.name})');
      return streamUrl;
    } catch (e) {
      debugPrint('❌ Stream extraction failed: $e');
      return null;
    }
  }

  // Pause audio
  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  // Resume audio
  Future<void> play() async {
    if (_currentAudio != null) {
      await _player.play();
      notifyListeners();
    }
  }

  // Stop audio
  Future<void> stop() async {
    await _player.stop();
    _currentAudio = null;
    notifyListeners();
  }

  void _notifyProgressUpdate() {
    notifyListeners();
  }

  void _addActiveDownload(String videoId, String title) {
    _activeDownloads[videoId] = DownloadProgress(
      videoId: videoId,
      title: title,
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

  void _completeDownload(String videoId) {
    debugPrint('_completeDownload: Completing download for videoId: $videoId');
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!;
      if (!download.completer!.isCompleted) {
        download.completer!.complete();
      }
      _activeDownloads.remove(videoId);
      _notifyProgressUpdate();
      debugPrint(
          '_completeDownload: Download for videoId: $videoId completed and removed from active list.');
    }
  }

  Future<bool> cancelDownload(String videoId) async {
    final d = _activeDownloads[videoId];
    if (d == null) return false;

    d.cancelRequested = true;
    d.isDownloading = false;

    // Immediately remove from the list to update UI
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();

    // Background cancellation
    Future.microtask(() async {
      try {
        await d.subscription?.cancel();
        debugPrint('cancelDownload: Subscription cancelled for $videoId');
      } catch (e) {
        debugPrint('Error during background subscription cancellation: $e');
      }
    });

    return true;
  }

  Future<List<YouTubeAudio>> searchAudio(String query) async {
    try {
      final searchResults = await _yt.search.search(query);
      _searchPages[query] = searchResults;
      final videos = searchResults.whereType<Video>().toList();
      return videos.map(YouTubeAudio.fromVideo).toList();
    } catch (e) {
      debugPrint('Error searching YouTube: $e');
      rethrow;
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
      return videos.map(YouTubeAudio.fromVideo).toList();
    } catch (e) {
      debugPrint('Error loading next page for "$query": $e');
      rethrow;
    }
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streams = manifest.audioOnly;
      if (streams.isNotEmpty) {
        return streams.withHighestBitrate().url.toString();
      }
      // Audio-only streams required - no video fallback
      debugPrint(
          'getAudioStreamUrl: No audio-only streams available for videoId: $videoId');
      return null;
    } catch (e) {
      debugPrint('Error getting audio stream URL: $e');
      rethrow;
    }
  }

  Future<DownloadResult?> downloadAudio({
    required String videoId,
    void Function(double)? onProgress,
    AudioFormat preferredFormat = AudioFormat.auto,
    String downloadLocation = 'internal',
  }) async {
    if (_activeDownloads.containsKey(videoId)) {
      debugPrint(
        'downloadAudio: Download for videoId: $videoId is already in progress. Ignoring duplicate request.',
      );
      return null;
    }

    final video = await _yt.videos.get(videoId);
    _addActiveDownload(videoId, video.title);
    debugPrint('downloadAudio: Starting download for videoId: $videoId');

    try {
      StreamManifest manifest;
      try {
        // Try androidVr client - often works better for audio-only
        manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [YoutubeApiClient.androidVr],
        );
      } catch (e) {
        debugPrint(
          'Failed to get manifest with androidVr client: $e. Trying default client.',
        );
        manifest = await _yt.videos.streamsClient.getManifest(videoId);
      }

      // Select stream based on preferred format
      StreamInfo streamInfo;
      final audioStreams = manifest.audioOnly.toList();

      if (audioStreams.isEmpty) {
        throw Exception('No audio streams available for video $videoId');
      }

      // Select format based on user preference
      StreamInfo? selectedStream;

      if (preferredFormat == AudioFormat.m4a) {
        // User wants M4A - find best m4a stream
        final m4aStreams =
            audioStreams.where((s) => s.container.name == 'mp4').toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint('downloadAudio: Selected m4a format as requested');
        }
      } else if (preferredFormat == AudioFormat.opus) {
        // User wants OPUS - find best webm/opus stream
        final opusStreams =
            audioStreams.where((s) => s.container.name == 'webm').toList();
        if (opusStreams.isNotEmpty) {
          selectedStream = opusStreams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint('downloadAudio: Selected opus format as requested');
        }
      } else if (preferredFormat == AudioFormat.mp3) {
        // MP3 typically comes as m4a container or webm
        final mp3Streams = audioStreams
            .where(
                (s) => s.container.name == 'mp4' || s.container.name == 'webm')
            .toList();
        if (mp3Streams.isNotEmpty) {
          selectedStream = mp3Streams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint('downloadAudio: Selected stream for MP3 preference');
        }
      }

      // Auto mode or fallback: prefer m4a for Android compatibility, then highest bitrate
      if (selectedStream == null) {
        final m4aStreams =
            audioStreams.where((s) => s.container.name == 'mp4').toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint(
              'downloadAudio: Auto mode - selected m4a for Android compatibility');
        } else {
          // Fallback to highest bitrate available
          selectedStream = audioStreams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint(
              'downloadAudio: Auto mode - using highest bitrate ${selectedStream.container.name}');
        }
      }

      streamInfo = selectedStream;

      final musicDir = await _getMusicDirectory(downloadLocation);
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      // Use proper audio extension based on container format
      String audioExtension;
      if (streamInfo.container.name == 'mp4') {
        audioExtension = 'm4a';
      } else if (streamInfo.container.name == 'webm') {
        audioExtension = 'opus';
      } else {
        audioExtension = streamInfo.container.name;
      }

      // Check if this video is already downloaded (check by youtube_id in database)
      final db = await DatabaseHelper().database;
      final existingByVideoId = await db.query(
        'songs',
        where: 'youtube_id = ?',
        whereArgs: [videoId],
      );

      if (existingByVideoId.isNotEmpty) {
        final existingPath = existingByVideoId.first['file_path'] as String;
        final existingFile = File(existingPath);
        if (await existingFile.exists()) {
          debugPrint(
              'downloadAudio: Video $videoId already downloaded at $existingPath');
          _completeDownload(videoId);
          return DownloadResult(
            filePath: existingPath,
            song: await _addDownloadedSongToLibrary(
              videoId: videoId,
              filePath: existingPath,
              title: video.title,
              artists: YouTubeArtistParser.parseArtistName(
                  video.title, video.author),
              duration: video.duration?.inMilliseconds ?? 0,
            ),
          );
        }
      }

      // Simple filename: Title.extension (video ID stored in metadata, not filename)
      final finalFile = File(
        path.join(
          musicDir.path,
          '$safeTitle.$audioExtension',
        ),
      );

      if (await finalFile.exists()) {
        final fileSize = await finalFile.length();
        if (fileSize > 0) {
          debugPrint(
              'downloadAudio: File already exists and is valid: ${finalFile.path}. Skipping.');
          _completeDownload(videoId);
          return DownloadResult(
            filePath: finalFile.path,
            song: await _addDownloadedSongToLibrary(
              videoId: videoId,
              filePath: finalFile.path,
              title: video.title,
              artists: YouTubeArtistParser.parseArtistName(
                  video.title, video.author),
              duration: video.duration?.inMilliseconds ?? 0,
            ),
          );
        } else {
          debugPrint(
              'downloadAudio: Empty file found: ${finalFile.path}. Deleting and re-downloading.');
          await finalFile.delete();
        }
      }

      final downloadProgress = _activeDownloads[videoId];
      debugPrint('downloadAudio: Getting stream for videoId: $videoId');

      // Use YouTube Explode copyTo method - more reliable than manual streaming
      final contentLength = streamInfo.size.totalBytes;
      debugPrint(
          'downloadAudio: Expected content length: $contentLength bytes');

      var receivedBytes = 0;
      var lastProgressUpdate = DateTime.now();

      try {
        // Create a custom sink to track progress
        final sink = finalFile.openWrite();

        // Use listen instead of await for to have more control
        final stream = _yt.videos.streamsClient.get(streamInfo);

        await for (final chunk in stream) {
          if (downloadProgress?.cancelRequested == true) {
            break;
          }

          sink.add(chunk);
          receivedBytes += chunk.length;

          // Update progress every 100ms to avoid flooding
          final now = DateTime.now();
          if (now.difference(lastProgressUpdate).inMilliseconds > 100) {
            lastProgressUpdate = now;
            if (contentLength > 0) {
              final progress = receivedBytes / contentLength;
              _updateDownloadProgress(videoId, progress);
              onProgress?.call(progress);
              debugPrint(
                  'downloadAudio: Progress ${(progress * 100).toStringAsFixed(1)}%');
            }
          }
        }

        await sink.flush();
        await sink.close();
      } on Exception catch (e) {
        debugPrint('downloadAudio: Stream error: $e');
        // Clean up partial file
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        rethrow;
      }

      final finalFileSize = await finalFile.length();
      debugPrint(
          'downloadAudio: Download completed. Final file size: $finalFileSize bytes');

      if (downloadProgress?.cancelRequested == true) {
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        _completeDownload(videoId);
        return null;
      }

      final song = await _addDownloadedSongToLibrary(
        videoId: videoId,
        filePath: finalFile.path,
        title: video.title,
        artists: YouTubeArtistParser.parseArtistName(video.title, video.author),
        duration: video.duration?.inMilliseconds ?? 0,
      );

      _updateDownloadProgress(videoId, 1.0);
      _completeDownload(videoId);

      return DownloadResult(filePath: finalFile.path, song: song);
    } catch (e) {
      debugPrint('downloadAudio: Download $videoId failed with error: $e');
      _completeDownload(videoId);
      final download = _activeDownloads[videoId];
      if (download != null) {
        download.isDownloading = false;
        download.error =
            download.cancelRequested ? 'Canceled' : 'Download failed';
        _notifyProgressUpdate();
      }
      rethrow;
    } finally {
      debugPrint('downloadAudio: Exiting download for videoId: $videoId');
    }
  }

  Future<Directory> _getMusicDirectory(String downloadLocation) async {
    if (kIsWeb) {
      throw UnsupportedError('Downloads are not supported on Web.');
    }

    Directory? baseDir;

    if (Platform.isAndroid) {
      if (downloadLocation == 'downloads') {
        // Use public Downloads folder
        baseDir = Directory('/storage/emulated/0/Download');
      } else if (downloadLocation == 'music') {
        // Use public Music folder
        baseDir = Directory('/storage/emulated/0/Music');
      } else {
        // internal - use app documents directory
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else if (Platform.isIOS) {
      // iOS only supports internal app storage
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      // Desktop platforms
      baseDir = await getDownloadsDirectory();
      if (baseDir == null) {
        throw Exception('Could not get downloads directory.');
      }
    }

    final musicDir = Directory(path.join(baseDir.path, 'tsmusic'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<ts.Song> _addDownloadedSongToLibrary({
    required String videoId,
    required String filePath,
    required String title,
    required List<String> artists,
    required int duration,
  }) async {
    try {
      final dbHelper = DatabaseHelper();
      return await dbHelper.addSongFromYouTube(
        videoId: videoId,
        filePath: filePath,
        title: title,
        artists: artists,
        duration: duration,
      );
    } catch (e) {
      debugPrint('Error adding downloaded song to library: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    for (final download in _activeDownloads.values) {
      download.completer?.completeError('Service disposed');
    }
    _activeDownloads.clear();
    _player.dispose();
    _httpClient.close(); // Close the http client
    isLoading.dispose();
    super.dispose();
  }
}
