import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/providers/music_provider.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:sqflite/sqflite.dart';

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

class YoutubeDownloadService with ChangeNotifier {
  late YoutubeExplode _yt;
  final http.Client _httpClient = http.Client();
  final Map<String, DownloadProgress> _activeDownloads = {};

  void setYoutubeExplode(YoutubeExplode yt) {
    _yt = yt;
  }

  List<DownloadProgress> get activeDownloads => _activeDownloads.values.toList();

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

      // Get the appropriate directory for storing music
      Directory musicDir;
      if (kIsWeb) return null;
      
      try {
        if (Platform.isAndroid) {
          // Try external storage first (requires MANAGE_EXTERNAL_STORAGE permission)
          try {
            musicDir = Directory('/storage/emulated/0/Music/tsmusic');
            if (!await musicDir.exists()) {
              await musicDir.create(recursive: true);
            }
            // Verify we can write to the directory
            final testFile = File('${musicDir.path}/.test');
            await testFile.writeAsString('test');
            await testFile.delete();
          } catch (e) {
            print('Could not use external storage, falling back to app directory: $e');
            // Fall back to app's documents directory
            final appDocDir = await getApplicationDocumentsDirectory();
            musicDir = Directory('${appDocDir.path}/tsmusic');
            if (!await musicDir.exists()) {
              await musicDir.create(recursive: true);
            }
          }
        } else if (Platform.isIOS) {
          // On iOS, use the documents directory
          final appDocDir = await getApplicationDocumentsDirectory();
          musicDir = Directory('${appDocDir.path}/tsmusic');
          if (!await musicDir.exists()) {
            await musicDir.create(recursive: true);
          }
        } else {
          // For other platforms
          final appDocDir = await getApplicationDocumentsDirectory();
          musicDir = Directory('${appDocDir.path}/tsmusic');
          if (!await musicDir.exists()) {
            await musicDir.create(recursive: true);
          }
        }
      } catch (e) {
        print('Error setting up download directory: $e');
        _removeDownload(videoId, error: 'Failed to set up download directory');
        return null;
      }

      final file = File('${musicDir.path}/$safeTitle');
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

      // Get audio stream URL
      String? audioUrl;
      try {
        audioUrl = await _getAudioStream(videoId);
        if (audioUrl == null) {
          throw Exception('No audio stream available');
        }
      } catch (e) {
        print('Error getting audio stream: $e');
        _updateDownloadProgress(videoId, 0.0);
        _removeDownload(videoId, error: 'Failed to get audio stream: ${e.toString()}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: Failed to get audio stream')),
          );
        }
        return null;
      }

      final request = http.Request('GET', Uri.parse(audioUrl));
      final response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        _updateDownloadProgress(videoId, 0.0);
        _removeDownload(videoId,
            error: 'Download failed with status ${response.statusCode}');
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

      if (_activeDownloads[videoId]?.cancelRequested == true) return null;
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
    
    // Request storage permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
      if (await Permission.audio.request().isGranted) Permission.audio,
    ].request();
    
    // Check if we have the necessary permissions
    bool hasStoragePermission = statuses[Permission.storage]?.isGranted ?? false;
    bool hasManageExternal = statuses[Permission.manageExternalStorage]?.isGranted ?? false;
    
    // For Android 10 and below, storage permission is enough
    if (hasStoragePermission) return true;
    
    // For Android 11+, we need manage external storage
    if (hasManageExternal) return true;
    
    // If we get here, permissions were denied
    return false;
  }

  
Future<String?> _getAudioStream(String videoId) async {
  try {
    print('Fetching manifest for video: $videoId');
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final audioStreams = manifest.audioOnly;

    if (audioStreams.isNotEmpty) {
      final bestAudio = audioStreams.withHighestBitrate();
      print('Selected audio stream: ${bestAudio.bitrate}');
      return bestAudio.url.toString();
    }

    print('No audio-only streams found, trying muxed fallback...');
    final muxed = manifest.muxed;
    if (muxed.isNotEmpty) {
      final fallback = muxed.withHighestBitrate();
      print('Using muxed fallback stream: ${fallback.bitrate}');
      return fallback.url.toString();
    }

    print('No audio or muxed streams available for $videoId');
    return null;
  } on YoutubeExplodeException catch (e) {
    print('YoutubeExplode error: $e');
    await Future.delayed(const Duration(seconds: 1));
    try {
      print('Retrying manifest fetch for $videoId...');
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        final bestAudio = audioStreams.withHighestBitrate();
        return bestAudio.url.toString();
      }
    } catch (err) {
      print('Retry failed: $err');
    }
    return null;
  } catch (e, s) {
    print('Unexpected error fetching audio stream for $videoId: $e');
    print(s);
    return null;
  }
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

        if (existingSongs.isNotEmpty) return;

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

        final artistId =
            await _getOrCreateArtist(txn, video.author.isNotEmpty ? video.author : 'Unknown Artist');

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
    } catch (_) {}
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
    super.dispose();
  }
}
