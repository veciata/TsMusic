/// Classifying and monitoring progress of an online (HLS) track.
///
/// Why this exists
/// ---------------
/// An online track is streamed from a manifest whose segments are byte ranges
/// into a single file. media_kit surfaces each segment as its own playback item,
/// so `stream.completed` fires **once per segment** — a 4-minute track produces
/// roughly 43 events — and on every one of them `player.state.position` and
/// `player.state.duration` describe only that segment (a few seconds), never
/// the whole track.
///
/// Measured on a device (Android 16, real network) for a 239s track:
///
/// ```
/// completedCount=2 within 12s of wall time
/// completion#1 posMs=5750 durMs=6106
/// completion#2 posMs=3620 durMs=3970
/// ```
///
/// The previous inline logic in `MusicProvider` treated `position < 20s` as a
/// dead stream. Since position is always a per-segment value, that predicate
/// was permanently true: every segment boundary was misread as a failure and
/// pushed playback onto the DASH fallback, which buffers indefinitely on this
/// network (measured 0ms after 120s). Online songs in a mixed playlist could
/// therefore not be heard to the end.
///
/// Two things follow, and both are load-bearing:
///
///  * Segment boundaries must be classified against *accumulated* progress, not
///    against the per-segment values (otherwise the queue advances ~43 times
///    per track and skips through the playlist in seconds).
///  * A boundary cannot tell you the stream died. Attempting that with the
///    player's `playing` flag was measured and is unreliable: mpv drops
///    `playing` to false between segments, so 23 of 43 healthy boundaries were
///    misread as deaths on a track that played to 221s of 239s. Death is a
///    *stall over time*, so it belongs in a watchdog, not in a boundary check.
library;

/// What a segment-boundary event means for the track.
enum TrackEndVerdict {
  /// The track genuinely reached its end; advance to the next queue item.
  finished,

  /// A segment boundary mid-track. The track is still playing: neither advance
  /// nor retry.
  continueTrack,
}

/// A snapshot of playback progress at the moment `stream.completed` fired.
class PlaybackEndSignal {
  const PlaybackEndSignal({
    required this.position,
    required this.expectedDuration,
    required this.progressBeforeEvent,
    this.isPlaying = true,
  });

  /// `player.state.position` at the event. Per-segment for HLS.
  final Duration position;

  /// The track's real length from metadata or the database. Zero when unknown.
  final Duration expectedDuration;

  /// Progress already banked from earlier segments of this track.
  final Duration progressBeforeEvent;

  /// Whether the player was still running when the event fired.
  final bool isPlaying;

  /// Tracks shorter than this are treated as unknown-length rather than
  /// truncated, so a short track never ends early by miscount.
  static const Duration meaningfulLength = Duration(seconds: 30);

  /// Slack allowed when comparing banked progress against the expected length,
  /// absorbing EXTINF rounding at the final segment.
  static const Duration endTolerance = Duration(seconds: 3);

  /// Fraction of the track that must have played before a stopped player is
  /// taken as end-of-track rather than a stall.
  ///
  /// Banked progress systematically under-counts on HLS: the position reported
  /// at a boundary lags the segment's real length by roughly 400ms, which over
  /// a 43-segment track accumulates to ~17s of shortfall. Measured on a device,
  /// a track that played every one of its 43 segments banked 221.9s of a 239s
  /// track (92.8%). Requiring an exact match would never end the track, leaving
  /// the player idle after the last segment.
  static const double endOfTrackFraction = 0.85;

  /// Progress including the segment that just finished.
  Duration get progressAfterEvent => progressBeforeEvent + position;

  /// Whether the player has stopped.
  bool get stopped => !isPlaying;

  /// Classifies this boundary.
  ///
  /// There are only two honest answers here. A boundary is either the end of
  /// the track or it is not; deciding that a stream *died* is the watchdog's
  /// job, because it requires observing that progress has stopped over time.
  TrackEndVerdict classify() {
    // Without a usable track length there is nothing to compare against, and
    // guessing "finished" would advance the queue at every segment boundary.
    if (expectedDuration <= meaningfulLength) {
      return TrackEndVerdict.continueTrack;
    }

    // Banked progress reached the real length.
    if (progressAfterEvent >= expectedDuration - endTolerance) {
      return TrackEndVerdict.finished;
    }

    // The playlist ran out while the player stopped, and nearly all of the
    // track played. This is the end of the track with under-counted progress,
    // not a stall: a stream that genuinely died never gets this far.
    if (stopped &&
        progressAfterEvent >= expectedDuration * endOfTrackFraction) {
      return TrackEndVerdict.finished;
    }

    return TrackEndVerdict.continueTrack;
  }

