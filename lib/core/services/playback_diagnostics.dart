import 'dart:async';

import 'package:flutter/foundation.dart';

/// A single observation of the player's timeline.
///
/// Deliberately not `PlayerState`: diagnostics must not depend on media_kit so
/// they stay usable from unit tests and from any future player backend.
typedef PlayerSample = ({
  int positionMs,
  int durationMs,
  bool buffering,
  bool playing,
  bool completed,
});

/// Structured, greppable playback tracing.
///
/// Every line is emitted under the single tag [tag] so the whole trace can be
/// captured with:
///
/// ```
/// adb logcat -s PlaybackTrace
/// ```
///
/// This is a *diagnostic* aid for the online-playback truncation work. It is
/// deliberately no-op outside debug builds so release binaries carry no
/// formatting cost or log noise.
class PlaybackDiagnostics {
  PlaybackDiagnostics._();

  static const String tag = 'PlaybackTrace';

  /// Master switch. Kept mutable so tests and debug menus can silence tracing
  /// without recompiling.
  static bool enabled = kDebugMode;

  /// Monotonic counter so consecutive events for one track can be ordered even
  /// when logcat interleaves output from other threads.
  static int _seq = 0;

  static void _emit(String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final seq = ++_seq;
    final rendered = fields.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    debugPrint('[$tag] #$seq $event $rendered');
  }

  /// A stream URL was resolved for [videoId].
  ///
  /// [resolver] is `hls` or `dash`. [fromCache] tells us whether the URL was
  /// reused from the short-TTL cache, which matters when diagnosing repeated
  /// failures on the same track.
  static void resolved({
    required String videoId,
    required String resolver,
    required String? url,
    required bool fromCache,
    required Duration resolveDuration,
  }) => _emit('resolved', {
    'videoId': videoId,
    'resolver': resolver,
    'host': url == null ? null : Uri.tryParse(url)?.host,
    'fromCache': fromCache,
    'tookMs': resolveDuration.inMilliseconds,
  });

  /// A resolved URL was rejected outright and playback could not start.
  static void resolveFailed({
    required String videoId,
    required String reason,
  }) => _emit('resolve-failed', {'videoId': videoId, 'reason': reason});

  /// A track was handed to the player.
  ///
  /// The duration comparison is the important part: `playerDurationMs` is what
  /// libmpv reports for the stream, `expectedDurationMs` is the duration we
  /// persisted in the database. A large gap means the DB row is missing
  /// metadata, which disables the premature-end detector downstream.
  static void trackOpened({
    required String videoId,
    required String origin,
    required int? expectedDurationMs,
    required int? playerDurationMs,
    required bool fromQueue,
  }) => _emit('track-opened', {
    'videoId': videoId,
    'origin': origin,
    'expectedMs': expectedDurationMs,
    'playerMs': playerDurationMs,
    'expectedMissing': expectedDurationMs == null || expectedDurationMs <= 0,
    'fromQueue': fromQueue,
  });

  /// The player reported end-of-track.
  ///
  /// [branch] records which recovery path was taken, which is the single most
  /// useful field when working out why a track stopped early.
  static void trackCompleted({
    required String videoId,
    required int positionMs,
    required int? expectedDurationMs,
    required int? playerDurationMs,
    required String branch,
    required int retries,
  }) => _emit('track-completed', {
    'videoId': videoId,
    'posMs': positionMs,
    'expectedMs': expectedDurationMs,
    'playerMs': playerDurationMs,
    'branch': branch,
    'retries': retries,
  });

  /// Playback failed after the URL resolved (player refused the media).
  static void playbackFailed({
    required String videoId,
    required Object error,
    String? origin,
  }) => _emit('playback-failed', {
    'videoId': videoId,
    'origin': origin,
    'error': error.toString(),
  });

  static Timer? _sampler;

  /// Samples the player's timeline every [interval] for the life of the track.
  ///
  /// `trackOpened` reads `player.state.duration` immediately after `open()`,
  /// which races the demuxer: libmpv may not have parsed the playlist yet and
  /// reports zero regardless of whether playback will succeed. This sampler
  /// settles the question by showing what duration *settles* to.
  ///
  /// Enable with [startSampling]; it is inert unless [enabled].
  static void startSampling(
    String? videoId,
    PlayerSample Function() readState, {
    Duration interval = const Duration(seconds: 5),
  }) {
    if (!enabled) return;
    stopSampling();
    var tick = 0;
    _sampler = Timer.periodic(interval, (_) {
      final s = readState();
      _emit('sample', {
        'videoId': videoId,
        't': tick * interval.inSeconds,
        'posMs': s.positionMs,
        'durMs': s.durationMs,
        'buffering': s.buffering,
        'playing': s.playing,
        'completed': s.completed,
      });
      tick++;
    });
  }

  /// Converts a live [PlayerState] into a [PlayerSample].
  ///
  /// Kept as a plain function on the diagnostics class so call sites stay
  /// one-liners and the media_kit import lives in exactly one place.
  static PlayerSample sampleOf(dynamic state) => (
    positionMs: state.position.inMilliseconds as int,
    durationMs: state.duration.inMilliseconds as int,
    buffering: state.buffering as bool,
    playing: state.playing as bool,
    completed: state.completed as bool,
  );

  /// Stops any running [startSampling] loop.
  static void stopSampling() {
    _sampler?.cancel();
    _sampler = null;
  }

  /// The queue was loaded or replaced.
  static void queueLoaded({
    required String source,
    required int length,
    required int onlineCount,
    required int missingDurationCount,
    required int startIndex,
  }) => _emit('queue-loaded', {
    'source': source,
    'len': length,
    'online': onlineCount,
    'onlineMissingDuration': missingDurationCount,
    'start': startIndex,
  });
}
