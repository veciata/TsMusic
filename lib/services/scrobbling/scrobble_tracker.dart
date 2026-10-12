import 'package:tsmusic/models/song.dart';

/// Accumulates how much of a track the user has actually played so the
/// scrobbling rules can be applied at the right moment.
///
/// The rule mirrors Last.fm's: a track must be at least [minimumTrackLength]
/// long and must have been played for at least half its length, or for
/// [fourMinutes], whichever comes first.
class ScrobbleTracker {
  static const Duration minimumTrackLength = Duration(seconds: 30);
  static const Duration fourMinutes = Duration(minutes: 4);

  Song? _song;
  DateTime? _startedAt;
  Duration _maxPosition = Duration.zero;

  Song? get song => _song;
  DateTime? get startedAt => _startedAt;
  Duration get maxPosition => _maxPosition;

  /// True once the tracked track has met the scrobbling threshold.
  bool get hasReachedThreshold =>
      _song != null &&
      ScrobbleTracker.isEligible(_song!.duration, _maxPosition);

  void begin(Song song, DateTime now) {
    _song = song;
    _startedAt = now;
    _maxPosition = Duration.zero;
  }

  void update(Duration position) {
    if (position > _maxPosition) _maxPosition = position;
  }

  void reset() {
    _song = null;
    _startedAt = null;
    _maxPosition = Duration.zero;
  }

  /// Whether a track of [durationMs] played for [played] should be scrobbled.
  static bool isEligible(int durationMs, Duration played) {
    if (durationMs < minimumTrackLength.inMilliseconds) return false;
    final half = Duration(milliseconds: durationMs ~/ 2);
    return played >= half || played >= fourMinutes;
  }
}
