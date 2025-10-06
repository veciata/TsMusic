import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
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
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  
  // Now Playing playlist ID
  int get nowPlayingPlaylistId => DatabaseHelper.nowPlayingPlaylistId;
  
  // Load songs from database with optimized queries
  Future<void> _loadSongsFromDatabase() async {
    if (_songsMap.isNotEmpty) {
      _playlist = _cachedSongs;
      return;
    }
    
    try {
      // Get all songs in a single query
      final db = await _databaseHelper.database;
      
      // Get all songs with their artists and genres in a single query
      final songsQuery = '''
        SELECT 
          s.*,
          GROUP_CONCAT(DISTINCT a.name, '|') as artist_names,
          GROUP_CONCAT(DISTINCT g.name, '|') as genre_names
        FROM ${DatabaseHelper.tableSongs} s
        LEFT JOIN ${DatabaseHelper.tableSongArtist} sa ON s.id = sa.song_id
        LEFT JOIN ${DatabaseHelper.tableArtists} a ON sa.artist_id = a.id
        LEFT JOIN ${DatabaseHelper.tableSongGenre} sg ON s.id = sg.song_id
        LEFT JOIN ${DatabaseHelper.tableGenres} g ON sg.genre_id = g.id
        WHERE s.playlist_id = ?
        GROUP BY s.id
      ''';
      
      final songs = await db.rawQuery(songsQuery, [nowPlayingPlaylistId]);
      
      // Clear current data
      _playlist.clear();
      _songsMap.clear();
      
      // Process all songs in a single batch
      for (final songData in songs) {
        try {
          // Parse artists
          final artistNames = (songData['artist_names'] as String? ?? '')
              .split('|')
              .where((name) => name.isNotEmpty && name != 'Unknown Artist')
              .toSet() // Remove duplicates
              .toList();
          
          final artists = artistNames.isNotEmpty ? artistNames : ['Unknown Artist'];
          
          // Parse genres/tags
          final tags = (songData['genre_names'] as String? ?? '')
              .split('|')
              .where((tag) => tag.isNotEmpty)
              .toSet() // Remove duplicates
              .toList();
          
          final song = Song(
            id: songData['id'].toString(),
            title: songData['title'] as String? ?? 'Unknown Title',
            artists: artists,
            album: songData['album'] as String? ?? 'Unknown Album',
            albumArtUrl: songData['album_art_url'] as String?,
            url: songData['file_path'] as String,
            duration: songData['duration'] as int? ?? 0,
            isFavorite: songData['is_favorite'] == 1,
            isDownloaded: songData['is_downloaded'] == 1,
            tags: tags,
            trackNumber: songData['track_number'] as int?,
            dateAdded: songData['created_at'] != null 
                ? DateTime.parse(songData['created_at'] as String)
                : DateTime.now(),
          );
          
          // Use URL as key to prevent duplicates
          if (!_songsMap.containsKey(song.url)) {
            _songsMap[song.url] = song;
            _playlist.add(song);
          }
        } catch (e) {
          debugPrint('Error loading song from database: $e');
        }
      }
      
      _displayedSongs = List.from(_playlist);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading songs from database: $e');
      rethrow;
    }
  }
  
  // Load Now Playing playlist from database
  Future<void> _loadNowPlayingPlaylist() async {
    try {
      final songs = await _databaseHelper.getSongsInPlaylist(nowPlayingPlaylistId);
      // Clear current playlist and add songs from database
      _playlist.clear();
      _songsMap.clear(); // Clear the map when reloading the playlist
      for (final songData in songs) {
        final song = Song.fromJson(Map<String, dynamic>.from(songData));
        _addSongIfNotExists(song);
      }
      _displayedSongs = List.from(_playlist);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading Now Playing playlist: $e');
      }
    }
  }
  
  // Update Now Playing playlist in database
  Future<void> _updateNowPlayingPlaylist() async {
    try {
      final songIds = _playlist.map((song) => int.tryParse(song.id) ?? 0).where((id) => id > 0).toList();
      await _databaseHelper.updateNowPlayingPlaylist(songIds);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating Now Playing playlist: $e');
      }
    }
  }

  static const List<String> audioExtensions = ['.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus', '.m4b', '.mp4'];
  static const String _songsKey = 'cached_songs';
  
  bool _isLoading = false;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(false);
  List<Song> _playlist = [];
  List<Song> _displayedSongs = [];
  List<Song> _filteredSongs = [];
  int _currentIndex = 0;
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
  List<Song> get allSongs => _songsMap.values.toList();
  List<Song> get youtubeSongs =>
      _playlist.where((song) => song.hasTag('tsmusic')).toList();

  List<String> get albums {
    final albumSet = <String>{};
    for (final song in _playlist) {
      if (song.album != null && song.album!.isNotEmpty && song.album!.toLowerCase() != 'unknown album') {
        albumSet.add(song.album!);
      }
    }
    return albumSet.toList()..sort((a, b) => a.compareTo(b));
  }

  List<String> get artists {
    final artistSet = <String>{};
    for (final song in _playlist) {
      for (final artist in song.artists) {
        if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') artistSet.add(artist);
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }

  String? getArtistImageUrl(String artistName) {
    final artistSongs = getSongsByArtist(artistName);
    if (artistSongs.isNotEmpty) {
      return artistSongs.first.albumArtUrl;
    }
    return null;
  }

  String? getAlbumArtUrl(String albumName, {String? artistName}) {
    for (final song in _playlist) {
      if (song.album == albumName && 
          (artistName == null || song.artists.any((artist) => artist == artistName))) {
        return song.albumArtUrl;
      }
    }
    return null;
  }

  List<Song> getSongsByArtist(String artistName) {
    return _playlist.where((song) => song.artists.any((artist) => artist == artistName)).toList();
  }

  List<Song> getSongsByAlbum(String albumName, {String? artistName}) {
    return _playlist.where((song) => 
      song.album == albumName && 
      (artistName == null || song.artists.any((artist) => artist == artistName))
    ).toList();
  }

  List<String> getAlbumsByArtist(String artistName) {
    final albumSet = <String>{};
    for (final song in _playlist) {
      if (song.artists.any((artist) => artist == artistName) && song.album != null && song.album!.isNotEmpty) {
        albumSet.add(song.album!);
      }
    }
    return albumSet.toList()..sort();
  }

  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  ValueNotifier<bool> get loadingNotifier => _loadingNotifier;
  String? get error => _error;

  NewMusicProvider() {
    _positionSubscription = _audioPlayer.positionStream.listen((_) => notifyListeners());
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
          if (_currentIndex == _playlist.length - 1) _currentIndex = 0;
          else _currentIndex++;
          await _setAudioSource(_playlist[_currentIndex]);
          await _audioPlayer.play();
          await _updateNotification();
          notifyListeners();
        } else if (_playlist.length > 1 && _currentIndex < _playlist.length - 1) {
          await next();
        }
      }
    });

    _initialize();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    AudioNotificationService.dispose();
    _audioPlayer.dispose();
    _loadingNotifier.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Load Now Playing playlist first to show something immediately
    await _loadNowPlayingPlaylist();
    
    // Then load songs in the background
    loadLocalMusic().catchError((e) {
      debugPrint('Error during initialization: $e');
    });
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;
    try {
      _isLoading = true;
      notifyListeners();
      await _audioPlayer.play();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  Future<void> addSong(Song song) async {
    final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _playlist[existingIndex] = song;
      _displayedSongs = List.from(_playlist);
      await _saveSongsToStorage();
      notifyListeners();
      return;
    }

    final db = await _databaseHelper.database;
    final existingSongs = await db.query(
      DatabaseHelper.tableSongs,
      where: 'id = ?',
      whereArgs: [song.id],
    );

    if (existingSongs.isNotEmpty) return;

    _addSongIfNotExists(song);
    _displayedSongs = List.from(_playlist);

    await db.transaction((txn) async {
      final songId = await txn.insert(
        DatabaseHelper.tableSongs,
        song.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final artistName in song.artists) {
        if (artistName.isNotEmpty) {
          final artistId = await _getOrCreateArtist(txn, artistName);
          await txn.insert(
            DatabaseHelper.tableSongArtist,
            {
              'song_id': songId,
              'artist_id': artistId,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      for (final tag in song.tags) {
        if (tag.isNotEmpty) {
          final genreId = await _getOrCreateGenre(txn, tag);
          await txn.insert(
            DatabaseHelper.tableSongGenre,
            {
              'song_id': songId,
              'genre_id': genreId,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });

    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<int> _getOrCreateArtist(DatabaseExecutor txn, String artistName) async {
    final existingArtist = await txn.query(
      DatabaseHelper.tableArtists,
      where: '${DatabaseHelper.columnName} = ?',
      whereArgs: [artistName],
    );

    if (existingArtist.isNotEmpty) {
      return existingArtist.first[DatabaseHelper.columnId] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableArtists,
      {'name': artistName, 'created_at': DateTime.now().toIso8601String()},
    );
  }

  Future<int> _getOrCreateGenre(DatabaseExecutor txn, String genreName) async {
    final existingGenre = await txn.query(
      DatabaseHelper.tableGenres,
      where: '${DatabaseHelper.columnName} = ?',
      whereArgs: [genreName],
    );

    if (existingGenre.isNotEmpty) {
      return existingGenre.first[DatabaseHelper.columnId] as int;
    }

    return await txn.insert(
      DatabaseHelper.tableGenres,
      {'name': genreName, 'created_at': DateTime.now().toIso8601String()},
    );
  }

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      await _updateNowPlayingPlaylist();
      notifyListeners();
    }
  }

  Future<void> clearQueue() async {
    _playlist.clear();
    _displayedSongs.clear();
    await _updateNowPlayingPlaylist();
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
    _updateNowPlayingPlaylist();
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

  bool isFavorite(String songId) => false;

  void toggleFavorite(String songId) {
    notifyListeners();
  }

  Future<Duration> _getAudioDuration(String filePath) async {
    try {
      final audioPlayer = AudioPlayer();
      try {
        await audioPlayer.setFilePath(filePath);
        await Future.delayed(const Duration(milliseconds: 50)); // Small delay to allow metadata to load
        return audioPlayer.duration ?? Duration.zero;
      } finally {
        await audioPlayer.dispose();
      }
    } catch (e) {
      debugPrint('Error getting duration for $filePath: $e');
      return Duration.zero;
    }
  }

  // Cache for songs to avoid repeated database queries
  static final Map<String, Song> _songsMap = {}; // Using map to prevent duplicates by file path
  static List<Song> get _cachedSongs => _songsMap.values.toList();
  
  // Track if database has been initialized
  bool _isDatabaseInitialized = false;

  // Helper method to update songs map and playlist
  void _updateSongsList(List<Song> newSongs) {
    _songsMap.clear();
    _playlist.clear();
    for (final song in newSongs) {
      _addSongIfNotExists(song);
    }
  }
  
  /// Loads music from database first, then checks for new music in background
  /// Refreshes the music library, checking for new and deleted files
  Future<void> refreshLibrary() async {
    await loadLocalMusic(forceRescan: true);
  }
  
  Future<void> loadLocalMusic({bool forceRescan = false}) async {
    if (_isLoading) return;
    
    try {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Loading music...';
      notifyListeners();

      // Clear current lists
      _playlist.clear();
      _displayedSongs.clear();
      
      // If we have cached songs and not forcing rescan, use them
      if (_songsMap.isNotEmpty && !forceRescan) {
        _playlist = _cachedSongs;
        _displayedSongs = List.from(_playlist);
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
        return;
      }
      
      // First try to load from database
      await _loadSongsFromDatabase();
      
      // If we have songs, update UI
      if (_playlist.isNotEmpty) {
        _displayedSongs = List.from(_playlist);
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
        
        // Check for new music in background
        _checkForNewMusicInBackground();
      } else {
        // If no songs in database, do a full scan
        await _scanLocalStorageForMusic();
      }
      
    } catch (e) {
      _error = 'Error loading music: $e';
      _isLoading = false;
      _loadingNotifier.value = false;
      notifyListeners();
      
      // Try to recover by forcing a rescan
      if (_playlist.isEmpty) {
        await _scanLocalStorageForMusic();
      }
    } finally {
      _isLoading = false;
      _loadingNotifier.value = false;
      notifyListeners();
    }
  }
  
  /// Checks for new music files in the background without blocking the UI
  Future<void> _checkForNewMusicInBackground() async {
    try {
      // Skip if we just did a full scan
      if (_isDatabaseInitialized) return;
      
      _isDatabaseInitialized = true;
      
      // Check if we need to rescan for new music (e.g., first run or after a while)
      final prefs = await SharedPreferences.getInstance();
      final lastScanTime = prefs.getInt('last_music_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneDayInMs = 24 * 60 * 60 * 1000;
      
      if (now - lastScanTime > oneDayInMs || _cachedSongs.isEmpty) {
        // Do a background scan for new music
        await _scanLocalStorageForMusic(background: true);
        await prefs.setInt('last_music_scan', now);
      }
    } catch (e) {
      debugPrint('Background music check failed: $e');
    }
  }


  // Helper method to add a song only if it doesn't exist
  void _addSongIfNotExists(Song song) {
    if (!_songsMap.containsKey(song.url)) {
      _songsMap[song.url] = song;
      _playlist.add(song);
    }
  }

  Future<void> _scanLocalStorageForMusic({bool background = false}) async {
    if (!background) {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Scanning for music...';
      notifyListeners();
    }
    
    try {
      // Clear current data
      _playlist.clear();
      _songsMap.clear();
      _displayedSongs.clear();
      
      // First, check for deleted files
      final db = await _databaseHelper.database;
      final allSongs = await db.query('songs');
      
      // Create a list to store IDs of songs that no longer exist
      final List<int> songsToRemove = [];
      
      // Check each song if it still exists on the device
      for (final songData in allSongs) {
        final file = File(songData['url'] as String);
        if (!await file.exists()) {
          songsToRemove.add(songData['id'] as int);
        }
      }
      
      // Remove deleted songs from the database
      if (songsToRemove.isNotEmpty) {
        await db.delete(
          'songs',
          where: 'id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );
        
        // Also remove from playlist_songs
        await db.delete(
          'playlist_songs',
          where: 'song_id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );
      }
    } catch (e) {
      debugPrint('Error checking for deleted files: $e');
      // Continue with normal scanning even if there was an error
    }
    
    bool hasPermission = false;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 33) {
        var status = await Permission.audio.status;
        if (!status.isGranted) status = await Permission.audio.request();
        hasPermission = status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        hasPermission = status.isGranted;
        if (hasPermission && sdkInt >= 30) await Permission.manageExternalStorage.request();
      }
    } else {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      hasPermission = status.isGranted;
    }

    if (!hasPermission) {
      _error = 'Storage permission is required to scan for music.';
      _isLoading = false;
      _loadingNotifier.value = false;
      notifyListeners();
      return;
    }

    _error = 'Scanning for music files...';
    notifyListeners();

    final musicDirectories = <String>[];
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        musicDirectories.add(externalDir.path);
        musicDirectories.add('${externalDir.path}/Music');
        musicDirectories.add('${externalDir.path}/Download');
        musicDirectories.add('${externalDir.path}/media');
      }
    } catch (_) {}

    musicDirectories.addAll([
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/sdcard/Music',
      '/sdcard/Download',
      '/storage/emulated/0/TSMusic',
    ]);

    final List<File> musicFiles = [];
    final Set<String> processedPaths = {};
    int totalFilesFound = 0;

    for (final dirPath in musicDirectories) {
      if (!_isLoading) break;
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final stream = dir.list(recursive: true, followLinks: false);
          await for (final entity in stream) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (audioExtensions.contains(ext) && !processedPaths.contains(entity.path)) {
                try {
                  final stat = await entity.stat();
                  if (stat.size > 10 * 1024) {
                    musicFiles.add(entity);
                    processedPaths.add(entity.path);
                    totalFilesFound++;
                    if (totalFilesFound % 10 == 0) {
                      _error = 'Found $totalFilesFound songs...';
                      notifyListeners();
                    }
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }

    final List<Song> songs = [];
    for (int i = 0; i < musicFiles.length; i++) {
      if (!_isLoading) break;
      final file = musicFiles[i];
      final fileName = path.basenameWithoutExtension(file.path);

      if (i % 5 == 0) {
        _error = 'Processing ${i + 1} of ${musicFiles.length} songs...';
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 1));
      }

      try {
        String cleanFileName(String fileName) {
          return fileName
              .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false), '')
              .replaceAll(RegExp(r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps', caseSensitive: false), '')
              .replaceAll(RegExp(r'\b(official|music|video|lyrics|hd|clear)\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
        }

        final cleanedName = cleanFileName(fileName);
        String title = cleanedName;
        List<String> artistsList = ['Unknown Artist'];

        final mainPattern = RegExp(r'^\s*(.*?)\s*[-–]\s*(.*?)\s*$');
        final match = mainPattern.firstMatch(fileName);

        if (match != null) {
          String mainArtist = match.group(1)?.trim() ?? 'Unknown Artist';
          String rawTitle = match.group(2)?.trim() ?? fileName;

          artistsList = [mainArtist];

          String? featuredArtists;
          final featPattern = RegExp(r'^(.*?)\s*(?:ft\.?|feat\.?|featuring)\s+(.+)$', caseSensitive: false);
          final featMatch = featPattern.firstMatch(rawTitle);

          if (featMatch != null) {
            rawTitle = featMatch.group(1)?.trim() ?? rawTitle;
            featuredArtists = featMatch.group(2)?.trim();
          }

          List<String> featuredList = [];
          if (featuredArtists != null && featuredArtists.isNotEmpty) {
            featuredList = featuredArtists
                .split(RegExp(r'\s*(?:,|&|and|\+)\s*', caseSensitive: false))
                .map((a) => a.trim())
                .where((a) => a.isNotEmpty)
                .toList();
          }
          artistsList.addAll(featuredList);

          title = rawTitle
              .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false), '')
              .replaceAll(RegExp(r'(?:ft\.?|feat\.?|featuring)\s+.+$', caseSensitive: false), '')
              .replaceAll(RegExp(r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps', caseSensitive: false), '')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
        }

        // Get duration without blocking the main thread
        final duration = await _getAudioDuration(file.path);
        
        // Check if this song is already in the playlist (from database)
        final existingIndex = _playlist.indexWhere((s) => s.url == file.path);
        
        if (existingIndex == -1) {
          // Check if the song is in the music/tsmusic directory
          final isTSMusic = file.path.toLowerCase().contains('music/tsmusic');
          
          final song = Song(
            id: '${file.path}_${(await file.lastModified()).millisecondsSinceEpoch}',
            title: title,
            artists: artistsList,
            album: 'Unknown Album',
            albumArtUrl: null,
            url: file.path,
            duration: duration.inMilliseconds,
            tags: isTSMusic ? ['tsmusic'] : [],
          );

          songs.add(song);
          await addSong(song);
        }
      } catch (_) {}
    }

    for (final song in songs) {
      _addSongIfNotExists(song);
    }
    _displayedSongs = List.from(_playlist);
    await _updateNowPlayingPlaylist();
    _isLoading = false;
    if (_playlist.isEmpty) _error = 'No music files found.';
    notifyListeners();
  }

  Future<void> updateSong(Song updatedSong) async {
    final index = _playlist.indexWhere((song) => song.id == updatedSong.id);
    if (index != -1) {
      _playlist[index] = updatedSong;
      _displayedSongs = List.from(_playlist);
      await _saveSongsToStorage();
      await _updateNowPlayingPlaylist();
      notifyListeners();
    }
  }

  Future<void> _saveSongsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_songsKey, jsonEncode(_playlist.map((s) => s.toJson()).toList()));
  }

  Future<void> loadSongsFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final songsJson = prefs.getString(_songsKey);
    if (songsJson != null) {
      final List<dynamic> jsonList = jsonDecode(songsJson);
      _playlist = jsonList.map((json) => Song.fromJson(json)).toList();
      _displayedSongs = List.from(_playlist);
      await _updateNowPlayingPlaylist();
      notifyListeners();
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
    if (song.url.startsWith('http')) await _audioPlayer.setUrl(song.url);
    else await _audioPlayer.setFilePath(song.url);
    await _updateNotification();
  }

  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      await audioHandler.setAudioSource(AudioSource.uri(Uri.parse(currentSong!.url)), song: currentSong);
      if (_audioPlayer.playing) await audioHandler.play();
      else await audioHandler.pause();
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_shuffleEnabled) {
      int nextIndex = _currentIndex;
      final random = Random();
      while (nextIndex == _currentIndex && _playlist.length > 1) nextIndex = random.nextInt(_playlist.length);
      _currentIndex = nextIndex;
    } else _currentIndex = (_currentIndex + 1) % _playlist.length;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) _currentIndex = _playlist.length - 1;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) await _audioPlayer.pause();
    else await _audioPlayer.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<void> playSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      await _audioPlayer.play();
      await _updateNotification();
      await _updateNowPlayingPlaylist();
      notifyListeners();
    }
  }

  Future<void> sortSongs({required SongSortOption sortBy, bool ascending = true}) async {
    try {
      _currentSortOption = sortBy;
      _sortAscending = ascending;
      
      // Sort the songs
      final sortedSongs = _songsMap.values.toList()..sort((a, b) {
        int compare;
        switch (sortBy) {
          case SongSortOption.title:
            compare = a.title.compareTo(b.title);
            break;
          case SongSortOption.artist:
            final artistA = a.artists.isNotEmpty ? a.artists.first : '';
            final artistB = b.artists.isNotEmpty ? b.artists.first : '';
            compare = artistA.compareTo(artistB);
            break;
          case SongSortOption.album:
            compare = (a.album ?? '').compareTo(b.album ?? '');
            break;
          case SongSortOption.duration:
            compare = a.duration.compareTo(b.duration);
            break;
          case SongSortOption.dateAdded:
            compare = (a.dateAdded ?? DateTime.now()).compareTo(b.dateAdded ?? DateTime.now());
            break;
        }
        return ascending ? compare : -compare;
      });
      
      // Update the playlist with sorted songs
      _playlist = sortedSongs;
      
      // Update the database in the background
      try {
        final db = await _databaseHelper.database;
        await db.transaction((txn) async {
          // Clear and rebuild the playlist in the database
          await txn.delete(
            'playlist_songs',
            where: 'playlist_id = ?',
            whereArgs: [nowPlayingPlaylistId],
          );
          
          // Re-add all songs in the new order
          for (int i = 0; i < _playlist.length; i++) {
            await txn.insert(
              'playlist_songs',
              {
                'playlist_id': nowPlayingPlaylistId,
                'song_id': _playlist[i].id,
                'position': i,
              },
            );
          }
        });
      } catch (e) {
        debugPrint('Error saving sort order: $e');
        // Don't rethrow, as the in-memory sort still worked
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error sorting songs: $e');
      rethrow;
    }
  }

  Future<void> filterSongs(String query) async {
    if (query.isEmpty) {
      _displayedSongs = List.from(_playlist);
      notifyListeners();
      return;
    }
    
    try {
      // First try database search for more accurate results
      final results = await _databaseHelper.searchSongs(query);
      if (results.isNotEmpty) {
        _displayedSongs = results.map((e) => Song.fromJson(e)).toList();
      } else {
        // Fallback to in-memory search if no results from database
        final lowerQuery = query.toLowerCase();
        _displayedSongs = _playlist.where((song) {
          return song.title.toLowerCase().contains(lowerQuery) ||
                 song.artists.any((artist) => artist.toLowerCase().contains(lowerQuery)) ||
                 (song.album?.toLowerCase().contains(lowerQuery) ?? false);
        }).toList();
      }
    } catch (e) {
      debugPrint('Error searching songs: $e');
      // Fallback to in-memory search on error
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _playlist.where((song) {
        return song.title.toLowerCase().contains(lowerQuery) ||
               song.artists.any((artist) => artist.toLowerCase().contains(lowerQuery)) ||
               (song.album?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    }
    
    notifyListeners();
  }
}
