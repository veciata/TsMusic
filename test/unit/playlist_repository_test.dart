import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tsmusic/data/repositories/playlist_repository.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/models/song.dart';

Song _song(String url) => Song(
  id: url.hashCode,
  title: 'Title of $url',
  artists: ['Test Artist'],
  url: url,
  duration: 180000,
);

void main() {
  late PlaylistRepository repository;
  late SongRepository songs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(
      Directory.systemTemp.createTempSync('tsmusic_playlist_repo').path,
    );
  });

  setUp(() {
    repository = PlaylistRepository();
    songs = SongRepository();
  });

  test('creates a playlist and lists it', () async {
    final id = await repository.createPlaylist('Road Trip');

    final playlists = await repository.getAllPlaylists();
    final created = playlists.where((p) => p.id == id).toList();
    expect(created, hasLength(1));
    expect(created.first.name, 'Road Trip');

    final fetched = await repository.getPlaylist(id);
    expect(fetched?.name, 'Road Trip');
  });

  test('always exposes the Now Playing playlist', () async {
    final nowPlaying = await repository.getPlaylist(
      PlaylistRepository.nowPlayingPlaylistId,
    );
    expect(nowPlaying?.name, 'Now Playing');
  });

  test('maps playlist rows to typed Playlist fields', () async {
    final id = await repository.createPlaylist('Typed Fields');

    final playlists = await repository.getAllPlaylists();
    final created = playlists.firstWhere((p) => p.id == id);
    expect(created.name, 'Typed Fields');
    expect(created.description, isNull);

    final nowPlaying = playlists.firstWhere(
      (p) => p.id == PlaylistRepository.nowPlayingPlaylistId,
    );
    expect(nowPlaying.name, 'Now Playing');
  });

  test('adds and removes songs from a playlist', () async {
    await songs.saveSongs([
      _song('/music/a.mp3'),
      _song('/music/b.mp3'),
      _song('/music/c.mp3'),
    ]);
    final all = await songs.getAllSongs();
    final ids = all.map((s) => s.id).toList();

    final playlistId = await repository.createPlaylist('Favorites');
    final added = await repository.addSongsToPlaylist(
      playlistId,
      ids,
    );
    expect(added, ids.length);

    var tracks = await songs.getPlaylistSongs(playlistId);
    expect(tracks.map((s) => s.url), containsAll(['/music/a.mp3', '/music/b.mp3']));

    final removed = await repository.removeSongsFromPlaylist(
      playlistId,
      [ids.first],
    );
    expect(removed, 1);

    tracks = await songs.getPlaylistSongs(playlistId);
    expect(tracks, hasLength(2));
  });

  test('persists now-playing playlist order and reads it back', () async {
    await songs.saveSongs([
      _song('/music/order_a.mp3'),
      _song('/music/order_b.mp3'),
      _song('/music/order_c.mp3'),
    ]);
    final all = await songs.getAllSongs();
    final orderSongs = all.where((s) => s.url.startsWith('/music/order_')).toList()
      ..sort((a, b) => a.url.compareTo(b.url));
    final ids = orderSongs.map((s) => s.id).toList();
    expect(ids, hasLength(3));

    await repository.reorderNowPlayingPlaylist([...ids.reversed]);

    var playlist = await songs.getPlaylistSongs(
      PlaylistRepository.nowPlayingPlaylistId,
    );
    expect(playlist.map((s) => s.url), [
      '/music/order_c.mp3',
      '/music/order_b.mp3',
      '/music/order_a.mp3',
    ]);

    await repository.updateNowPlayingPlaylist(ids);

    playlist = await songs.getPlaylistSongs(
      PlaylistRepository.nowPlayingPlaylistId,
    );
    expect(playlist.map((s) => s.url), [
      '/music/order_a.mp3',
      '/music/order_b.mp3',
      '/music/order_c.mp3',
    ]);
  });

  test('cannot delete the Now Playing playlist', () async {
    await expectLater(
      repository.deletePlaylist(PlaylistRepository.nowPlayingPlaylistId),
      throwsA(isA<Exception>()),
    );
  });
}