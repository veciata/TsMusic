import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/scrobbling/scrobbler.dart';

/// Submits listens to [ListenBrainz](https://listenbrainz.org) using a
/// personal user token. No application registration is required.
class ListenBrainzScrobbler implements Scrobbler {
  ListenBrainzScrobbler({required String token, http.Client? client})
    : _token = token.trim(),
      _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const String _endpoint =
      'https://api.listenbrainz.org/1/submit-listens';

  @override
  String get name => 'ListenBrainz';

  @override
  Future<bool> updateNowPlaying(Song song) =>
      _submit('playing_now', song, startedAt: null);

  @override
  Future<bool> scrobble(Song song, DateTime startedAt) =>
      _submit('single', song, startedAt: startedAt);

  Future<bool> _submit(
    String listenType,
    Song song, {
    required DateTime? startedAt,
  }) async {
    final payload = <String, dynamic>{
      'listen_type': listenType,
      'payload': [
        {
          'track_metadata': _trackMetadata(song),
          if (startedAt != null)
            'listened_at': startedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        },
      ],
    };
    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Token $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Map<String, dynamic> _trackMetadata(Song song) => {
    'artist_name': song.artist,
    'track_name': song.title,
    if ((song.album ?? '').isNotEmpty) 'release_name': song.album,
    'additional_info': {
      'submission_client': 'tsmusic',
      if (song.youtubeId != null) 'music_service': 'youtube',
    },
  };
}
