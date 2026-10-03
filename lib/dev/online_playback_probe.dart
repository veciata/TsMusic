// Standalone device probe for online playback, run as a normal app process
// instead of through `flutter test integration_test`.
//
// Why not the integration_test harness: on this device it failed twice before
// running any test logic (a VM-service WebSocket drop during load, then a
// SIGKILL of the runner). `flutter run` is the flow that actually works here.
//
// It exercises the production path -- `YouTubeService.playAudio` against the
// real network and a real mpv core -- and prints VERIFY lines that can be read
// straight out of logcat or the terminal.
//
// Run:
//   flutter run -t lib/dev/online_playback_probe.dart -d 192.168.1.100:5555
//   adb logcat | grep VERIFY

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:tsmusic/domain/playback/playback_end_signal.dart';
import 'package:tsmusic/services/youtube_service.dart';

/// A ~248s track, so a real play-through takes minutes rather than seconds.
const _videoId = '5qm8PH4xAss';

const _visionOsUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    MediaKit.ensureInitialized();

    // Phase 1 opens four concurrent HLS streams on purpose. That starves the
    // device's resolver for the rest of the process (every later lookup then
    // fails with errno 7), so skip it when only the play-through matters.
    if (!const bool.fromEnvironment('SKIP_PHASE1')) {
      await _probeConcurrentCycles();
    }
    // Phase 2: the actual user complaint -- a long online track playing through
    // inside a mixed playlist.
    await _probeFullPlaythrough();
    debugPrint('VERIFY ALL DONE');
  }

  Future<void> _probeConcurrentCycles() async {
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
    final service = YouTubeService(httpClient: http.Client(), player: player);
    try {
      final audio = _audio(_videoId);
      await Future.wait([
        service.playAudio(audio),
        service.playAudio(audio),
        service.playAudio(audio),
        service.playAudio(audio),
      ]);
      await Future<void>.delayed(const Duration(seconds: 15));
      debugPrint(
        'VERIFY phase1 survived currentAudio=${service.currentAudio?.id} '
        'playing=${player.state.playing}',
      );
    } catch (e) {
      debugPrint('VERIFY phase1 FAILED $e');
    } finally {
      await service.stop();
      await player.dispose();
    }
  }

  Future<void> _probeFullPlaythrough() async {
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
    final service = YouTubeService(httpClient: http.Client(), player: player);
    service.invalidateStreamCache(_videoId);

    final acc = TrackProgressAccumulator();
    final watchdog = PlaybackStallWatchdog();

    var expected = Duration.zero;
    var finished = 0;
    var boundaries = 0;
    var truncationFlags = 0;
    var trackElapsed = Duration.zero;

    void handleCompleted() {
      final s = player.state;
      final signal = PlaybackEndSignal(
        position: s.position,
        expectedDuration: expected,
        progressBeforeEvent: acc.banked,
        isPlaying: s.playing,
      );
      if (signal.classify() == TrackEndVerdict.finished) {
        finished++;
      } else {
        boundaries++;
      }
      acc.bank(s.position);
    }

    try {
      // Take the track's real length from the media playlist, not from the
      // metadata API: the metadata call intermittently comes back with no
      // duration, and a zero expected length makes every boundary classify as
      // "keep going" so the track can never end. The manifest is the ground
      // truth the player is actually consuming.
      expected = await _manifestDuration(service) ?? Duration.zero;
      debugPrint('VERIFY phase2 expectedMs=${expected.inMilliseconds}');

      player.stream.completed.listen((done) {
        if (done) handleCompleted();
      });

      final sw = Stopwatch()..start();
      // The device in testing resolves DNS over TLS to 8.8.8.8 and blips
      // intermittently ("No address associated with hostname"), which is an
      // environment problem rather than a code one. Retry setup so the probe
      // measures playback rather than the network.
      // trackOnline: false is queue mode: the mode in which the service
      // watchdog must stand down and leave recovery to MusicProvider.
      var started = false;
      for (var attempt = 0; attempt < 6 && !started; attempt++) {
        try {
          await service.playAudio(_audio(_videoId), trackOnline: false);
          started = true;
        } catch (e) {
          debugPrint('VERIFY phase2 setup attempt $attempt failed: $e');
          await Future<void>.delayed(const Duration(seconds: 10));
        }
      }
      if (!started) {
        debugPrint('VERIFY phase2 FAILED could not start playback');
        return;
      }
      sw.reset();

      while (sw.elapsed.inSeconds < 900 && finished == 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
        trackElapsed += const Duration(seconds: 2);
        final s = player.state;
        if (watchdog.observe(
              trackElapsed,
              acc.banked + s.position,
              isBuffering: s.buffering,
            ) &&
            watchdog.isTruncated(
              expectedDuration: expected,
              banked: acc.banked,
            )) {
          truncationFlags++;
        }
      }

      final pct = expected.inMilliseconds == 0
          ? 0.0
          : (acc.banked.inMilliseconds / expected.inMilliseconds * 100);
      debugPrint(
        'VERIFY phase2 wallSeconds=${sw.elapsed.inSeconds} '
        'finished=$finished boundaries=$boundaries '
        'truncationFlags=$truncationFlags '
        'bankedMs=${acc.banked.inMilliseconds} '
        'expectedMs=${expected.inMilliseconds} '
        'pct=${pct.toStringAsFixed(1)}',
      );
      debugPrint(
        finished == 1
            ? 'VERIFY phase2 PASS ended exactly once'
            : 'VERIFY phase2 FAIL finished=$finished',
      );
    } catch (e) {
      debugPrint('VERIFY phase2 FAILED $e');
    } finally {
      await service.stop();
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('probe'))),
  );
}

YouTubeAudio _audio(String id) => YouTubeAudio(
  id: id,
  title: 'Verification $id',
  author: 'tsmusic',
  artists: const ['tsmusic'],
  duration: const Duration(seconds: 240),
);

/// Total duration of the track, summed from the media playlist's `EXTINF`
/// entries -- the same numbers mpv walks through.
Future<Duration?> _manifestDuration(YouTubeService service) async {
  try {
    final resolved = await service.getHlsPlaylistUrl(_videoId);
    if (resolved == null) return null;
    final res = await http.get(
      Uri.parse(resolved.url),
      headers: const {'User-Agent': _visionOsUserAgent},
    );
    if (res.statusCode != 200) return null;
    var seconds = 0.0;
    for (final m in RegExp(r'#EXTINF:([\d.]+)').allMatches(res.body)) {
      seconds += double.parse(m.group(1)!);
    }
    if (seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  } catch (_) {
    return null;
  }
}
