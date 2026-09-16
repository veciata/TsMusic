import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/services/youtube_service.dart';

import 'youtube_hls_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tsmusic_hls_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('getHlsPlaylistUrl picks the best audio group (largest clen)', () async {
    final service = YouTubeService(
      httpClient: buildMockHttpClient(),
      player: FakePlayer(),
    );

    final playlist = await service.getHlsPlaylistUrl('video-1');
    expect(playlist, isNotNull);
    expect(playlist!.totalBytes, 3861999);
    expect(playlist.url, contains('media-high'));
    expect(playlist.url, isNot(contains('media-low')));
  });

  test(
    'getHlsPlaylistUrl returns null when the player refuses (no HLS)',
    () async {
      final service = YouTubeService(
        httpClient: buildMockHttpClient(hlsAvailable: false),
        player: FakePlayer(),
      );

      final playlist = await service.getHlsPlaylistUrl('video-2');
      expect(playlist, isNull);
    },
  );

  test('fetchHlsAudioSegments resolves ordered media segment URLs', () async {
    final service = YouTubeService(
      httpClient: buildMockHttpClient(),
      player: FakePlayer(),
    );

    final audio = await service.fetchHlsAudioSegments('video-3');
    expect(audio, isNotNull);
    expect(audio!.totalBytes, 3861999);
    expect(audio.segments, hasLength(3));
    expect(audio.segments.map((s) => s.split('/seg').last), ['0', '1', '2']);
  });

  test(
    'downloadHlsSegments reassembles segments in order, in parallel',
    () async {
      final active = <int>[];
      final service = YouTubeService(
        httpClient: buildMockHttpClient(
          perSegmentDelay: const Duration(milliseconds: 150),
          onSegmentActive: active.add,
        ),
        player: FakePlayer(),
      );

      final audio = await service.fetchHlsAudioSegments('video-4');
      expect(audio, isNotNull);
      expect(audio!.totalBytes, 3861999);

      final file = File('${tempDir.path}/out.m4a');
      final progress = <double>[];
      final stopwatch = Stopwatch()..start();
      final written = await service.downloadHlsSegments(
        videoId: 'video-4',
        segmentUrls: audio.segments,
        file: file,
        totalBytes: audio.segments.length * 'SEG0'.length,
        onProgress: progress.add,
      );
      stopwatch.stop();

      expect(written, 'SEG0SEG1SEG2'.length);
      expect(file.readAsStringSync(), 'SEG0SEG1SEG2');
      // All three segments were in flight simultaneously, not sequentially.
      expect(active.reduce((a, b) => a > b ? a : b), 3);
      // Parallel completes well under the ~450ms a sequential walk would take.
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 400)));
      // Progress is reported, monotonic, and reaches 1.0.
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    },
  );

  test(
    'downloadHlsSegments fails cleanly when a segment keeps erroring',
    () async {
      final service = YouTubeService(
        httpClient: buildMockHttpClient(failSegment: 1),
        player: FakePlayer(),
      );

      final audio = await service.fetchHlsAudioSegments('video-5');
      expect(audio, isNotNull);

      final file = File('${tempDir.path}/out-fail.m4a');
      await expectLater(
        service.downloadHlsSegments(
          videoId: 'video-5',
          segmentUrls: audio!.segments,
          file: file,
          totalBytes: audio.totalBytes,
        ),
        throwsA(isA<HttpException>()),
      );

      // Nothing was committed to disk on failure.
      expect(file.existsSync(), isFalse);
    },
  );
}
