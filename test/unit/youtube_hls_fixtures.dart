// Shared fixtures and fakes for YouTube HLS download/playback tests.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mockito/mockito.dart' show Fake;

/// Visitor data returned by the mocked YouTube homepage.
const kVisitorData = 'TESTVISITORDATA';

/// Master playlist with two audio groups (233 = low quality, 234 = high).
/// The best-quality pick must be media-high (clen 3861999).
const kMasterPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=358400,AVERAGE-BANDWIDTH=358400,CODECS="avc1.64001e,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=30.0,VIDEO-RANGE=SDR
https://rr2.googlevideo.com/master-main.m3u8
#EXT-X-MEDIA:URI="https://rr1.googlevideo.com/media-low.m3u8?clen%3D1456032%3Bdur%3D231.0",TYPE=AUDIO,GROUP-ID="233",NAME="audio-lo",DEFAULT=YES,AUTOSELECT=YES
#EXT-X-MEDIA:URI="https://rr1.googlevideo.com/media-high.m3u8?clen%3D3861999%3Bdur%3D231.0",TYPE=AUDIO,GROUP-ID="234",NAME="audio-hi",DEFAULT=YES,AUTOSELECT=YES
''';

/// Media playlist for the high-quality audio group (3 segments).
const kMediaPlaylist = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:5.666667,
https://rr1.googlevideo.com/seg0
#EXTINF:5.666667,
https://rr1.googlevideo.com/seg1
#EXTINF:5.666667,
https://rr1.googlevideo.com/seg2
#EXT-X-ENDLIST
''';

/// No-op [PlayerStream] so [YouTubeService._init] subscriptions are safe.
class FakePlayerStream extends Fake implements PlayerStream {
  @override
  Stream<bool> get playing => const Stream<bool>.empty();
  @override
  Stream<bool> get completed => const Stream<bool>.empty();
}

/// A [Player] that records its last opened [Playable] without touching any
/// native media_kit initialization, so unit tests never need real playback.
class FakePlayer extends Fake implements Player {
  FakePlayer() : stream = FakePlayerStream();

  @override
  final PlayerStream stream;

  /// Mutable so tests can simulate what the player reports after a stream dies
  /// early (a truncated duration, a short position, a zero duration).
  PlayerState playerState = const PlayerState();

  @override
  PlayerState get state => playerState;

  Playable? lastOpened;
  bool stopCalled = false;
  bool playCalled = false;
  bool pauseCalled = false;

  /// Delay applied inside [open], so a test can provoke a second player cycle
  /// while the first one is still running.
  Duration openDelay = Duration.zero;

  /// Whether a [stop] landed while an [open] was still in flight.
  ///
  /// That is the exact pattern that killed the app on device: two overlapping
  /// `stop -> open -> play` cycles on one mpv core, ending in SIGSEGV.
  bool stopDuringOpen = false;

  /// Highest number of [open] calls that were ever in flight at once.
  int maxConcurrentOpens = 0;

  int _activeOpens = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    _activeOpens++;
    if (_activeOpens > maxConcurrentOpens) maxConcurrentOpens = _activeOpens;
    lastOpened = playable;
    if (openDelay > Duration.zero) {
      await Future<void>.delayed(openDelay);
    }
    _activeOpens--;
  }

  @override
  Future<void> stop() async {
    if (_activeOpens > 0) stopDuringOpen = true;
    stopCalled = true;
  }

  @override
  Future<void> play() async {
    playCalled = true;
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
  }
}

/// Mock client simulating the YouTube HLS flow:
///   homepage (visitorData) -> youtubei player -> master -> media -> segments.
/// [perSegmentDelay] makes the parallel-download test observable. When
/// [hlsAvailable] is false the player reports LOGIN_REQUIRED so the HLS path
/// returns null and playback falls back to DASH.
MockClient buildMockHttpClient({
  bool hlsAvailable = true,
  Duration perSegmentDelay = Duration.zero,
  void Function(int activeSegments)? onSegmentActive,
  int? failSegment,
  // Called once per master-playlist fetch with the 1-based count, so tests
  // can observe whether a stream URL was extracted fresh vs served from cache.
  void Function(int masterFetches)? onMasterFetched,
}) {
  var activeSegments = 0;
  var masterFetches = 0;
  return MockClient((request) async {
    final url = request.url;
    final path = url.path;

    if (path == '/') {
      return http.Response(
        'window.YT = {"VISITOR_DATA":"$kVisitorData"};',
        200,
      );
    }
    if (path == '/youtubei/v1/player') {
      if (!hlsAvailable) {
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'streamingData': {
            'hlsManifestUrl': 'https://youtube.com/master.m3u8',
          },
        }),
        200,
      );
    }

    final full = url.toString();
    if (full.contains('/master.m3u8')) {
      masterFetches++;
      onMasterFetched?.call(masterFetches);
      // Vary the resolved media URI per extraction so tests can tell a fresh
      // extraction (gen=N) apart from a cached stream URL (gen=1 forever).
      return http.Response(
        kMasterPlaylist.replaceFirst(
          'media-high.m3u8',
          'media-high.m3u8?gen=$masterFetches',
        ),
        200,
      );
    }
    if (full.contains('media-high')) {
      return http.Response(kMediaPlaylist, 200);
    }
    if (full.contains('media-low')) {
      return http.Response(
        '#EXTM3U\n#EXTINF:6.0,\n'
        'https://rr1.googlevideo.com/low0\n#EXT-X-ENDLIST\n',
        200,
      );
    }
    if (full.contains('rr1.googlevideo.com/seg')) {
      final index = int.parse(RegExp(r'/seg(\d+)').firstMatch(full)!.group(1)!);
      if (failSegment == index) {
        return http.Response('upstream error', 500);
      }
      activeSegments++;
      onSegmentActive?.call(activeSegments);
      await Future<void>.delayed(perSegmentDelay);
      activeSegments--;
      onSegmentActive?.call(activeSegments);
      return http.Response.bytes(utf8.encode('SEG$index'), 200);
    }

    // Anything else fails fast so cleanup paths resolve promptly.
    return http.Response('internal error', 505);
  });
}
