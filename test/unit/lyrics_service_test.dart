import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/lyrics/lyrics_service.dart';

Song _song({
  String url = '/music/x.mp3',
  String title = 'Song',
  String artist = 'Artist',
  int duration = 200000,
}) =>
    Song(id: 1, title: title, artists: [artist], url: url, duration: duration);

void main() {
  group('LrclibLyricsSource', () {
    test('uses the exact endpoint and returns synced lyrics', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'lrclib.net');
        expect(request.url.path, '/api/get');
        return http.Response(
          jsonEncode({
            'syncedLyrics': '[00:01.00]Hello\n[00:05.00]World',
            'plainLyrics': 'Hello\nWorld',
          }),
          200,
        );
      });

      final lyrics = await LrclibLyricsSource(client: client).fetch(_song());
      expect(lyrics, isNotNull);
      expect(lyrics!.hasSynced, isTrue);
      expect(lyrics.synced, hasLength(2));
      expect(lyrics.source, 'LRCLIB');
    });

    test('falls back to search and keeps plain lyrics when unsynced', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode([
            {'syncedLyrics': '', 'plainLyrics': 'Only plain'},
          ]),
          200,
        );
      });

      final lyrics = await LrclibLyricsSource(client: client).fetch(_song());
      expect(lyrics!.hasSynced, isFalse);
      expect(lyrics.plain, 'Only plain');
    });
  });

  group('LyricsService', () {
    test('returns the first provider that has a result', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'lrclib.net') {
          return http.Response(
            jsonEncode({'syncedLyrics': '[00:01.00]Hi', 'plainLyrics': 'Hi'}),
            200,
          );
        }
        return http.Response('{}', 500);
      });
      final service = LyricsService(
        sources: [
          LrclibLyricsSource(client: client),
          LyricsOvhSource(client: client),
        ],
      );

      final lyrics = await service.fetch(_song());
      expect(lyrics!.source, 'LRCLIB');
    });

    test('falls through to lyrics.ovh when LRCLIB has nothing', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'lrclib.net') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(jsonEncode({'lyrics': 'Ovh lyrics'}), 200);
      });
      final service = LyricsService(
        sources: [
          LrclibLyricsSource(client: client),
          LyricsOvhSource(client: client),
        ],
      );

      final lyrics = await service.fetch(_song());
      expect(lyrics!.source, 'lyrics.ovh');
      expect(lyrics.plain, 'Ovh lyrics');
    });

    test('returns null when every provider fails', () async {
      final client = MockClient(
        (request) async => throw const SocketException('offline'),
      );
      final service = LyricsService(
        sources: [
          LrclibLyricsSource(client: client),
          LyricsOvhSource(client: client),
        ],
      );

      expect(await service.fetch(_song()), isNull);
    });

    test(
      'reads a sibling .lrc file for local songs without any network',
      () async {
        final dir = Directory.systemTemp.createTempSync('tsmusic_lyrics');
        final audio = File('${dir.path}/track.mp3')..writeAsStringSync('x');
        File('${dir.path}/track.lrc').writeAsStringSync('[00:02.00]Local line');

        final lyrics = await const LrcFileLyricsSource().fetch(
          _song(url: audio.path),
        );
        expect(lyrics, isNotNull);
        expect(lyrics!.source, 'LRC file');
        expect(lyrics.synced.single.text, 'Local line');
      },
    );

    test('ignores the sidecar source for online (yt:) tracks', () async {
      final lyrics = await const LrcFileLyricsSource().fetch(
        _song(url: 'yt:abc123'),
      );
      expect(lyrics, isNull);
    });
  });
}
