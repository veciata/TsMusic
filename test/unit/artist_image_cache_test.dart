import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/artist_image_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('artist_img_cache_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Song songWithArt(String artist, {String? artUrl, String? thumbPath}) => Song(
    id: 1,
    title: 'Track',
    artists: [artist],
    album: 'Album',
    albumArtUrl: artUrl,
    url: '/s/track.mp3',
    duration: 1000,
    localThumbnailPath: thumbPath,
  );

  test('album art is downloaded once and persisted to the cache', () async {
    var artRequests = 0;
    final client = MockClient((request) async {
      artRequests++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    });

    final cache = ArtistImageCache(
      httpClient: client,
      directoryOverride: tempDir,
    );
    final localSongs = [
      songWithArt('Test Artist', artUrl: 'http://example.com/art.jpg'),
    ];

    final path1 = await cache.ensureArtistImage(
      'Test Artist',
      localSongs: localSongs,
    );
    expect(path1, isNotNull);
    expect(artRequests, 1, reason: 'first lookup must download the image');
    expect(File(path1!).existsSync(), isTrue);
    expect(File(path1).readAsBytesSync(), [1, 2, 3, 4]);

    // Same session, same artist: served from cache, no second download.
    final path2 = await cache.ensureArtistImage('Test Artist');
    expect(path2, path1);
    expect(artRequests, 1, reason: 'no re-download when the image is cached');
  });

  test(
    'a fresh service instance reuses the disk cache without downloading',
    () async {
      var artRequests = 0;
      final client = MockClient((request) async {
        artRequests++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final first = ArtistImageCache(
        httpClient: client,
        directoryOverride: tempDir,
      );
      final path = await first.ensureArtistImage(
        'Test Artist',
        localSongs: [songWithArt('Test Artist', artUrl: 'http://x/art.jpg')],
      );
      expect(path, isNotNull);
      expect(artRequests, 1);

      // Simulates an app restart: new instance, same cache directory.
      final second = ArtistImageCache(
        httpClient: client,
        directoryOverride: tempDir,
      );
      final rerun = await second.ensureArtistImage('Test Artist');
      expect(rerun, path);
      expect(
        artRequests,
        1,
        reason: 'restart must reuse the persisted image, not fetch again',
      );
    },
  );

  test('a local song thumbnail is used without any network request', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes([9], 200);
    });
    final thumb = File('${tempDir.path}/local_thumb.jpg')
      ..writeAsBytesSync([8, 8, 8]);

    final cache = ArtistImageCache(
      httpClient: client,
      directoryOverride: tempDir,
    );
    final path = await cache.ensureArtistImage(
      'Local Artist',
      localSongs: [songWithArt('Local Artist', thumbPath: thumb.path)],
    );

    expect(path, thumb.path);
    expect(requests, 0, reason: 'local thumbnails need no download');
  });

  test(
    'returns null without network when nothing can resolve an image',
    () async {
      var requests = 0;
      final cache = ArtistImageCache(
        httpClient: MockClient((request) async {
          requests++;
          return http.Response.bytes([1], 200);
        }),
        directoryOverride: tempDir,
      );

      expect(await cache.ensureArtistImage('No Images Artist'), isNull);
      expect(requests, 0, reason: 'no stuck-yet source -> no requests');
    },
  );
}
