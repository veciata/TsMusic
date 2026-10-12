import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/scrobble_config.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';
import 'package:tsmusic/services/scrobbling/scrobble_tracker.dart';
import 'package:tsmusic/services/scrobbling/scrobbling_service.dart';

/// Watches playback and submits "now playing" / scrobble events to the
/// configured service.
///
/// It observes [MusicProvider] rather than the other way around, so playback
/// stays unaware of scrobbling.
class ScrobblingProvider extends ChangeNotifier {
  ScrobblingProvider({ScrobblingService? service})
    : _service = service ?? ScrobblingService();

  static const String _prefsKey = 'scrobbling_config';

  final ScrobblingService _service;
  final ScrobbleTracker _tracker = ScrobbleTracker();

  ScrobblingConfig _config = const ScrobblingConfig();
  MusicProvider? _music;
  StreamSubscription<Duration>? _positionSubscription;
  String? _lastSongKey;
  bool _scrobbledCurrent = false;
  String? _lastError;

  ScrobblingConfig get config => _config;

  /// Message from the most recent failed submit, cleared on the next success.
  String? get lastError => _lastError;

  ScrobblingService get service => _service;

  /// Loads the saved configuration. Call once at startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _config = ScrobblingConfig.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        notifyListeners();
      }
    } catch (e) {
      // A corrupt config simply falls back to "disabled".
    }
  }

  Future<void> updateConfig(ScrobblingConfig config) async {
    _config = config;
    _lastError = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(config.toMap()));
    } catch (e) {
      // Persisting is best-effort.
    }
  }

  /// Starts observing [music]. Safe to call once; later calls are ignored.
  void attach(MusicProvider music) {
    if (_music == music) return;
    _music = music;
    _positionSubscription ??= music.positionStream.listen(_onPosition);
    music.addListener(_onMusicChanged);
    _onMusicChanged();
  }

  void _onMusicChanged() {
    final song = _music?.activeSong;
    final key = song == null ? null : _songKey(song);
    if (key == _lastSongKey) return;
    _lastSongKey = key;
    _scrobbledCurrent = false;
    _tracker.reset();
    if (song == null || !_config.isConfigured) return;
    if (song.duration < ScrobbleTracker.minimumTrackLength.inMilliseconds) {
      return;
    }
    _tracker.begin(song, DateTime.now());
    unawaited(_submitNowPlaying(song));
  }

  void _onPosition(Duration position) {
    if (_tracker.song == null) return;
    _tracker.update(position);
    if (_scrobbledCurrent ||
        !_config.isConfigured ||
        !_tracker.hasReachedThreshold) {
      return;
    }
    _scrobbledCurrent = true;
    unawaited(_submitScrobble(_tracker.song!, _tracker.startedAt!));
  }

  Future<void> _submitNowPlaying(Song song) async {
    try {
      final ok = await _service.updateNowPlaying(_config, song);
      if (!ok) _recordError('Now playing not accepted');
    } catch (e) {
      _recordError(e.toString());
    }
  }

  Future<void> _submitScrobble(Song song, DateTime startedAt) async {
    try {
      final ok = await _service.scrobble(_config, song, startedAt);
      if (!ok) _recordError('Scrobble not accepted');
    } catch (e) {
      _recordError(e.toString());
    }
  }

  void _recordError(String message) {
    _lastError = message;
    debugPrint('Scrobbling failed: $message');
    notifyListeners();
  }

  static String _songKey(Song song) {
    final id = (song.youtubeId?.isNotEmpty ?? false)
        ? song.youtubeId!
        : song.url;
    return '$id|${song.title}|${song.artist}'.toLowerCase();
  }

  @override
  void dispose() {
    _music?.removeListener(_onMusicChanged);
    _positionSubscription?.cancel();
    super.dispose();
  }
}
