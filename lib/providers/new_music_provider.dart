import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import '../models/song.dart';
import '../services/audio_notification_service.dart';
import '../services/metadata_enrichment_service.dart';
import '../database/database_helper.dart';

// Add this extension for string manipulation
extension StringExtension on String {
  String trimAll() => this.trim().replaceAll(RegExp(r'\s+'), ' ');
}

enum SongSortOption {
  title,
  artist,
  duration,
  dateAdded,
}

class NewMusicProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MetadataEnrichmentService _enrichment = MetadataEnrichmentService();
  List<Song> _playlist = [];
  List<Song> _songs = [];
  List<Song> _displayedSongs = [];
  List<Song> _filteredSongs = [];
  List<Song> get songs => _displayedSongs;
  List<Song> get filteredSongs => _filteredSongs;
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;
  SongSortOption _currentSortOption = SongSortOption.title;
  bool _sortAscending = true;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isEnriching = false;
  int _enrichedCount = 0;
  bool get isEnriching => _isEnriching;
  int get enrichedCount => _enrichedCount;

  // Notification service related
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

  NewMusicProvider() {
    // Listen to position changes and notify listeners
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      notifyListeners();
    });
    // Initialize audio notification service with this provider's player
    AudioNotificationService.init(
      player: _audioPlayer,
      onCurrentSongChanged: (song) {
        // keep UI in sync when media item changes via notification
        notifyListeners();
      },
      onPlaybackStateChanged: (isPlaying) {
        notifyListeners();
      },
    );

    // Load songs from storage when provider is created
    _initialize();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    AudioNotificationService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await loadSongsFromStorage();
  }

  List<Song> get allSongs => _playlist;
  List<Song> get youtubeSongs =>
      _playlist.where((song) => song.hasTag('tsmusic')).toList();
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> addSong(Song song) async {
    // Check if song already exists by ID
    final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      // Update existing song
      _playlist[existingIndex] = song;
    } else {
      // Add new song
      _playlist.add(song);
    }

    _displayedSongs = List.from(_playlist);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> updateSong(Song updatedSong) async {
    final index = _playlist.indexWhere((song) => song.id == updatedSong.id);
    if (index != -1) {
      _playlist[index] = updatedSong;
      _displayedSongs = List.from(_playlist);
      await _saveSongsToStorage();
      notifyListeners();
    }
  }

  static const String _songsKey = 'cached_songs';

  Future<void> _saveSongsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songsJson = _playlist.map((song) => song.toJson()).toList();
      await prefs.setString(_songsKey, jsonEncode(songsJson));
    } catch (e) {
      debugPrint('Error saving songs to storage: $e');
      // Don't throw, as we don't want to break the app if saving fails
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
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading songs from storage: $e');
      // If there's an error, start with an empty playlist
      _playlist = [];
      _displayedSongs = [];
    }
  }

  // Favorites helpers
  bool isFavorite(String songId) {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    if (idx == -1) return false;
    return _playlist[idx].isFavorite;
  }

  Future<void> toggleFavorite(String songId) async {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    if (idx == -1) return;
    final song = _playlist[idx];
    final updated = song.copyWith(isFavorite: !song.isFavorite);
    _playlist[idx] = updated;
    _displayedSongs = List.from(_playlist);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;

    try {
      // If no audio source is set, set it up
      if (_audioPlayer.audioSource == null && currentSong != null) {
        await _setAudioSource(currentSong!);
      }
      await _audioPlayer.play();
      await _updateNotification();
      notifyListeners();
    } catch (e) {
      _error = 'Error playing audio: $e';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      await _updateNotification();
      notifyListeners();
    } catch (e) {
      _error = 'Error pausing audio: $e';
      notifyListeners();
    }
  }

  // Stop playback completely
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _updateNotification();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to stop: $e';
      notifyListeners();
    }
  }

  // Set the current song by index
  Future<void> setCurrentSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      notifyListeners();
    }
  }

  // Set audio source for playback
  Future<void> _setAudioSource(Song song) async {
    try {
      final isRemote =
          song.url.startsWith('http://') || song.url.startsWith('https://');
      if (isRemote) {
        await _audioPlayer.setUrl(song.url);
      } else {
        await _audioPlayer.setFilePath(song.url);
      }
      await _updateNotification();
    } catch (e) {
      _error = 'Error setting audio source: $e';
      notifyListeners();
      rethrow;
    }
  }

  // Update the notification with current song info
  Future<void> _updateNotification() async {
    if (currentSong == null) return;

    try {
      final audioHandler = AudioNotificationService.audioHandler;
      if (audioHandler != null) {
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
    } catch (e) {
      debugPrint('Error updating notification: $e');
    }
  }

  // Helper method to extract metadata from audio file
  Future<Map<String, String>> _extractMetadata(File file) async {
    try {
      final fileName = path.basenameWithoutExtension(file.path);

      // Try different patterns in order of likelihood

      // Pattern 1: "Artist - Title"
      if (fileName.contains(' - ')) {
        final parts = fileName.split(' - ');
        if (parts.length >= 2) {
          return {
            'title': parts.sublist(1).join(' - ').trimAll(),
            'artist': parts[0].trimAll(),
            'album': 'Unknown Album',
          };
        }
      }

      // Pattern 2: "Title | Artist | Album"
      if (fileName.contains('|')) {
        final parts = fileName.split('|').map((s) => s.trimAll()).toList();
        if (parts.length >= 3) {
          return {
            'title': parts[0],
            'artist': parts[1],
            'album': parts[2],
          };
        } else if (parts.length == 2) {
          return {
            'title': parts[0],
            'artist': parts[1],
            'album': 'Unknown Album',
          };
        }
      }

      // Default: Use filename as title
      return {
        'title': fileName.trimAll(),
        'artist': 'Unknown Artist',
        'album': 'Unknown Album',
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting metadata from ${file.path}: $e');
      }
      return {};
    }
  }

  // Parse metadata from filename patterns
  Map<String, String> _parseMetadataFromFilename(String filePath) {
    final name = path.basenameWithoutExtension(filePath);
    final result = {
      'title': name,
      'artist': 'Unknown Artist',
      'album': 'Unknown Album',
    };

    // Try different patterns in order of specificity

    // Pattern 1: "Title | Artist | Album"
    if (name.contains('|')) {
      final parts = name.split('|').map((s) => s.trimAll()).toList();
      if (parts.length >= 3) {
        return {
          'title': parts[0],
          'artist': parts[1],
          'album': parts[2],
        };
      } else if (parts.length == 2) {
        return {
          'title': parts[0],
          'artist': parts[1],
          'album': 'Unknown Album',
        };
      }
    }

    // Pattern 2: "Artist - Title"
    if (name.contains(' - ')) {
      final parts = name.split(' - ').map((s) => s.trimAll()).toList();
      if (parts.length >= 2) {
        return {
          'title': parts.sublist(1).join(' - '),
          'artist': parts[0],
          'album': 'Unknown Album',
        };
      }
    }

    // Pattern 3: "Title - Artist"
    if (name.contains(' - ')) {
      final parts = name.split(' - ').map((s) => s.trimAll()).toList();
      if (parts.length >= 2) {
        return {
          'title': parts[0],
          'artist': parts.sublist(1).join(' - '),
          'album': 'Unknown Album',
        };
      }
    }

    return result;
  }

  // Helper method to find music files in a directory
  Future<List<FileSystemEntity>> _findMusicFiles(Directory dir) async {
    final List<FileSystemEntity> files = [];
    if (kDebugMode) {
      print('Scanning directory: ${dir.path}');
    }

    try {
      // First, check if directory exists
      if (!await dir.exists()) {
        if (kDebugMode) {
          print('Directory does not exist: ${dir.path}');
        }
        return [];
      }

      final List<FileSystemEntity> entities =
          await dir.list(recursive: true, followLinks: false).toList();
      if (kDebugMode) {
        print('Found ${entities.length} items in ${dir.path}');
      }

      for (var entity in entities) {
        try {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            final ext = path.split('.').last;
            if (['mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'].contains(ext)) {
              if (kDebugMode) {
                print('Found music file: ${entity.path}');
              }
              files.add(entity);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error processing entity ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scanning directory ${dir.path}: $e');
      }
    }
    return files;
  }

  // Load local music files
  Future<bool> loadLocalMusic() async {
    if (_isLoading) {
      if (kDebugMode) {
        print('loadLocalMusic: Already loading, skipping');
      }
      return false;
    }

    _isLoading = true;
    _error = null;
    _playlist.clear();
    _displayedSongs.clear();
    _filteredSongs.clear();
    notifyListeners();

    if (kDebugMode) {
      print('loadLocalMusic: Starting music scan');
    }

    try {
      // Check storage permission
      if (kDebugMode) {
        print('loadLocalMusic: Checking storage permission');
      }
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _error = 'Storage permission is required to access your music files.';
        _isLoading = false;
        notifyListeners();
        if (kDebugMode) {
          print('loadLocalMusic: Storage permission denied');
        }
        return false;
      }

      if (kDebugMode) {
        print('loadLocalMusic: Permission granted, starting directory scan');
      }

      // Common music directories to scan
      final List<Directory> directories = [
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/DCIM'),
        Directory('/storage/emulated/0/Notifications'),
        Directory('/storage/emulated/0/Ringtones'),
        Directory('/storage/emulated/0/Podcasts'),
        Directory('/storage/emulated/0/Audio'),
        Directory('/sdcard/Music'),
        Directory('/sdcard/Download'),
      ];

      if (kDebugMode) {
        print('loadLocalMusic: Checking external storage directory');
      }

      // Add external storage directory if it exists
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        if (kDebugMode) {
          print(
              'loadLocalMusic: Found external storage directory: ${externalDir.path}');
        }
        directories.add(externalDir);
      } else if (kDebugMode) {
        print('loadLocalMusic: No external storage directory found');
      }

      if (kDebugMode) {
        print(
            'loadLocalMusic: Scanning ${directories.length} directories for music files');
      }

      // Process all directories in parallel
      final List<FileSystemEntity> allMusicFiles = [];

      for (var dir in directories) {
        try {
          if (await dir.exists()) {
            if (kDebugMode) {
              print('loadLocalMusic: Scanning directory: ${dir.path}');
            }
            final files = await _findMusicFiles(dir);
            if (files.isNotEmpty) {
              allMusicFiles.addAll(files);
              if (kDebugMode) {
                print(
                    'loadLocalMusic: Found ${files.length} music files in ${dir.path}');
              }
            }
          } else if (kDebugMode) {
            print('loadLocalMusic: Directory does not exist: ${dir.path}');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error scanning directory ${dir.path}: $e');
          }
        }
      }

      // Convert FileSystemEntity to Song objects with metadata extraction
      final Set<String> uniquePaths = {}; // To avoid duplicates
      _playlist = [];

      // Process files one by one to handle async metadata extraction
      for (final file in allMusicFiles) {
        if (!uniquePaths.add(file.path)) continue; // Skip duplicates

        try {
          // Get metadata from file (if available)
          final fileMetadata = await _extractMetadata(File(file.path));
          // Parse metadata from filename as fallback
          final filenameMetadata = _parseMetadataFromFilename(file.path);

          // Use metadata if available, otherwise fall back to filename parsing
          final title = fileMetadata['title']?.isNotEmpty == true
              ? fileMetadata['title']!
              : filenameMetadata['title']!;

          final artist = fileMetadata['artist']?.isNotEmpty == true
              ? fileMetadata['artist']!
              : filenameMetadata['artist']!;

          final album = fileMetadata['album']?.isNotEmpty == true
              ? fileMetadata['album']!
              : filenameMetadata['album']!;

          _playlist.add(Song(
            id: file.path,
            title: title,
            artist: artist,
            album: album,
            url: file.path,
            duration: 0, // Will be updated later
          ));
        } catch (e) {
          if (kDebugMode) {
            print('Error processing file ${file.path}: $e');
          }
          // Add with basic info if there's an error
          _playlist.add(Song(
            id: file.path,
            title: path.basenameWithoutExtension(file.path),
            artist: 'Unknown Artist',
            album: 'Unknown Album',
            url: file.path,
            duration: 0,
          ));
        }
      }

      if (kDebugMode) {
        print('loadLocalMusic: Found ${_playlist.length} unique music files');
      }

      if (kDebugMode) {
        print(
            'loadLocalMusic: After deduplication, ${_playlist.length} unique files');
      }

      // Load durations in the background
      if (_playlist.isNotEmpty) {
        if (kDebugMode) {
          print('loadLocalMusic: Starting background duration loading');
        }
        _loadDurationsInBackground();
      } else if (kDebugMode) {
        print('loadLocalMusic: No music files found to load durations for');
      }

      _applySorting();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to load music: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _addSong(Song song) {
    if (!_playlist.any((s) => s.id == song.id)) {
      _playlist.add(song);
      _applySorting();
      notifyListeners();
    }
  }

  void filterSongs(String query) {
    if (query.isEmpty) {
      _filteredSongs.clear();
    } else {
      final searchQuery = query.toLowerCase();
      _filteredSongs = _playlist.where((song) {
        return song.title.toLowerCase().contains(searchQuery) ||
            song.artist.toLowerCase().contains(searchQuery);
      }).toList();
    }
    notifyListeners();
  }

  void clearSearch() {
    _filteredSongs.clear();
    notifyListeners();
  }

  void sortSongs({required SongSortOption sortBy, bool ascending = true}) {
    _currentSortOption = sortBy;
    _sortAscending = ascending;
    _applySorting();
    notifyListeners();
  }

  void _applySorting() {
    _displayedSongs = List<Song>.from(_playlist);

    _displayedSongs.sort((a, b) {
      int comparison;

      switch (_currentSortOption) {
        case SongSortOption.title:
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SongSortOption.artist:
          comparison = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case SongSortOption.duration:
          comparison = a.duration.compareTo(b.duration);
          break;
        case SongSortOption.dateAdded:
          // Assuming we have a dateAdded field in the Song model
          // If not, we can use the file's last modified date
          comparison = 0; // Default to no change if dateAdded is not available
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });
  }

  // Play a song
  Future<void> playSong(Song song) async {
    try {
      // Ensure the song exists in the playlist and set current index
      var index = _playlist.indexWhere((s) => s.id == song.id);
      if (index == -1) {
        _playlist.add(song);
        _displayedSongs = List.from(_playlist);
        index = _playlist.length - 1;
      }
      _currentIndex = index;

      // Set audio source based on URL type and start playback
      await _setAudioSource(song);
      await _audioPlayer.play();
      await _updateNotification();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to play song: $e';
      notifyListeners();
    }
  }

  // Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    notifyListeners();
  }

  // Request storage permission
  Future<bool> _requestStoragePermission() async {
    if (kDebugMode) {
      print('_requestStoragePermission: Starting permission request');
    }

    Permission permission;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+ needs READ_MEDIA_AUDIO
        permission = Permission.audio;
        if (kDebugMode) {
          print(
              '_requestStoragePermission: Android 13+ detected, using READ_MEDIA_AUDIO');
        }
      } else if (sdkInt >= 29) {
        // Android 10-12 needs READ_EXTERNAL_STORAGE
        permission = Permission.storage;
        if (kDebugMode) {
          print(
              '_requestStoragePermission: Android 10-12 detected, using READ_EXTERNAL_STORAGE');
        }
      } else {
        // Android 9 and below needs both READ and WRITE
        permission = Permission.storage;
        if (kDebugMode) {
          print(
              '_requestStoragePermission: Android 9 or below detected, using READ/WRITE_EXTERNAL_STORAGE');
        }
      }
    } else {
      // For non-Android platforms, use storage permission
      permission = Permission.storage;
    }

    // Check if we already have permission
    var status = await permission.status;
    if (kDebugMode) {
      print('_requestStoragePermission: Current permission status: $status');
    }

    // If permission is already granted, return true
    if (status.isGranted) {
      if (kDebugMode) {
        print('_requestStoragePermission: Permission already granted');
      }
      return true;
    }

    // If permission is permanently denied, open app settings
    if (status.isPermanentlyDenied) {
      if (kDebugMode) {
        print(
            '_requestStoragePermission: Permission permanently denied, opening app settings');
      }
      _error =
          'Storage permission is required to access music files. Please enable it in app settings.';
      notifyListeners();
      await openAppSettings();
      return false;
    }

    // Request the permission
    if (kDebugMode) {
      print('_requestStoragePermission: Requesting permission');
    }
    status = await permission.request();

    if (kDebugMode) {
      print('_requestStoragePermission: Permission request result: $status');
    }

    // Check the result
    if (status.isGranted) {
      if (kDebugMode) {
        print('_requestStoragePermission: Permission granted after request');
      }
      return true;
    } else if (status.isPermanentlyDenied) {
      if (kDebugMode) {
        print(
            '_requestStoragePermission: Permission permanently denied after request');
      }
      _error =
          'Storage permission is required to access music files. Please enable it in app settings.';
      notifyListeners();
      await openAppSettings();
    } else {
      if (kDebugMode) {
        print('_requestStoragePermission: Permission denied');
      }
      _error = 'Storage permission is required to access music files.';
      notifyListeners();
    }

    return status.isGranted;
  }

  /// Enrich songs with unknown/empty artist using MusicBrainz and persist to DB
  Future<void> enrichUnknownArtists() async {
    if (_isEnriching) return;
    _isEnriching = true;
    _enrichedCount = 0;
    notifyListeners();

    try {
      // Define unknown heuristics
      bool isUnknown(String? a) {
        if (a == null) return true;
        final t = a.trim().toLowerCase();
        return t.isEmpty || t == 'unknown' || t == 'unknown artist';
      }

      for (var i = 0; i < _playlist.length; i++) {
        final s = _playlist[i];
        if (!isUnknown(s.artist)) continue;

        try {
          final result = await _enrichment.enrichSong(s);
          if (result != null && result.updatedSong.artist.trim().isNotEmpty) {
            final enriched = result.updatedSong;
            // Update in memory
            _playlist[i] = enriched;
            _displayedSongs = List.from(_playlist);

            // Persist JSON cache
            await _saveSongsToStorage();

            // Update DB relations
            await DatabaseHelper().updateSongMetadataByFilePath(
              filePath: enriched.url,
              title: enriched.title,
              artistName: enriched.artist,
              album: enriched.album,
              genreName: result.genreName,
            );

            _enrichedCount++;
            // Notify occasionally to update any UI
            if (_enrichedCount % 3 == 0) {
              notifyListeners();
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Enrichment failed for ${s.title}: $e');
          }
        }
      }
    } finally {
      _isEnriching = false;
      notifyListeners();
    }
  }

  // Seek to a specific position in the current track
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to seek: $e';
      notifyListeners();
    }
  }

  // Play the previous track in the playlist
  Future<void> previous() async {
    if (_playlist.isEmpty) return;

    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) {
      _currentIndex = _playlist.length - 1;
    }

    await playSong(_playlist[_currentIndex]);
  }

  // Play the next track in the playlist
  Future<void> next() async {
    if (_playlist.isEmpty) return;

    _currentIndex = (_currentIndex + 1) % _playlist.length;
    await playSong(_playlist[_currentIndex]);
  }

  @override
  Future<void> _loadDurationsInBackground() async {
    // Process songs in chunks to avoid blocking the UI
    const chunkSize = 10;
    for (var i = 0; i < _playlist.length; i += chunkSize) {
      final end =
          (i + chunkSize < _playlist.length) ? i + chunkSize : _playlist.length;
      final chunk = _playlist.sublist(i, end);

      // Process each song in the current chunk
      for (var song in chunk) {
        try {
          final file = File(song.url);
          if (await file.exists()) {
            final audioPlayer = AudioPlayer();
            await audioPlayer.setFilePath(file.path);
            final duration = audioPlayer.duration ?? Duration.zero;
            await audioPlayer.dispose();

            // Update the song duration
            final index = _playlist.indexWhere((s) => s.id == song.id);
            if (index != -1) {
              _playlist[index] =
                  song.copyWith(duration: duration.inMilliseconds);
              // Notify listeners after each chunk is processed
              if (index % 5 == 0) {
                notifyListeners();
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error loading duration for ${song.title}: $e');
          }
        }
      }

      // Notify listeners after each chunk
      notifyListeners();
    }
  }
}
