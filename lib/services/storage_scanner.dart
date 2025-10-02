import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/song.dart';
import 'package:path/path.dart' as path;

class StorageScanner {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Scans device storage for music files with proper permission checking
  Future<List<Song>> scanForMusic() async {
    // Check storage permission
    if (!await _checkAndRequestPermission()) {
      throw Exception('Storage permission not granted');
    }

    try {
      // Get music directories (you can add more paths as needed)
      final musicDirs = await _getMusicDirectories();
      final List<Song> foundSongs = [];

      // Process each directory
      for (final dir in musicDirs) {
        try {
          if (await Directory(dir).exists()) {
            final songs = await _scanDirectory(Directory(dir));
            foundSongs.addAll(songs);
          }
        } catch (e) {
          print('Error scanning directory $dir: $e');
          // Continue with next directory on error
          continue;
        }
      }

      return foundSongs;
    } catch (e) {
      print('Error during storage scan: $e');
      rethrow;
    }
  }

  /// Checks and requests storage permission
  Future<bool> _checkAndRequestPermission() async {
    try {
      final status = await Permission.storage.request();
      if (status.isGranted) return true;
      
      if (status.isPermanentlyDenied) {
        // Show rationale and open app settings
        return await openAppSettings();
      }
      return false;
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }

  /// Returns common music directories
  Future<List<String>> _getMusicDirectories() async {
    final List<String> dirs = [];
    
    // Common music directories on Android
    if (Platform.isAndroid) {
      dirs.addAll([
        '/sdcard/Music',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Download/Music',
      ]);
    }
    
    // For iOS, you might want to use the documents directory
    if (Platform.isIOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      dirs.add(appDocDir.path);
    }

    return dirs;
  }

  /// Recursively scans a directory for music files
  Future<List<Song>> _scanDirectory(Directory dir) async {
    final List<Song> songs = [];
    
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            final filePath = entity.path;
            if (_isMusicFile(filePath)) {
              final song = await _createSongFromFile(filePath);
              if (song != null) {
                songs.add(song);
              }
            }
          } catch (e) {
            print('Error processing file ${entity.path}: $e');
            // Continue with next file on error
            continue;
          }
        }
      }
    } catch (e) {
      print('Error listing directory ${dir.path}: $e');
      rethrow;
    }

    return songs;
  }

  /// Checks if a file is a music file based on extension
  bool _isMusicFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return [
      'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'wma', 'alac'
    ].contains(ext);
  }

  /// Creates a Song object from a file
  Future<Song?> _createSongFromFile(String filePath) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      
      // Skip files that are too small to be valid music files
      if (stat.size < 1024 * 10) { // 10KB minimum
        return null;
      }

      // Extract metadata from file name if needed
      final fileName = path.basename(filePath);
      final title = path.basenameWithoutExtension(fileName);
      
      return Song(
        id: filePath, // Use file path as ID for local files
        title: title,
        artists: ['Unknown Artist'],
        url: 'file://$filePath',
        source: 'local',
        duration: 0, // Will be updated later
        fileSize: stat.size,
        isFavorite: false,
        isDownloaded: true,
        tags: [],
        dateAdded: stat.modified,
      );
    } catch (e) {
      print('Error creating song from file $filePath: $e');
      return null;
    }
  }
}
