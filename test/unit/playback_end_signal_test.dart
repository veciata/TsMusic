// Regression tests for online-track end classification and stall detection.
//
// These exist because the original bug was invisible to the existing suite: the
// premature-end predicate lived inside a 1500-line ChangeNotifier, so nothing
// could assert its behaviour without a real player, a database and a network.
//
// The defect they pin down, measured on a device (Android 16, real network)
// for a 239s track streamed from HLS:
//
//   completedCount=2 within 12s of wall time
//   completion#1 posMs=5750 durMs=6106 phantom=false diedPrematurely=true
//   completion#2 posMs=3620 durMs=3970 phantom=false diedPrematurely=true
//
// media_kit reports `completed` once per HLS segment, and on each event
// position/duration describe only that segment. The old predicate treated
// `position < 20s` as a dead stream, so it was permanently true and every
// segment boundary drove playback onto the DASH fallback, which buffers
// indefinitely on this network. Online songs in a mixed playlist therefore
// could not be heard to the end.
//
// Both failure directions are covered, because they are opposite:
// treating segment boundaries as "finished" would skip ~43 queue entries per
// track instead.
//
// A second measured result shaped the design: an attempt to detect death from a
// boundary using the player's `playing` flag misread 23 of 43 healthy
// boundaries on a track that still played to 221s of 239s, because mpv drops
// `playing` to false between segments. Death is a stall over time, so it is
// tested against the watchdog instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/domain/playback/playback_end_signal.dart';

const _track = Duration(minutes: 3, seconds: 59); // 239s, the measured track

