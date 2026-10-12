import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:tsmusic/models/song.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  final Map<String, Song> _songsMap = {};
  final List<Song> _localSongs = [];
  final List<Song> _displayedSongs = [];
  static const String tableArtists = 'artists';
  static const String tableGenres = 'genres';
  static const String tableSongs = 'songs';
  static const String tableAlbums = 'albums';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistSongs = 'playlist_songs';
  static const String tableTags = 'tags';
  static const String tableSongTags = 'song_tags';
  static const String tableArtistGenre = 'artist_genre';
  static const String tableSongArtist = 'song_artist';
  static const String tableSongGenre = 'song_genre';
  static const String columnId = 'id';
  static const String columnName = 'name';
  static const String columnCreatedAt = 'created_at';
  static const String columnYouTubeId = 'youtube_id';
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<List<Map<String, dynamic>>> getUniqueSongsWithArtist() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.$columnId as song_id,
            s.title,
            s.file_path,
            s.duration,
            s.thumbnail_path,
            COALESCE(a.$columnName, '') as artist
      FROM $tableSongs s
      LEFT JOIN (
        SELECT sa.song_id, MIN(sa.artist_id) as artist_id
        FROM $tableSongArtist sa
        GROUP BY sa.song_id
      ) x ON x.song_id = s.$columnId
      LEFT JOIN $tableArtists a ON a.$columnId = x.artist_id
      GROUP BY s.file_path
      ORDER BY s.title COLLATE NOCASE ASC
    ''');
  }

  DatabaseHelper._internal() {
    _initDatabase().then(_verifyDatabaseSchema);
  }
  factory DatabaseHelper() => _instance;
  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableSongs,
      orderBy: 'date_added DESC',
    );
    final songs = <Song>[];
    for (final map in maps) {
      final songId = map['id'] as int;
      final artistsData = await getArtistsForSong(songId);
      final artists = artistsData.map((row) => row['name'] as String).toList();
      final tagsData = await getTagsForSong(songId);
      final tags = tagsData.map((row) => row['name'] as String).toList();
      songs.add(
        Song(
          id: songId,
          title: map['title'] as String,
          url: map['file_path'] as String,
          duration: map['duration'] as int,
          artists: artists,
          tags: tags,
          dateAdded: DateTime.parse(map['created_at'] as String),
          localThumbnailPath: map['thumbnail_path'] as String?,
        ),
      );
    }
    return songs;
  }

  Future<bool> isDatabaseEmpty() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableSongs'),
    );
    return count == 0 || count == null;
  }

  Future<void> clearSongs() async {
    final db = await database;
    await db.delete(tableSongs);
    _localSongs.clear();
    _displayedSongs.clear();
    _songsMap.clear();
  }

  Future<void> _verifyDatabaseSchema(Database db) async {
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final existingTables = tables.map((t) => t['name'] as String).toSet();
      final requiredTables = [
        tableArtists,
        tableGenres,
        tableSongs,
        tableAlbums,
        tablePlaylists,
        tablePlaylistSongs,
        tableTags,
        tableSongTags,
        tableArtistGenre,
        tableSongArtist,
        tableSongGenre,
      ];
      final missingTables = requiredTables
          .where((t) => !existingTables.contains(t))
          .toList();
      if (missingTables.isNotEmpty) {
        await db.close();
        final path = join(await getDatabasesPath(), 'music_player.db');
        await deleteDatabase(path);
        _database = null;
        _database = await _initDatabase();
        return;
      }
      final version = await db.getVersion();
      if (version < databaseVersion) {
        await _onUpgrade(db, version, databaseVersion);
        await db.setVersion(databaseVersion);
      }
    } catch (e) {
      try {
        await db.close();
        final path = join(await getDatabasesPath(), 'music_player.db');
        await deleteDatabase(path);
        _database = null;
        _database = await _initDatabase();
      } catch (recoveryError) {
        rethrow;
      }
    }
  }

  Future<bool> verifyAndRepairTables() async {
    try {
      final db = await database;
      await _verifyDatabaseSchema(db);
      return true;
    } catch (e) {
      return false;
    }
  }

  static const int databaseVersion = 7;
  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'music_player.db');
    final db = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await repairLegacyPlaylistDownloads(db);
    return db;
  }

  /// Repair for installs that downloaded playlist tracks before placeholder
  /// reconciliation existed (older app versions).
  ///
  /// Those installs ended up with two rows per video: a `yt:<id>` placeholder
  /// that playlists and the queue still reference, and a separate real-file
  /// row carrying the download. This upgrades the placeholder in place (same
  /// row id, so every reference follows automatically), re-points any
  /// playlist link that pointed at the duplicate, and drops the duplicate.
  ///
  /// Idempotent: rows that are no longer placeholders are left untouched, so
  /// it is safe to run on every database open and to call from tests.
  Future<void> repairLegacyPlaylistDownloads(Database db) async {
    try {
      final placeholders = await db.query(
        tableSongs,
        where: "file_path LIKE 'yt:%' AND youtube_id IS NOT NULL",
      );
      for (final placeholder in placeholders) {
        final videoId = placeholder['youtube_id'] as String;
        final placeholderId = placeholder['id'] as int;
        final duplicates = await db.query(
          tableSongs,
          where: 'youtube_id = ? AND file_path NOT LIKE ? AND $columnId != ?',
          whereArgs: [videoId, 'yt:%', placeholderId],
        );
        if (duplicates.isEmpty) continue;
        final duplicate = duplicates.first;
        final duplicateId = duplicate['id'] as int;
        final duplicateArtists = await db.query(
          tableSongArtist,
          where: 'song_id = ?',
          whereArgs: [duplicateId],
        );
        // 1) Re-point playlist references that pointed at the duplicate, then
        //    delete the duplicate's own rows. `file_path` is UNIQUE, so the
        //    duplicate has to release the real path before the placeholder can
        //    take it (otherwise the UPDATE below fails the constraint).
        await db.rawDelete(
          '''
          UPDATE $tablePlaylistSongs
          SET song_id = ?
          WHERE song_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM $tablePlaylistSongs p2
              WHERE p2.playlist_id = $tablePlaylistSongs.playlist_id
                AND p2.song_id = ?
            )
          ''',
          [placeholderId, duplicateId, placeholderId],
        );
        await db.delete(
          tablePlaylistSongs,
          where: 'song_id = ?',
          whereArgs: [duplicateId],
        );
        await db.delete(
          tableSongArtist,
          where: 'song_id = ?',
          whereArgs: [duplicateId],
        );
        await db.delete(
          tableSongTags,
          where: 'song_id = ?',
          whereArgs: [duplicateId],
        );
        await db.delete(
          tableSongs,
          where: '$columnId = ?',
          whereArgs: [duplicateId],
        );
        // 2) Point the placeholder at the real file (path is now free). Same
        //    row id, so everything that referenced it follows automatically.
        await db.update(
          tableSongs,
          {
            'title': duplicate['title'],
            'file_path': duplicate['file_path'],
            'duration': duplicate['duration'],
            'thumbnail_path': duplicate['thumbnail_path'],
            'play_count': duplicate['play_count'] ?? 0,
            'last_played_at': duplicate['last_played_at'],
          },
          where: '$columnId = ?',
          whereArgs: [placeholderId],
        );
        // 3) Copy the artists onto the placeholder.
        await db.delete(
          tableSongArtist,
          where: 'song_id = ?',
          whereArgs: [placeholderId],
        );
        for (final row in duplicateArtists) {
          await db.insert(tableSongArtist, {
            'song_id': placeholderId,
            'artist_id': row['artist_id'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        // 4) Make sure the placeholder carries the download tag.
        final tagId = await _getOrCreateTag(db, 'tsmusic');
        await db.insert(tableSongTags, {
          'song_id': placeholderId,
          'tag_id': tagId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (e) {
      // Non-fatal: the app works without the repair; it just retries next run.
      debugPrint('repairLegacyPlaylistDownloads failed: $e');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tablePlaylists (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          description TEXT,
          cover_art_url TEXT,
          $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tablePlaylistSongs (
          playlist_id INTEGER NOT NULL,
          song_id INTEGER NOT NULL,
          position INTEGER NOT NULL,
          $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (playlist_id, song_id),
          FOREIGN KEY (playlist_id) REFERENCES $tablePlaylists($columnId) ON DELETE CASCADE,
          FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE
        )
      ''');
      await db.insert(tablePlaylists, {
        columnId: nowPlayingPlaylistId,
        'name': 'Now Playing',
        'description':
            'Currently playing queue. This playlist is managed automatically.',
        'cover_art_url': null,
        columnCreatedAt: DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableTags (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnName TEXT NOT NULL UNIQUE,
          $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSongTags (
          song_id INTEGER NOT NULL,
          tag_id INTEGER NOT NULL,
          $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (song_id, tag_id),
          FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE,
          FOREIGN KEY (tag_id) REFERENCES $tableTags($columnId) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE $tableSongs ADD COLUMN youtube_id TEXT');
      } catch (e) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE $tableSongs ADD COLUMN thumbnail_path TEXT',
        );
      } catch (e) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE $tableSongs ADD COLUMN play_count INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE $tableSongs ADD COLUMN last_played_at INTEGER',
        );
      } catch (e) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableArtists (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylists (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        cover_art_url TEXT,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.insert(tablePlaylists, {
      columnId: nowPlayingPlaylistId,
      'name': 'Now Playing',
      'description':
          'Currently playing queue. This playlist is managed automatically.',
      'cover_art_url': null,
      columnCreatedAt: DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableGenres (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableAlbums (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        artist_id INTEGER NOT NULL,
        year INTEGER,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(name, artist_id),
        FOREIGN KEY (artist_id) REFERENCES $tableArtists($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSongs (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        youtube_id TEXT,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        duration INTEGER,
        track_number INTEGER,
        thumbnail_path TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableArtistGenre (
        artist_id INTEGER NOT NULL,
        genre_id INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (artist_id, genre_id),
        FOREIGN KEY (artist_id) REFERENCES $tableArtists($columnId) ON DELETE CASCADE,
        FOREIGN KEY (genre_id) REFERENCES $tableGenres($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSongArtist (
        song_id INTEGER NOT NULL,
        artist_id INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (song_id, artist_id),
        FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE,
        FOREIGN KEY (artist_id) REFERENCES $tableArtists($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSongGenre (
        song_id INTEGER NOT NULL,
        genre_id INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (song_id, genre_id),
        FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE,
        FOREIGN KEY (genre_id) REFERENCES $tableGenres($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylistSongs (
        playlist_id INTEGER NOT NULL,
        song_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (playlist_id, song_id),
        FOREIGN KEY (playlist_id) REFERENCES $tablePlaylists($columnId) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableTags (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSongTags (
        song_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (song_id, tag_id),
        FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES $tableTags($columnId) ON DELETE CASCADE
      )
    ''');
  }

  Future<int> insertArtist(Map<String, dynamic> artist) async {
    final db = await database;
    return await db.insert(
      tableArtists,
      artist,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertGenre(Map<String, dynamic> genre) async {
    final db = await database;
    return await db.insert(
      tableGenres,
      genre,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getGenres() async {
    final db = await database;
    return await db.query(tableGenres, orderBy: columnName);
  }

  Future<int> findSongIdByPath(String filePath) async {
    final db = await database;
    final result = await db.query(
      tableSongs,
      columns: ['id'],
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    return result.isNotEmpty ? result.first['id'] as int : -1;
  }

  Future<int> insertSong(Map<String, dynamic> song) async {
    final db = await database;
    final existingId = await findSongIdByPath(song['file_path']);
    if (existingId != -1) {
      return -1;
    }
    final songWithTimestamps = Map<String, dynamic>.from(song)
      ..['created_at'] = DateTime.now().toIso8601String()
      ..['updated_at'] = DateTime.now().toIso8601String();
    return await db.insert(
      tableSongs,
      songWithTimestamps,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSongs() async {
    final db = await database;
    return await db.query(tableSongs, orderBy: 'title', distinct: true);
  }

  Future<List<Map<String, dynamic>>> getSongsWithArtist() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.$columnId as song_id,
             s.youtube_id as youtube_id,
             s.title as title,
             s.file_path as file_path,
             s.duration as duration,
             s.thumbnail_path as thumbnail_path,
             COALESCE(a.$columnName, '') as artist
      FROM $tableSongs s
      LEFT JOIN (
        SELECT sa.song_id, MIN(sa.artist_id) as artist_id
        FROM $tableSongArtist sa
        GROUP BY sa.song_id
      ) x ON x.song_id = s.$columnId
      LEFT JOIN $tableArtists a ON a.$columnId = x.artist_id
      ORDER BY s.title COLLATE NOCASE ASC
    ''');
  }

  Future<int> addArtistToGenre(int artistId, int genreId) async {
    final db = await database;
    return await db.insert(tableArtistGenre, {
      'artist_id': artistId,
      'genre_id': genreId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> addArtistToSong(int songId, int artistId) async {
    final db = await database;
    return await db.insert(tableSongArtist, {
      'song_id': songId,
      'artist_id': artistId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> addGenreToSong(int songId, int genreId) async {
    final db = await database;
    return await db.insert(tableSongGenre, {
      'song_id': songId,
      'genre_id': genreId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> addTagToSong(int songId, int tagId) async {
    final db = await database;
    return await db.insert(tableSongTags, {
      'song_id': songId,
      'tag_id': tagId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getGenresForArtist(int artistId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT g.* FROM $tableGenres g
      INNER JOIN $tableArtistGenre ag ON g.id = ag.genre_id
      WHERE ag.artist_id = ?
      ORDER BY g.name
    ''',
      [artistId],
    );
  }

  Future<List<Map<String, dynamic>>> getArtistsForSong(int songId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT a.* FROM $tableArtists a
      INNER JOIN $tableSongArtist sa ON a.id = sa.artist_id
      WHERE sa.song_id = ?
      ORDER BY a.name
    ''',
      [songId],
    );
  }

  Future<List<Map<String, dynamic>>> getSongsByArtist(int artistId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT s.* FROM $tableSongs s
      INNER JOIN $tableSongArtist sa ON s.id = sa.song_id
      WHERE sa.artist_id = ?
      ORDER BY s.title
    ''',
      [artistId],
    );
  }

  Future<List<Map<String, dynamic>>> getSongsByGenre(int genreId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT s.* FROM $tableSongs s
      JOIN $tableSongGenre sg ON s.$columnId = sg.song_id
      WHERE sg.genre_id = ?
    ''',
      [genreId],
    );
  }

  Future<List<Map<String, dynamic>>> searchSongs(String query) async {
    final db = await database;
    final searchTerm = '%$query%';
    return await db.rawQuery(
      '''
      SELECT DISTINCT s.*
      FROM $tableSongs s
      LEFT JOIN $tableSongArtist sa ON sa.song_id = s.$columnId
      LEFT JOIN $tableArtists a ON a.$columnId = sa.artist_id
      WHERE s.title LIKE ?
         OR a.name LIKE ?
      ORDER BY s.title
    ''',
      [searchTerm, searchTerm],
    );
  }

  Future<List<Map<String, dynamic>>> getGenresForSong(int songId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT g.* FROM $tableGenres g
      INNER JOIN $tableSongGenre sg ON g.id = sg.genre_id
      WHERE sg.song_id = ?
      ORDER BY g.name
    ''',
      [songId],
    );
  }

  Future<List<Map<String, dynamic>>> getTagsForSong(int songId) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT t.* FROM $tableTags t
      INNER JOIN $tableSongTags st ON t.id = st.tag_id
      WHERE st.song_id = ?
      ORDER BY t.name
    ''',
      [songId],
    );
  }

  /// Every YouTube `videoId` already saved on this device, across all
  /// playlists and saved lists.
  ///
  /// Callers need this to answer "is this track already downloaded?" no matter
  /// which list happens to be open. Reading the in-memory song list instead
  /// gives a false negative whenever the download happened while a different
  /// list was loaded, which makes the track download a second time.
  Future<List<String>> getDownloadedYouTubeIds() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT s.youtube_id FROM $tableSongs s
      INNER JOIN $tableSongTags st ON st.song_id = s.id
      INNER JOIN $tableTags t ON t.id = st.tag_id
      WHERE t.name = ?
        AND s.youtube_id IS NOT NULL
        AND s.youtube_id != ''
    ''',
      ['tsmusic'],
    );
    return rows
        .map((row) => row['youtube_id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<void> updateSongMetadataByFilePath({
    required String filePath,
    String? title,
    required List<String> artists,
    String? album,
    String? genreName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        tableSongs,
        columns: [columnId],
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final songId = rows.first[columnId] as int;
      if (title != null && title.isNotEmpty) {
        await txn.update(
          tableSongs,
          {'title': title},
          where: '$columnId = ?',
          whereArgs: [songId],
        );
      }
      await txn.delete(
        tableSongArtist,
        where: 'song_id = ?',
        whereArgs: [songId],
      );
      for (final artist in artists) {
        final artistId = await _getOrCreateArtist(txn, artist);
        await txn.insert(tableSongArtist, {
          'song_id': songId,
          'artist_id': artistId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      if (album != null && album.isNotEmpty) {
        final genreId = await _getOrCreateGenre(txn, album);
        await txn.insert(tableSongGenre, {
          'song_id': songId,
          'genre_id': genreId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      if (genreName != null && genreName.isNotEmpty) {
        final gId = await _getOrCreateGenre(txn, genreName);
        await txn.insert(tableSongGenre, {
          'song_id': songId,
          'genre_id': gId,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<int> _getOrCreateArtist(
    DatabaseExecutor txn,
    String artistName,
  ) async {
    if (artistName.trim().isEmpty) {
      throw ArgumentError('Artist name cannot be empty');
    }
    final trimmedName = artistName.trim();
    final existingArtist = await txn.query(
      tableArtists,
      where: 'LOWER($columnName) = LOWER(?)',
      whereArgs: [trimmedName],
    );
    if (existingArtist.isNotEmpty) {
      return existingArtist.first[columnId] as int;
    }
    return await txn.insert(tableArtists, {
      columnName: trimmedName,
      columnCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  Future<int> _getOrCreateGenre(Transaction txn, String genreName) async {
    if (genreName.trim().isEmpty) {
      throw ArgumentError('Genre name cannot be empty');
    }
    final existingGenre = await txn.query(
      tableGenres,
      where: '$columnName = ?',
      whereArgs: [genreName],
    );
    if (existingGenre.isNotEmpty) {
      return existingGenre.first[columnId] as int;
    }
    return await txn.insert(tableGenres, {
      columnName: genreName,
      columnCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  Future<int> _getOrCreateTag(DatabaseExecutor txn, String tagName) async {
    if (tagName.trim().isEmpty) {
      throw ArgumentError('Tag name cannot be empty');
    }
    final existingTag = await txn.query(
      tableTags,
      where: '$columnName = ?',
      whereArgs: [tagName],
    );
    if (existingTag.isNotEmpty) {
      return existingTag.first[columnId] as int;
    }
    return await txn.insert(tableTags, {
      columnName: tagName,
      columnCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  static const int nowPlayingPlaylistId = 1;
  Future<void> _ensureNowPlayingPlaylist() async {
    final db = await database;
    await db.insert(tablePlaylists, {
      columnId: nowPlayingPlaylistId,
      'name': 'Now Playing',
      'description':
          'Currently playing queue. This playlist is managed automatically.',
      'cover_art_url': null,
      columnCreatedAt: DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> createPlaylist(
    String name, {
    String? description,
    String? coverArtUrl,
  }) async {
    final db = await database;
    await _ensureNowPlayingPlaylist();
    return await db.insert(tablePlaylists, {
      'name': name,
      'description': description,
      'cover_art_url': coverArtUrl,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updatePlaylist(
    int playlistId, {
    String? name,
    String? description,
    String? coverArtUrl,
  }) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (coverArtUrl != null) data['cover_art_url'] = coverArtUrl;
    if (data.isEmpty) return 0;
    return await db.update(
      tablePlaylists,
      data,
      where: '$columnId = ?',
      whereArgs: [playlistId],
    );
  }

  Future<int> deletePlaylist(int playlistId) async {
    if (playlistId == nowPlayingPlaylistId) {
      throw Exception('Cannot delete the Now Playing playlist');
    }
    final db = await database;
    return await db.delete(
      tablePlaylists,
      where: '$columnId = ?',
      whereArgs: [playlistId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    try {
      final db = await database;
      await _ensureNowPlayingPlaylist();
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final playlistsTableExists = tables.any(
        (table) => table['name'] == tablePlaylists,
      );
      if (!playlistsTableExists) {
        await _onUpgrade(db, 1, databaseVersion);
      }
      try {
        final playlists = await db.query(
          tablePlaylists,
          orderBy: 'name COLLATE NOCASE ASC',
        );
        return playlists;
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS $tablePlaylistSongs');
        await db.execute('DROP TABLE IF EXISTS $tablePlaylists');
        await _onUpgrade(db, 1, databaseVersion);
        return await db.query(
          tablePlaylists,
          orderBy: 'name COLLATE NOCASE ASC',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getPlaylist(int playlistId) async {
    final db = await database;
    if (playlistId == nowPlayingPlaylistId) {
      await _ensureNowPlayingPlaylist();
    }
    final result = await db.query(
      tablePlaylists,
      where: '$columnId = ?',
      whereArgs: [playlistId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        '''
        SELECT COALESCE(MAX(position), 0) as max_position
        FROM $tablePlaylistSongs
        WHERE playlist_id = ?
      ''',
        [playlistId],
      );
      int position = (result.first['max_position'] as int?) ?? 0;
      for (final songId in songIds) {
        try {
          await txn.insert(tablePlaylistSongs, {
            'playlist_id': playlistId,
            'song_id': songId,
            'position': ++position,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          count++;
        } catch (e) {
          continue;
        }
      }
    });
    return count;
  }

  Future<int> removeSongsFromPlaylist(int playlistId, List<int> songIds) async {
    if (songIds.isEmpty) return 0;
    final db = await database;
    return await db.delete(
      tablePlaylistSongs,
      where:
          'playlist_id = ? AND song_id IN (${List.filled(songIds.length, '?').join(',')})',
      whereArgs: [playlistId, ...songIds],
    );
  }

  Future<List<Map<String, dynamic>>> getSongsInPlaylist(int playlistId) async {
    final db = await database;
    if (playlistId == nowPlayingPlaylistId) {
      await _ensureNowPlayingPlaylist();
    }
    return await db.rawQuery(
      '''
      SELECT s.*, ps.position
      FROM $tableSongs s
      INNER JOIN $tablePlaylistSongs ps ON s.$columnId = ps.song_id
      WHERE ps.playlist_id = ?
      ORDER BY ps.position ASC
    ''',
      [playlistId],
    );
  }

  Future<void> updateNowPlayingPlaylist(List<int> songIds) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        tablePlaylistSongs,
        where: 'playlist_id = ?',
        whereArgs: [nowPlayingPlaylistId],
      );
      for (int i = 0; i < songIds.length; i++) {
        await txn.insert(tablePlaylistSongs, {
          'playlist_id': nowPlayingPlaylistId,
          'song_id': songIds[i],
          'position': i + 1,
        });
      }
    });
  }

  Future<bool> isSongInPlaylist(int playlistId, int songId) async {
    final db = await database;
    final result = await db.query(
      tablePlaylistSongs,
      columns: ['COUNT(*) as count'],
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
    return (result.first['count'] as int?) == 1;
  }

  Future<int> reorderPlaylistSongs(
    int playlistId,
    Map<int, int> newPositions,
  ) async {
    if (newPositions.isEmpty) return 0;
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      for (final entry in newPositions.entries) {
        final songId = entry.key;
        final position = entry.value;
        await txn.update(
          tablePlaylistSongs,
          {'position': position},
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [playlistId, songId],
        );
        count++;
      }
    });
    return count;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  Future<void> updateThumbnailPath(int songId, String thumbnailPath) async {
    final db = await database;
    await db.update(
      tableSongs,
      {'thumbnail_path': thumbnailPath},
      where: '$columnId = ?',
      whereArgs: [songId],
    );
  }

  Future<void> deleteSong(int songId) async {
    final db = await database;
    await db.delete(tableSongs, where: '$columnId = ?', whereArgs: [songId]);
  }

  Future<Song> addSongFromYouTube({
    required String videoId,
    required String filePath,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailPath,
  }) async {
    final db = await database;
    int? songId;
    await db.transaction((txn) async {
      // 1) Already downloaded for this video: keep that row so anything that
      // references a real file (playlists added after the first download) keeps
      // pointing at it. Re-running a download of the same video must not insert
      // a duplicate row.
      final downloadedForVideo = await txn.query(
        tableSongs,
        where: 'youtube_id = ? AND file_path NOT LIKE ?',
        whereArgs: [videoId, 'yt:%'],
      );
      if (downloadedForVideo.isNotEmpty) {
        songId = downloadedForVideo.first['id'] as int;
        return;
      }
      // 2) The song is still a YouTube placeholder (`file_path = 'yt:<id>'`)
      // that playlists and the queue point at. Upgrade that row in place so
      // every reference automatically starts resolving to the local file.
      final placeholder = await txn.query(
        tableSongs,
        where: 'youtube_id = ? AND file_path = ?',
        whereArgs: [videoId, 'yt:$videoId'],
      );
      if (placeholder.isNotEmpty) {
        final placeholderId = placeholder.first['id'] as int;
        // `file_path` is UNIQUE. If some other row already owns this path we
        // cannot move the placeholder onto it — fall through to the path-reuse
        // branch below instead of throwing.
        final pathOwner = await txn.query(
          tableSongs,
          columns: [columnId],
          where: 'file_path = ? AND $columnId != ?',
          whereArgs: [filePath, placeholderId],
        );
        if (pathOwner.isEmpty) {
          songId = placeholderId;
          await txn.update(
            tableSongs,
            {
              'title': title,
              'file_path': filePath,
              'duration': duration,
              'thumbnail_path': thumbnailPath,
            },
            where: '$columnId = ?',
            whereArgs: [songId],
          );
          await txn.delete(
            tableSongArtist,
            where: 'song_id = ?',
            whereArgs: [songId],
          );
          final artistsList = artists.isNotEmpty ? artists : ['Unknown Artist'];
          for (final artistName in artistsList) {
            final artistId = await _getOrCreateArtist(txn, artistName);
            await txn.insert(tableSongArtist, {
              'song_id': songId,
              'artist_id': artistId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          final tagId = await _getOrCreateTag(txn, 'tsmusic');
          await txn.insert(tableSongTags, {
            'song_id': songId,
            'tag_id': tagId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          return;
        }
      }
      // 3) Nothing references this video yet. Reuse a row that already points
      // at the same file path (re-download landing in the same location), else
      // insert a new row tagged as an app download.
      final existingByPath = await txn.query(
        tableSongs,
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
      if (existingByPath.isNotEmpty) {
        songId = existingByPath.first['id'] as int;
      } else {
        final songMap = {
          'title': title,
          'file_path': filePath,
          'duration': duration,
          'youtube_id': videoId,
          'thumbnail_path': thumbnailPath,
          'created_at': DateTime.now().toIso8601String(),
        };
        songId = await txn.insert(
          tableSongs,
          songMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final artistsList = artists.isNotEmpty ? artists : ['Unknown Artist'];
        for (final artistName in artistsList) {
          final artistId = await _getOrCreateArtist(txn, artistName);
          await txn.insert(tableSongArtist, {
            'song_id': songId,
            'artist_id': artistId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final tagId = await _getOrCreateTag(txn, 'tsmusic');
        await txn.insert(tableSongTags, {
          'song_id': songId,
          'tag_id': tagId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    final songData = await db.query(
      tableSongs,
      where: '$columnId = ?',
      whereArgs: [songId],
    );
    if (songData.isEmpty) {
      throw Exception('Failed to retrieve downloaded song from database.');
    }
    final artistsData = await getArtistsForSong(songId!);
    final dbArtists = artistsData.map((row) => row['name'] as String).toList();
    final tagsData = await getTagsForSong(songId!);
    final tags = tagsData.map((row) => row['name'] as String).toList();
    final map = songData.first;
    return Song(
      id: map['id'] as int,
      youtubeId: map['youtube_id'] as String?,
      title: map['title'] as String,
      url: map['file_path'] as String,
      duration: map['duration'] as int,
      artists: dbArtists.isNotEmpty ? dbArtists : ['Unknown Artist'],
      tags: tags,
      isDownloaded: true,
      dateAdded: DateTime.parse(map['created_at'] as String),
      localThumbnailPath: map['thumbnail_path'] as String?,
    );
  }

  Future<int> addYouTubeSongToDatabase({
    required String youtubeId,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailUrl,
  }) async {
    final db = await database;
    final existing = await db.query(
      tableSongs,
      where: 'youtube_id = ?',
      whereArgs: [youtubeId],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    late final int songId;
    await db.transaction((txn) async {
      songId = await txn.insert(tableSongs, {
        'youtube_id': youtubeId,
        'title': title,
        'file_path': 'yt:$youtubeId',
        'duration': duration,
        'thumbnail_path': thumbnailUrl,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final artist in artists.where((a) => a.isNotEmpty)) {
        final artistId = await _getOrCreateArtist(txn, artist);
        await txn.insert(tableSongArtist, {
          'song_id': songId,
          'artist_id': artistId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    return songId;
  }
}
