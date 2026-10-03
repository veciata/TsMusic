import 'dart:async' show unawaited;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/utils/lru_cache.dart';

class ArtistImageCache extends ChangeNotifier {
  ArtistImageCache({
    http.Client? httpClient,
    YouTubeService? youTubeService,
    Directory? directoryOverride,
  }) : _httpClient = httpClient ?? http.Client(),
       // ignore: prefer_initializing_formals - this._youTubeService would make the param private
       _youTubeService = youTubeService,
       // ignore: prefer_initializing_formals - this._directoryOverride would make the param private
       _directoryOverride = directoryOverride;
  final http.Client _httpClient;
  final YouTubeService? _youTubeService;
  final Directory? _directoryOverride;
  Directory? _dir;
  bool _initDone = false;
  final LRUCache<String, String> _resolved = LRUCache<String, String>(
    maxCapacity: 200,
  );
  final Map<String, Future<String?>> _inFlight = {};
  final Set<String> _failed = {};
  static String normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  Future<void> _ensureInit() async {
    if (_initDone) return;
    _initDone = true;
    try {
      final base =
          _directoryOverride ?? await getApplicationDocumentsDirectory();
      _dir = Directory(path.join(base.path, 'thumbnails'));
      if (!await _dir!.exists()) {
        await _dir!.create(recursive: true);
      }
    } catch (e) {}
  }

  Future<String?> getCachedImage(String artistName) async {
    final key = normalizeName(artistName);
    final inMemory = _resolved.get(key);
    if (inMemory != null) return inMemory;
    await _ensureInit();
    if (_dir == null) return null;
    final file = File(_cachePath(key));
    if (await file.exists()) {
      _resolved.put(key, file.path);
      return file.path;
    }
    return null;
  }

  Future<String?> ensureArtistImage(
    String artistName, {
    List<Song>? localSongs,
  }) async {
    final key = normalizeName(artistName);
    final cached = await getCachedImage(artistName);
    if (cached != null) return cached;
    if (_failed.contains(key)) return null;
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final future = _resolve(key, artistName, localSongs);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      unawaited(_inFlight.remove(key));
    }
  }

  Future<String?> _resolve(
    String key,
    String artistName,
    List<Song>? localSongs,
  ) async {
    await _ensureInit();
    if (localSongs != null) {
      for (final song in localSongs) {
        if (song.localThumbnailPath != null &&
            await File(song.localThumbnailPath!).exists()) {
          _resolved.put(key, song.localThumbnailPath!);
          notifyListeners();
          return song.localThumbnailPath;
        }
      }
      for (final song in localSongs) {
        final art = song.albumArtUrl;
        if (art == null || art.isEmpty) continue;
        final saved = await _downloadToCache(key, art);
        if (saved != null) return saved;
      }
    }
    final yt = _youTubeService;
    if (yt != null) {
      try {
        final results = await yt.searchAudio(artistName);
        for (final audio in results) {
          final thumb = audio.thumbnailUrl;
          if (thumb == null || thumb.isEmpty) continue;
          final saved = await _downloadToCache(key, thumb);
          if (saved != null) return saved;
        }
      } catch (e) {}
    }
    _failed.add(key);
    return null;
  }

  Future<String?> _downloadToCache(String key, String url) async {
    if (_dir == null) return null;
    if (!url.startsWith('http')) {
      final local = File(url);
      if (await local.exists()) {
        _resolved.put(key, local.path);
        notifyListeners();
        return local.path;
      }
      return null;
    }
    final target = _cachePath(key);
    try {
      final response = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final file = File(target);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      _resolved.put(key, file.path);
      notifyListeners();
      return file.path;
    } catch (e) {
      return null;
    }
  }

  String _cachePath(String key) =>
      path.join(_dir!.path, 'artist_${key}_thumb.jpg');
  void close() {
    _httpClient.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
