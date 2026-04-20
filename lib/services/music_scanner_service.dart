import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:media_kit/media_kit.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/utils/artist_parser.dart';

String normalizeStoragePath(String filePath) {
  if (filePath.startsWith('/sdcard/')) {
    return '/storage/emulated/0/${filePath.substring(8)}';
  }
  if (filePath.startsWith('/mnt/sdcard/')) {
    return '/storage/emulated/0/${filePath.substring(12)}';
  }
  if (filePath.startsWith('/data/media/0/')) {
    return '/storage/emulated/0/${filePath.substring(14)}';
  }
  if (filePath.startsWith('/data/data/')) {
    return filePath;
  }
  return filePath;
}

class MusicScannerService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Player _audioPlayer = Player();

  // Supported audio file extensions
  static const List<String> _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.aac',
    '.flac',
    '.ogg',
  ];

  // Scan device for music files and update database
  Future<void> scanDeviceForMusic() async {
    try {
      final Directory? primaryStorage = await getExternalStorageDirectory();
      if (primaryStorage == null) return;

      final musicDir = Directory(path.join(primaryStorage.path, 'Music'));
      final downloadsDir =
          Directory(path.join(primaryStorage.path, 'Download'));

      if (await musicDir.exists()) {
        await _scanDirectory(musicDir);
      }
      if (await downloadsDir.exists()) {
        await _scanDirectory(downloadsDir);
      }
    } catch (e) {
      print('Error scanning for music: $e');
    }
  }

  // Recursively scan a directory for music files
  Future<void> _scanDirectory(Directory dir) async {
    try {
      // Skip hidden directories
      if (path.basename(dir.path).startsWith('.')) return;

      await for (var entity in dir.list()) {
        if (entity is File) {
          await _processFile(entity);
        } else if (entity is Directory) {
          await _scanDirectory(entity);
        }
      }
    } catch (e) {
      print('Error scanning directory ${dir.path}: $e');
    }
  }

  // Process a file and add it to the database if it's a music file
  Future<void> _processFile(File file) async {
    try {
      final extension = path.extension(file.path).toLowerCase();
      if (!_supportedExtensions.contains(extension)) return;

      // Normalize path to avoid duplicates from symlinks
      final normalizedPath = normalizeStoragePath(file.path);

      // Check if file already exists in database (using normalized path)
      final db = await _dbHelper.database;
      final existingSongs = await db.query(
        DatabaseHelper.tableSongs,
        where: 'file_path = ?',
        whereArgs: [normalizedPath],
      );

      if (existingSongs.isNotEmpty) return; // Skip if already in database

      // Extract metadata
      final metadata = await _extractMetadata(file, normalizedPath);

      // Insert into database
      await _insertSongToDatabase(file, metadata, normalizedPath);
    } catch (e) {
      print('Error processing file ${file.path}: $e');
    }
  }

// Extract metadata from audio file
  Future<Map<String, dynamic>> _extractMetadata(
      File file, String normalizedPath) async {
    try {
      // Load the audio file to get metadata
      await _audioPlayer.open(Media(file.path));
      await Future.delayed(const Duration(milliseconds: 100));
      final duration = _audioPlayer.state.duration.inMilliseconds;

      return {
        'title': path.basenameWithoutExtension(file.path),
        'artists': ArtistParser.parseArtists('Unknown Artist'),
        'album': 'Unknown Album',
        'genre': 'Unknown Genre',
        'file_path': normalizedPath,
        'duration': duration,
        'track_number': 0,
      };
    } catch (e) {
      return {
        'title': path.basenameWithoutExtension(file.path),
        'artists': ArtistParser.parseArtists('Unknown Artist'),
        'album': 'Unknown Album',
        'genre': 'Unknown Genre',
        'file_path': normalizedPath,
        'duration': 0,
        'track_number': 0,
      };
    } finally {
      await _audioPlayer.stop();
    }
  }

  // Insert song and related data into database
  Future<void> _insertSongToDatabase(
      File file, Map<String, dynamic> songData, String normalizedPath) async {
    final db = await _dbHelper.database;
    final List<String> artists =
        songData['artists'] as List<String>? ?? ['Unknown Artist'];

    // Start a transaction
    await db.transaction((txn) async {
      // Insert or get all artists
      final List<int> artistIds = [];
      for (final artistName in artists) {
        final artistId = await _getOrCreateArtist(txn, artistName);
        artistIds.add(artistId);
      }

      // Insert or get genre
      final int genreId = await _getOrCreateGenre(txn, songData['genre']);

      // Insert or get album (use first artist)
      final int albumId = await _getOrCreateAlbum(
        txn,
        songData['album'],
        artistIds.isNotEmpty ? artistIds.first : 0,
        songData['year'],
      );

      // Insert song
      final songId = await txn.insert(
        DatabaseHelper.tableSongs,
        {
          'title': songData['title'],
          'album_id': albumId,
          'genre_id': genreId,
          'file_path': songData['file_path'],
          'duration': songData['duration'],
          'track_number': songData['track_number'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Add all artists to song
      for (final artistId in artistIds) {
        await txn.insert(
          DatabaseHelper.tableSongArtist,
          {'song_id': songId, 'artist_id': artistId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Add tag if in tsmusic folder
      if (file.path.contains('/Music/tsmusic/')) {
        final tagId = await _getOrCreateTag(txn, 'tsmusic');
        await txn.insert(
          DatabaseHelper.tableSongTags,
          {'song_id': songId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  // Helper method to get or create an artist (case-insensitive match)
  Future<int> _getOrCreateArtist(Transaction txn, String artistName) async {
    final trimmedName = artistName.trim();
    if (trimmedName.isEmpty) {
      return 0;
    }

    // Try to find existing artist (case-insensitive)
    final artists = await txn.query(
      DatabaseHelper.tableArtists,
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [trimmedName],
    );

    if (artists.isNotEmpty) {
      return artists.first['id'] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableArtists,
      {'name': trimmedName},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Helper method to get or create a genre
  Future<int> _getOrCreateGenre(Transaction txn, String genreName) async {
    final genres = await txn.query(
      DatabaseHelper.tableGenres,
      where: 'name = ?',
      whereArgs: [genreName],
    );

    if (genres.isNotEmpty) {
      return genres.first['id'] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableGenres,
      {'name': genreName},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Helper method to get or create an album
  Future<int> _getOrCreateAlbum(
    Transaction txn,
    String albumName,
    int artistId,
    int? year,
  ) async {
    final albums = await txn.query(
      DatabaseHelper.tableAlbums,
      where: 'name = ? AND artist_id = ?',
      whereArgs: [albumName, artistId],
    );

    if (albums.isNotEmpty) {
      return albums.first['id'] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableAlbums,
      {
        'name': albumName,
        'artist_id': artistId,
        if (year != null) 'year': year,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Helper method to get or create a tag
  Future<int> _getOrCreateTag(Transaction txn, String tagName) async {
    final tags = await txn.query(
      DatabaseHelper.tableTags,
      where: 'name = ?',
      whereArgs: [tagName],
    );

    if (tags.isNotEmpty) {
      return tags.first['id'] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableTags,
      {'name': tagName},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
