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

  Playable? lastOpened;
  bool stopCalled = false;
  bool playCalled = false;
  bool pauseCalled = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    lastOpened = playable;
  }

  @override
  Future<void> stop() async {
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
}) {
  var activeSegments = 0;
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
      return http.Response(kMasterPlaylist, 200);
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
