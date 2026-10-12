import 'package:http/http.dart' as http;
import 'package:tsmusic/models/scrobble_config.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/scrobbling/lastfm_scrobbler.dart';
import 'package:tsmusic/services/scrobbling/listenbrainz_scrobbler.dart';
import 'package:tsmusic/services/scrobbling/scrobbler.dart';

/// Chooses the configured [Scrobbler] and forwards submits to it.
class ScrobblingService {
  ScrobblingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Scrobbler? scrobblerFor(ScrobblingConfig config) {
    if (!config.isConfigured) return null;
    switch (config.type) {
      case ScrobblingProviderType.disabled:
        return null;
      case ScrobblingProviderType.listenBrainz:
        return ListenBrainzScrobbler(
          token: config.listenBrainzToken,
          client: _client,
        );
      case ScrobblingProviderType.lastFm:
        return LastFmScrobbler(
          apiKey: config.lastFmApiKey,
          secret: config.lastFmSecret,
          sessionKey: config.lastFmSessionKey,
          client: _client,
        );
    }
  }

  Future<bool> updateNowPlaying(ScrobblingConfig config, Song song) async {
    final scrobbler = scrobblerFor(config);
    if (scrobbler == null) return false;
    return scrobbler.updateNowPlaying(song);
  }

  Future<bool> scrobble(
    ScrobblingConfig config,
    Song song,
    DateTime startedAt,
  ) async {
    final scrobbler = scrobblerFor(config);
    if (scrobbler == null) return false;
    return scrobbler.scrobble(song, startedAt);
  }

  LastFmAuth lastFmAuth() => LastFmAuth(client: _client);
}
