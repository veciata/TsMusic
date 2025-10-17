import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/music_provider.dart' as music_provider;

class YTDownloadProgress {
  final String videoId;
  String title;
  double progress;
  bool isDownloading;
  String? error;
  StreamSubscription? subscription;
  bool cancelRequested;
  String? filePath;

  YTDownloadProgress({
    required this.videoId,
    required this.title,
    this.progress = 0.0,
    this.isDownloading = true,
    this.error,
    this.subscription,
    this.cancelRequested = false,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'progress': progress,
        'isDownloading': isDownloading,
        'error': error,
        'cancelRequested': cancelRequested,
        'filePath': filePath,
      };
}

class YoutubeDownloadService with ChangeNotifier {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, YTDownloadProgress> _activeDownloads = {};
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  List<YTDownloadProgress> get activeDownloads =>
      _activeDownloads.values.toList();
  bool get hasActiveDownloads => _activeDownloads.isNotEmpty;

  bool isDownloading(String videoId) => _activeDownloads.containsKey(videoId);

  YTDownloadProgress? getDownload(String videoId) => _activeDownloads[videoId];

  Future<String?> downloadAudio({
    required String videoId,
    required BuildContext context,
    required void Function(double progress) onProgress,
  }) async {
    if (_activeDownloads.containsKey(videoId)) {
      debugPrint('Download already in progress for video: $videoId');
      return _activeDownloads[videoId]?.filePath;
    }

    final progress = YTDownloadProgress(
      videoId: videoId,
      title: 'Downloading...',
      progress: 0.0,
      isDownloading: true,
    );

    _activeDownloads[videoId] = progress;
    notifyListeners();

    try {
      isLoading.value = true;

      // Check storage permission
      if (!await _checkStoragePermission()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission required')),
          );
        }
        _removeDownload(videoId, error: 'Storage permission denied');
        return null;
      }

      // Get video info
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      // Update progress with video title
      progress.title = _sanitizeFileName(video.title);
      notifyListeners();

      try {
        // Get download directory
        final directory = await _getDownloadDirectory();
        final fileName = '${_sanitizeFileName(video.title)}.m4a';
        final file = File('${directory.path}/$fileName');

        // Create directory if it doesn't exist
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        // Download the audio
        final videoStream = _yt.videos.streamsClient.get(audioStreamInfo);
        final fileStream = file.openWrite();

        final contentLength = audioStreamInfo.size.totalBytes;
        int receivedLength = 0;

        await for (final data in videoStream) {
          if (progress.cancelRequested) {
            await fileStream.close();
            await file.delete();
            _removeDownload(videoId);
            return null;
          }

          fileStream.add(data);
          receivedLength += data.length;

          // Update progress
          final progressValue =
              contentLength > 0 ? receivedLength / contentLength : 0.0;
          progress.progress = progressValue;
          onProgress(progressValue);
          notifyListeners();
        }

        await fileStream.close();
        progress.filePath = file.path;
        progress.isDownloading = false;

        // Add to music library
        if (context.mounted) {
          await _addToMusicLibrary(context, video, file.path);
        }

        _removeDownload(videoId);
        return file.path;
      } catch (e) {
        _removeDownload(videoId, error: e.toString());
        rethrow;
      }
    } catch (e) {
      debugPrint('Error downloading audio: $e');
      _removeDownload(videoId, error: e.toString());
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _addToMusicLibrary(
    BuildContext context,
    Video video,
    String filePath,
  ) async {
    try {
      final musicProvider =
          Provider.of<music_provider.MusicProvider>(context, listen: false);

      // Check if song already exists
      final existingSong = musicProvider.songs.firstWhere(
        (s) => s.id == video.id.value,
        orElse: () => Song(
          id: '',
          title: '',
          artists: [],
          url: '',
          duration: 0,
        ),
      );

      if (existingSong.id.isEmpty) {
        final song = Song(
          id: video.id.value,
          title: video.title,
          artists: [video.author],
          album: 'YouTube',
          url: filePath,
          duration: video.duration?.inMilliseconds ?? 0,
          isDownloaded: true,
          albumArtUrl: video.thumbnails.highResUrl,
        );

        await musicProvider.addSong(song);
      } else {
        // Update existing song
        await musicProvider.updateSong(existingSong.copyWith(
          url: filePath,
          isDownloaded: true,
        ));
      }
    } catch (e) {
      debugPrint('Error adding/updating song in library: $e');
      rethrow;
    }
  }

  void _removeDownload(String videoId, {String? error}) {
    final progress = _activeDownloads[videoId];
    if (progress != null) {
      if (error != null) {
        progress.error = error;
        progress.isDownloading = false;
        // Keep the download in the list for a while to show the error
        Future.delayed(const Duration(seconds: 5), () {
          _activeDownloads.remove(videoId);
          notifyListeners();
        });
      } else {
        _activeDownloads.remove(videoId);
      }
      notifyListeners();
    }
  }

  Future<void> cancelDownload(String videoId) async {
    final progress = _activeDownloads[videoId];
    if (progress != null) {
      progress.cancelRequested = true;
      await progress.subscription?.cancel();

      // Delete the partially downloaded file if it exists
      if (progress.filePath != null) {
        try {
          final file = File(progress.filePath!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting partial download: $e');
        }
      }

      _removeDownload(videoId, error: 'Download cancelled');
    }
  }

  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    } else if (Platform.isIOS) {
      // On iOS, we don't need storage permission for app's documents directory
      return true;
    }
    // For other platforms (web, desktop, etc.)
    return true;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // For Android, use the music directory
      final directory = Directory('/storage/emulated/0/Music/TSMusic');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } else if (Platform.isIOS) {
      // For iOS, use the documents directory
      return await getApplicationDocumentsDirectory();
    } else {
      // For other platforms (web, desktop, etc.)
      return Directory.current;
    }
  }

  String _sanitizeFileName(String name) {
    // Remove invalid characters and limit length
    var sanitized = name
        .replaceAll(RegExp(r'[\\/*?:"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Limit length to 100 characters to avoid filesystem issues
    if (sanitized.length > 100) {
      sanitized = '${sanitized.substring(0, 97)}...';
    }

    return sanitized;
  }

  @override
  void dispose() {
    // Close resources
    _yt.close();

    // Cancel all active downloads
    for (final download in _activeDownloads.values) {
      download.subscription?.cancel();
    }

    _activeDownloads.clear();
    super.dispose();
  }
}
