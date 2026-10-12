import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/lyrics.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/lyrics/lyrics_service.dart';

/// Loads and caches lyrics for the track the user is looking at.
///
/// Results (including "no lyrics") are cached per song for the session, so
/// reopening the lyrics sheet is instant and a missing track is not retried
/// on every rebuild.
class LyricsProvider extends ChangeNotifier {
  LyricsProvider({LyricsService? service})
    : _service = service ?? LyricsService();

  final LyricsService _service;
  final Map<String, Lyrics?> _cache = <String, Lyrics?>{};

  Lyrics? _lyrics;
  bool _isLoading = false;
  String? _songKey;
  int _requestId = 0;

  Lyrics? get lyrics => _lyrics;
  bool get isLoading => _isLoading;

  /// Stable cache key for [song]. Falls back to the file path for local songs
  /// that have no YouTube id.
  static String keyFor(Song song) {
    final id = (song.youtubeId?.isNotEmpty ?? false)
        ? song.youtubeId!
        : song.url;
    return '$id|${song.title}|${song.artist}'.toLowerCase();
  }

  /// Loads lyrics for [song]. No-op when the same song is already resolved or
  /// loading, unless [force] is set.
  Future<void> load(Song song, {bool force = false}) async {
    final key = keyFor(song);
    if (!force && key == _songKey) return;
    _songKey = key;

    if (!force && _cache.containsKey(key)) {
      _lyrics = _cache[key];
      _isLoading = false;
      notifyListeners();
      return;
    }

    final requestId = ++_requestId;
    _lyrics = null;
    _isLoading = true;
    notifyListeners();

    final result = await _service.fetch(song);
    if (requestId != _requestId) return; // a newer track took over.
    _cache[key] = result;
    _lyrics = result;
    _isLoading = false;
    notifyListeners();
  }

  /// Drops the visible lyrics without touching the cache.
  void clear() {
    _lyrics = null;
    _isLoading = false;
    _songKey = null;
    notifyListeners();
  }
}