void main() {
  group('PlaybackEndSignal.classify', () {
    test('a segment boundary mid-track is not the end of the track', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 5750),
        expectedDuration: _track,
        progressBeforeEvent: Duration.zero,
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('a later segment boundary with banked progress continues', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 3620),
        expectedDuration: _track,
        progressBeforeEvent: const Duration(seconds: 120),
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('progress reaching the track length means the track finished', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 6000),
        expectedDuration: _track,
        // 233s banked + 6s segment = 239s: the end of the track.
        progressBeforeEvent: const Duration(seconds: 233),
      );

      expect(signal.classify(), TrackEndVerdict.finished);
    });

    test('EXTINF rounding at the final segment still counts as finished', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 5400),
        expectedDuration: _track,
        progressBeforeEvent: const Duration(milliseconds: 236000),
      );

      expect(signal.classify(), TrackEndVerdict.finished);
    });

    test('an unknown track length never advances the queue', () {
      // The old code read a zero reported duration as "phantom" and retried.
      // Zero duration is normal for a segment and says nothing about the
      // track, so an unknown length must simply keep playing.
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 3000),
        expectedDuration: Duration.zero,
        progressBeforeEvent: const Duration(seconds: 90),
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('a short track is not mistaken for a finished long one', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 8000),
        expectedDuration: const Duration(seconds: 20),
        progressBeforeEvent: Duration.zero,
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('an exhausted playlist with the player stopped ends the track', () {
      // Measured on a device: a track that played all 43 of its segments banked
      // 221.9s of a 239s track (92.8%) because position at a boundary lags the
      // segment by ~400ms. Requiring an exact match would never end the track,
      // leaving the player idle after the final segment.
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 900),
        expectedDuration: _track,
        progressBeforeEvent: const Duration(milliseconds: 221000),
        isPlaying: false,
      );

      expect(signal.classify(), TrackEndVerdict.finished);
    });

    test('a stopped player well short of the length is not the end', () {
      // The same stopped player, but only a fifth of the track played: that is
      // a dead stream, and it must not advance the queue.
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 900),
        expectedDuration: _track,
        progressBeforeEvent: const Duration(seconds: 48),
        isPlaying: false,
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('a running player is not the end regardless of banked progress', () {
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 900),
        expectedDuration: _track,
        progressBeforeEvent: const Duration(milliseconds: 221000),
        isPlaying: true,
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });

    test('the first segment of a healthy track is not a failure', () {
      // Regression guard for the discarded `playing`-flag heuristic: this case
      // looks identical to a dead stream unless banked progress is used.
      final signal = PlaybackEndSignal(
        position: const Duration(milliseconds: 5750),
        expectedDuration: _track,
        progressBeforeEvent: Duration.zero,
      );

      expect(signal.classify(), TrackEndVerdict.continueTrack);
    });
  });

  group('TrackProgressAccumulator', () {
    test('banks segment positions into a running total', () {
      final acc = TrackProgressAccumulator()
        ..bank(const Duration(seconds: 6))
        ..bank(const Duration(seconds: 6))
        ..bank(const Duration(seconds: 4));

      expect(acc.banked, const Duration(seconds: 16));
    });

    test('ignores zero positions rather than banking them', () {
      final acc = TrackProgressAccumulator()..bank(Duration.zero);
      expect(acc.banked, Duration.zero);
    });

    test('reset discards the previous track', () {
      final acc = TrackProgressAccumulator()
        ..bank(const Duration(seconds: 100))
        ..reset();

      expect(acc.banked, Duration.zero);
    });

    test('accumulates a whole 239s track across its segments to one finish',
        () {
      // Replays the real sequence: ~39 segment boundaries, each reporting a
      // few seconds, must add up to exactly one track ending and one advance.
      final acc = TrackProgressAccumulator();
      const fullSegments = 38;
      final segmentLengths = List.generate(fullSegments, (_) => 6000);
      final remaining = _track - const Duration(seconds: fullSegments * 6);
      segmentLengths.add(remaining.inMilliseconds);

      var finished = 0;
      for (final segment in segmentLengths) {
        final signal = PlaybackEndSignal(
          position: Duration(milliseconds: segment),
          expectedDuration: _track,
          progressBeforeEvent: acc.banked,
        );
        if (signal.classify() == TrackEndVerdict.finished) finished++;
        acc.bank(Duration(milliseconds: segment));
      }

      expect(finished, 1, reason: 'a track must end exactly once');
      expect(acc.banked,
          greaterThanOrEqualTo(_track - const Duration(seconds: 1)));
    });
  });

  group('PlaybackStallWatchdog', () {
    test('does not fire while position keeps advancing', () {
      final wd = PlaybackStallWatchdog();
      var detected = false;
      for (var i = 0; i < 12; i++) {
        detected |= wd.observe(
          Duration(seconds: i * 5),
          Duration(seconds: i * 5),
        );
      }

      expect(detected, isFalse);
      expect(wd.isStalled, isFalse);
    });

    test('fires when position stops advancing before the track ends', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 20),
        gracePeriod: const Duration(seconds: 10),
      );
      // Play a little, then freeze.
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      var detected = false;
      for (var i = 1; i <= 10 && !detected; i++) {
        detected = wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
        );
      }

      expect(detected, isTrue);
      expect(wd.isStalled, isTrue);
      expect(
        wd.isTruncated(
          expectedDuration: _track,
          banked: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('does not fire during initial buffering or resolve time', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 20),
        gracePeriod: const Duration(seconds: 30),
      );
      var detected = false;
      for (var i = 0; i < 5; i++) {
        detected |= wd.observe(Duration(seconds: i * 5), Duration.zero);
      }

      expect(detected, isFalse, reason: 'grace period must suppress stalls');
    });

    test('a fully played track is finished, not stalled', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 10),
        gracePeriod: const Duration(seconds: 5),
      );
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      var detected = false;
      for (var i = 1; i <= 8 && !detected; i++) {
        detected = wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
        );
      }

      expect(wd.isStalled, isTrue);
      expect(
        wd.isTruncated(
          expectedDuration: _track,
          banked: _track,
        ),
        isFalse,
        reason: 'everything played, so nothing was lost',
      );
    });

    test('an unknown track length is never treated as truncated', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 10),
        gracePeriod: const Duration(seconds: 5),
      );
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      var detected = false;
      for (var i = 1; i <= 8 && !detected; i++) {
        detected = wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
        );
      }

      expect(
        wd.isTruncated(
          expectedDuration: Duration.zero,
          banked: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('buffering is not counted as a stall', () {
      // Measured on a real network: a healthy 239s track took 330s of wall
      // time and still had a multi-second buffering gap near the end. Treating
      // that as a dead stream would restart a track that was playing fine.
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 10),
        gracePeriod: const Duration(seconds: 5),
      );
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      var detected = false;
      for (var i = 1; i <= 10 && !detected; i++) {
        detected = wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
          isBuffering: true,
        );
      }

      expect(detected, isFalse);
      expect(wd.isStalled, isFalse);
    });

    test('a stall is still detected once buffering stops', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 10),
        gracePeriod: const Duration(seconds: 5),
      );
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      // Buffer for a while, then sit still without buffering.
      for (var i = 1; i <= 4; i++) {
        wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
          isBuffering: true,
        );
      }
      var detected = false;
      for (var i = 5; i <= 12 && !detected; i++) {
        detected = wd.observe(
          Duration(seconds: 5 + i * 5),
          const Duration(seconds: 5),
        );
      }

      expect(detected, isTrue);
    });

    test('reset clears a detected stall for the next track', () {
      final wd = PlaybackStallWatchdog(
        stallTimeout: const Duration(seconds: 10),
        gracePeriod: const Duration(seconds: 5),
      );
      wd.observe(const Duration(seconds: 5), const Duration(seconds: 5));
      wd.observe(const Duration(seconds: 10), const Duration(seconds: 5));
      wd.observe(const Duration(seconds: 15), const Duration(seconds: 5));
      expect(wd.isStalled, isTrue);

      wd.reset();

      expect(wd.isStalled, isFalse);
      expect(wd.position, Duration.zero);
    });
  });
}