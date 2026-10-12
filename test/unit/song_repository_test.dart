import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tsmusic/data/repositories/playlist_repository.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/song.dart';

Song _song({required String url, List<String>? artists, List<String>? tags}) =>
    Song(
      id: url.hashCode,
      title: 'Title of $url',
      artists: artists ?? ['Test Artist'],
      url: url,
      duration: 180000,
      tags: tags ?? <String>[],
    );

void main() {
  late SongRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(
      Directory.systemTemp.createTempSync('tsmusic_song_repo').path,
    );
  });

  setUp(() {
    repository = SongRepository();
  });

  test('saves a song and reloads it with artists and downloaded tag', () async {
    final song = _song(
      url: '/music/hello.mp3',
      artists: ['Alpha', 'Beta'],
      tags: ['tsmusic'],
    );

    await repository.saveSong(song);

    final loaded = await repository.search('hello.mp3');
    expect(loaded, hasLength(1));
    expect(loaded.first.url, '/music/hello.mp3');
    expect(loaded.first.artists, containsAll(['Alpha', 'Beta']));
    expect(loaded.first.isDownloaded, isTrue);

    expect(await repository.existsById(loaded.first.id), isTrue);
  });

  test('saves a batch of songs in a single transaction', () async {
    await repository.saveSongs([
      _song(url: '/music/one.mp3'),
      _song(url: '/music/two.mp3'),
      _song(url: '/music/three.mp3'),
    ]);

    final one = await repository.search('one.mp3');
    final two = await repository.search('two.mp3');
    final three = await repository.search('three.mp3');
    expect(one, hasLength(1));
    expect(two, hasLength(1));
    expect(three, hasLength(1));
  });

  test('searches by artist name', () async {
    final byArtist = await repository.search('Test Artist');
    expect(byArtist, isNotEmpty);
    expect(
      byArtist.map((s) => s.url),
      containsAll(['/music/one.mp3', '/music/two.mp3', '/music/three.mp3']),
    );
  });

  test('updates thumbnail and youtube id in place', () async {
    await repository.saveSong(_song(url: '/music/update.mp3'));

    final target = (await repository.search('update.mp3')).single;
    expect(target.localThumbnailPath, isNull);

    await repository.updateThumbnailPath(target.id, '/thumbs/update.jpg');
    await repository.updateYouTubeId(
      filePath: '/music/update.mp3',
      youtubeId: 'dQw4w9WgXcQ',
    );

    final updated = (await repository.search('update.mp3')).single;
    expect(updated.localThumbnailPath, '/thumbs/update.jpg');
    expect(updated.youtubeId, 'dQw4w9WgXcQ');
  });

  test('ensures cached songs are persisted when missing', () async {
    await repository.ensureSongsInDatabase([
      _song(url: '/music/existing.mp3'),
      _song(url: '/music/newly_seen.mp3'),
    ]);

    final all = await repository.getAllSongs();
    final urls = all.map((s) => s.url).toSet();
    expect(urls, contains('/music/existing.mp3'));
    expect(urls, contains('/music/newly_seen.mp3'));
  });

  test('deletes songs and their playlist memberships', () async {
    await repository.saveSong(_song(url: '/music/del_one.mp3'));
    await repository.saveSong(_song(url: '/music/del_two.mp3'));
    await repository.saveSong(_song(url: '/music/del_three.mp3'));

    final all = await repository.getAllSongs();
    final deletable = all
        .where((s) => s.url.startsWith('/music/del_'))
        .toList();
    expect(deletable, hasLength(3));
    expect(await repository.search('del_one.mp3'), hasLength(1));

    await repository.deleteSongsByIds(deletable.map((s) => s.id).toList());

    expect(await repository.search('del_one.mp3'), isEmpty);
    expect(await repository.search('del_two.mp3'), isEmpty);
    expect(await repository.search('del_three.mp3'), isEmpty);
    expect(await repository.search('hello.mp3'), hasLength(1));
  });

  test('finds a song by youtube id and returns null when absent', () async {
    expect(await repository.getSongByYouTubeId('missingVideoId'), isNull);

    final song = await repository.addSongFromYouTube(
      videoId: 'dQw4wY9WgXcQ',
      filePath: '/music/downloaded.mp3',
      title: 'Downloaded Song',
      artists: ['Download Artist'],
      duration: 210000,
    );
    expect(song.isDownloaded, isTrue);
    expect(song.youtubeId, 'dQw4wY9WgXcQ');

    final found = await repository.getSongByYouTubeId('dQw4wY9WgXcQ');
    expect(found, isNotNull);
    expect(found!.url, '/music/downloaded.mp3');
    expect(found.artists, contains('Download Artist'));
  });

  test('reuses the existing row when adding the same download twice', () async {
    await repository.addSongFromYouTube(
      videoId: 'dupVideoId123',
      filePath: '/music/dup.mp3',
      title: 'Dup Song',
      artists: ['Dup Artist'],
      duration: 90000,
    );
    final again = await repository.addSongFromYouTube(
      videoId: 'dupVideoId123',
      filePath: '/music/dup.mp3',
      title: 'Dup Song',
      artists: ['Dup Artist'],
      duration: 90000,
    );

    final all = await repository.getAllSongs();
    expect(all.where((s) => s.url == '/music/dup.mp3'), hasLength(1));
    expect(again.url, '/music/dup.mp3');
  });

  test('records plays and surfaces recently/most played songs', () async {
    Future<Song> saveAndFind(String url) async {
      await repository.saveSong(_song(url: url));
      return (await repository.search(url.split('/').last)).single;
    }

    final a = await saveAndFind('/music/stats_a.mp3');
    final b = await saveAndFind('/music/stats_b.mp3');
    final c = await saveAndFind('/music/stats_c.mp3');

    await repository.recordPlay(a.id);
    await repository.recordPlay(b.id);
    await repository.recordPlay(b.id);
    await repository.recordPlay(c.id);
    await repository.recordPlay(c.id);
    await repository.recordPlay(c.id);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repository.recordPlay(a.id);

    final recent = await repository.getRecentlyPlayed(limit: 10);
    final recentStats = recent
        .where((s) => s.url.startsWith('/music/stats_'))
        .toList();
    expect(recentStats.map((s) => s.url).toSet(), {
      '/music/stats_a.mp3',
      '/music/stats_b.mp3',
      '/music/stats_c.mp3',
    });
    expect(recentStats.first.url, '/music/stats_a.mp3');

    final most = await repository.getMostPlayed(limit: 10);
    final mostStats = most
        .where((s) => s.url.startsWith('/music/stats_'))
        .toList();
    expect(mostStats.first.url, '/music/stats_c.mp3');
    expect(mostStats, hasLength(3));
  });

  test(
    'downloading a placeholder track upgrades that row in place so playlists switch to local',
    () async {
      const videoId = 'reconcileVideo1';
      final placeholdersRepo = repository;

      // Add-to-playlist flow: creates the `yt:<id>` placeholder row that the
      // playlist (and queue) reference.
      final placeholderId = await placeholdersRepo.addYouTubeSong(
        youtubeId: videoId,
        title: 'Remote Song',
        artists: ['Remote Artist'],
        duration: 200000,
      );
      final playlistId = await PlaylistRepository().createPlaylist('Reconcile');
      await placeholdersRepo.addToPlaylist(playlistId, [placeholderId]);

      // Download flow: must reconcile the placeholder into a real file instead
      // of inserting a second row.
      final song = await placeholdersRepo.addSongFromYouTube(
        videoId: videoId,
        filePath: '/music/reconciled.mp3',
        title: 'Remote Song',
        artists: ['Remote Artist'],
        duration: 200000,
        thumbnailPath: '/thumbs/reconciled.jpg',
      );

      expect(song.id, placeholderId, reason: 'row id must not change');
      expect(song.url, '/music/reconciled.mp3');
      expect(song.isDownloaded, isTrue);
      expect(song.hasTag('tsmusic'), isTrue);
      expect(song.localThumbnailPath, '/thumbs/reconciled.jpg');

      final viaYtId = await placeholdersRepo.getSongByYouTubeId(videoId);
      expect(viaYtId?.id, placeholderId);
      expect(viaYtId?.url, '/music/reconciled.mp3');

      // No leftover duplicate row for this video.
      final all = await placeholdersRepo.getAllSongs();
      expect(
        all.where((s) => s.youtubeId == videoId),
        hasLength(1),
        reason: 'placeholder + download must collapse to a single row',
      );

      // The playlist that referenced the placeholder now sees the local file.
      final playlistSongs = await placeholdersRepo.getPlaylistSongs(playlistId);
      expect(playlistSongs, hasLength(1));
      expect(playlistSongs.single.id, placeholderId);
      expect(playlistSongs.single.url, '/music/reconciled.mp3');

      // The real file + tag makes it count as downloaded everywhere.
      expect(
        await placeholdersRepo.getDownloadedYouTubeIds(),
        contains(videoId),
      );
    },
  );

  test(
    're-downloading to a new path reuses the existing downloaded row',
    () async {
      const videoId = 'redownloadVideo1';
      final r = repository;
      final first = await r.addSongFromYouTube(
        videoId: videoId,
        filePath: '/music/original.mp3',
        title: 'Re Download',
        artists: ['Re Artist'],
        duration: 150000,
      );
      final second = await r.addSongFromYouTube(
        videoId: videoId,
        filePath: '/music/relocated.mp3',
        title: 'Re Download',
        artists: ['Re Artist'],
        duration: 150000,
      );
      expect(second.id, first.id);
      final all = await r.getAllSongs();
      expect(all.where((s) => s.youtubeId == videoId), hasLength(1));
    },
  );

  test(
    'legacy repair merges a placeholder with its old duplicate download',
    () async {
      const videoId = 'legacyVideo1';
      final r = repository;

      // State written by app versions before reconciliation existed: a `yt:`
      // placeholder that the playlist references ...
      final placeholderId = await r.addYouTubeSong(
        youtubeId: videoId,
        title: 'Legacy Song',
        artists: ['Legacy Artist'],
        duration: 170000,
      );
      final playlistId = await PlaylistRepository().createPlaylist(
        'Legacy Fix',
      );
      await r.addToPlaylist(playlistId, [placeholderId]);

      // ... plus a separate real-file row from the old download.
      await r.saveSong(
        Song(
          id: -1,
          youtubeId: videoId,
          title: 'Legacy Song',
          artists: ['Legacy Artist'],
          url: '/music/legacy.mp3',
          duration: 170000,
          tags: ['tsmusic'],
        ),
      );
      // Both rows exist in the raw table (getAllSongs filters out `yt:` rows).
      Future<int> rawRowsForVideo() async {
        final db = await DatabaseHelper().database;
        final rows = await db.query(
          DatabaseHelper.tableSongs,
          where: 'youtube_id = ?',
          whereArgs: [videoId],
        );
        return rows.length;
      }

      expect(await rawRowsForVideo(), 2);

      await DatabaseHelper().repairLegacyPlaylistDownloads(
        await DatabaseHelper().database,
      );

      final rows = (await r.getAllSongs())
          .where((s) => s.youtubeId == videoId)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.id, placeholderId, reason: 'keep the referenced row');
      expect(rows.single.url, '/music/legacy.mp3');
      expect(rows.single.hasTag('tsmusic'), isTrue);

      final playlistSongs = await r.getPlaylistSongs(playlistId);
      expect(playlistSongs, hasLength(1));
      expect(playlistSongs.single.id, placeholderId);
      expect(playlistSongs.single.url, '/music/legacy.mp3');

      // Running again is a no-op (idempotent).
      await DatabaseHelper().repairLegacyPlaylistDownloads(
        await DatabaseHelper().database,
      );
      expect(
        (await r.getAllSongs()).where((s) => s.youtubeId == videoId),
        hasLength(1),
      );
    },
  );
}
