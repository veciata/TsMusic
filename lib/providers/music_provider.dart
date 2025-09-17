import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/song_sort_option.dart';
import '../services/audio_notification_service.dart';
import '../services/metadata_enrichment_service.dart';
import '../database/database_helper.dart';

extension StringExtension on String {
  String trimAll() => trim().replaceAll(RegExp(r'\s+'), ' ');
}


class NewMusicProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MetadataEnrichmentService _enrichment = MetadataEnrichmentService();
  List<Song> _playlist = [];
  List<Song> _displayedSongs = [];
  List<Song> _filteredSongs = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;
  SongSortOption _currentSortOption = SongSortOption.title;
  bool _sortAscending = true;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isEnriching = false;
  int _enrichedCount = 0;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  List<Song> get songs => _displayedSongs;
  List<Song> get filteredSongs => _filteredSongs;
  bool get isEnriching => _isEnriching;
  int get enrichedCount => _enrichedCount;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<bool> get playingStream => _audioPlayer.playingStream;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration get duration => _audioPlayer.duration ?? Duration.zero;
  Song? get currentSong =>
      _playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length
          ? _playlist[_currentIndex]
          : null;
  int? get currentIndex =>
      (_playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _currentIndex
          : null;
  List<Song> get queue => List.unmodifiable(_playlist);
  List<Song> get allSongs => _playlist;
  List<Song> get youtubeSongs =>
      _playlist.where((song) => song.hasTag('tsmusic')).toList();
      
  // Get unique artists from the playlist, excluding 'Unknown Artist'
  List<String> get artists {
    final artistSet = <String>{};
    for (final song in _playlist) {
      if (song.artist.isNotEmpty && song.artist.toLowerCase() != 'unknown artist') {
        artistSet.add(song.artist);
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }
  
  // Get artist image URL (placeholder implementation - replace with actual implementation)
  String? getArtistImageUrl(String artistName) {
    // In a real app, you would fetch this from a music metadata API
    // For now, return null to use a default icon
    return null;
  }
  
  // Get songs by artist
  List<Song> getSongsByArtist(String artistName) {
    return _playlist.where((song) => song.artist == artistName).toList();
  }
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Playback control methods
  Future<void> play() async {
    await _audioPlayer.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _audioPlayer.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  void cycleRepeatMode() {
    _loopMode = LoopMode.values[(_loopMode.index + 1) % LoopMode.values.length];
    _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  // Queue management methods
  Future<void> addSong(Song song) async {
    final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _playlist[existingIndex] = song;
    } else {
      _playlist.add(song);
    }
    _displayedSongs = List.from(_playlist);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      notifyListeners();
    }
  }

  Future<void> clearQueue() async {
    _playlist.clear();
    _currentIndex = 0;
    notifyListeners();
  }

  void moveInQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length || newIndex < 0 || newIndex >= _playlist.length) {
      return;
    }
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  void playAt(int index) {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      _audioPlayer.seek(Duration.zero);
      _audioPlayer.play();
      notifyListeners();
    }
  }

  // Favorite methods
  bool isFavorite(String songId) {
    // Implement your favorite logic here
    return false;
  }

  void toggleFavorite(String songId) {
    // Implement your favorite toggling logic here
    notifyListeners();
  }

  // Local music loading
  Future<void> loadLocalMusic() async {
    try {
      await loadMusicFromDevice();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load local music: $e';
      notifyListeners();
      rethrow;
    }
  }

  static const String _songsKey = 'cached_songs';

  // Common music directories to scan
  static const List<String> _musicDirectories = [
    // Primary storage
    '/storage/emulated/0',
    '/sdcard',
    '/mnt/sdcard',
    
    // Common music directories
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Media',
    '/storage/emulated/0/Media/Music',
    '/storage/emulated/0/audio',
    '/storage/emulated/0/sounds',
    
    // SD card directories (common variations)
    '/storage/sdcard0',
    '/storage/sdcard1',
    '/storage/extSdCard',
    '/storage/emulated/0/external_sd',
    '/mnt/external_sd',
    '/mnt/sdcard/external_sd',
    '/storage/external_sd',
    
    // Manufacturer specific paths
    '/storage/0000-0000',  // Common SD card path on some devices
    '/storage/self/primary',
    
    // Legacy paths
    '/sdcard',
    '/mnt/sdcard',
    '/sdcard/external_sd',
    '/mnt/sdcard/external_sd',
    
    // Try root directories
    '/',
  ];
  
  // File extensions to look for (case insensitive)
  static const _audioExtensions = [
    '.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus',
    '.m4b', '.alac', '.aiff', '.wma', '.amr', '.mid', '.midi',
    '.3gp', '.mkv', '.mp4', '.wmv', '.mpga', '.weba', '.webm'
  ];
  
  // Additional music folders to check within each directory
  static const _musicFolders = [
    'Music', 'Müzik', 'Музыка', '音乐', '音楽', '음악',
    'media/audio/music', 'media/music', 'audio/music',
    'sounds/music', 'media/audio', 'media/sounds', 'audio',
    'Download', 'Downloads', 'DCIM', 'Documents', 'Ringtones',
    'Notifications', 'Alarms', 'Podcasts', 'Audiobooks',
    'Android/media', 'Android/data', 'WhatsApp/Media/WhatsApp Music',
    'Telegram/Telegram Audio', 'VK/music', 'YandexMusic', 'Spotify'
  ];

  NewMusicProvider() {
    _positionSubscription = _audioPlayer.positionStream.listen((_) {
      notifyListeners();
    });

    AudioNotificationService.init(
      player: _audioPlayer,
      onCurrentSongChanged: (_) => notifyListeners(),
      onPlaybackStateChanged: (_) => notifyListeners(),
    );

    _audioPlayer.loopModeStream.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });

    _audioPlayer.shuffleModeEnabledStream.listen((enabled) {
      _shuffleEnabled = enabled;
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.play();
        } else if (_loopMode == LoopMode.all) {
          if (_currentIndex == _playlist.length - 1) {
            _currentIndex = 0;
          } else {
            _currentIndex++;
          }
          await _setAudioSource(_playlist[_currentIndex]);
          await _audioPlayer.play();
          await _updateNotification();
          notifyListeners();
        } else {
          if (_playlist.length > 1 && _currentIndex < _playlist.length - 1) {
            await next();
          }
        }
      }
    });

    _initialize();
  }

  @override
  Future<void> dispose() async {
    _positionSubscription?.cancel();
    await _audioPlayer.dispose();
    super.dispose();
  }

  /// Scans common directories for music files
  Future<List<FileSystemEntity>> scanForMusicFiles() async {
    final List<FileSystemEntity> musicFiles = [];
    final Set<String> processedPaths = {}; // To avoid duplicates
    final Set<String> scannedDirs = {}; // To avoid scanning same directory multiple times
    int totalDirsChecked = 0;
    int accessibleDirs = 0;
    final stopwatch = Stopwatch()..start();
    
    if (kDebugMode) {
      print('Starting music file scan...');
      print('Supported extensions: $_audioExtensions');
    }
    
    // Check storage permission
    if (!(await _checkStoragePermission())) {
      throw Exception('Storage permission not granted');
    }
    
    // Function to process a single directory
    Future<void> processDirectory(String dirPath) async {
      totalDirsChecked++;
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          accessibleDirs++;
          if (kDebugMode) {
            print('Scanning directory: $dirPath');
          }
          
          // Check if this is a music file
          if (await FileSystemEntity.isFile(dirPath)) {
            final ext = path.extension(dirPath).toLowerCase();
            if (_audioExtensions.contains(ext) && !processedPaths.contains(dirPath)) {
              musicFiles.add(File(dirPath));
              processedPaths.add(dirPath);
              if (kDebugMode) {
                print('Found music file: $dirPath');
              }
            }
            return;
          }
          
          // Process directory contents
          try {
            final fileList = await dir.list(recursive: true).toList();
            if (kDebugMode) {
              print('Found ${fileList.length} items in $dirPath');
            }
            
            for (final entity in fileList) {
              try {
                if (entity is File) {
                  final ext = path.extension(entity.path).toLowerCase();
                  if (_audioExtensions.contains(ext)) {
                    if (!processedPaths.contains(entity.path)) {
                      musicFiles.add(entity);
                      processedPaths.add(entity.path);
                      if (kDebugMode) {
                        print('Found music file: ${entity.path}');
                      }
                    }
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Error processing ${entity?.path}: $e');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error listing $dirPath: $e');
            }
          }
        } else if (kDebugMode) {
          print('Directory does not exist: $dirPath');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error processing directory $dirPath: $e');
        }
      }
    }
    
    // Process all base directories
    for (final dirPath in _musicDirectories) {
      if (scannedDirs.contains(dirPath)) continue;
      scannedDirs.add(dirPath);
      
      if (kDebugMode) {
        print('Processing base directory: $dirPath');
      }
      await processDirectory(dirPath);
      
      // Also check for music subdirectories
      for (final musicFolder in _musicFolders) {
        final fullPath = path.join(dirPath, musicFolder);
        if (scannedDirs.contains(fullPath)) continue;
        scannedDirs.add(fullPath);
        
        if (kDebugMode) {
          print('Processing music folder: $fullPath');
        }
        await processDirectory(fullPath);
      }
    }
    
    stopwatch.stop();
    if (kDebugMode) {
      print('=' * 80);
      print('SCAN COMPLETE');
      print('=' * 80);
      print('Found ${musicFiles.length} music files in ${stopwatch.elapsed}');
      print('Total directories checked: $totalDirsChecked');
      print('Accessible directories: $accessibleDirs');
      print('Scanned directories:');
      scannedDirs.take(20).forEach(print);
      if (scannedDirs.length > 20) print('... and ${scannedDirs.length - 20} more');
      
      if (musicFiles.isEmpty) {
        print('\n⚠️ No music files found!');
        print('Please check the following:');
        print('1. The app has storage permissions');
        print('2. Music files exist on the device');
        print('3. Try restarting the app');
        print('\nScanned directories were:');
        scannedDirs.take(10).forEach(print);
      } else {
        print('\nFirst few files found:');
        musicFiles.take(5).forEach((file) => print('- ${file.path}'));
        if (musicFiles.length > 5) print('... and ${musicFiles.length - 5} more');
      }
      print('=' * 80);
    }
    
    return musicFiles;
  }

  /// Checks and requests storage permission
  Future<bool> _checkStoragePermission() async {
    var status = await Permission.storage.status;
    if (status.isDenied) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  /// Loads music files from device storage
  Future<void> loadMusicFromDevice() async {
    try {
      _isLoading = true;
      _error = null;
      
      // Check storage permission first
      if (!await Permission.storage.isGranted) {
        _error = 'Storage permission not granted';
        _isLoading = false;
        notifyListeners();
        return;
      }
      notifyListeners();

      if (kDebugMode) {
        print('Starting to load music from device...');
      }

      // First, check permissions
      if (!(await _checkStoragePermission())) {
        _error = 'Storage permission not granted. Please grant the permission in app settings.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Get external storage directories
      final appDocDir = await getApplicationDocumentsDirectory();
      final externalDirs = await getExternalStorageDirectories();
      
      if (kDebugMode) {
        print('App documents directory: ${appDocDir.path}');
        if (externalDirs != null) {
          for (var dir in externalDirs) {
            print('External storage directory: ${dir.path}');
          }
        } else {
          print('No external storage directories found');
        }
      }

      // Scan for music files
      final musicFiles = await scanForMusicFiles();
      
      if (kDebugMode) {
        print('Found ${musicFiles.length} music files');
        if (musicFiles.isNotEmpty) {
          print('First few files:');
          for (var i = 0; i < (musicFiles.length > 5 ? 5 : musicFiles.length); i++) {
            print('  ${musicFiles[i].path}');
          }
        }
      }

      final List<Song> songs = [];
      int processedFiles = 0;
      final totalFiles = musicFiles.length;
      
      // Process files in batches to avoid blocking the UI
      for (final file in musicFiles) {
        try {
          final fileName = path.basenameWithoutExtension(file.path);
          final filePath = file.path;
          
          // Skip files that are too small to be valid audio files (less than 10KB)
          final fileSize = await File(filePath).length();
          if (fileSize < 10 * 1024) {
            if (kDebugMode) {
              print('Skipping small file: $filePath (${fileSize} bytes)');
            }
            continue;
          }
          
          songs.add(
            Song(
              id: filePath, // Use file path as ID for local files
              title: fileName,
              artist: 'Unknown Artist',
              album: 'Unknown Album',
              url: filePath,
              source: filePath,
              duration: 0, // Will be updated when played
              dateAdded: DateTime.now(),
              fileSize: fileSize,
            ),
          );
          
          processedFiles++;
          // Update progress every 10 files
          if (processedFiles % 10 == 0) {
            if (kDebugMode) {
              print('Processed $processedFiles of $totalFiles files...');
            }
            // Update UI with progress
            _isLoading = true;
            _error = 'Scanning music... ($processedFiles/$totalFiles)';
            notifyListeners();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error processing file ${file.path}: $e');
          }
        }
      }

      if (songs.isEmpty) {
        _error = 'No music files found. Please ensure you have music files in your device storage.';
        if (kDebugMode) {
          print('No valid music files found in the scanned directories');
        }
      } else {
        _playlist = songs;
        _displayedSongs = List.from(_playlist);
        _filteredSongs = List.from(_playlist);
        
        // Save to database in the background
        if (songs.isNotEmpty) {
          if (kDebugMode) {
            print('Saving ${songs.length} songs to database...');
          }
          final db = DatabaseHelper();
          await db.syncMusicLibrary(this.songs);
          if (kDebugMode) {
            print('Successfully saved songs to database');
          }
        }
      }
      
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _error = 'Error: ${e.toString()}';
      if (kDebugMode) {
        print('Permission error in loadMusicFromDevice: $e');
      }
    } on FileSystemException catch (e) {
      _error = 'File system error: ${e.message}';
      if (kDebugMode) {
        print('File system error in loadMusicFromDevice: $e');
      }
    } catch (e, stackTrace) {
      _error = 'Failed to load music: ${e.toString()}';
      if (kDebugMode) {
        print('Error in loadMusicFromDevice: $e');
        print('Stack trace: $stackTrace');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    await loadSongsFromStorage();
  }

  // addSong method is now implemented above with async/await support

  Future<void> updateSong(Song updatedSong) async {
    final index = _playlist.indexWhere((song) => song.id == updatedSong.id);
    if (index != -1) {
      _playlist[index] = updatedSong;
      _displayedSongs = List.from(_playlist);
      await _saveSongsToStorage();
      notifyListeners();
    }
  }

  Future<void> _saveSongsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songsJson = _playlist.map((song) => song.toJson()).toList();
      await prefs.setString(_songsKey, jsonEncode(songsJson));
    } catch (e) {
      if (kDebugMode) {
        print('Error saving songs to storage: $e');
      }
      rethrow;
    }
  }

  Future<void> loadSongsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songsJson = prefs.getString(_songsKey);
      if (songsJson != null) {
        final List<dynamic> jsonList = jsonDecode(songsJson);
        _playlist = jsonList.map((json) => Song.fromJson(json)).toList();
        _displayedSongs = List.from(_playlist);
        _filteredSongs = List.from(_playlist);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading songs from storage: $e');
      }
      rethrow;
    }
  }

  Future<void> setCurrentSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      notifyListeners();
    }
  }

  Future<void> _setAudioSource(Song song) async {
    if (song.url.startsWith('http')) {
      await _audioPlayer.setUrl(song.url);
    } else {
      await _audioPlayer.setFilePath(song.url);
    }
    await _updateNotification();
  }

  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      await audioHandler.setAudioSource(
        AudioSource.uri(Uri.parse(currentSong!.url)),
        song: currentSong,
      );
      if (_audioPlayer.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_shuffleEnabled) {
      int nextIndex = _currentIndex;
      final random = Random();
      while (nextIndex == _currentIndex && _playlist.length > 1) {
        nextIndex = random.nextInt(_playlist.length);
      }
      _currentIndex = nextIndex;
    } else {
      _currentIndex = (_currentIndex + 1) % _playlist.length;
    }
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) _currentIndex = _playlist.length - 1;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    await _updateNotification();
    notifyListeners();
  }

  Future<void> playSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      await _audioPlayer.play();
      await _updateNotification();
      notifyListeners();
    }
  }

  void sortSongs({required SongSortOption sortBy, bool ascending = true}) {
    _currentSortOption = sortBy;
    _sortAscending = ascending;
    _playlist.sort((a, b) {
      int compare;
      switch (sortBy) {
        case SongSortOption.title:
          compare = a.title.compareTo(b.title);
          break;
        case SongSortOption.artist:
          compare = a.artist.compareTo(b.artist);
          break;
        case SongSortOption.album:
          compare = (a.album ?? '').compareTo(b.album ?? '');
          break;
        case SongSortOption.duration:
          compare = a.duration.compareTo(b.duration);
          break;
        case SongSortOption.dateAdded:
          compare = a.dateAdded.compareTo(b.dateAdded);
          break;
      }
      return ascending ? compare : -compare;
    });
    _displayedSongs = List.from(_playlist);
    notifyListeners();
  }

  void filterSongs(String query) {
    if (query.isEmpty) {
      _displayedSongs = List.from(_playlist);
    } else {
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _playlist.where((song) {
        return song.title.toLowerCase().contains(lowerQuery) ||
            song.artist.toLowerCase().contains(lowerQuery) ||
            (song.album?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    }
    notifyListeners();
  }
}
