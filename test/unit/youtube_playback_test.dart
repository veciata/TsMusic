import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tsmusic/services/youtube_service.dart';

import 'youtube_hls_fixtures.dart';

void main() {
  setUpAll(() {
    // YouTubeService constructs a SongRepository (for local-match lookup),
    // which lazily touches the DatabaseHelper singleton — set up sqflite so
    // that never explodes in a bare test isolate.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(
      Directory.systemTemp.createTempSync('tsmusic_youtube_playback').path,
    );
  });

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

  test('cached stream URL is reused while fresh', () async {
    var masterFetches = 0;
    final player = FakePlayer();
    final service = YouTubeService(
      httpClient: buildMockHttpClient(
        onMasterFetched: (count) => masterFetches = count,
      ),
      player: player,
    );

    await service.playAudio(audio());
    final firstUri = (player.lastOpened as Media).uri.toString();
    expect(firstUri, contains('gen=1'));

    await service.playAudio(audio());
    final secondUri = (player.lastOpened as Media).uri.toString();

    expect(
      masterFetches,
      1,
      reason: 'a fresh stream URL should be served from cache',
    );
    expect(
      secondUri,
      firstUri,
      reason: 'the second play must reuse the cached stream URL',
    );
  });

  test(
    'invalidateStreamCache forces a fresh stream URL on next play',
    () async {
      var masterFetches = 0;
      final player = FakePlayer();
      final service = YouTubeService(
        httpClient: buildMockHttpClient(
          onMasterFetched: (count) => masterFetches = count,
        ),
        player: player,
      );

      await service.playAudio(audio());
      expect((player.lastOpened as Media).uri.toString(), contains('gen=1'));

      service.invalidateStreamCache('video-p1');
      await service.playAudio(audio());

      expect(
        masterFetches,
        2,
        reason: 'invalidation must force a fresh extraction next play',
      );
      expect((player.lastOpened as Media).uri.toString(), contains('gen=2'));
    },
  );

  test('concurrent playAudio calls never overlap on the player', () async {
    // Regression: the service watchdog and the provider watchdog both fired on
    // the same stall, each re-resolved the URL and re-entered playAudio. Two
    // overlapping stop->open->play cycles on one mpv core ended in SIGSEGV in
    // libmpv's core thread, killing the app partway through the track.
    final player = FakePlayer()..openDelay = const Duration(milliseconds: 20);
    final service = YouTubeService(
      httpClient: buildMockHttpClient(),
      player: player,
    );

    await Future.wait([
      service.playAudio(audio()),
      service.playAudio(audio()),
      service.playAudio(audio()),
    ]);

    expect(
      player.maxConcurrentOpens,
      1,
      reason: 'player cycles must be serialised',
    );
    expect(
      player.stopDuringOpen,
      isFalse,
      reason: 'a stop must never land while an open is in flight',
    );
    expect(player.playCalled, isTrue);
  });
}
