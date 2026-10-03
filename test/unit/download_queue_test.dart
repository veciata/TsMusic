import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsmusic/models/download_result.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/download_queue.dart';

DownloadRequest _req(String id) =>
    DownloadRequest(videoId: id, title: 'Track $id');

DownloadResult _result(String id) => DownloadResult(
  filePath: '/music/$id.m4a',
  song: Song(
    id: 1,
    youtubeId: id,
    title: 'Track $id',
    artists: const ['Artist'],
    url: '/music/$id.m4a',
    duration: 1000,
  ),
);

void main() {
  group('enqueue skips tracks already on the device', () {
    test('does not fetch a videoId the database already has', () async {
      final fetched = <String>[];
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          fetched.add(id);
          return _result(id);
        },
        // Stands in for a download made while a different playlist was open.
        downloadedVideoIds: () async => {'b', 'c'},
      );

      final result = await queue.enqueueAll([
        _req('a'),
        _req('b'),
        _req('c'),
        _req('d'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 2);
      expect(result.alreadyDownloaded, 2);
      expect(fetched, ['a', 'd']);
    });

    test('asks the database once for the whole batch', () async {
      var queries = 0;
      final queue = DownloadQueue(
        download: (id, onProgress) async => _result(id),
        downloadedVideoIds: () async {
          queries++;
          return <String>{};
        },
      );

      await queue.enqueueAll([_req('a'), _req('b'), _req('c'), _req('d')]);
      expect(queries, 1);
    });

    test('reports everything as skipped when all are on the device', () async {
      final queue = DownloadQueue(
        download: (id, onProgress) async => _result(id),
        downloadedVideoIds: () async => {'a', 'b'},
      );

      final result = await queue.enqueueAll([_req('a'), _req('b')]);
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 0);
      expect(result.alreadyDownloaded, 2);
      expect(queue.entries, isEmpty);
    });
  });

  group('enqueue de-duplicates', () {
    test('drops repeats of the same id inside one batch', () async {
      final fetched = <String>[];
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          fetched.add(id);
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      final result = await queue.enqueueAll([_req('a'), _req('a'), _req('b')]);
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 2);
      expect(result.alreadyQueued, 1);
      expect(fetched, ['a', 'b']);
    });

    test('rejects a track still waiting from an earlier batch', () async {
      final gate = Completer<DownloadResult?>();
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          if (id == 'a') await gate.future;
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      final first = await queue.enqueueAll([_req('a'), _req('b')]);
      await Future<void>.delayed(Duration.zero);
      final second = await queue.enqueueAll([_req('a'), _req('c')]);

      expect(first.added, 2);
      expect(second.added, 1);
      expect(second.alreadyQueued, 1);
      gate.complete(_result('a'));
    });
  });

  group('worker', () {
    test('downloads one track at a time', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          inFlight++;
          maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      await queue.enqueueAll([_req('a'), _req('b'), _req('c'), _req('d')]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(maxInFlight, 1,
          reason: 'parallel range requests are what draw YouTube 403s');
      expect(queue.completedCount, 4);
    });

    test('reports each finished track with its result', () async {
      final finished = <String>[];
      final queue = DownloadQueue(
        download: (id, onProgress) async => _result(id),
        downloadedVideoIds: () async => <String>{},
        onEntryFinished: (entry, result) => finished.add(
          '${entry.videoId}:${result?.song.youtubeId}',
        ),
      );

      await queue.enqueueAll([_req('a'), _req('b')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(finished, ['a:a', 'b:b']);
    });

    test('records a failure and keeps going', () async {
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          if (id == 'a') throw StateError('boom');
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      await queue.enqueueAll([_req('a'), _req('b')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(queue.failedCount, 1);
      expect(queue.completedCount, 1);
      final failed = queue.entries.firstWhere((e) => e.videoId == 'a');
      expect(failed.state, DownloadQueueState.failed);
      expect(failed.error, contains('boom'));
    });

    test('a track downloaded twice lands in the cache only once', () async {
      // The queue must consult the cache the service maintains, otherwise a
      // second batch re-fetches a track that just finished.
      final onDevice = <String>{};
      final fetched = <String>[];
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          fetched.add(id);
          onDevice.add(id);
          return _result(id);
        },
        downloadedVideoIds: () async => onDevice,
      );

      await queue.enqueueAll([_req('a')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final second = await queue.enqueueAll([_req('a')]);

      expect(second.added, 0);
      expect(fetched, ['a']);
    });
  });

  group('cancelling and retrying', () {
    test('stops after the track in flight and marks the rest cancelled',
        () async {
      final fetched = <String>[];
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          fetched.add(id);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      await queue.enqueueAll([_req('a'), _req('b'), _req('c'), _req('d')]);
      // Let 'a' start, then stop the batch.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      queue.requestCancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fetched.length, lessThan(4));
      expect(queue.entries.every((e) => e.state != DownloadQueueState.pending),
          isTrue);
    });

    test('a cleared failure can be queued again', () async {
      var attempts = 0;
      final queue = DownloadQueue(
        download: (id, onProgress) async {
          attempts++;
          if (attempts == 1) throw StateError('transient');
          return _result(id);
        },
        downloadedVideoIds: () async => <String>{},
      );

      await queue.enqueueAll([_req('a')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(queue.failedCount, 1);

      queue.clearFinished();
      final retry = await queue.enqueueAll([_req('a')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(retry.added, 1);
      expect(queue.completedCount, 1);
      expect(attempts, 2);
    });
  });
}