import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tsmusic/models/lyrics.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/utils/lrc_parser.dart';

/// A place lyrics can be fetched from.
abstract class LyricsSource {
  /// Human-readable provider name, shown to the user.
  String get name;

  /// Returns lyrics for [song], or null when this source has none.
  Future<Lyrics?> fetch(Song song);
}

/// Reads a sibling `.lrc` file next to a local audio file.
///
/// This is the highest-priority source: it needs no network and is exact for
/// the user's own files.
class LrcFileLyricsSource implements LyricsSource {
  const LrcFileLyricsSource();

  @override
  String get name => 'LRC file';

  @override
  Future<Lyrics?> fetch(Song song) async {
    if (song.url.startsWith('yt:')) return null;
    final dot = song.url.lastIndexOf('.');
    if (dot <= 0) return null;
    final file = File('${song.url.substring(0, dot)}.lrc');
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final synced = parseLrc(content);
    return Lyrics(plain: content, synced: synced, source: name);
  }
}

/// Fetches lyrics from [LRCLIB](https://lrclib.net) (no API key required).
///
/// Prefers synced lyrics; falls back to plain.
class LrclibLyricsSource implements LyricsSource {
  LrclibLyricsSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Map<String, String> _headers = {'User-Agent': 'tsmusic/1.4.0'};

  @override
  String get name => 'LRCLIB';

  @override
  Future<Lyrics?> fetch(Song song) async {
    final title = song.title.trim();
    if (title.isEmpty) return null;
    final artist = song.artist.trim();
    final durationSeconds = song.duration > 0
        ? (song.duration / 1000).round()
        : null;

    if (durationSeconds != null) {
      final exact = await _fetchExact(
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
      );
      if (exact != null) return exact;
    }
    return _search(title: title, artist: artist);
  }

  Future<Lyrics?> _fetchExact({
    required String title,
    required String artist,
    required int durationSeconds,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
      'duration': '$durationSeconds',
    });
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! Map) return null;
    final lyrics = _fromJson(Map<String, dynamic>.from(data));
    return (lyrics == null || lyrics.isEmpty) ? null : lyrics;
  }

  Future<Lyrics?> _search({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
    });
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! List) return null;

    Lyrics? plainFallback;
    for (final item in data) {
      if (item is! Map) continue;
      final lyrics = _fromJson(Map<String, dynamic>.from(item));
      if (lyrics == null || lyrics.isEmpty) continue;
      if (lyrics.hasSynced) return lyrics;
      plainFallback ??= lyrics;
    }
    return plainFallback;
  }

  Lyrics? _fromJson(Map<String, dynamic> item) {
    final synced = (item['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (item['plainLyrics'] as String?)?.trim() ?? '';
    if (synced.isNotEmpty) {
      return Lyrics(
        plain: plain.isEmpty ? synced : plain,
        synced: parseLrc(synced),
        source: name,
      );
    }
    if (plain.isNotEmpty) {
      return Lyrics(plain: plain, source: name);
    }
    return null;
  }
}

/// Plain-text fallback provider ([lyrics.ovh](https://lyrics.ovh)).
class LyricsOvhSource implements LyricsSource {
  LyricsOvhSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'lyrics.ovh';

  @override
  Future<Lyrics?> fetch(Song song) async {
    final title = song.title.trim();
    if (title.isEmpty) return null;
    final artist = song.artist.trim();
    final uri = Uri.parse(
      'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/'
      '${Uri.encodeComponent(title)}',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! Map) return null;
    final text = (data['lyrics'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    return Lyrics(plain: text, source: name);
  }
}

/// Runs the configured [LyricsSource]s in order and returns the first hit.
class LyricsService {
  LyricsService({http.Client? client, List<LyricsSource>? sources})
    : sources =
          sources ??
          <LyricsSource>[
            const LrcFileLyricsSource(),
            LrclibLyricsSource(client: client),
            LyricsOvhSource(client: client),
          ];

  final List<LyricsSource> sources;

  Future<Lyrics?> fetch(Song song) async {
    for (final source in sources) {
      try {
        final lyrics = await source.fetch(song);
        if (lyrics != null && !lyrics.isEmpty) return lyrics;
      } catch (e) {
        // A broken provider must not stop the next one from being tried.
        debugPrint('Lyrics source ${source.name} failed: $e');
      }
    }
    return null;
  }
}