  /// Short branch name for tracing and provider logging.
  String get label => switch (classify()) {
    TrackEndVerdict.finished => 'finish',
    TrackEndVerdict.continueTrack => 'segment-boundary',
  };
}

/// Accumulates per-segment progress into a running track total.
///
/// Without this, no single `completed` event can place itself within the track:
/// every event reports a position of a few seconds regardless of where it
/// actually falls. One instance belongs to each track.
class TrackProgressAccumulator {
  Duration _banked = Duration.zero;

  /// Progress banked from segments completed so far.
  Duration get banked => _banked;

  /// Called when a new track starts, discarding the previous track's progress.
  void reset() => _banked = Duration.zero;

  /// Adds a completed segment's [position] to the running total.
  void bank(Duration position) {
    if (position > Duration.zero) _banked += position;
  }
}

/// Detects a stream that stopped making progress partway through a track.
///
/// A boundary event cannot identify this: at every healthy boundary mpv reports
/// a short position, and it briefly reports `playing == false` while handing
/// off to the next segment. What distinguishes a dead stream is that position
/// *stops advancing* while the track is still short of its real length.
///
/// The caller feeds each observed position to [observe]. When position has not
/// moved for [stallTimeout] while the track is known to be longer than what has
/// played, [isStalled] becomes true and the caller may retry on a fresh URL.
class PlaybackStallWatchdog {
  PlaybackStallWatchdog({
    this.stallTimeout = const Duration(seconds: 90),
    this.gracePeriod = const Duration(seconds: 30),
  });

  /// How long progress must stop before the stream counts as stalled.
  ///
  /// Generous by necessity. Measured on a device over a real network, a healthy
  /// 239s track took 330s of wall time to play 222s of audio and still had a
  /// multi-second buffering gap near the end. A short timeout treats ordinary
  /// buffering as a dead stream and restarts a track that was playing fine.
  final Duration stallTimeout;

  /// Time from track start during which stalling is not judged.
  ///
  /// Covers resolve time and initial buffering, which legitimately look like a
  /// stalled stream.
  final Duration gracePeriod;

  Duration _lastPosition = Duration.zero;
  Duration _lastChangeAt = Duration.zero;
  bool _stalled = false;

  /// Whether the stream is currently judged stalled.
  bool get isStalled => _stalled;

  /// Position at the most recent change.
  Duration get position => _lastPosition;

  /// Called when a new track starts.
  void reset() {
    _lastPosition = Duration.zero;
    _lastChangeAt = Duration.zero;
    _stalled = false;
  }

  /// Feeds an observed player position, timed from [trackElapsed].
  ///
  /// [isBuffering] suppresses judgement: a stream waiting on the network is
  /// paused, not dead, and this project's own measurements show healthy tracks
  /// buffering for tens of seconds on a real connection.
  ///
  /// Returns true when this observation is the one that detected a stall.
  bool observe(
    Duration trackElapsed,
    Duration position, {
    bool isBuffering = false,
  }) {
    if (isBuffering) {
      // Don't advance the clock while waiting on the network, so a long
      // buffering gap cannot be counted as stalled time.
      _lastChangeAt = trackElapsed;
      return false;
    }
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastChangeAt = trackElapsed;
      _stalled = false;
      return false;
    }
    if (trackElapsed < gracePeriod) return false;
    if (trackElapsed - _lastChangeAt < stallTimeout) return false;
    _stalled = true;
    return true;
  }

  /// Whether a stall at the current position represents a genuinely lost track.
  ///
  /// Requires a known expected [expectedDuration]: a stream that played
  /// everything it had to play is finished, not stalled.
  bool isTruncated({required Duration expectedDuration, required Duration banked}) {
    if (!_stalled) return false;
    if (expectedDuration <= PlaybackEndSignal.meaningfulLength) return false;
    return banked <
        expectedDuration - PlaybackEndSignal.endTolerance;
  }
}