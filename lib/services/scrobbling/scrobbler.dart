import 'package:tsmusic/models/song.dart';

/// A service that can publish "now playing" and completed listens.
abstract class Scrobbler {
  /// Human-readable name, shown in the UI and error messages.
  String get name;

  /// Announces that [song] just started playing.
  Future<bool> updateNowPlaying(Song song);

  /// Submits a completed listen that started at [startedAt].
  Future<bool> scrobble(Song song, DateTime startedAt);
}
