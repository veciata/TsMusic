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

      final audioStream = manifest.audioOnly.withHighestBitrate() ??
          manifest.muxed.withHighestBitrate();
      return audioStream?.url.toString();
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
        manifest = await _yt.videos.streamsClient.getManifest(videoId);
      } catch (e) {
        debugPrint(
          'Failed to get manifest with default client: $e. Trying alternative clients.',
        );
        manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.android,
            YoutubeApiClient.ios,
          ],
        );
      }

      final streamInfo = manifest.audioOnly.withHighestBitrate();
      if (streamInfo == null) {
        throw Exception('No suitable audio stream found.');
      }

      final musicDir = await _getMusicDirectory();
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final finalFile = File(
        path.join(
          musicDir.path,
          '${safeTitle}_${streamInfo.bitrate.bitsPerSecond}.${streamInfo.container.name}',
        ),
      );

      if (await finalFile.exists()) {
        debugPrint('downloadAudio: File already exists: ${finalFile.path}. Skipping.');
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
      }

      final downloadProgress = _activeDownloads[videoId];
      final stream = _yt.videos.streamsClient.get(streamInfo);
      final contentLength = streamInfo.size.totalBytes;
      var receivedBytes = 0;
      final fileSink = finalFile.openWrite();
      final completer = Completer<void>();

      final sub = stream.listen(
        (chunk) {
          if (downloadProgress?.cancelRequested == true) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('Canceled by user'));
            }
            return;
          }
          fileSink.add(chunk);
          receivedBytes += chunk.length;
          if (contentLength > 0) {
            final progress = receivedBytes / contentLength;
            _updateDownloadProgress(videoId, progress);
            onProgress?.call(progress);
          }
        },
        onError: (e) {
          debugPrint('downloadAudio: Stream error for $videoId: $e');
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      if (downloadProgress != null) {
        downloadProgress.subscription = sub;
      }

      await completer.future;
      await fileSink.flush();
      await fileSink.close();

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

  Future<Directory> _getMusicDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Downloads are not supported on Web.');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // Store downloads inside the app's documents directory so they remain sandboxed
      final appDocDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory(path.join(appDocDir.path, 'tsmusic'));
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }
      return musicDir;
    } else {
      // For desktop platforms, use the downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not get downloads directory.');
      }
      final musicDir = Directory(path.join(downloadsDir.path, 'tsmusic'));
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }
      return musicDir;
    }
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