import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import '../models/song.dart';
import '../services/audio_notification_service.dart';
import '../services/metadata_enrichment_service.dart';
import '../database/database_helper.dart';

extension StringExtension on String {
  String trimAll() => trim().replaceAll(RegExp(r'\s+'), ' ');
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
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  String? get error => _error;

  static const String _songsKey = 'cached_songs';

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
    } catch (_) {}
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
    } catch (_) {
      _playlist = [];
      _displayedSongs = [];
    }
  }

  bool isFavorite(String songId) {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    return idx != -1 && _playlist[idx].isFavorite;
  }

  Future<void> toggleFavorite(String songId) async {
    final idx = _playlist.indexWhere((s) => s.id == songId);
    if (idx == -1) return;
    final song = _playlist[idx];
    _playlist[idx] = song.copyWith(isFavorite: !song.isFavorite);
    _displayedSongs = List.from(_playlist);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;
    if (_audioPlayer.audioSource == null && currentSong != null) {
      await _setAudioSource(currentSong!);
    }
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    await _updateNotification();
    notifyListeners();
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
    try {
      if (song.url.startsWith('http')) {
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

  Future<void> _updateNotification() async {
    if (currentSong == null) return;
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
  }

  Future<Map<String, String>> _extractMetadata(File file) async {
    try {
      final fileName = path.basenameWithoutExtension(file.path);
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
      return {
        'title': fileName.trimAll(),
        'artist': 'Unknown Artist',
        'album': 'Unknown Album',
      };
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _parseMetadataFromFilename(String filePath) {
    final name = path.basenameWithoutExtension(filePath);
    final result = {
      'title': name,
      'artist': 'Unknown Artist',
      'album': 'Unknown Album',
    };
    if (name.contains('|')) {
      final parts = name.split('|').map((s) => s.trimAll()).toList();
      if (parts.length >= 3) {
        return {'title': parts[0], 'artist': parts[1], 'album': parts[2]};
      } else if (parts.length == 2) {
        return {'title': parts[0], 'artist': parts[1], 'album': 'Unknown Album'};
      }
    }
    if (name.contains(' - ')) {
      final parts = name.split(' - ').map((s) => s.trimAll()).toList();
      if (parts.length >= 2) {
        return {'title': parts.sublist(1).join(' - '), 'artist': parts[0], 'album': 'Unknown Album'};
      }
    }
    return result;
  }

  // Method to load local music files
  Future<void> loadLocalMusic() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      await scanLocalMusic();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Scans for music files in common directories
  Future<void> scanLocalMusic() async {
    try {
      // Clear existing playlist to avoid duplicates
      _playlist.clear();
      _displayedSongs.clear();
      _filteredSongs.clear();
      
      // Get all possible external storage directories
      final List<Directory> dirs = [];
      
      // Add standard music directories
      final musicDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (musicDirs != null) {
        dirs.addAll(musicDirs);
      }
      
      // Add downloads directory
      final downloadDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (downloadDirs != null) {
        dirs.addAll(downloadDirs.where((dir) => !dirs.any((d) => d.path == dir.path)));
      }
      
      // Add root of external storage
      final externalStorage = await getExternalStorageDirectory();
      if (externalStorage != null && !dirs.any((d) => d.path == externalStorage.path)) {
        dirs.add(Directory(externalStorage.path));
      }
      
      // Add common music directories
      final commonMusicDirs = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Media/Music',
        '/storage/emulated/0/Media/Audio',
        '/storage/emulated/0/audio',
      ];
      
      for (final path in commonMusicDirs) {
        final dir = Directory(path);
        if (await dir.exists() && !dirs.any((d) => d.path == dir.path)) {
          dirs.add(dir);
        }
      }
      
      debugPrint('Scanning in ${dirs.length} directories for music files...');
      
      // Process each directory sequentially to avoid overwhelming the system
      for (final dir in dirs) {
        await _processDirectory(dir);
      }
      
      // Deduplicate songs by path
      final uniqueSongs = <String, Song>{};
      for (final song in _playlist) {
        uniqueSongs[song.id] = song;
      }
      
      _playlist = uniqueSongs.values.toList();
      _displayedSongs = List.from(_playlist);
      _filteredSongs = List.from(_playlist);
      
      debugPrint('Finished scanning. Found ${_playlist.length} unique music files.');
      
      // Save the updated playlist
      await _saveSongsToStorage();
      
      // Notify listeners after all processing is complete
      notifyListeners();
    } catch (e) {
      debugPrint('Error during music scan: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Processes a single directory for music files
  Future<void> _processDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) {
        debugPrint('Directory does not exist: ${dir.path}');
        return;
      }
      
      debugPrint('Scanning directory: ${dir.path}');
      
      // Get all music files in this directory
      final files = await _findMusicFiles(dir);
      
      if (files.isEmpty) {
        debugPrint('No music files found in ${dir.path}');
        return;
      }
      
      debugPrint('Found ${files.length} music files in ${dir.path}');
      
      // Process files in smaller batches to avoid overwhelming the system
      const batchSize = 5;
      int processedCount = 0;
      
      for (var i = 0; i < files.length; i += batchSize) {
        // Check if we should stop processing
        if (_isLoading == false) {
          debugPrint('Scan cancelled by user');
          break;
        }
        
        final batch = files.sublist(
          i, 
          i + batchSize > files.length ? files.length : i + batchSize
        );
        
        // Process batch
        await Future.wait(batch.map((file) async {
          try {
            // Skip if already in playlist (check by path)
            if (_playlist.any((song) => song.id == file.path)) {
              debugPrint('Skipping duplicate: ${file.path}');
              return;
            }
            
            // Extract metadata
            final metadata = await _extractMetadata(File(file.path));
            
            // Create song object
            final song = Song(
              id: file.path,
              title: (metadata['title'] as String?)?.trim() ?? path.basenameWithoutExtension(file.path),
              artist: (metadata['artist'] as String?)?.trim() ?? 'Unknown Artist',
              album: (metadata['album'] as String?)?.trim() ?? 'Unknown Album',
              url: file.path,
              duration: 0, // Will be updated when played
            );
            
            // Add to playlist
            await addSong(song);
            processedCount++;
            
            // Update progress every 10 files
            if (processedCount % 10 == 0) {
              debugPrint('Processed $processedCount files...');
              notifyListeners();
            }
            
          } catch (e) {
            debugPrint('Error processing file ${file.path}: $e');
          }
        }));
      }
      
      debugPrint('Processed $processedCount files from ${dir.path}');
      
    } catch (e) {
      debugPrint('Error processing directory ${dir.path}: $e');
    }
  }

  /// Recursively finds all music files in the given directory
  Future<List<FileSystemEntity>> _findMusicFiles(Directory dir) async {
    final List<FileSystemEntity> files = [];
    if (!await dir.exists()) return [];
    
    try {
      // Common music file extensions (unique set)
      const musicExtensions = {
        // Audio formats
        'mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac', 'aiff', 'alac', 'opus',
        'wma', 'wv', 'ape', 'mka', 'm4b', 'm4p', 'mp4', 'm4r', 'aa',
        'aax', 'dsf', 'mpc', 'mpp', 'oga',
        // Less common formats
        '3gp', 'aa3', 'aif', 'aifc', 'amr', 'awb', 'dff', 'dts', 'gsm',
        'm3u', 'mid', 'midi', 'mogg', 'ra', 'ram', 'rm', 'snd', 'vox'
      };
      
      // Skip system directories that are unlikely to contain music
      final skipDirs = {'android', 'data', 'obb', 'system', 'cache', 'temp', 'tmp', 'lost+found'};
      
      // Process directory contents
      final lister = dir.list(recursive: true, followLinks: false);
      
      await for (FileSystemEntity entity in lister) {
        try {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            
            // Skip files in system directories
            if (path.split(Platform.pathSeparator).any((part) => skipDirs.contains(part.toLowerCase()))) {
              continue;
            }
            
            // Check file extension
            final ext = path.split('.').last;
            if (musicExtensions.contains(ext)) {
              files.add(entity);
            }
          }
        } catch (e) {
          debugPrint('Error processing ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory ${dir.path}: $e');
    }
    
    return files;
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    notifyListeners();
  }

  void cycleRepeatMode() {
    switch (_loopMode) {
      case LoopMode.off:
        setLoopMode(LoopMode.all);
        break;
      case LoopMode.all:
        setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        setLoopMode(LoopMode.off);
        break;
    }
  }

  void setLoopMode(LoopMode mode) {
    _loopMode = mode;
    _audioPlayer.setLoopMode(mode);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _audioPlayer.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _playlist.clear();
    _displayedSongs.clear();
    _filteredSongs.clear();
    _currentIndex = 0;
    await _saveSongsToStorage();
    notifyListeners();
  }

  void moveInQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;
    if (newIndex < 0 || newIndex >= _playlist.length) return;
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _currentIndex = index;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _playlist.removeAt(index);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<Song> enrichSongMetadata(Song song) async {
    _isEnriching = true;
    notifyListeners();
    final result = await _enrichment.enrichSong(song);
    if (result != null) {
      updateSong(result.updatedSong);
      return result.updatedSong;
    }
    _enrichedCount++;
    _isEnriching = false;
    notifyListeners();
    return song;
  }

  // Play the next song in the queue
  Future<void> next() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _playlist.length;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  // Play the previous song in the queue
  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) _currentIndex = _playlist.length - 1;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  // Toggle play/pause state
  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    await _updateNotification();
    notifyListeners();
  }

  // Load and play a specific song from the playlist
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

  // Apply sorting to the current playlist
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
        case SongSortOption.duration:
          compare = a.duration.compareTo(b.duration);
          break;
        case SongSortOption.dateAdded:
          compare = 0; // Assuming all songs are added at the same time
          break;
      }
      return ascending ? compare : -compare;
    });
    
    _displayedSongs = List.from(_playlist);
    notifyListeners();
  }

  // Filter songs based on search query
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
