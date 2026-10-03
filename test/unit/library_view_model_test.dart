import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/providers/library_view_model.dart';

Song _song({
  required int id,
  required String url,
  required String title,
  List<String>? artists,
  String? album,
  int duration = 180000,
}) =>
    Song(
      id: id,
      title: title,
      artists: artists ?? ['Test Artist'],
      album: album,
      url: url,
      duration: duration,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(
      Directory.systemTemp.createTempSync('tsmusic_library_vm').path,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  LibraryViewModel buildVm() => LibraryViewModel();

  test('addSongToLibrary adds to library and displayed songs, dedups by URL',
      () {
    final song = _song(id: 1, url: '/music/a.mp3', title: 'Alpha');
    final vm = buildVm()
      ..addSongToLibrary(song)
      ..addSongToLibrary(song);

    expect(vm.librarySongs, hasLength(1));
    expect(vm.songs, hasLength(1));
    expect(vm.songs.first.title, 'Alpha');
  });

  test('removeSongFromLibrary removes from both collections', () {
    final song = _song(id: 1, url: '/music/a.mp3', title: 'Alpha');
    final vm = buildVm()
      ..addSongToLibrary(song)
      ..removeSongFromLibrary(song);

    expect(vm.librarySongs, isEmpty);
    expect(vm.songs, isEmpty);
  });

  test('updateSongInPlace replaces copies and fires onSongUpdated', () {
    final vm = buildVm();
    final song = _song(id: 1, url: '/music/a.mp3', title: 'Alpha');
    vm.addSongToLibrary(song);

    Song? updated;
    vm.onSongUpdated = (song) => updated = song;

    final replacement = song.copyWith(title: 'Renamed');
    vm.updateSongInPlace(replacement);

    expect(vm.librarySongs.first.title, 'Renamed');
    expect(vm.songs.first.title, 'Renamed');
    expect(updated?.title, 'Renamed');
  });

  test('setDisplayedSongs and clearDisplayedSongs control the UI list', () {
    final vm = buildVm();
    final a = _song(id: 1, url: '/music/a.mp3', title: 'Alpha');
    final b = _song(id: 2, url: '/music/b.mp3', title: 'Beta');

    vm.setDisplayedSongs([a, b]);
    expect(vm.songs, hasLength(2));

    vm.clearDisplayedSongs();
    expect(vm.songs, isEmpty);
  });

  test('sortLibrary sorts by title ascending and descending', () {
    final vm = buildVm()
      ..addSongToLibrary(_song(id: 1, url: '/c', title: 'Charlie'))
      ..addSongToLibrary(_song(id: 2, url: '/a', title: 'Alpha'))
      ..addSongToLibrary(_song(id: 3, url: '/b', title: 'Beta'));

    final ascending = vm.sortLibrary(sortBy: SongSortOption.title);
    expect(
      ascending.map((s) => s.title).toList(),
      ['Alpha', 'Beta', 'Charlie'],
    );
    expect(vm.currentSortOption, SongSortOption.title);
    expect(vm.sortAscending, isTrue);

    final descending = vm.sortLibrary(
      sortBy: SongSortOption.title,
      ascending: false,
    );
    expect(
      descending.map((s) => s.title).toList(),
      ['Charlie', 'Beta', 'Alpha'],
    );
    expect(vm.sortAscending, isFalse);
  });

  test('sortLibrary sorts by artist using first artist', () {
    final vm = buildVm()
      ..addSongToLibrary(
        _song(id: 1, url: '/a', title: 'One', artists: ['Zed']),
      )
      ..addSongToLibrary(
        _song(id: 2, url: '/b', title: 'Two', artists: ['Anna']),
      );

    final sorted = vm.sortLibrary(sortBy: SongSortOption.artist);
    expect(sorted.first.artists.first, 'Anna');
  });

  test('filterSongs with empty query resets to the full library', () async {
    final vm = buildVm()
      ..addSongToLibrary(_song(id: 1, url: '/a.mp3', title: 'Alpha'))
      ..addSongToLibrary(_song(id: 2, url: '/b.mp3', title: 'Beta'))
      ..sortLibrary(sortBy: SongSortOption.title, ascending: false)
      ..setDisplayedSongs([]);
    expect(vm.songs, isEmpty);

    await vm.filterSongs('');
    expect(vm.songs, hasLength(2));
  });

  test('filterSongs filters in-memory when the database has no matches',
      () async {
    final vm = buildVm()
      ..addSongToLibrary(_song(id: 1, url: '/a.mp3', title: 'Alpha Song'))
      ..addSongToLibrary(_song(id: 2, url: '/b.mp3', title: 'Beta Song'));

    await vm.filterSongs('alpha');

    expect(vm.songs, hasLength(1));
    expect(vm.songs.first.title, 'Alpha Song');
  });

  test('clearLibraryCache clears collections and fires callback', () async {
    final vm =
        buildVm()..addSongToLibrary(_song(id: 1, url: '/a.mp3', title: 'Alpha'));

    bool cacheCleared = false;
    vm.onLibraryCacheCleared = () => cacheCleared = true;

    await vm.saveSongsToCache();
    expect(
      (await SharedPreferences.getInstance()).getString('cached_songs'),
      isNotNull,
    );

    await vm.clearLibraryCache();

    expect(vm.librarySongs, isEmpty);
    expect(vm.songs, isEmpty);
    expect(cacheCleared, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getString('cached_songs'),
      isNull,
    );
  });

  test('saveSongsToCache persists the library as JSON', () async {
    final vm = buildVm()..addSongToLibrary(
        _song(id: 1, url: '/a.mp3', title: 'Alpha', artists: ['Tester']),
      );

    await vm.saveSongsToCache();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_songs');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as List<dynamic>;
    expect(decoded, hasLength(1));
    expect(decoded.first['title'], 'Alpha');
  });

  test('collection getters aggregate library songs', () {
    final vm = buildVm()
      ..addSongToLibrary(
        _song(
          id: 1,
          url: '/a.mp3',
          title: 'One',
          artists: ['Alpha'],
          album: 'Album X',
        ),
      )
      ..addSongToLibrary(
        _song(
          id: 2,
          url: '/b.mp3',
          title: 'Two',
          artists: ['Alpha'],
          album: 'Album Y',
        ),
      )
      ..addSongToLibrary(
        _song(
          id: 3,
          url: '/c.mp3',
          title: 'Three',
          artists: ['Beta'],
          album: 'Album X',
        ),
      );

    expect(vm.getSongsByArtist('Alpha'), hasLength(2));
    expect(vm.getSongsByAlbum('Album X'), hasLength(2));
    expect(vm.getSongsByAlbum('Album X', artistName: 'Alpha'), hasLength(1));
    expect(vm.getAlbumsByArtist('Alpha'), ['Album X', 'Album Y']);
    expect(vm.getArtistImageUrl('Alpha'), isNull);
    expect(vm.artists, containsAll(['Alpha', 'Beta']));
  });
}