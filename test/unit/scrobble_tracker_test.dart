import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/scrobbling/scrobble_tracker.dart';

Song _song({int duration = 200000}) => Song(
  id: 1,
  title: 'Song',
  artists: const ['Artist'],
  url: '/music/song.mp3',
  duration: duration,
);

void main() {
  group('ScrobbleTracker.isEligible', () {
    test('rejects tracks shorter than 30 seconds', () {
      expect(
        ScrobbleTracker.isEligible(20000, const Duration(seconds: 20)),
        isFalse,
      );
    });

    test('accepts half of the track length', () {
      expect(
        ScrobbleTracker.isEligible(200000, const Duration(seconds: 100)),
        isTrue,
      );
      expect(
        ScrobbleTracker.isEligible(200000, const Duration(seconds: 99)),
        isFalse,
      );
    });

    test('accepts four minutes even for very long tracks', () {
      expect(
        ScrobbleTracker.isEligible(3600000, const Duration(minutes: 4)),
        isTrue,
      );
    });
  });

  group('ScrobbleTracker', () {
    test('tracks the furthest position reached, not the latest', () {
      final tracker = ScrobbleTracker()
        ..begin(_song(), DateTime(2026))
        ..update(const Duration(seconds: 120))
        ..update(const Duration(seconds: 30));
      expect(tracker.maxPosition, const Duration(seconds: 120));
      expect(tracker.hasReachedThreshold, isTrue);
    });

    test('does not reach the threshold before half the track', () {
      final tracker = ScrobbleTracker()
        ..begin(_song(), DateTime(2026))
        ..update(const Duration(seconds: 30));
      expect(tracker.hasReachedThreshold, isFalse);
    });

    test('reset clears the accumulated state', () {
      final tracker = ScrobbleTracker()
        ..begin(_song(), DateTime(2026))
        ..update(const Duration(seconds: 150))
        ..reset();
      expect(tracker.song, isNull);
      expect(tracker.startedAt, isNull);
      expect(tracker.maxPosition, Duration.zero);
      expect(tracker.hasReachedThreshold, isFalse);
    });
  });
}
