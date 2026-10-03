import 'package:sqflite/sqflite.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/song.dart';
class SongRepository {
  SongRepository({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper();
  final DatabaseHelper _database;
  Future<Database> get _db => _database.database;
  Future<int> countSongs() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseHelper.tableSongs}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
  Future<bool> existsById(int id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseHelper.tableSongs,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
  static const String _notYouTubeOnly = "s.file_path NOT LIKE 'yt:%'";

  /// Tracks saved from YouTube: they carry a youtube_id and the 'tsmusic' tag.
  /// A file_path of 'yt:<id>' means the track is only a placeholder for an
  /// online stream, not something on the device.
  static const String _downloadedOnly = '''
    s.youtube_id IS NOT NULL
    AND s.youtube_id != ''
    AND s.file_path NOT LIKE 'yt:%'
    AND EXISTS (
      SELECT 1 FROM ${DatabaseHelper.tableSongTags} st
      INNER JOIN ${DatabaseHelper.tableTags} t ON t.id = st.tag_id
      WHERE st.song_id = s.id AND t.name = 'tsmusic'
    )
  ''';
  Future<List<Song>> getAllSongs() async {
    final db = await _db;
    final rows = await db.rawQuery(
      _songSelectQuery(where: _notYouTubeOnly),
    );
    return _mapJoinedRows(rows);
  }
  Future<List<Song>> search(String query) async {
    final rows = await _database.searchSongs(query);
    final songs = <Song>[];
    for (final row in rows) {
      try {
        songs.add(await _songFromRow(row));
      } catch (e) {
      }
    }
    return songs;
  }
  Future<List<Song>> getPlaylistSongs(int playlistId) async {
    final rows = await _database.getSongsInPlaylist(playlistId);
    final songs = <Song>[];
    for (final row in rows) {
      try {
        songs.add(await _songFromRow(row));
      } catch (e) {
      }
    }
    return songs;
  }
  Future<void> recordPlay(int songId) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE ${DatabaseHelper.tableSongs} '
      'SET play_count = play_count + 1, last_played_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, songId],
    );
  }
  Future<List<Song>> getRecentlyPlayed({int limit = 20}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '${_songSelectQuery(orderBy: 's.last_played_at IS NULL, s.last_played_at DESC')} '
      'LIMIT ?',
      [limit],
    );
    return _mapJoinedRows(rows);
  }
  Future<List<Song>> getMostPlayed({int limit = 20}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '${_songSelectQuery(orderBy: 's.play_count DESC, s.last_played_at DESC')} '
      'LIMIT ?',
      [limit],
    );
    return _mapJoinedRows(rows);
  }
  Future<void> saveSong(Song song) async {
    final db = await _db;
    await db.transaction((txn) async {
      final songId = await txn.insert(
        DatabaseHelper.tableSongs,
        song.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _insertArtistsAndTags(txn, song, songId,
          filterUnknownArtist: false);
    });
  }
  Future<void> saveSongs(List<Song> songs) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final song in songs) {
        try {
          final songId = await txn.insert(
            DatabaseHelper.tableSongs,
            song.toDbMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _insertArtistsAndTags(txn, song, songId,
              filterUnknownArtist: true);
        } catch (e) {
        }
      }
    });
  }
  Future<void> ensureSongsInDatabase(List<Song> songs) async {
    final db = await _db;
    final missingSongs = <Song>[];
    for (final song in songs) {
      final existing = await db.query(
        DatabaseHelper.tableSongs,
        columns: ['id'],
        where: 'file_path = ?',
        whereArgs: [song.url],
        limit: 1,
      );
      if (existing.isEmpty) {
        missingSongs.add(song);
      }
    }
    if (missingSongs.isEmpty) return;
    await db.transaction((txn) async {
      for (final song in missingSongs) {
        try {
          final songId = await txn.insert(
            DatabaseHelper.tableSongs,
            song.toDbMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _insertArtistsAndTags(txn, song, songId,
              filterUnknownArtist: true);
        } catch (e) {
        }
      }
    });
  }
  Future<void> deleteSong(int songId) => _database.deleteSong(songId);
  Future<void> deleteSongsByIds(List<int> songIds) async {
    if (songIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(songIds.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseHelper.tablePlaylistSongs,
        where: 'song_id IN ($placeholders)',
        whereArgs: songIds,
      );
      await txn.delete(
        DatabaseHelper.tableSongs,
        where: 'id IN ($placeholders)',
        whereArgs: songIds,
      );
    });
  }
  Future<void> updateThumbnailPath(int songId, String thumbnailPath) =>
      _database.updateThumbnailPath(songId, thumbnailPath);
  Future<void> updateYouTubeId({
    required String filePath,
    required String youtubeId,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseHelper.tableSongs,
      {'youtube_id': youtubeId},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }
  Future<void> updateNowPlayingPlaylist(List<int> songIds) =>
      _database.updateNowPlayingPlaylist(songIds);
  Future<int> addYouTubeSong({
    required String youtubeId,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailUrl,
  }) =>
      _database.addYouTubeSongToDatabase(
        youtubeId: youtubeId,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
      );
  /// YouTube ids already saved on the device, regardless of which list is open.
  Future<Set<String>> getDownloadedYouTubeIds() async =>
      (await _database.getDownloadedYouTubeIds()).toSet();

  /// Every track downloaded from YouTube, across all playlists and lists.
  ///
  /// The downloads page used to read the currently-loaded song list, which
  /// made downloads disappear whenever a different playlist was open.
  Future<List<Song>> getDownloadedYouTubeSongs() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      ${_songSelectQuery(
        where: '''
          ${_downloadedOnly}
        ''',
        orderBy: 's.created_at DESC',
      )}
    ''');
    return rows.map(_songFromJoinedRow).toList();
  }

  Future<Song?> getSongByYouTubeId(String youtubeId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseHelper.tableSongs,
      where: 'youtube_id = ?',
      whereArgs: [youtubeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return await _songFromRow(rows.first);
    } catch (e) {
      return null;
    }
  }
  Future<Song> addSongFromYouTube({
    required String videoId,
    required String filePath,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailPath,
  }) =>
      _database.addSongFromYouTube(
        videoId: videoId,
        filePath: filePath,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailPath: thumbnailPath,
      );
  Future<void> addToPlaylist(int playlistId, List<int> songIds) =>
      _database.addSongsToPlaylist(playlistId, songIds);
  Future<int> _getOrCreateArtist(
    DatabaseExecutor txn,
    String artistName,
  ) async {
    final trimmedName = artistName.trim();
    if (trimmedName.isEmpty) {
      return 0;
    }
    final existingArtist = await txn.query(
      DatabaseHelper.tableArtists,
      where: 'LOWER(${DatabaseHelper.columnName}) = LOWER(?)',
      whereArgs: [trimmedName],
    );
    if (existingArtist.isNotEmpty) {
      return existingArtist.first[DatabaseHelper.columnId] as int;
    }
    return await txn.insert(DatabaseHelper.tableArtists, {
      'name': trimmedName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  Future<int> _getOrCreateGenre(
    DatabaseExecutor txn,
    String genreName,
  ) async {
    final existingGenre = await txn.query(
      DatabaseHelper.tableGenres,
      where: '${DatabaseHelper.columnName} = ?',
      whereArgs: [genreName],
    );
    if (existingGenre.isNotEmpty) {
      return existingGenre.first[DatabaseHelper.columnId] as int;
    }
    return await txn.insert(DatabaseHelper.tableGenres, {
      'name': genreName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  Future<void> _insertArtistsAndTags(
    DatabaseExecutor txn,
    Song song,
    int songId, {
    required bool filterUnknownArtist,
  }) async {
    for (final artistName in song.artists) {
      if (artistName.isNotEmpty &&
          (!filterUnknownArtist || artistName != 'Unknown Artist')) {
        final artistId = await _getOrCreateArtist(txn, artistName);
        await txn.insert(DatabaseHelper.tableSongArtist, {
          'song_id': songId,
          'artist_id': artistId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    for (final tag in song.tags) {
      if (tag.isNotEmpty) {
        final genreId = await _getOrCreateGenre(txn, tag);
        await txn.insert(DatabaseHelper.tableSongGenre, {
          'song_id': songId,
          'genre_id': genreId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }
  List<Song> _mapJoinedRows(List<Map<String, dynamic>> rows) {
    final songs = <Song>[];
    for (final row in rows) {
      try {
        songs.add(_songFromJoinedRow(row));
      } catch (e) {
      }
    }
    return songs;
  }
  String _songSelectQuery({String? orderBy, String? where}) => '''
        SELECT
          s.*,
          (SELECT GROUP_CONCAT(name, ',') FROM artists a
           INNER JOIN song_artist sa ON a.id = sa.artist_id
           WHERE sa.song_id = s.id) as artist_names,
          (SELECT GROUP_CONCAT(name, ',') FROM genres g
           INNER JOIN song_genre sg ON g.id = sg.genre_id
           WHERE sg.song_id = s.id) as genre_names,
          (SELECT GROUP_CONCAT(name, ',') FROM ${DatabaseHelper.tableTags} t
           INNER JOIN ${DatabaseHelper.tableSongTags} st ON t.id = st.tag_id
           WHERE st.song_id = s.id) as tag_names
        FROM ${DatabaseHelper.tableSongs} s
        ${where != null ? 'WHERE $where' : ''}
        ${orderBy != null ? 'ORDER BY $orderBy' : ''}
      ''';
  List<String> _splitNames(Object? joined) {
    if (joined is! String || joined.isEmpty) return const [];
    return joined
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Song _songFromJoinedRow(Map<String, dynamic> row) {
    final artistNamesString = row['artist_names'] as String?;
    final artistNames = artistNamesString != null && artistNamesString.isNotEmpty
        ? artistNamesString
              .split(',')
              .where((name) => name.isNotEmpty && name != 'Unknown Artist')
              .toSet()
              .toList()
        : <String>[];
    final artists = artistNames.isNotEmpty ? artistNames : ['Unknown Artist'];
    // Read tags from both tables. They are not interchangeable: a download
    // records 'tsmusic' in song_tags, while saveSong files a song's tags under
    // genres. Reading only one of the two hides half of what is on disk --
    // reading only genres meant real downloads never reported as downloaded.
    final tags = <String>{
      ..._splitNames(row['tag_names']),
      ..._splitNames(row['genre_names']),
    }.toList();
    return Song(
      id: row['id'] as int,
      youtubeId: row['youtube_id'] as String?,
      title: row['title'] as String? ?? 'Unknown Title',
      artists: artists,
      url: row['file_path'] as String,
      duration: row['duration'] as int? ?? 0,
      tags: tags,
      trackNumber: row['track_number'] as int?,
      isDownloaded: tags.contains('tsmusic'),
      dateAdded: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      localThumbnailPath: row['thumbnail_path'] as String?,
    );
  }
  Future<Song> _songFromRow(Map<String, dynamic> row) async {
    final songId = row['id'] as int;
    final artistsData = await _database.getArtistsForSong(songId);
    final artists = artistsData.map((row) => row['name'] as String).toList();
    // Both tables, for the same reason as _songFromJoinedRow: downloads record
    // their tag in song_tags, saveSong records tags under genres.
    final tagRows = await _database.getTagsForSong(songId);
    final genreRows = await _database.getGenresForSong(songId);
    final tags = <String>{
      ...tagRows.map((row) => row['name'] as String),
      ...genreRows.map((row) => row['name'] as String),
    }.where((name) => name.isNotEmpty).toList();
    return Song(
      id: songId,
      youtubeId: row['youtube_id'] as String?,
      title: row['title'] as String? ?? 'Unknown Title',
      url: row['file_path'] as String,
      duration: row['duration'] as int? ?? 0,
      artists: artists.isNotEmpty ? artists : ['Unknown Artist'],
      tags: tags,
      isDownloaded: tags.contains('tsmusic'),
      dateAdded: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      localThumbnailPath: row['thumbnail_path'] as String?,
    );
  }
}
