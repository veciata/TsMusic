import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/scrobbling/lastfm_scrobbler.dart';
import 'package:tsmusic/services/scrobbling/listenbrainz_scrobbler.dart';

Song _song() => Song(
  id: 1,
  youtubeId: 'abc',
  title: 'Song Title',
  artists: const ['The Artist'],
  album: 'The Album',
  url: 'yt:abc',
  duration: 200000,
);

void main() {
  group('lastFmSignature', () {
    test('sorts params, drops format/callback and appends the secret', () {
      final signature = lastFmSignature({
        'api_key': 'abc',
        'method': 'auth.getToken',
        'token': 'tok',
        'format': 'json',
        'callback': 'cb',
      }, 'secret');
      expect(signature, 'f0f62e11b0fecbc5bec207841f2cff68');
    });
  });

  group('ListenBrainzScrobbler', () {
    test('submits a now-playing listen without listened_at', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['Authorization'], 'Token my-token');
        return http.Response('{"status":"ok"}', 200);
      });

      final ok = await ListenBrainzScrobbler(
        token: 'my-token',
        client: client,
      ).updateNowPlaying(_song());

      expect(ok, isTrue);
      expect(body['listen_type'], 'playing_now');
      final payload = body['payload'] as List;
      expect(payload, hasLength(1));
      final listen = payload.first as Map<String, dynamic>;
      expect(listen.containsKey('listened_at'), isFalse);
      final metadata = listen['track_metadata'] as Map<String, dynamic>;
      expect(metadata['artist_name'], 'The Artist');
      expect(metadata['track_name'], 'Song Title');
      expect(metadata['release_name'], 'The Album');
    });

    test('submits a scrobble with a listened_at timestamp', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"status":"ok"}', 200);
      });

      final startedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final ok = await ListenBrainzScrobbler(
        token: 't',
        client: client,
      ).scrobble(_song(), startedAt);

      expect(ok, isTrue);
      expect(body['listen_type'], 'single');
      final listen = (body['payload'] as List).first as Map<String, dynamic>;
      expect(listen['listened_at'], startedAt.millisecondsSinceEpoch ~/ 1000);
    });

    test('returns false on a non-2xx response', () async {
      final client = MockClient((request) async => http.Response('nope', 401));
      final ok = await ListenBrainzScrobbler(
        token: 't',
        client: client,
      ).updateNowPlaying(_song());
      expect(ok, isFalse);
    });
  });

  group('LastFmScrobbler', () {
    test('signs and submits a scrobble', () async {
      late Map<String, String> body;
      final client = MockClient((request) async {
        body = Uri.splitQueryString(request.body);
        return http.Response('{}', 200);
      });

      final startedAt = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
      final ok = await LastFmScrobbler(
        apiKey: 'key',
        secret: 'secret',
        sessionKey: 'sk',
        client: client,
      ).scrobble(_song(), startedAt);

      expect(ok, isTrue);
      expect(body['method'], 'track.scrobble');
      expect(body['artist'], 'The Artist');
      expect(body['track'], 'Song Title');
      expect(body['sk'], 'sk');
      expect(body['timestamp'], '1000');
      expect(body['api_sig'], isNotEmpty);
    });

    test('treats an error body as a failure', () async {
      final client = MockClient(
        (request) async =>
            http.Response('{"error":10,"message":"Invalid API key"}', 200),
      );
      final ok = await LastFmScrobbler(
        apiKey: 'key',
        secret: 'secret',
        sessionKey: 'sk',
        client: client,
      ).updateNowPlaying(_song());
      expect(ok, isFalse);
    });
  });

  group('LastFmAuth', () {
    test('requests a token', () async {
      late Map<String, String> body;
      final client = MockClient((request) async {
        body = Uri.splitQueryString(request.body);
        return http.Response('{"token":"request-token"}', 200);
      });

      final token = await LastFmAuth(
        client: client,
      ).getToken(apiKey: 'key', secret: 'secret');

      expect(token, 'request-token');
      expect(body['method'], 'auth.getToken');
      expect(body['api_sig'], isNotEmpty);
    });

    test('builds the authorization URL', () {
      final url = LastFmAuth().authorizeUrl(apiKey: 'key', token: 'tok');
      expect(url.host, 'www.last.fm');
      expect(url.queryParameters['api_key'], 'key');
      expect(url.queryParameters['token'], 'tok');
    });

    test('exchanges a token for a session', () async {
      final client = MockClient(
        (request) async => http.Response(
          '{"session":{"key":"session-key","name":"listener"}}',
          200,
        ),
      );

      final session = await LastFmAuth(
        client: client,
      ).getSession(apiKey: 'key', secret: 'secret', token: 'tok');

      expect(session, isNotNull);
      expect(session!.sessionKey, 'session-key');
      expect(session.username, 'listener');
    });

    test('returns null when the response carries an error', () async {
      final client = MockClient(
        (request) async => http.Response('{"error":4,"message":"auth"}', 200),
      );
      final session = await LastFmAuth(
        client: client,
      ).getSession(apiKey: 'key', secret: 'secret', token: 'tok');
      expect(session, isNull);
    });
  });
}
