import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/new_music_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  // Table names
  static const String tableArtists = 'artists';
  static const String tableGenres = 'genres';
  static const String tableSongs = 'songs';
  static const String tableAlbums = 'albums';
  
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

  // Returns unique songs by (title, artist) case-insensitive to avoid duplicates
  Future<List<Map<String, dynamic>>> getUniqueSongsWithArtist() async {
    final db = await database;
    return await db.rawQuery('''
      WITH song_artist_first AS (
        SELECT s.$columnId AS song_id,
               s.title,
               s.file_path,
               s.duration,
               a.$columnName AS artist,
               ROW_NUMBER() OVER (PARTITION BY s.$columnId ORDER BY sa.artist_id) AS rn
        FROM $tableSongs s
        LEFT JOIN $tableSongArtist sa ON sa.song_id = s.$columnId
        LEFT JOIN $tableArtists a ON a.$columnId = sa.artist_id
      ),
      normalized AS (
        SELECT title, file_path, duration, COALESCE(artist, '') AS artist,
               LOWER(TRIM(title)) AS norm_title,
               LOWER(TRIM(COALESCE(artist, ''))) AS norm_artist
        FROM song_artist_first
        WHERE rn = 1 OR rn IS NULL
      )
      SELECT MIN(file_path) AS file_path,
             MIN(title) AS title,
             MIN(artist) AS artist,
             MIN(duration) AS duration
      FROM normalized
      GROUP BY norm_title, norm_artist
      ORDER BY title COLLATE NOCASE ASC
    ''');
  }

  DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'music_player.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create artists table
    await db.execute('''
      CREATE TABLE $tableArtists (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create genres table
    await db.execute('''
      CREATE TABLE $tableGenres (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create albums table
    await db.execute('''
      CREATE TABLE $tableAlbums (
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
      CREATE TABLE $tableSongs (
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
      CREATE TABLE $tableArtistGenre (
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
      CREATE TABLE $tableSongArtist (
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
      CREATE TABLE $tableSongGenre (
        song_id INTEGER NOT NULL,
        genre_id INTEGER NOT NULL,
        $columnCreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (song_id, genre_id),
        FOREIGN KEY (song_id) REFERENCES $tableSongs($columnId) ON DELETE CASCADE,
        FOREIGN KEY (genre_id) REFERENCES $tableGenres($columnId) ON DELETE CASCADE
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

  Future<List<Map<String, dynamic>>> getArtists() async {
    final db = await database;
    return await db.query(tableArtists, orderBy: columnName);
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
  Future<int> insertSong(Map<String, dynamic> song) async {
    final db = await database;
    return await db.insert(
      tableSongs,
      song,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSongs() async {
    final db = await database;
    return await db.query(tableSongs, orderBy: 'title');
  }

  // Returns songs with a primary artist (first linked artist) to simplify UI
  Future<List<Map<String, dynamic>>> getSongsWithArtist() async {
    final db = await database;
    // Join songs with first artist relation (min artist_id per song_id)
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
      INNER JOIN $tableSongGenre sg ON s.id = sg.song_id
      WHERE sg.genre_id = ?
      ORDER BY s.title
    ''', [genreId]);
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

  /// Fetches music data from NewMusicProvider and stores it in the database
  Future<void> syncMusicLibrary(NewMusicProvider musicProvider) async {
    try {
      // Clear existing data to avoid duplicates
      await _clearExistingMusicData();
      
      // Get all songs from the music provider
      final songs = musicProvider.songs;
      
      // Process each song and store in database
      for (final song in songs) {
        await _processSong(song);
      }
      
      if (kDebugMode) {
        print('Successfully synced ${songs.length} songs to the database');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing music library: $e');
      }
      rethrow;
    }
  }
  
  /// Clears all music-related data from the database
  Future<void> _clearExistingMusicData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(tableSongGenre);
      await txn.delete(tableSongArtist);
      await txn.delete(tableArtistGenre);
      await txn.delete(tableSongs);
      await txn.delete(tableArtists);
      await txn.delete(tableGenres);
    });
  }
  
  /// Processes a single song and stores it in the database with all relationships
  Future<void> _processSong(Song song) async {
    final db = await database;
    
    await db.transaction((txn) async {
      // Insert or get artist
      final artistId = await _getOrCreateArtist(txn, song.artist);
      
      // Insert song
      final songId = await txn.insert(
        tableSongs,
        {
          'title': song.title,
          'file_path': song.url,
          'duration': song.duration,
          'track_number': 0, // Default value, can be updated if available
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Link song to artist
      await txn.insert(
        tableSongArtist,
        {
          'song_id': songId,
          'artist_id': artistId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      
      // Process genres (if any)
      if (song.album != null) {
        // For simplicity, using album as a genre
        // In a real app, you might want to extract actual genres from metadata
        final genreId = await _getOrCreateGenre(txn, song.album!);
        
        // Link song to genre
        await txn.insert(
          tableSongGenre,
          {
            'song_id': songId,
            'genre_id': genreId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        
        // Link artist to genre
        await txn.insert(
          tableArtistGenre,
          {
            'artist_id': artistId,
            'genre_id': genreId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }
  
  /// Upserts an artist by name and returns the artist id
  Future<int> upsertArtistByName(String artistName) async {
    final db = await database;
    final existing = await db.query(
      tableArtists,
      where: '$columnName = ?',
      whereArgs: [artistName],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first[columnId] as int;
    }
    return await db.insert(tableArtists, {
      columnName: artistName,
      columnCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  /// Updates a song's metadata and artist relation using the unique file_path as key
  Future<void> updateSongMetadataByFilePath({
    required String filePath,
    String? title,
    required String artistName,
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
        whereArgs: [filePath],
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

      // Ensure artist exists
      final artistId = await _getOrCreateArtist(txn, artistName);

      // Reset and set song-artist relation
      await txn.delete(tableSongArtist, where: 'song_id = ?', whereArgs: [songId]);
      await txn.insert(
        tableSongArtist,
        {
          'song_id': songId,
          'artist_id': artistId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
    // Try to find existing artist
    final existingArtist = await txn.query(
      tableArtists,
      where: '$columnName = ?',
      whereArgs: [artistName],
    );
    
    if (existingArtist.isNotEmpty) {
      return existingArtist.first['id'] as int;
    }
    
    // Create new artist if not found
    return await txn.insert(
      tableArtists,
      {
        'name': artistName,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }
  
  /// Gets an existing genre ID or creates a new one if it doesn't exist
  Future<int> _getOrCreateGenre(Transaction txn, String genreName) async {
    // Try to find existing genre
    final existingGenre = await txn.query(
      tableGenres,
      where: '$columnName = ?',
      whereArgs: [genreName],
    );
    
    if (existingGenre.isNotEmpty) {
      return existingGenre.first['id'] as int;
    }
    
    // Create new genre if not found
    return await txn.insert(
      tableGenres,
      {
        'name': genreName,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  // Close the database when done
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
