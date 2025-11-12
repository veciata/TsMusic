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

  // Table names
  static const String tableArtists = 'artists';
  static const String tableGenres = 'genres';
  static const String tableSongs = 'songs';
  static const String tableAlbums = 'albums';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistSongs = 'playlist_songs';
  
  // Junction tables for many-to-many relationships
  static const String tableArtistGenre = 'artist_genre';
  static const String tableSongArtist = 'song_artist';
  static const String tableSongGenre = 'song_genre';

  // Common column
  static const String columnId = 'id';
  static const String columnName = 'name';
  static const String columnCreatedAt = 'created_at';

  // Initialize database
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Returns songs by (title, artist, duration)
  Future<List<Map<String, dynamic>>> getUniqueSongsWithArtist() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.$columnId as song_id,
            s.title,
            s.file_path,
            s.duration,
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
    // Initialize the database when the singleton is created
    _initDatabase().then((db) {
      _verifyDatabaseSchema(db);
    });
  }
  
  factory DatabaseHelper() => _instance;

  // Get all songs from database
  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableSongs,
      orderBy: 'date_added DESC',
    );
    return List.generate(maps.length, (i) => Song.fromJson(maps[i]),);
  }

  // Check if database is empty
  Future<bool> isDatabaseEmpty() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableSongs')
    );
    return count == 0 || count == null;
  }


  // Clear all songs from database
  Future<void> clearSongs() async {
    final db = await database;
    await db.delete(tableSongs);
    _localSongs.clear();
    _displayedSongs.clear();
    _songsMap.clear();
  }
  
  Future<void> _verifyDatabaseSchema(Database db) async {
    try {
      // Check if playlists table exists
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final playlistsTableExists = tables.any((table) => table['name'] == tablePlaylists);
      
      if (!playlistsTableExists) {
        debugPrint('Playlists table missing - recreating database schema');
        // Drop and recreate the database
        await db.close();
        final path = join(await getDatabasesPath(), 'music_player.db');
        await deleteDatabase(path);
        _database = await _initDatabase();
      } else {
        // Check if we need to upgrade
        final version = await db.getVersion();
        if (version < databaseVersion) {
          debugPrint('Database needs upgrade from $version to $databaseVersion');
          await _onUpgrade(db, version, databaseVersion);
          await db.setVersion(databaseVersion);
        }
      }
    } catch (e) {
      debugPrint('Error verifying database schema: $e');
      rethrow;
    }
  }

  // Increment this version when making schema changes
  static const int databaseVersion = 2;

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'music_player.db');
    
    // Check if database exists and get its version
    final dbExists = await databaseExists(path);
    if (dbExists) {
      debugPrint('Database exists at $path');
      // Get the current database version
      final db = await openDatabase(path);
      try {
        final version = await db.getVersion();
        debugPrint('Current database version: $version');
      } catch (e) {
        debugPrint('Error getting database version: $e');
      } finally {
        await db.close();
      }
    } else {
      debugPrint('Creating new database at $path');
    }
    
    return await openDatabase(
      path,
      version: databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Version 2: Add playlists and playlist_songs tables
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

      // Create the Now Playing playlist
      await db.insert(
        tablePlaylists,
        {
          columnId: nowPlayingPlaylistId,
          'name': 'Now Playing',
          'description': 'Currently playing queue. This playlist is managed automatically.',
          'cover_art_url': null,
          columnCreatedAt: DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('Creating database tables with version: $version');
    // Create artists table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableArtists (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Create playlists table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylists (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        cover_art_url TEXT,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Create the Now Playing playlist
    await db.insert(
      tablePlaylists,
      {
        columnId: nowPlayingPlaylistId,
        'name': 'Now Playing',
        'description': 'Currently playing queue. This playlist is managed automatically.',
        'cover_art_url': null,
        columnCreatedAt: DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // Create genres table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableGenres (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create albums table
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

    // Create songs table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSongs (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        duration INTEGER,
        track_number INTEGER,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create artist_genre junction table (many-to-many)
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

    // Create song_artist junction table (many-to-many)
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

      // Create song_genre junction table (many-to-many)
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
    
    // Create playlist_songs junction table
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
  }

  // Helper methods for artists
  Future<int> insertArtist(Map<String, dynamic> artist) async {
    final db = await database;
    return await db.insert(
      tableArtists,
      artist,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  // Helper methods for genres
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

  // Helper methods for songs
  /// Checks if a song with the given file path already exists
  /// Returns the song ID if it exists, otherwise returns -1
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
    
    // Check if song with this file path already exists
    final existingId = await findSongIdByPath(song['file_path']);
    if (existingId != -1) {
      if (kDebugMode) {
        debugPrint('Song already exists (ID: $existingId): ${song['file_path']}');
      }
      return -1; // Indicate that no new row was inserted
    }
    
    // Add timestamps
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
    return await db.query(
      tableSongs, 
      orderBy: 'title',
      distinct: true,  // Ensure we only get distinct songs
    );
  }

  // Returns songs with a primary artist (first linked artist) to simplify UI
  Future<List<Map<String, dynamic>>> getSongsWithArtist() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.$columnId as song_id,
             s.title as title,
             s.file_path as file_path,
             s.duration as duration,
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

  // Junction table methods
  Future<int> addArtistToGenre(int artistId, int genreId) async {
    final db = await database;
    return await db.insert(
      tableArtistGenre,
      {
        'artist_id': artistId,
        'genre_id': genreId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> addArtistToSong(int songId, int artistId) async {
    final db = await database;
    return await db.insert(
      tableSongArtist,
      {
        'song_id': songId,
        'artist_id': artistId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> addGenreToSong(int songId, int genreId) async {
    final db = await database;
    return await db.insert(
      tableSongGenre,
      {
        'song_id': songId,
        'genre_id': genreId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Get related items
  Future<List<Map<String, dynamic>>> getGenresForArtist(int artistId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT g.* FROM $tableGenres g
      INNER JOIN $tableArtistGenre ag ON g.id = ag.genre_id
      WHERE ag.artist_id = ?
      ORDER BY g.name
    ''', [artistId]);
  }

  Future<List<Map<String, dynamic>>> getArtistsForSong(int songId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT a.* FROM $tableArtists a
      INNER JOIN $tableSongArtist sa ON a.id = sa.artist_id
      WHERE sa.song_id = ?
      ORDER BY a.name
    ''', [songId]);
  }

  Future<List<Map<String, dynamic>>> getSongsByArtist(int artistId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.* FROM $tableSongs s
      INNER JOIN $tableSongArtist sa ON s.id = sa.song_id
      WHERE sa.artist_id = ?
      ORDER BY s.title
    ''', [artistId]);
  }

  Future<List<Map<String, dynamic>>> getSongsByGenre(int genreId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.* FROM $tableSongs s
      JOIN $tableSongGenre sg ON s.$columnId = sg.song_id
      WHERE sg.genre_id = ?
    ''', [genreId]);
  }
  
  /// Search for songs by title, artist, or album
  /// Returns a list of songs that match the search query
  Future<List<Map<String, dynamic>>> searchSongs(String query) async {
    final db = await database;
    final searchTerm = '%$query%';
    
    return await db.rawQuery('''
      SELECT DISTINCT s.* 
      FROM $tableSongs s
      LEFT JOIN $tableSongArtist sa ON sa.song_id = s.$columnId
      LEFT JOIN $tableArtists a ON a.$columnId = sa.artist_id
      WHERE s.title LIKE ? 
         OR s.album LIKE ?
         OR a.name LIKE ?
      ORDER BY s.title
    ''', [searchTerm, searchTerm, searchTerm]);
  }

  Future<List<Map<String, dynamic>>> getGenresForSong(int songId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT g.* FROM $tableGenres g
      INNER JOIN $tableSongGenre sg ON g.id = sg.genre_id
      WHERE sg.song_id = ?
      ORDER BY g.name
    ''', [songId]);
  }

  /// Updates a song's metadata and artist relation using the unique file_path as key
  Future<void> updateSongMetadataByFilePath({
    required String filePath,
    String? title,
    required List<String> artists,
    String? album,
    String? genreName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Find song id by file_path
      final rows = await txn.query(
        tableSongs,
        columns: [columnId],
        where: 'file_path = ?',
        whereArgs: [filePath,],
        limit: 1,
      );
      if (rows.isEmpty) return; // song not found in DB
      final songId = rows.first[columnId] as int;

      // Update title if provided
      if (title != null && title.isNotEmpty) {
        await txn.update(
          tableSongs,
          {'title': title},
          where: '$columnId = ?',
          whereArgs: [songId],
        );
      }

      // Reset and set song-artist relations
      await txn.delete(tableSongArtist, where: 'song_id = ?', whereArgs: [songId]);
      
      // Add all artists (main and featured)
      for (final artist in artists) {
        final artistId = await _getOrCreateArtist(txn, artist);
        await txn.insert(
          tableSongArtist,
          {
            'song_id': songId,
            'artist_id': artistId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Optionally link album as a genre for simplicity
      if (album != null && album.isNotEmpty) {
        final genreId = await _getOrCreateGenre(txn, album);
        await txn.insert(
          tableSongGenre,
          {
            'song_id': songId,
            'genre_id': genreId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Also link detected genre name if provided (preferred)
      if (genreName != null && genreName.isNotEmpty) {
        final gId = await _getOrCreateGenre(txn, genreName);
        await txn.insert(
          tableSongGenre,
          {
            'song_id': songId,
            'genre_id': gId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Gets an existing artist ID or creates a new one if it doesn't exist
  Future<int> _getOrCreateArtist(Transaction txn, String artistName) async {
    if (artistName.trim().isEmpty) {
      throw ArgumentError('Artist name cannot be empty');
    }
    
    // Try to find existing artist
    final existingArtist = await txn.query(
      tableArtists,
      where: '$columnName = ?',
      whereArgs: [artistName],
    );
    
    if (existingArtist.isNotEmpty) {
      return existingArtist.first[columnId] as int;
    }
    
    // Create new artist if not found
    return await txn.insert(
      tableArtists,
      {
        columnName: artistName,
        columnCreatedAt: DateTime.now().toIso8601String(),
      },
    );
  }
  

  
  /// Gets an existing genre ID or creates a new one if it doesn't exist
  Future<int> _getOrCreateGenre(Transaction txn, String genreName) async {
    if (genreName.trim().isEmpty) {
      throw ArgumentError('Genre name cannot be empty');
    }
    
    // Try to find existing genre
    final existingGenre = await txn.query(
      tableGenres,
      where: '$columnName = ?',
      whereArgs: [genreName],
    );
    
    if (existingGenre.isNotEmpty) {
      return existingGenre.first[columnId] as int;
    }
    
    // Create new genre if not found
    return await txn.insert(
      tableGenres,
      {
        columnName: genreName,
        columnCreatedAt: DateTime.now().toIso8601String(),
      },
    );
  }

  // Close the database when done
  // Playlist methods
  static const int nowPlayingPlaylistId = 1;
  
  Future<void> _ensureNowPlayingPlaylist() async {
    final db = await database;
    // Try to insert the Now Playing playlist if it doesn't exist
    await db.insert(
      tablePlaylists,
      {
        columnId: nowPlayingPlaylistId,
        'name': 'Now Playing',
        'description': 'Currently playing queue. This playlist is managed automatically.',
        'cover_art_url': null,
        columnCreatedAt: DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  
  Future<int> createPlaylist(String name, {String? description, String? coverArtUrl}) async {
    final db = await database;
    // Ensure Now Playing playlist exists
    await _ensureNowPlayingPlaylist();
    
    return await db.insert(
      tablePlaylists,
      {
        'name': name,
        'description': description,
        'cover_art_url': coverArtUrl,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updatePlaylist(int playlistId, {String? name, String? description, String? coverArtUrl}) async {
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
    // Prevent deletion of Now Playing playlist
    if (playlistId == nowPlayingPlaylistId) {
      throw Exception('Cannot delete the Now Playing playlist');
    }
    
    final db = await database;
    // The ON DELETE CASCADE will handle the playlist_songs entries
    return await db.delete(
      tablePlaylists,
      where: '$columnId = ?',
      whereArgs: [playlistId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPlaylists() async {
    try {
      final db = await database;
      
      // Ensure Now Playing playlist exists
      await _ensureNowPlayingPlaylist();
      
      // Log all tables in the database
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      debugPrint('Tables in database: ${tables.map((e) => e['name']).toList()}');
      
      // Check if playlists table exists
      final playlistsTableExists = tables.any((table) => table['name'] == tablePlaylists);
      if (!playlistsTableExists) {
        debugPrint('ERROR: $tablePlaylists table does not exist!');
        // Try to create the table if it doesn't exist
        await _onUpgrade(db, 1, databaseVersion);
      }
      
      // Try to query the playlists
      try {
        final playlists = await db.query(
          tablePlaylists,
          orderBy: 'name COLLATE NOCASE ASC',
        );
        debugPrint('Found ${playlists.length} playlists');
        return playlists;
      } catch (e) {
        debugPrint('Error querying $tablePlaylists: $e');
        // If query fails, try to recreate the table
        await db.execute('DROP TABLE IF EXISTS $tablePlaylistSongs');
        await db.execute('DROP TABLE IF EXISTS $tablePlaylists');
        await _onUpgrade(db, 1, databaseVersion);
        return await db.query(
          tablePlaylists,
          orderBy: 'name COLLATE NOCASE ASC',
        );
      }
    } catch (e) {
      debugPrint('Error in getAllPlaylists: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getPlaylist(int playlistId) async {
    final db = await database;
    // Ensure Now Playing playlist exists when requested
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
      // Get current max position
      final result = await txn.rawQuery('''
        SELECT COALESCE(MAX(position), 0) as max_position 
        FROM $tablePlaylistSongs 
        WHERE playlist_id = ?
      ''', [playlistId]);
      
      int position = (result.first['max_position'] as int?) ?? 0;
      
      // Insert each song with an incremented position
      for (final songId in songIds) {
        try {
          await txn.insert(
            tablePlaylistSongs,
            {
              'playlist_id': playlistId,
              'song_id': songId,
              'position': ++position,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          count++;
        } catch (e) {
          // Skip duplicates or invalid song IDs
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
      where: 'playlist_id = ? AND song_id IN (${List.filled(songIds.length, '?').join(',')})',
      whereArgs: [playlistId, ...songIds],
    );
  }

  Future<List<Map<String, dynamic>>> getSongsInPlaylist(int playlistId) async {
    final db = await database;
    // Ensure Now Playing playlist exists when requested
    if (playlistId == nowPlayingPlaylistId) {
      await _ensureNowPlayingPlaylist();
    }
    
    return await db.rawQuery('''
      SELECT s.*, ps.position
      FROM $tableSongs s
      INNER JOIN $tablePlaylistSongs ps ON s.$columnId = ps.song_id
      WHERE ps.playlist_id = ?
      ORDER BY ps.position ASC
    ''', [playlistId]);
  }
  
  /// Updates the Now Playing playlist with new song IDs
  /// This will replace all existing songs in the Now Playing playlist
  Future<void> updateNowPlayingPlaylist(List<int> songIds) async {
    final db = await database;
    await db.transaction((txn) async {
      // First, clear existing songs from Now Playing
      await txn.delete(
        tablePlaylistSongs,
        where: 'playlist_id = ?',
        whereArgs: [nowPlayingPlaylistId],
      );
      
      // Then add all new songs with their positions
      for (int i = 0; i < songIds.length; i++) {
        await txn.insert(
          tablePlaylistSongs,
          {
            'playlist_id': nowPlayingPlaylistId,
            'song_id': songIds[i],
            'position': i + 1,
          },
        );
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

  Future<int> reorderPlaylistSongs(int playlistId, Map<int, int> newPositions) async {
    if (newPositions.isEmpty) return 0;
    
    final db = await database;
    int count = 0; // Initialize count
    
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

  Future<Song> addSongFromYouTube({
    required String filePath,
    required String title,
    required String author,
    required int duration,
  }) async {
    final db = await database;
    int? songId;

    await db.transaction((txn) async {
      // First, check if song already exists by file path
      final existingSongs = await txn.query(
        tableSongs,
        where: 'file_path = ?',
        whereArgs: [filePath],
      );

      if (existingSongs.isNotEmpty) {
        songId = existingSongs.first['id'] as int;
      } else {
        final songMap = {
          'title': title,
          'file_path': filePath,
          'duration': duration,
          'created_at': DateTime.now().toIso8601String(),
        };

        songId = await txn.insert(
          tableSongs,
          songMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final artistId = await _getOrCreateArtist(txn, author.isNotEmpty ? author : 'Unknown Artist');
        
        await txn.insert(
          tableSongArtist,
          {'song_id': songId, 'artist_id': artistId,},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        await txn.insert(
          tableSongGenre,
          {'song_id': songId, 'genre_id': await _getOrCreateGenre(txn, 'tsmusic'),},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    // Fetch the complete song details to return
    final songData = await db.query(
      tableSongs,
      where: '$columnId = ?',
      whereArgs: [songId],
    );

    if (songData.isEmpty) {
      throw Exception('Failed to retrieve downloaded song from database.');
    }

    final artistsData = await getArtistsForSong(songId!);
    final artists = artistsData.map((row) => row['name'] as String).toList();

    final map = songData.first;
    // The Song model expects a String ID, but the database provides an int.
    // It also expects 'url' but the db has 'file_path'.
    // We need to manually map the fields.
    return Song(
      id: map['id'] as int,
      title: map['title'] as String,
      url: map['file_path'] as String,
      duration: map['duration'] as int,
      artists: artists.isNotEmpty ? artists : [author],
      isDownloaded: true, // It's a downloaded song
      dateAdded: DateTime.parse(map['created_at'] as String),
    );
  }
}
