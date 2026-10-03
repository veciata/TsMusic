import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/domain/playback/online_progress_display.dart';

void main() {
  const fourMinutes = Duration(minutes: 4, seconds: 8); // 248s
  const segment = Duration(seconds: 7);

  group('resolveOnlineTrackDuration', () {
    test('prefers metadata over the player segment length', () {
      expect(
        resolveOnlineTrackDuration(
          metadataDuration: fourMinutes,
          segmentDuration: segment,
        ),
        fourMinutes,
      );
    });

    test('falls back to the segment length before metadata arrives', () {
      expect(
        resolveOnlineTrackDuration(
          metadataDuration: Duration.zero,
          segmentDuration: segment,
        ),
        segment,
      );
    });

    test('rejects an absurd metadata length instead of trusting it', () {
      expect(
        resolveOnlineTrackDuration(
          metadataDuration: const Duration(days: 9),
          segmentDuration: segment,
        ),
        segment,
      );
    });

    test('reports unknown when nothing is known', () {
      expect(
        resolveOnlineTrackDuration(
          metadataDuration: Duration.zero,
          segmentDuration: Duration.zero,
        ),
        Duration.zero,
      );
    });
  });

  group('onlineDisplayPosition', () {
    test('adds banked progress to the current segment', () {
      expect(
        onlineDisplayPosition(
          banked: const Duration(seconds: 100),
          segmentPosition: const Duration(seconds: 3),
          trackDuration: fourMinutes,
        ),
        const Duration(seconds: 103),
      );
    });

    test('pins to the track length when a boundary double-counts', () {
      // The segment was banked but the player still reports its full length.
      final shown = onlineDisplayPosition(
        banked: const Duration(seconds: 248),
        segmentPosition: segment,
        trackDuration: fourMinutes,
      );
      expect(shown, fourMinutes);
      expect(shown, lessThanOrEqualTo(fourMinutes));
    });

    test('never goes below zero', () {
      expect(
        onlineDisplayPosition(
          banked: const Duration(seconds: -5),
          segmentPosition: Duration.zero,
          trackDuration: fourMinutes,
        ),
        Duration.zero,
      );
    });

    test('does not clamp while the track length is still unknown', () {
      expect(
        onlineDisplayPosition(
          banked: const Duration(seconds: 30),
          segmentPosition: const Duration(seconds: 4),
          trackDuration: Duration.zero,
        ),
        const Duration(seconds: 34),
      );
    });
  });

  group('across a whole track', () {
    // Simulates the real defect: 43 segment boundaries on a 248s track, each
    // reporting a position that restarts near zero. The displayed value must
    // count up and finish on the track length.
    test('displayed position counts up and never jumps back', () {
      final samples = <Duration>[];
      var banked = Duration.zero;

      for (var i = 0; i < 43; i++) {
        // Player position inside the segment: grows, then resets at boundary.
        for (final p in [0.5, 2, 4, 6, 6.9]) {
          samples.add(
            onlineDisplayPosition(
              banked: banked,
              segmentPosition: Duration(milliseconds: (p * 1000).round()),
              trackDuration: fourMinutes,
            ),
          );
        }
        // Boundary: the segment completes and its progress is banked.
        banked += segment;
      }

      expect(isMonotonicProgress(samples), isTrue,
          reason: 'counter jumped backwards');
      expect(samples.last, lessThanOrEqualTo(fourMinutes));
      expect(samples.last, greaterThan(Duration.zero));

      // Contrast with what the UI used to receive.
      final rawPlayerPositions = <Duration>[
        for (var i = 0; i < 43; i++) ...[
          Duration.zero,
          const Duration(seconds: 6, milliseconds: 900),
        ],
      ];
      expect(isMonotonicProgress(rawPlayerPositions), isFalse,
          reason: 'raw player values are exactly what looked wrong');
    });
  });
}