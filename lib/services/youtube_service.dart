import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/core/exceptions/storage_permission_exception.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/song.dart' as ts;

class DownloadResult {
  final String filePath;
  final ts.Song song;
  DownloadResult({required this.filePath, required this.song});
}

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
  final YoutubeExplode _yt;
  final http.Client _httpClient;
  final AudioPlayer _audioPlayer;

  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;

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
      final url = await _getExplodeAudioStream(videoId);
      if (url != null) return url;
      return null;
    } catch (e) {
      debugPrint('Failed to get audio stream: $e');
      rethrow;
    }
  }
  
  
  // Download audio using YouTube Explode
  Future<File?> downloadWithExplode(String videoId, String title, {void Function(double)? onProgress}) async {
    try {
      // Get the video manifest
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // Get the best audio stream
      final audioStream = manifest.audioOnly.withHighestBitrate();
      
      // Get the app's documents directory for saving the file
      final appDocDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${appDocDir.path}/music');
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }
      
      // Create a safe filename
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = '${musicDir.path}/$safeTitle.${audioStream.container.name}';
      final file = File(filePath);
      
      // Download the audio
      final fileStream = file.openWrite();
      final stream = _yt.videos.streamsClient.get(audioStream);
      
      // Track download progress
      var received = 0;
      final total = audioStream.size.totalBytes;
      
      await for (final data in stream) {
        fileStream.add(data);
        received += data.length;
        if (onProgress != null && total > 0) {
          onProgress(received / total);
        }
      }
      
      await fileStream.close();
      return file;
      
    } catch (e) {
      debugPrint('Error downloading with YouTube Explode: $e');
      rethrow;
    }
  }

  // Get audio stream using YouTube Explode with retry logic
  Future<String?> _getExplodeAudioStream(String videoId, {int retryCount = 2}) async {
    debugPrint('_getExplodeAudioStream: Attempting to get audio stream for video $videoId');
    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        debugPrint('_getExplodeAudioStream: Attempt $attempt to get stream for video $videoId');
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        
        // Try different audio qualities
        for (final _ in _audioQualityPreference) {
          try {
            // Filter streams by codec and sort by bitrate (highest first)
            final streams = manifest.audio
                .where((s) => s.audioCodec == 'mp4' || s.audioCodec == 'm4a' || s.audioCodec == 'webm')
                .toList()
                ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
                
            if (streams.isNotEmpty) {
              final stream = streams.first;
              debugPrint('_getExplodeAudioStream: Found audio stream: ${stream.url} (${stream.bitrate} bps)');
              return stream.url.toString();
            }
          } catch (e) {
            debugPrint('_getExplodeAudioStream: Error processing stream quality: $e');
            continue;
          }
        }
        
        // If no preferred quality found, try any audio stream
        final anyAudio = manifest.audio.firstOrNull;
        if (anyAudio != null) {
          debugPrint('_getExplodeAudioStream: Falling back to any available audio stream: ${anyAudio.url}');
          return anyAudio.url.toString();
        }
      } catch (e) {
        debugPrint('_getExplodeAudioStream: Error in YouTube Explode audio stream (attempt $attempt): $e');
        if (attempt == retryCount) {
          rethrow;
        }
        // Wait a bit before retrying
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    debugPrint('_getExplodeAudioStream: No audio stream found for video $videoId after $retryCount attempts.');
    return null;
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
      return videos.map((video) => YouTubeAudio.fromVideo(video)).toList();
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
      return videos.map((video) => YouTubeAudio.fromVideo(video)).toList();
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
      // Fallback for streams that are not audio-only
      final muxedStreams = manifest.muxed;
      if (muxedStreams.isNotEmpty) {
        return muxedStreams.withHighestBitrate().url.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Error getting audio stream URL: $e');
      rethrow;
    }
  }

  Future<DownloadResult?> downloadAudio({
    required String videoId,
    void Function(double)? onProgress,
  }) async {
    debugPrint('downloadAudio: Starting download for videoId: $videoId');
    File? tempFile;
    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streamInfo = manifest.muxed.withHighestBitrate();
      final container = streamInfo.container.name;

      final safeTitle =
          '${video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$container';
      _addActiveDownload(videoId, video.title);
      onProgress?.call(0.0);
      _updateDownloadProgress(videoId, 0.0);
      debugPrint('downloadAudio: Video title: ${video.title}, safeTitle: $safeTitle');

      final musicDir = await _getMusicDirectory();
      final finalFile = File(path.join(musicDir.path, safeTitle));
      debugPrint('downloadAudio: Music directory: ${musicDir.path}, finalFile path: ${finalFile.path}');
      
      tempFile = File('${finalFile.path}.tmp');
      debugPrint('downloadAudio: Temporary file path: ${tempFile.path}');

      if (await finalFile.exists()) {
        debugPrint('downloadAudio: File already exists: ${finalFile.path}');
        _updateDownloadProgress(videoId, 1.0);
        _completeDownload(videoId);
        final song = await _addDownloadedSongToLibrary(
          videoId: videoId,
          filePath: finalFile.path,
        );
        debugPrint('downloadAudio: Existing file added to library.');
        return DownloadResult(filePath: finalFile.path, song: song);
      }

      final streamUrl = streamInfo.url.toString();
      debugPrint('downloadAudio: Got stream URL: $streamUrl');

      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? streamInfo.size.totalBytes;
      debugPrint('downloadAudio: Content length: $contentLength bytes');
      var receivedBytes = 0;
      final fileStream = tempFile.openWrite();
      final completer = Completer<void>();

      final sub = response.stream.listen(
        (chunk) {
          if (_activeDownloads[videoId]?.cancelRequested == true) {
            debugPrint('downloadAudio: Cancellation requested for $videoId');
            if (!completer.isCompleted) {
              completer.completeError(Exception('Canceled by user'));
            }
            return;
          }
          fileStream.add(chunk);
          receivedBytes += chunk.length;
          if (contentLength > 0) {
            final progress = receivedBytes / contentLength;
            _updateDownloadProgress(videoId, progress);
            onProgress?.call(progress);
            debugPrint('downloadAudio: VideoId: $videoId, Received: $receivedBytes, Total: $contentLength, Progress: ${progress.toStringAsFixed(2)}');
          }
        },
        onError: (e) {
          debugPrint('downloadAudio: Stream error for $videoId: $e');
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          debugPrint('downloadAudio: Stream done for $videoId');
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      _activeDownloads[videoId]?.subscription = sub;

      await completer.future;
      await fileStream.flush();
      await fileStream.close();
      
      if (_activeDownloads[videoId]?.cancelRequested == true) {
        debugPrint('downloadAudio: Download cancelled before rename for $videoId');
        return null;
      }

      await tempFile.rename(finalFile.path);
      tempFile = null;
      debugPrint('downloadAudio: Renamed temp file to final file: ${finalFile.path}');

      final song = await _addDownloadedSongToLibrary(
        videoId: videoId,
        filePath: finalFile.path,
      );
      _updateDownloadProgress(videoId, 1.0);
      _completeDownload(videoId);
      debugPrint('downloadAudio: Download completed and added to library for $videoId');
      return DownloadResult(filePath: finalFile.path, song: song);

    } catch (e) {
      final download = _activeDownloads[videoId];
      if (download != null) {
        download.isDownloading = false;
        if (download.cancelRequested) {
          download.error = 'Canceled';
          debugPrint('downloadAudio: Download $videoId cancelled by user.');
        } else {
          download.error = 'Download failed';
          debugPrint('downloadAudio: Download $videoId failed with error: $e');
        }
        _notifyProgressUpdate();
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          debugPrint('downloadAudio: Deleted temporary file: ${tempFile.path}');
        } catch (e) {
          debugPrint('downloadAudio: Failed to delete temporary download file: $e');
        }
      }
      debugPrint('downloadAudio: Exiting download for videoId: $videoId');
    }
    return null;
  }

  Future<Directory> _getMusicDirectory() async {
    Directory appDocDir;
    if (kIsWeb) {
      throw UnsupportedError('Downloads are not supported on Web.');
    }
    
    appDocDir = await getApplicationDocumentsDirectory();
    
    final musicDir = Directory(path.join(appDocDir.path, 'tsmusic_downloads'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }



  Future<ts.Song> _addDownloadedSongToLibrary({
    required String videoId,
    required String filePath,
  }) async {
    try {
      final video = await _yt.videos.get(videoId);
      final dbHelper = DatabaseHelper();

      return await dbHelper.addSongFromYouTube(
        filePath: filePath,
        title: video.title,
        author: video.author,
        duration: video.duration?.inMilliseconds ?? 0,
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
