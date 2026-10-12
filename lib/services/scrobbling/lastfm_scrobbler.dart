import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/scrobbling/scrobbler.dart';

/// Builds the Last.fm `api_sig` value for [params].
///
/// The signature is the md5 of the concatenated, alphabetically sorted
/// parameter names and values (excluding `format` and `callback`) followed by
/// the shared secret.
String lastFmSignature(Map<String, String> params, String secret) {
  final keys =
      params.keys
          .where(
            (key) =>
                key != 'format' &&
                key != 'callback' &&
                (params[key] ?? '').isNotEmpty,
          )
          .toList()
        ..sort();
  final buffer = StringBuffer();
  for (final key in keys) {
    buffer
      ..write(key)
      ..write(params[key]);
  }
  buffer.write(secret);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// A Last.fm web-service response that carries a session key.
class LastFmSession {
  const LastFmSession({required this.sessionKey, required this.username});

  final String sessionKey;
  final String username;
}

/// Submits scrobbles to Last.fm.
///
/// Requires an API key/shared secret registered by the user plus a session key
/// obtained through [LastFmAuth].
class LastFmScrobbler implements Scrobbler {
  LastFmScrobbler({
    required this.apiKey,
    required this.secret,
    required this.sessionKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String secret;
  final String sessionKey;
  final http.Client _client;

  static const String _endpoint = 'https://ws.audioscrobbler.com/2.0/';

  @override
  String get name => 'Last.fm';

  @override
  Future<bool> updateNowPlaying(Song song) => _call('track.updateNowPlaying', {
    'artist': song.artist,
    'track': song.title,
    if ((song.album ?? '').isNotEmpty) 'album': song.album!,
    'api_key': apiKey,
    'sk': sessionKey,
  });

  @override
  Future<bool> scrobble(Song song, DateTime startedAt) =>
      _call('track.scrobble', {
        'artist': song.artist,
        'track': song.title,
        if ((song.album ?? '').isNotEmpty) 'album': song.album!,
        'timestamp': '${startedAt.millisecondsSinceEpoch ~/ 1000}',
        'api_key': apiKey,
        'sk': sessionKey,
      });

  Future<bool> _call(String method, Map<String, String> params) async {
    final signed = Map<String, String>.from(params)..['method'] = method;
    signed['api_sig'] = lastFmSignature(signed, secret);
    signed['format'] = 'json';
    final response = await _client.post(Uri.parse(_endpoint), body: signed);
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    // Errors come back as {"error": n, "message": "..."} (sometimes with HTTP
    // 200), so the body has to be inspected too.
    if (data is Map && data.containsKey('error')) return false;
    return true;
  }
}

/// Drives the Last.fm desktop-style authorization flow.
///
/// The flow is: request a token, send the user to the authorization page, then
/// exchange the token for a session key.
class LastFmAuth {
  LastFmAuth({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint = 'https://ws.audioscrobbler.com/2.0/';
  static const String _authPage = 'https://www.last.fm/api/auth/';

  /// Returns a request token, or null when the credentials are invalid.
  Future<String?> getToken({
    required String apiKey,
    required String secret,
  }) async {
    final params = <String, String>{
      'method': 'auth.getToken',
      'api_key': apiKey,
    };
    params['api_sig'] = lastFmSignature(params, secret);
    params['format'] = 'json';
    final response = await _client.post(Uri.parse(_endpoint), body: params);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! Map || data.containsKey('error')) return null;
    final token = data['token'] as String?;
    return (token == null || token.isEmpty) ? null : token;
  }

  /// The URL the user must open to grant this application access.
  Uri authorizeUrl({required String apiKey, required String token}) =>
      Uri.parse(
        _authPage,
      ).replace(queryParameters: {'api_key': apiKey, 'token': token});

  /// Exchanges an authorized [token] for a session key.
  Future<LastFmSession?> getSession({
    required String apiKey,
    required String secret,
    required String token,
  }) async {
    final params = <String, String>{
      'method': 'auth.getSession',
      'api_key': apiKey,
      'token': token,
    };
    params['api_sig'] = lastFmSignature(params, secret);
    params['format'] = 'json';
    final response = await _client.post(Uri.parse(_endpoint), body: params);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! Map || data.containsKey('error')) return null;
    final session = data['session'];
    if (session is! Map) return null;
    final key = session['key'] as String?;
    final username = session['name'] as String?;
    if (key == null || key.isEmpty) return null;
    return LastFmSession(sessionKey: key, username: username ?? '');
  }
}
