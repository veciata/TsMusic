import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../models/song.dart';
import '../models/song_sort_option.dart';
import '../services/audio_notification_service.dart';
import '../database/database_helper.dart';

/// Main music provider class for managing music playback and library
class MusicProvider extends ChangeNotifier {
  // ===== CORE DEPENDENCIES =====
  final Player _player = Player();

  final DatabaseHelper _databaseHelper = DatabaseHelper();

  // ===== CONSTANTS =====
  static const List<String> audioExtensions = ['.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg', '.opus', '.m4b'];
  static const String _songsKey = 'cached_songs';
  static const int nowPlayingPlaylistId = 1;

  // ===== STATE VARIABLES =====
  bool _isLoading = false;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(false);
  List<Song> _playlist = [];
  List<Song> _displayedSongs = [];
  final List<Song> _filteredSongs = [];
  int _currentIndex = 0;
  String? _error;
  SongSortOption _currentSortOption = SongSortOption.title;
  bool _sortAscending = true;
  StreamSubscription<Duration>? _positionSubscription;
  final bool _isEnriching = false;
  final int _enrichedCount = 0;
  bool _shuffleEnabled = false;
  PlaylistMode _loopMode = PlaylistMode.none;

  // Auto-retry tracking
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const int _baseRetryDelay = 3; // seconds

  // Cache for songs to avoid repeated database queries
  static final Map<String, Song> _songsMap = {};
  static List<Song> get _cachedSongs => _songsMap.values.toList();

  // Track if database has been initialized
  bool _isDatabaseInitialized = false;

  // ===== GETTERS =====
  List<Song> get songs => _displayedSongs;
  List<Song> get filteredSongs => _filteredSongs;
  bool get isEnriching => _isEnriching;
  int get enrichedCount => _enrichedCount;
  bool get shuffleEnabled => _shuffleEnabled;
  PlaylistMode get loopMode => _loopMode;
  Stream<Duration> get positionStream => _player.stream.position;
  Stream<bool> get playingStream => _player.stream.playing;
  bool get isPlaying => _player.state.playing;
  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  Song? get currentSong => _playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;
  int? get currentIndex => (_playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length)
      ? _currentIndex
      : null;
  List<Song> get queue => List.unmodifiable(_playlist);
  List<Song> get allSongs => _playlist;
  List<Song> get youtubeSongs => _playlist.where((song) => song.hasTag('tsmusic')).toList();

