import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/utils/lru_cache.dart';

/// Persistent on-disk cache for artist images, shared between the Artists tab
/// and the artist detail page.
///
/// Resolution order (a network fetch happens at most once per artist per app
/// install):
///  1. existing disk cache -> reuse it, no download;
///  2. a matching library song's local thumbnail -> used directly;
///  3. a matching library song's album art URL -> downloaded once, persisted;
///  4. first YouTube search thumbnail -> downloaded once, persisted.
///
/// Images are stored under `<documents>/thumbnails/artist_<name>_thumb.jpg`
/// with the same naming ThumbnailService already uses, so previously fetched
/// artist thumbs are picked up too. Because results live on disk (plus an
/// in-memory layer and in-flight deduplication), reopening the artist page or
/// relaunching the app never re-downloads the picture.
class ArtistImageCache extends ChangeNotifier {
  ArtistImageCache({
    http.Client? httpClient,
    YouTubeService? youTubeService,
    Directory? directoryOverride,
  }) : _httpClient = httpClient ?? http.Client(),
       _youTubeService = youTubeService,
       _directoryOverride = directoryOverride;

  final http.Client _httpClient;
  final YouTubeService? _youTubeService;
  final Directory? _directoryOverride;

  Directory? _dir;
  bool _initDone = false;

  /// In-memory layer on top of the disk cache, plus single-flight dedup so a
  /// list and a detail screen never download the same artist twice.
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
    } catch (e) {
      debugPrint('ArtistImageCache: unable to init dir: $e');
    }
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

  /// Returns a path that can be handed straight to an [ImageProvider]. Existing
  /// cache is returned instantly; otherwise the first available source from the
  /// resolution order above is fetched and persisted so later calls are free.
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

    // 1. Local library thumbnails are already on disk — use them directly.
    if (localSongs != null) {
      for (final song in localSongs) {
        if (song.localThumbnailPath != null &&
            await File(song.localThumbnailPath!).exists()) {
          _resolved.put(key, song.localThumbnailPath!);
          notifyListeners();
          return song.localThumbnailPath;
        }
      }
      // 2. Album art: persist one URL so it is only fetched once.
      for (final song in localSongs) {
        final art = song.albumArtUrl;
        if (art == null || art.isEmpty) continue;
        final saved = await _downloadToCache(key, art);
        if (saved != null) return saved;
      }
    }

    // 3. YouTube fallback: search the artist name and cache the first thumb.
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
      } catch (e) {
        debugPrint('ArtistImageCache: search failed for "$artistName": $e');
      }
    }

    _failed.add(key);
    return null;
  }

  Future<String?> _downloadToCache(String key, String url) async {
    if (_dir == null) return null;

    // Non-http "URLs" are local file paths already present on disk.
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
      debugPrint('ArtistImageCache: download failed for "$url": $e');
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
