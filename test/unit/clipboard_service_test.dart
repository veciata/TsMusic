import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/core/services/clipboard_service.dart';

void main() {
  late ClipboardService service;

  setUp(() {
    service = ClipboardService();
  });

  group('YouTube URL RegEx Parser', () {
    test('parses standard youtube.com/watch?v= URL', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
      expect(result.isPlaylist, isFalse);
    });

    test('parses youtu.be short URL', () {
      final result = service.parseYouTubeLink(
        'https://youtu.be/dQw4w9WgXcQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
      expect(result.isPlaylist, isFalse);
    });

    test('parses youtube.com/embed/ URL', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
    });

    test('parses youtube.com/v/ URL', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/v/dQw4w9WgXcQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
    });

    test('parses music.youtube.com URL', () {
      final result = service.parseYouTubeLink(
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
    });

    test('parses playlist URL', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf',
      );

      expect(result, isNotNull);
      expect(result!.isPlaylist, isTrue);
      expect(result.playlistId, equals('PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf'));
    });

    test('parses video in playlist URL', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
      expect(result.playlistId, equals('PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf'));
      expect(result.isPlaylist, isFalse);
    });

    test('returns null for non-YouTube URL', () {
      final result = service.parseYouTubeLink(
        'https://www.example.com/some-video',
      );

      expect(result, isNull);
    });

    test('returns null for random text', () {
      final result = service.parseYouTubeLink(
        'this is not a URL at all',
      );

      expect(result, isNull);
    });

    test('handles URL with extra query parameters', () {
      final result = service.parseYouTubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc123&t=120',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('dQw4w9WgXcQ'));
    });

    test('is case insensitive', () {
      final result = service.parseYouTubeLink(
        'HTTPS://WWW.YOUTUBE.COM/WATCH?V=DQW4W9WGXCQ',
      );

      expect(result, isNotNull);
      expect(result!.videoId, equals('DQW4W9WGXCQ'));
    });
  });
}
