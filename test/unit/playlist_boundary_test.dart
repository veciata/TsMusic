import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/models/storage_type.dart';
import 'package:tsmusic/utils/playlist_boundary.dart';

void main() {
  group('StorageType', () {
    test('local has isLocal true and isRemote false', () {
      expect(StorageType.local.isLocal, isTrue);
      expect(StorageType.local.isRemote, isFalse);
    });

    test('remote has isRemote true and isLocal false', () {
      expect(StorageType.remote.isRemote, isTrue);
      expect(StorageType.remote.isLocal, isFalse);
    });
  });

  group('PlaylistBoundary.canAddToPlaylist', () {
    test('local song can be added to localOnly playlist', () {
      expect(
        PlaylistBoundary.canAddToPlaylist(StorageType.local, PlaylistType.localOnly),
        isTrue,
      );
    });

    test('local song can be added to remoteCompatible playlist', () {
      expect(
        PlaylistBoundary.canAddToPlaylist(StorageType.local, PlaylistType.remoteCompatible),
        isTrue,
      );
    });

    test('remote song cannot be added to localOnly playlist', () {
      expect(
        PlaylistBoundary.canAddToPlaylist(StorageType.remote, PlaylistType.localOnly),
        isFalse,
      );
    });

    test('remote song can be added to remoteCompatible playlist', () {
      expect(
        PlaylistBoundary.canAddToPlaylist(StorageType.remote, PlaylistType.remoteCompatible),
        isTrue,
      );
    });
  });

  group('PlaylistBoundary.getWarningMessage', () {
    test('returns null when add is allowed', () {
      expect(
        PlaylistBoundary.getWarningMessage(StorageType.local, PlaylistType.localOnly),
        isNull,
      );
      expect(
        PlaylistBoundary.getWarningMessage(StorageType.remote, PlaylistType.remoteCompatible),
        isNull,
      );
    });

    test('returns message when add is blocked', () {
      final message = PlaylistBoundary.getWarningMessage(
        StorageType.remote,
        PlaylistType.localOnly,
      );

      expect(message, isNotNull);
      expect(message, contains('local tracks'));
    });
  });
}
