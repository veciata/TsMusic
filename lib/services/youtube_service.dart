import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/audio_format.dart';
import 'package:tsmusic/models/song.dart' as ts;

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
  final YoutubeExplode _yt;
  final http.Client _httpClient;
  final AudioPlayer _audioPlayer;

  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final Map<String, VideoSearchList> _searchPages = {};

  // Getters
  List<DownloadProgress> get activeDownloads => _activeDownloads.values.toList();
  YouTubeAudio? get currentAudio => _currentAudio;
  bool get isPlaying => _audioPlayer.playing;

  // Public constructor
  YouTubeService({YoutubeExplode? yt, http.Client? httpClient, AudioPlayer? audioPlayer})
      : _yt = yt ?? YoutubeExplode(),
        _httpClient = httpClient ?? http.Client(),
        _audioPlayer = audioPlayer ?? AudioPlayer() {
    _init();
  }

  void _init() {
    // Initialize audio player
    _audioPlayer.playbackEventStream.listen((event) {

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
      final String? audioUrl = await _getAudioStream(audio.id);
      
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
        );

        // Wait for the audio to be ready
        await _audioPlayer.load();
        
        // Start playing
        _audioPlayer.play();

        
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

  // Get audio stream using YouTube Explode
  Future<String?> _getAudioStream(String videoId) async {
    try {
      StreamManifest manifest;
      try {
        manifest = await _yt.videos.streamsClient.getManifest(videoId);
      } catch (e) {
        debugPrint('Failed to get manifest with default client: $e. Trying alternative clients.');
        manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.android,
            YoutubeApiClient.ios,
          ],
        );
      }

      final audioStream = manifest.audioOnly.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      debugPrint('Failed to get audio stream: $e');
      rethrow;
    }
  }
  
  // Pause audio
  Future<void> pause() async {
    await _audioPlayer.pause();
    notifyListeners();
  }
  
  // Stop audio
  Future<void> stop() async {
    await _audioPlayer.stop();
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
      debugPrint('_completeDownload: Download for videoId: $videoId completed and removed from active list.');
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
      debugPrint('getAudioStreamUrl: No audio-only streams available for videoId: $videoId');
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
      
      if (preferredFormat == AudioFormat.auto || preferredFormat == AudioFormat.all) {
        // Auto: pick highest bitrate
        streamInfo = audioStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
      } else {
        // Filter by container type
        final preferredContainer = preferredFormat.name; // m4a, opus, mp3
        final matchingStreams = audioStreams.where((s) => 
          s.container.name.toLowerCase() == preferredContainer ||
          (preferredFormat == AudioFormat.m4a && s.container.name == 'mp4') ||
          (preferredFormat == AudioFormat.opus && s.container.name == 'webm')
        ).toList();
        
        if (matchingStreams.isNotEmpty) {
          streamInfo = matchingStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint('downloadAudio: Selected ${streamInfo.container.name} format as requested');
        } else {
          // Fallback to best available
          streamInfo = audioStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          debugPrint('downloadAudio: Preferred format $preferredContainer not available, using ${streamInfo.container.name}');
        }
      }

      final musicDir = await _getMusicDirectory(downloadLocation);
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      
      // Use proper audio extension based on container format
      String audioExtension;
      if (streamInfo.container.name == 'mp4') {
        audioExtension = 'm4a';
      } else if (streamInfo.container.name == 'webm') {
        audioExtension = 'webm';
      } else {
        audioExtension = streamInfo.container.name;
      }
      
      final finalFile = File(
        path.join(
          musicDir.path,
          '${safeTitle}_${videoId}_${streamInfo.bitrate.bitsPerSecond}.$audioExtension',
        ),
      );

      if (await finalFile.exists()) {
        final fileSize = await finalFile.length();
        if (fileSize > 0) {
          debugPrint('downloadAudio: File already exists and is valid: ${finalFile.path}. Skipping.');
          _completeDownload(videoId);
          return DownloadResult(
            filePath: finalFile.path,
            song: await _addDownloadedSongToLibrary(
              videoId: videoId,
              filePath: finalFile.path,
              title: video.title,
              author: video.author,
              duration: video.duration?.inMilliseconds ?? 0,
            ),
          );
        } else {
          debugPrint('downloadAudio: Empty file found: ${finalFile.path}. Deleting and re-downloading.');
          await finalFile.delete();
        }
      }

      final downloadProgress = _activeDownloads[videoId];
      debugPrint('downloadAudio: Getting stream for videoId: $videoId');
      
      // Use YouTube Explode copyTo method - more reliable than manual streaming
      final contentLength = streamInfo.size.totalBytes;
      debugPrint('downloadAudio: Expected content length: $contentLength bytes');
      
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
              debugPrint('downloadAudio: Progress ${(progress * 100).toStringAsFixed(1)}%');
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
      debugPrint('downloadAudio: Download completed. Final file size: $finalFileSize bytes');

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
        author: video.author,
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
        download.error = download.cancelRequested ? 'Canceled' : 'Download failed';
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
    required String author,
    required int duration,
  }) async {
    try {
      final dbHelper = DatabaseHelper();
      return await dbHelper.addSongFromYouTube(
        filePath: filePath,
        title: title,
        author: author,
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
    _audioPlayer.dispose();
    _httpClient.close(); // Close the http client
    isLoading.dispose();
    super.dispose();
  }
}
