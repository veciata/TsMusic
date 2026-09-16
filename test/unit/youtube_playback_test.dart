import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tsmusic/services/youtube_service.dart';

import 'youtube_hls_fixtures.dart';

void main() {
  YouTubeAudio audio() => YouTubeAudio(
    id: 'video-p1',
    title: 'Test Track',
    author: 'Artist',
    artists: const ['Artist'],
    duration: const Duration(minutes: 3, seconds: 51),
  );

  test('playAudio streams the HLS media playlist URL via the player', () async {
    final player = FakePlayer();
    final service = YouTubeService(
      httpClient: buildMockHttpClient(),
      player: player,
    );

    await service.playAudio(audio());

    expect(player.stopCalled, isTrue);
    expect(player.playCalled, isTrue);
    expect(player.lastOpened, isNotNull);
    final media = player.lastOpened as Media;
    expect(media.uri.toString(), contains('media-high'));
    // The current audio carried the resolved HLS URL.
    expect(service.currentAudio?.audioUrl, contains('media-high'));
  });

  test(
    'playAudio fails without touching the player when HLS is unavailable',
    () async {
      final player = FakePlayer();
      final service = YouTubeService(
        httpClient: buildMockHttpClient(hlsAvailable: false),
        player: player,
      );

      await expectLater(service.playAudio(audio()), throwsA(isA<Exception>()));

      expect(player.lastOpened, isNull);
      expect(player.playCalled, isFalse);
    },
  );
}
