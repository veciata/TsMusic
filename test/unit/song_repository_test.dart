import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/models/song.dart';

Song _song({
  required String url,
  List<String>? artists,
  List<String>? tags,
}) =>
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
    final deletable = all.where((s) => s.url.startsWith('/music/del_')).toList();
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
    final recentStats = recent.where((s) => s.url.startsWith('/music/stats_')).toList();
    expect(recentStats.map((s) => s.url).toSet(), {
      '/music/stats_a.mp3',
      '/music/stats_b.mp3',
      '/music/stats_c.mp3',
    });
    expect(recentStats.first.url, '/music/stats_a.mp3');

    final most = await repository.getMostPlayed(limit: 10);
    final mostStats = most.where((s) => s.url.startsWith('/music/stats_')).toList();
    expect(mostStats.first.url, '/music/stats_c.mp3');
    expect(mostStats, hasLength(3));
  });
}