  // Collection getters
  List<String> get albums {
    final albumSet = <String>{};
    if (songs.isNotEmpty) {
      for (final song in _playlist) {
        if (song.album != null && song.album!.isNotEmpty && song.album!.toLowerCase() != 'unknown album') {
          albumSet.add(song.album!);
        }
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

  // UI state getters
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  ValueNotifier<bool> get loadingNotifier => _loadingNotifier;
  String? get error => _error;

  // ===== INITIALIZATION =====
  MusicProvider() {
    // Listen to playlist mode changes
    _player.stream.playlistMode.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });

    // Listen to playback completion
    _player.stream.completed.listen((completed) async {
      if (completed) {
        if (_loopMode == PlaylistMode.single) {
          await _player.seek(Duration.zero);
          await _player.play();
        } else if (_loopMode == PlaylistMode.loop) {
          if (_currentIndex == _playlist.length - 1) {
            _currentIndex = 0;
          } else {
            _currentIndex++;
          }
          await _setAudioSource(_playlist[_currentIndex]);
          await _player.play();
          notifyListeners();
        } else if (_playlist.length > 1 && _currentIndex < _playlist.length - 1) {
          await next();
        }
      }
    });

    _initialize();
  }

  Future<void> _initialize() async {
    // Load Now Playing playlist first to show something immediately
    await _loadNowPlayingPlaylist();

    // Then load songs in the background
    loadLocalMusic().catchError((e) {
      debugPrint('Error during initialization: $e');
    });
  }

  // ===== PLAYBACK CONTROLS =====
  Future<void> play() async {
    if (_playlist.isEmpty) return;
    try {
      _isLoading = true;
      notifyListeners();
      await _player.play();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    notifyListeners();
  }

  // ===== PLAYBACK SETTINGS =====
  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    // Shuffle is handled manually in next() method
    notifyListeners();
  }

  void cycleRepeatMode() {
    // Cycle through: none -> single -> loop -> none
    if (_loopMode == PlaylistMode.none) {
      _loopMode = PlaylistMode.single;
    } else if (_loopMode == PlaylistMode.single) {
      _loopMode = PlaylistMode.loop;
    } else {
      _loopMode = PlaylistMode.none;
    }
    _player.setPlaylistMode(_loopMode);
    notifyListeners();
  }

  // ===== SORTING METHODS =====
  void setSortOption(SongSortOption option) {
    _currentSortOption = option;
    _applySorting();
    notifyListeners();
  }

  void toggleSortDirection() {
    _sortAscending = !_sortAscending;
    _applySorting();
    notifyListeners();
  }

  void _applySorting() {
    switch (_currentSortOption) {
      case SongSortOption.title:
        _displayedSongs.sort((a, b) => _sortAscending 
          ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case SongSortOption.artist:
        _displayedSongs.sort((a, b) {
          final artistA = a.artists.isNotEmpty ? a.artists.first.toLowerCase() : '';
          final artistB = b.artists.isNotEmpty ? b.artists.first.toLowerCase() : '';
          return _sortAscending 
            ? artistA.compareTo(artistB)
            : artistB.compareTo(artistA);
        });
        break;
      case SongSortOption.dateAdded:
        // Assuming newer songs are at the end of the list
        if (!_sortAscending) {
          _displayedSongs = _displayedSongs.reversed.toList();
        }
        break;
      case SongSortOption.album:
        // Sort by album name if available
        _displayedSongs.sort((a, b) {
          final albumA = a.album?.toLowerCase() ?? '';
          final albumB = b.album?.toLowerCase() ?? '';
          return _sortAscending 
            ? albumA.compareTo(albumB)
            : albumB.compareTo(albumA);
        });
        break;
      case SongSortOption.duration:
        // Sort by duration
        _displayedSongs.sort((a, b) => _sortAscending 
          ? a.duration.compareTo(b.duration)
          : b.duration.compareTo(a.duration));
        break;
    }
  }

  Future<void> refreshSongs() async {
    debugPrint('MusicProvider: refreshSongs() called');
    try {
      await _loadSongsFromDatabase();
      _displayedSongs = List.from(_playlist);
      _applySorting();
      notifyListeners();
      debugPrint('MusicProvider: refreshSongs() completed - ${_playlist.length} songs loaded');
    } catch (e) {
      debugPrint('Error refreshing songs: $e');
    }
  }

  // ===== AUTO-RETRY LOGIC =====
  String? _lastError;
  
  /// Attempts to load music with automatic retry on failure
  Future<void> loadLocalMusicWithRetry({bool forceRescan = false}) async {
    try {
      await loadLocalMusic(forceRescan: forceRescan);
      // Reset retry count on success
      _retryCount = 0;
      _lastError = null;
    } catch (e) {
      debugPrint('MusicProvider: Error loading music (attempt ${_retryCount + 1}/$_maxRetries): $e');
      _lastError = e.toString();
      
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delaySeconds = _baseRetryDelay * _retryCount;
        
        _error = 'Error: $_lastError\n\nRetrying in ${delaySeconds}s... (attempt $_retryCount/$_maxRetries)';
        notifyListeners();
        
        debugPrint('MusicProvider: Auto-retrying in ${delaySeconds} seconds...');
        await Future.delayed(Duration(seconds: delaySeconds));
        
        // Recursive retry
        await loadLocalMusicWithRetry(forceRescan: forceRescan);
      } else {
        _error = 'Error loading music:\n$_lastError\n\nPlease try again.';
        _retryCount = 0;
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
        debugPrint('MusicProvider: All retry attempts exhausted');
      }
    }
  }
  
  /// Manual retry - resets retry count and tries again
  Future<void> retryLoading() async {
    _retryCount = 0;
    _error = null;
    notifyListeners();
    await loadLocalMusicWithRetry(forceRescan: true);
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

  // ===== DATABASE OPERATIONS =====
  /// Loads music from database only (no scanning)
  Future<void> loadFromDatabaseOnly() async {
    if (_isLoading) return;

    try {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Loading music from database...';
      notifyListeners();

      // Clear current lists
      _playlist.clear();
      _displayedSongs.clear();

      // Load from database only
      await _loadSongsFromDatabase();

      // Update displayed songs
      _displayedSongs = List.from(_playlist);
      _isLoading = false;
      _loadingNotifier.value = false;

      if (_playlist.isEmpty) {
        // If no songs in database, automatically scan for music
        debugPrint('No songs in database, scanning for music...');
        await _scanLocalStorageForMusic();
      } else {
        _error = null;
      }

      notifyListeners();
    } catch (e) {
      _error = 'Error loading music from database: $e';
      _isLoading = false;
      _loadingNotifier.value = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Loads music with optional scanning for new files
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

        // Ensure cached songs are also in database for consistency
        await _ensureCachedSongsInDatabase();

        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null; // Clear error on success
        notifyListeners();
        return;
      }

      // Clear cache when forcing rescan
      if (forceRescan) {
        await _clearCache();
      }

      // First try to load from database
      await _loadSongsFromDatabase();

      // If we have songs, update UI
      if (_playlist.isNotEmpty) {
        _displayedSongs = List.from(_playlist);
        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null; // Clear error on success
        notifyListeners();

        // Check for new music in background
        _checkForNewMusicInBackground();
      } else {
        // If no songs in database, do a full scan
        await _scanLocalStorageForMusic();
        
        // Ensure all scanned songs are saved to database
        await _ensureCachedSongsInDatabase();
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

  // ===== PLAYLIST MANAGEMENT =====
  Future<void> playSong(Song song) async {
    var index = _playlist.indexWhere((s) => s.id == song.id);
    
    // If song not in playlist, add it
    if (index == -1) {
      _addSongIfNotExists(song);
      index = _playlist.indexWhere((s) => s.id == song.id);
    }
    
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      await _player.play();
      await _updateNotification();
      await _updateNowPlayingPlaylist();
      notifyListeners();
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
    await _player.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) _currentIndex = _playlist.length - 1;
    await _setAudioSource(_playlist[_currentIndex]);
    await _player.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  // ===== COLLECTION METHODS =====
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

  List<Song> getSongsByArtist(String artistName) => _playlist.where((song) => song.artists.any((artist) => artist == artistName)).toList();

  List<Song> getSongsByAlbum(String albumName, {String? artistName}) => _playlist.where((song) =>
      song.album == albumName &&
      (artistName == null || song.artists.any((artist) => artist == artistName))
    ).toList();

  List<String> getAlbumsByArtist(String artistName) {
    final albumSet = <String>{};
    for (final song in _playlist) {
      if (song.artists.any((artist) => artist == artistName) && song.album != null && song.album!.isNotEmpty) {
        albumSet.add(song.album!);
      }
    }
    return albumSet.toList()..sort();
  }

  // ===== SORTING AND FILTERING =====
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
            compare = a.dateAdded.compareTo(b.dateAdded);
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
        final List<Song> searchedSongs = [];
        for (final songData in results) {
          final songId = songData['id'] as int;
          final artistsData = await _databaseHelper.getArtistsForSong(songId);
          final artists = artistsData.map((row) => row['name'] as String).toList();
          
          searchedSongs.add(Song(
            id: songId,
            youtubeId: songData['youtube_id'] as String?,
            title: songData['title'] as String,
            url: songData['file_path'] as String,
            duration: songData['duration'] as int,
            artists: artists.isNotEmpty ? artists : ['Unknown Artist'],
            dateAdded: songData['created_at'] != null
                ? DateTime.parse(songData['created_at'] as String)
                : DateTime.now(),
          ),);
        }
        _displayedSongs = searchedSongs;
      } else {
        // Fallback to in-memory search if no results from database
        final lowerQuery = query.toLowerCase();
        _displayedSongs = _playlist.where((song) => song.title.toLowerCase().contains(lowerQuery) ||
                 song.artists.any((artist) => artist.toLowerCase().contains(lowerQuery)) ||
                 (song.album?.toLowerCase().contains(lowerQuery) ?? false)).toList();
      }
    } catch (e) {
      debugPrint('Error searching songs: $e');
      // Fallback to in-memory search on error
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _playlist.where((song) => song.title.toLowerCase().contains(lowerQuery) ||
               song.artists.any((artist) => artist.toLowerCase().contains(lowerQuery)) ||
               (song.album?.toLowerCase().contains(lowerQuery) ?? false)).toList();
    }

    notifyListeners();
  }

  // ===== PRIVATE HELPER METHODS =====
  /// Load songs from database with optimized queries
  Future<void> _loadSongsFromDatabase() async {
    debugPrint('🔍 _loadSongsFromDatabase called, _songsMap.isNotEmpty=${_songsMap.isNotEmpty}, _songsMap.length=${_songsMap.length}');
    
    if (_songsMap.isNotEmpty) {
      _playlist = _cachedSongs;
      debugPrint('⚡ Using cached songs: ${_playlist.length} songs');
      return;
    }

    try {
      // Get all songs in a single query
      final db = await _databaseHelper.database;

      // First, just count total songs in database
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM ${DatabaseHelper.tableSongs}');
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;
      debugPrint('📊 Total songs in database table: $totalCount');

      // Get all songs with their artists and genres in a single query
      final songsQuery = '''
        SELECT
          s.*,
          (SELECT GROUP_CONCAT(name, ',') FROM artists a
           INNER JOIN song_artist sa ON a.id = sa.artist_id
           WHERE sa.song_id = s.id) as artist_names,
          (SELECT GROUP_CONCAT(name, ',') FROM genres g
           INNER JOIN song_genre sg ON g.id = sg.genre_id
           WHERE sg.song_id = s.id) as genre_names
        FROM ${DatabaseHelper.tableSongs} s
      ''';

      final songs = await db.rawQuery(songsQuery);
      debugPrint('📊 SQL query returned ${songs.length} songs');

      // Clear current data
      _playlist.clear();
      _songsMap.clear();

      // Process all songs in a single batch
      for (final songData in songs) {
        try {
          // Parse artists
          final artistNamesString = songData['artist_names'] as String?;
          final artistNames = artistNamesString != null && artistNamesString.isNotEmpty
              ? artistNamesString
                  .split(',')
                  .where((name) => name.isNotEmpty && name != 'Unknown Artist')
                  .toSet()
                  .toList()
              : <String>[];

          final artists = artistNames.isNotEmpty ? artistNames : ['Unknown Artist'];

          // Parse genres/tags
          final tagsString = songData['genre_names'] as String?;
          final tags = tagsString != null && tagsString.isNotEmpty
              ? tagsString
                  .split(',')
                  .where((tag) => tag.isNotEmpty)
                  .toSet()
                  .toList()
              : <String>[];

          final song = Song(
            id: songData['id'] as int,
            youtubeId: songData['youtube_id'] as String?,
            title: songData['title'] as String? ?? 'Unknown Title',
            artists: artists,
            url: songData['file_path'] as String,
            duration: songData['duration'] as int? ?? 0,
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

  /// Load Now Playing playlist from database
  Future<void> _loadNowPlayingPlaylist() async {
    try {
      final songMaps = await _databaseHelper.getSongsInPlaylist(nowPlayingPlaylistId);
      // Clear current playlist and add songs from database
      _playlist.clear();
      _songsMap.clear(); // Clear the map when reloading the playlist
      
      for (final songData in songMaps) {
        final songId = songData['id'] as int;
        final artistsData = await _databaseHelper.getArtistsForSong(songId);
        final artists = artistsData.map((row) => row['name'] as String).toList();

        final song = Song(
          id: songId,
          youtubeId: songData['youtube_id'] as String?,
          title: songData['title'] as String? ?? 'Unknown Title',
          url: songData['file_path'] as String,
          duration: songData['duration'] as int? ?? 0,
          artists: artists.isNotEmpty ? artists : ['Unknown Artist'],
          dateAdded: songData['created_at'] != null
              ? DateTime.parse(songData['created_at'] as String)
              : DateTime.now(),
        );
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

  /// Update Now Playing playlist in database
  Future<void> _updateNowPlayingPlaylist() async {
    try {
      final songIds = _playlist.map((song) => song.id).where((id) => id > 0).toList();
      await _databaseHelper.updateNowPlayingPlaylist(songIds);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating Now Playing playlist: $e');
      }
    }
  }

  /// Helper method to add a song only if it doesn't exist
  void _addSongIfNotExists(Song song) {
    if (!_songsMap.containsKey(song.url)) {
      _songsMap[song.url] = song;
      _playlist.add(song);
    }
  }

  /// Public method to add a song to playlist (used by DownloadsScreen)
  void addSongToPlaylist(Song song) {
    _addSongIfNotExists(song);
    notifyListeners();
  }

  /// Set audio source for playback
  Future<void> _setAudioSource(Song song) async {
    final mediaPath = song.url.startsWith('/') ? 'file://${song.url}' : song.url;
    final media = Media(mediaPath);
    await _player.open(media);
    await _updateNotification();
  }

  /// Update notification with current song
  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      await audioHandler.setMedia(Media(currentSong!.url), song: currentSong);
      if (_player.state.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  /// Save songs to storage cache
  Future<void> _saveSongsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_songsKey, jsonEncode(_playlist.map((s) => s.toJson()).toList()));
  }

  /// Clear cache when forcing rescan
  Future<void> _clearCache() async {
    try {
      _playlist.clear();
      _songsMap.clear();
      _displayedSongs.clear();

      // Clear SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_songsKey);

      debugPrint('🗑️ CLEARED MUSIC CACHE');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Ensure cached songs are also saved to database for consistency
  Future<void> _ensureCachedSongsInDatabase() async {
    try {
      final db = await _databaseHelper.database;

      // Check which cached songs are missing from database
      final missingSongs = <Song>[];
      for (final song in _playlist) {
        final existingSongs = await db.query(
          DatabaseHelper.tableSongs,
          where: 'file_path = ?',
          whereArgs: [song.url],
        );

        if (existingSongs.isEmpty) {
          missingSongs.add(song);
        }
      }

      if (missingSongs.isNotEmpty) {
        debugPrint('📊 ENSURING ${missingSongs.length} CACHED SONGS ARE IN DATABASE');

        // Save missing songs to database
        await db.transaction((txn) async {
          for (final song in missingSongs) {
            try {
              // Insert song
              final songId = await txn.insert(
                DatabaseHelper.tableSongs,
                song.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );

              // Insert artists
              for (final artistName in song.artists) {
                if (artistName.isNotEmpty && artistName != 'Unknown Artist') {
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

              // Insert genres/tags
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
            } catch (e) {
              debugPrint('Error saving cached song ${song.title} to database: $e');
            }
          }
        });

        debugPrint('✅ ENSURED ${missingSongs.length} CACHED SONGS ARE IN DATABASE');
      }
    } catch (e) {
      debugPrint('Error ensuring cached songs in database: $e');
      // Don't rethrow - this is just for consistency
    }
  }

  /// Set current song for playback
  Future<void> setCurrentSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      notifyListeners();
    }
  }

  /// Update existing song
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

  // ===== SCANNING METHODS =====
  /// Public method to scan for new music files (can be called from settings)
  Future<void> scanForNewMusic() async {
    await loadLocalMusic(forceRescan: true);
  }

  /// Comprehensive music scanning with parallel processing and bulk database insertion
  Future<void> _scanLocalStorageForMusic({bool background = false}) async {
    if (!background) {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Scanning for music...';
      notifyListeners();
    }

    try {
      // First, check for deleted files and clean database
      await _cleanupDeletedSongs();

      final bool hasPermission = await _checkStoragePermission();

      if (!hasPermission) {
        _error = 'Storage permission is required to scan for music.';
        if (!background) {
          _isLoading = false;
          _loadingNotifier.value = false;
        }
        notifyListeners();
        return;
      }

      // Get comprehensive list of music directories to scan
      final musicDirectories = await _getAllMusicDirectories();

      debugPrint('🔍 SCANNING ${musicDirectories.length} DIRECTORIES FOR MUSIC FILES');
      debugPrint('Directories to scan:');
      for (final dir in musicDirectories) {
        debugPrint('  📁 $dir');
      }

      _error = 'Scanning all directories simultaneously...';
      if (!background) notifyListeners();

      // Scan all directories in parallel for maximum speed
      final scanResults = await _scanAllDirectoriesParallel(musicDirectories);

      final totalFilesFound = scanResults['totalFiles'] as int;
      final musicFiles = scanResults['files'] as List<File>;

      debugPrint('🎵 TOTAL MUSIC FILES FOUND: $totalFilesFound');

      if (totalFilesFound == 0) {
        debugPrint('❌ NO MUSIC FILES FOUND - CHECKING ALTERNATIVE LOCATIONS');
        // Try alternative scanning approach
        final alternativeFiles = await _scanAlternativeLocations();
        if (alternativeFiles.isNotEmpty) {
          musicFiles.addAll(alternativeFiles);
          debugPrint('✅ FOUND ${alternativeFiles.length} FILES IN ALTERNATIVE LOCATIONS');
        }
      }

      if (musicFiles.isEmpty) {
        _error = 'No music files found on device.';
        if (!background) {
          _isLoading = false;
          _loadingNotifier.value = false;
        }
        notifyListeners();
        return;
      }

      debugPrint('📊 PROCESSING ${musicFiles.length} MUSIC FILES...');

      // Process all files and add to database in one transaction
      await _processAndAddAllSongs(musicFiles, background);

      if (!background) {
        _isLoading = false;
        _loadingNotifier.value = false;
        if (_playlist.isEmpty) {
          _error = 'No valid music files found.';
        } else {
          _error = null;
          debugPrint('✅ SUCCESSFULLY ADDED ${_playlist.length} SONGS TO DATABASE');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ ERROR DURING MUSIC SCAN: $e');
      if (!background) {
        _error = 'Error scanning for music: $e';
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
      }
    }
  }

  /// Clean up deleted songs from database
  Future<void> _cleanupDeletedSongs() async {
    try {
      final db = await _databaseHelper.database;
      final allSongs = await db.query('songs');

      final List<int> songsToRemove = [];

      for (final songData in allSongs) {
        final filePath = songData['file_path'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final file = File(filePath);
          if (!await file.exists()) {
            songsToRemove.add(songData['id'] as int);
          }
        }
      }

      if (songsToRemove.isNotEmpty) {
        debugPrint('Removing ${songsToRemove.length} deleted songs from database');
        await db.delete(
          'songs',
          where: 'id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );

        await db.delete(
          'playlist_songs',
          where: 'song_id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );
      }
    } catch (e) {
      debugPrint('Error cleaning up deleted songs: $e');
    }
  }

  /// Check storage permissions
  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 33) {
        var status = await Permission.audio.status;
        if (!status.isGranted) status = await Permission.audio.request();
        return status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        final hasStorage = status.isGranted;
        if (hasStorage && sdkInt >= 30) {
          await Permission.manageExternalStorage.request();
        }
        return hasStorage;
      }
    } else {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Get comprehensive list of music directories to scan
  Future<List<String>> _getAllMusicDirectories() async {
    final musicDirectories = <String>{};

    // Try to get external storage directory dynamically
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final basePaths = [
          externalDir.path,
          '${externalDir.path}/Music',
          '${externalDir.path}/Download',
          '${externalDir.path}/Music/tsmusic',
        ];
        musicDirectories.addAll(basePaths);
      }
    } catch (e) {
      debugPrint('Error getting external storage directory: $e');
    }

    // Add standard Android paths - comprehensive list
    final standardPaths = [
      // Primary storage
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/sdcard/Music',
      '/sdcard/Download',
      // Alternative mount points
      '/mnt/sdcard/Music',
      '/mnt/sdcard/Download',

      // System media paths
      '/data/media/0/Music',
      '/data/media/0/Download',

      // TSMusic specific
      '/data/data/com.veciata.tsmusic/files',
    ];

    musicDirectories.addAll(standardPaths);

    // Remove duplicates and filter out null/empty paths
    final uniquePaths = musicDirectories.where((path) => path.isNotEmpty).toList();

    return uniquePaths;
  }

  /// Scan all directories in parallel for maximum speed
  Future<Map<String, dynamic>> _scanAllDirectoriesParallel(List<String> directories) async {
    final List<File> allMusicFiles = [];
    final Set<String> processedPaths = {};
    int totalFilesFound = 0;

    // Process directories in batches to avoid overwhelming the system
    const batchSize = 5;

    for (int i = 0; i < directories.length; i += batchSize) {
      final endIndex = (i + batchSize < directories.length) ? i + batchSize : directories.length;
      final batch = directories.sublist(i, endIndex);

      // Process each directory in this batch
      final futures = batch.map((dirPath) => _scanSingleDirectory(dirPath, processedPaths)).toList();

      try {
        final results = await Future.wait(futures);

        for (final result in results) {
          if (result != null) {
            allMusicFiles.addAll(result['files'] as List<File>);
            totalFilesFound += result['count'] as int;
          }
        }
      } catch (e) {
        debugPrint('Error in parallel scanning batch: $e');
      }
    }

    return {
      'files': allMusicFiles,
      'totalFiles': totalFilesFound,
    };
  }

  /// Scan a single directory for music files
  Future<Map<String, dynamic>?> _scanSingleDirectory(String dirPath, Set<String> processedPaths) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return null;

      final List<File> musicFiles = [];
      int fileCount = 0;

      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && !processedPaths.contains(entity.path)) {
          final ext = path.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            try {
              final stat = await entity.stat();
              // Lower minimum file size to catch more files
              if (stat.size > 512) { // Even smaller threshold
                musicFiles.add(entity);
                processedPaths.add(entity.path);
                fileCount++;
              }
            } catch (_) {
              // Skip files that can't be accessed
            }
          }
        }
      }

      if (fileCount > 0) {
        debugPrint('  📁 $dirPath: $fileCount files');
      }

      return {
        'files': musicFiles,
        'count': fileCount,
      };
    } catch (e) {
      debugPrint('  ❌ Error scanning $dirPath: $e');
      return null;
    }
  }

  /// Scan alternative locations when standard scanning fails
  Future<List<File>> _scanAlternativeLocations() async {
    final List<File> alternativeFiles = [];

    // Try some additional locations
    final alternativePaths = [
      '/storage',
      '/mnt',
      '/data',
      '/system',
    ];

    for (final basePath in alternativePaths) {
      try {
        final dir = Directory(basePath);
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (audioExtensions.contains(ext)) {
                try {
                  final stat = await entity.stat();
                  if (stat.size > 512) {
                    alternativeFiles.add(entity);
                    debugPrint('  🎵 Alternative location: ${entity.path}');
                  }
                } catch (_) {
                  // Skip inaccessible files
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('  ❌ Error scanning alternative path $basePath: $e');
      }
    }

    return alternativeFiles;
  }

  /// Process all music files and add them to database in a single transaction
  Future<void> _processAndAddAllSongs(List<File> musicFiles, bool background) async {
    debugPrint('🔄 PROCESSING ${musicFiles.length} MUSIC FILES...');

    // Clear existing data
    _playlist.clear();
    _songsMap.clear();

    // Get database connection
    final db = await _databaseHelper.database;

    // Process all files first, then add to database in one transaction
    final List<Song> validSongs = [];

    for (int i = 0; i < musicFiles.length; i++) {
      final file = musicFiles[i];

      if (i % 20 == 0) {
        _error = 'Processing ${i + 1} of ${musicFiles.length} files...';
        if (!background) notifyListeners();
      }

      try {
        final song = await _processMusicFile(file);
        if (song != null) {
          validSongs.add(song);
        }
      } catch (e) {
        debugPrint('Error processing ${file.path}: $e');
      }
    }

    debugPrint('✅ PROCESSED ${validSongs.length} VALID SONGS');

    if (validSongs.isEmpty) {
      return;
    }

    // Add all songs to database in a single transaction
    await db.transaction((txn) async {
      for (final song in validSongs) {
        try {
          // Insert song
          final songId = await txn.insert(
            DatabaseHelper.tableSongs,
            song.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Insert artists
          for (final artistName in song.artists) {
            if (artistName.isNotEmpty && artistName != 'Unknown Artist') {
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

          // Insert genres/tags
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
        } catch (e) {
          debugPrint('Error adding song ${song.title} to database: $e');
        }
      }
    });

    // Update in-memory playlist
    for (final song in validSongs) {
      _addSongIfNotExists(song);
    }

    _displayedSongs = List.from(_playlist);
    await _updateNowPlayingPlaylist();

    debugPrint('🎉 SUCCESSFULLY ADDED ${validSongs.length} SONGS TO DATABASE');
    
    // Ensure all songs are saved to database for consistency
    await _ensureCachedSongsInDatabase();
  }

  /// Helper method to get or create artist
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

  /// Helper method to get or create genre
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

  /// Process a single music file and extract metadata
  Future<Song?> _processMusicFile(File file) async {
    try {
      final fileName = path.basenameWithoutExtension(file.path);

      // Clean up filename
      String cleanFileName(String fileName) => fileName
            .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false), '')
            .replaceAll(RegExp(r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b(official|music|video|lyrics|hd|clear|audio)\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();

      final cleanedName = cleanFileName(fileName);
      String title = cleanedName;
      List<String> artistsList = ['Unknown Artist'];

      // Parse artist - title pattern
      final mainPattern = RegExp(r'^\s*(.*?)\s*[-–]\s*(.*?)\s*$');
      final match = mainPattern.firstMatch(fileName);

      if (match != null) {
        final String mainArtist = match.group(1)?.trim() ?? 'Unknown Artist';
        String rawTitle = match.group(2)?.trim() ?? fileName;

        artistsList = [mainArtist];

        // Handle featured artists
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

      // Get duration
      final duration = await _getAudioDuration(file.path);

      // Skip files with zero duration
      if (duration == Duration.zero) {
        debugPrint('Skipping file with zero duration: ${file.path}');
        return null;
      }

      // Create new song
      final isTSMusic = file.path.toLowerCase().contains('music/tsmusic') ||
                       file.path.toLowerCase().contains('tsmusic');

      final song = Song(
        id: file.path.hashCode,
        title: title.isNotEmpty ? title : path.basenameWithoutExtension(file.path),
        artists: artistsList,
        album: 'Unknown Album',
        url: file.path,
        duration: duration.inMilliseconds,
        tags: isTSMusic ? ['tsmusic'] : [],
      );

      return song;
    } catch (e) {
      debugPrint('Error processing music file ${file.path}: $e');
      return null;
    }
  }

  /// Get audio duration for a file
  Future<Duration> _getAudioDuration(String filePath) async {
    try {
      // First, check if file exists and is readable
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return Duration.zero;
      }

      final fileSize = await file.length();
      if (fileSize < 1024) { // File too small to be valid audio
        debugPrint('File too small to be valid audio: $filePath ($fileSize bytes)');
        return Duration.zero;
      }

      final audioPlayer = Player();
      try {
        // Set file path and wait for it to load
        await audioPlayer.open(Media(filePath));

        // Wait for metadata to load with timeout
        Duration? duration;
        int attempts = 0;
        const maxAttempts = 10;

        while (duration == null && attempts < maxAttempts) {
          duration = audioPlayer.state.duration;
          if (duration == null || duration == Duration.zero) {
            await Future.delayed(const Duration(milliseconds: 100));
            attempts++;
          }
        }

        if (duration == null) {
          debugPrint('Could not get duration for $filePath after $maxAttempts attempts');
          return Duration.zero;
        }

        return duration;
      } catch (e) {
        debugPrint('Error getting duration for $filePath: $e');

        // Handle specific error types
        if (e.toString().contains('Source error') || e.toString().contains('source')) {
          debugPrint('Source error for file: $filePath - file may be corrupted or in unsupported format');
          return Duration.zero;
        }

        if (e.toString().contains('Codec') || e.toString().contains('codec')) {
          debugPrint('Codec error for file: $filePath - unsupported codec');
          return Duration.zero;
        }

        // For other errors, try a shorter timeout
        try {
          await audioPlayer.open(Media(filePath));
          await Future.delayed(const Duration(milliseconds: 200));
          final duration = audioPlayer.state.duration;
          return duration ?? Duration.zero;
        } catch (retryError) {
          debugPrint('Retry failed for $filePath: $retryError');
          return Duration.zero;
        }
      } finally {
        try {
          await audioPlayer.dispose();
        } catch (_) {
          // Ignore dispose errors
        }
      }
    } catch (e) {
      debugPrint('Error accessing file $filePath: $e');
      return Duration.zero;
    }
  }

  // ===== BACKGROUND SCANNING =====
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

  // ===== CLEANUP METHODS =====
  @override
  void dispose() {
    _positionSubscription?.cancel();
    AudioNotificationService.dispose();
    _player.dispose();
    _loadingNotifier.dispose();
    super.dispose();
  }

  // ===== STUB METHODS =====
  bool isFavorite(String songId) => false;
  void toggleFavorite(String songId) {
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
      _player.seek(Duration.zero);
      _player.play();
      notifyListeners();
    }
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
}