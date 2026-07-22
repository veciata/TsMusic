import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/models/playlist_item.dart';
import 'package:tsmusic/models/storage_type.dart';
import 'package:tsmusic/services/audio_notification_service.dart';
import 'package:tsmusic/services/home_widget_service.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/services/thumbnail_service.dart';
import 'package:tsmusic/services/youtube_service.dart';

/// Main music provider class for managing music playback and library
class MusicProvider extends ChangeNotifier with WidgetsBindingObserver {
  // ===== CORE DEPENDENCIES =====
  final Player _player = Player();

  YouTubeService? _youTubeService;

  final DatabaseHelper _databaseHelper = DatabaseHelper();

  VoidCallback? _onWidgetUpdateNeeded;

  set onWidgetUpdateNeeded(VoidCallback callback) {
    _onWidgetUpdateNeeded = callback;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _onWidgetUpdateNeeded?.call();
  }

  void setYouTubeService(YouTubeService service) {
    _youTubeService = service;
    service.stopOtherPlayerCallback = () {
      if (_playlist.isNotEmpty && currentSong != null) {
        stop();
      }
    };
    // ignore: cascade_invocations
    service.localSongsCallback = () => librarySongs;
    // ignore: cascade_invocations
    service.addListener(_onYouTubeServiceStateChanged);
  }

  void _onYouTubeServiceStateChanged() {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler == null) return;

    final audio = _youTubeService?.currentAudio;
    final isOnlinePlaying = _youTubeService?.isPlaying ?? false;

    if (audio != null) {
      final song = Song(
        id: -1,
        youtubeId: audio.id,
        title: audio.title,
        artists: audio.artists.isNotEmpty ? audio.artists : [audio.author],
        album: 'YouTube',
        duration: audio.duration?.inMilliseconds ?? 0,
        albumArtUrl: audio.thumbnailUrl,
        url: audio.audioUrl ?? '',
        storageType: StorageType.remote,
      );
      if (!audioHandler.isOnlineMode) {
        audioHandler.setOnlineMode(
          online: true,
          onPlay: () => _youTubeService?.play(),
          onPause: () => _youTubeService?.pause(),
          onStop: _stopOnlineAndResumeLocal,
        );
      }
      audioHandler.setOnlineMedia(song, isPlaying: isOnlinePlaying);
    } else {
      if (audioHandler.isOnlineMode) {
        audioHandler.setOnlineMode(online: false);
        if (currentSong != null) {
          _updateNotification();
          HomeWidgetService.updatePlayerWidget(
            currentSong: currentSong,
            isPlaying: _player.state.playing,
            isOnlinePlaying: false,
          );
        }
      }
    }
  }

  Future<void> _stopOnlineAndResumeLocal() async {
    await _youTubeService?.stop();
    final audioHandler = AudioNotificationService.audioHandler;
    audioHandler?.setOnlineMode(online: false);

    final activePlaylist = _getActivePlaylist();
    if (activePlaylist.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < activePlaylist.length) {
      await _setAudioSource(activePlaylist[_currentIndex]);
      await _player.play();
      await _updateNotification();
      if (!_isUsingTempPlaylist) {
        await _updateNowPlayingPlaylist();
      }
      requestThumbnail(activePlaylist[_currentIndex], priority: 0);
    }
    notifyListeners();
  }

  // ===== CONSTANTS =====
  static const List<String> audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.opus',
    '.m4b',
  ];
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

  // ===== THUMBNAIL LAZY LOADING =====
  ThumbnailService? _thumbnailService;
  final Set<String> _thumbnailLoadingIds = {};
  bool _thumbnailBgStarted = false;

  // Auto-retry tracking
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const int _baseRetryDelay = 3; // seconds

  // Last played song for resume functionality
  Song? _lastPlayedSong;
  static const String _lastPlayedSongKey = 'last_played_song';

  // ===== LIFECYCLE / RESUME STATE =====
  static const String _resumeIndexKey = 'resume_current_index';
  static const String _resumePositionKey = 'resume_position_ms';
  static const String _resumeShuffleKey = 'resume_shuffle';
  static const String _resumeLoopModeKey = 'resume_loop_mode';
  static const String _resumeUsingTempPlaylistKey =
      'resume_using_temp_playlist';
  static const String _resumeTempPlaylistIdsKey = 'resume_temp_playlist_ids';
  static const String _resumePlaylistIdsKey = 'resume_playlist_ids';
  bool _hasRestoredState = false;

  // Cache for songs to avoid repeated database queries
  static final Map<String, Song> _songsMap = {};
  static List<Song> get _cachedSongs => _songsMap.values.toList();
  List<Song> get librarySongs => _songsMap.values.toList();

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
  Song? get currentSong {
    final List<Song> activePlaylist = _isUsingTempPlaylist
        ? _tempPlaylist
        : _playlist;
    return activePlaylist.isNotEmpty &&
            _currentIndex >= 0 &&
            _currentIndex < activePlaylist.length
        ? activePlaylist[_currentIndex]
        : null;
  }

  int? get currentIndex {
    final List<Song> activePlaylist = _isUsingTempPlaylist
        ? _tempPlaylist
        : _playlist;
    return (activePlaylist.isNotEmpty &&
            _currentIndex >= 0 &&
            _currentIndex < activePlaylist.length)
        ? _currentIndex
        : null;
  }

  List<Song> get queue => _isUsingTempPlaylist
      ? List.unmodifiable(_tempPlaylist)
      : List.unmodifiable(_playlist);
  List<Song> get allSongs => _isUsingTempPlaylist ? _tempPlaylist : _playlist;
  List<Song> get youtubeSongs =>
      _playlist.where((song) => song.hasTag('tsmusic')).toList();

  List<Song> get onlinePlaylist {
    final yt = _youTubeService;
    if (yt == null) return [];
    return yt.onlinePlaylist
        .map(
          (a) => Song(
            id: -1,
            youtubeId: a.id,
            title: a.title,
            artists: a.artists.isNotEmpty ? a.artists : [a.author],
            album: 'YouTube',
            duration: a.duration?.inMilliseconds ?? 0,
            albumArtUrl: a.thumbnailUrl,
            url: a.audioUrl ?? '',
            tags: ['youtube'],
            storageType: StorageType.remote,
          ),
        )
        .toList();
  }

  int get onlinePlaylistIndex => _youTubeService?.onlinePlaylistIndex ?? -1;

  // Collection getters
  List<String> get albums {
    final albumSet = <String>{};
    if (songs.isNotEmpty) {
      for (final song in _playlist) {
        if (song.album != null &&
            song.album!.isNotEmpty &&
            song.album!.toLowerCase() != 'unknown album') {
          albumSet.add(song.album!);
        }
      }
    }
    return albumSet.toList()..sort((a, b) => a.compareTo(b));
  }

  List<String> get artists {
    final artistSet = <String>{};
    for (final song in _songsMap.values) {
      for (final artist in song.artists) {
        if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') {
          artistSet.add(artist);
        }
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

  final Color? _notificationColor;

  // ===== INITIALIZATION =====
  MusicProvider({Color? notificationColor})
    : _notificationColor = notificationColor {
    WidgetsBinding.instance.addObserver(this);

    // Listen to playlist mode changes
    _player.stream.playlistMode.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });

    // Listen to playing state changes (e.g. from widget/notification)
    _player.stream.playing.listen((_) {
      notifyListeners();
    });

    // Listen to playback completion
    _player.stream.completed.listen((completed) async {
      if (completed) {
        await _onPlaybackCompleted();
      }
    });

    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
    } else if (state == AppLifecycleState.resumed) {
      _onWidgetUpdateNeeded?.call();
    }
  }

  Future<void> _onPlaybackCompleted() async {
    final activePlaylist = _getActivePlaylist();
    if (activePlaylist.isEmpty) return;

    if (_loopMode == PlaylistMode.single) {
      await _player.seek(Duration.zero);
      await _player.play();
    } else if (_loopMode == PlaylistMode.loop) {
      _currentIndex = (_currentIndex + 1) % activePlaylist.length;
      await _setAudioSource(activePlaylist[_currentIndex]);
      await _player.play();
      await _updateNotification();
      notifyListeners();
    } else if (_currentIndex < activePlaylist.length - 1) {
      await next();
    }
  }

  List<Song> _getActivePlaylist() =>
      _isUsingTempPlaylist ? _tempPlaylist : _playlist;

  /// Save current playback state for resume after app restart
  Future<void> _savePlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activePlaylist = _getActivePlaylist();

      await prefs.setInt(_resumeIndexKey, _currentIndex);
      await prefs.setInt(
        _resumePositionKey,
        _player.state.position.inMilliseconds,
      );
      await prefs.setBool(_resumeShuffleKey, _shuffleEnabled);
      await prefs.setString(_resumeLoopModeKey, _loopMode.name);
      await prefs.setBool(_resumeUsingTempPlaylistKey, _isUsingTempPlaylist);

      // Save playlist IDs for restoring queue
      final playlistIds = activePlaylist.map((s) => s.id).join(',');
      await prefs.setString(_resumePlaylistIdsKey, playlistIds);

      if (_isUsingTempPlaylist) {
        final tempIds = _tempPlaylist.map((s) => s.id).join(',');
        await prefs.setString(_resumeTempPlaylistIdsKey, tempIds);
      } else {
        await prefs.remove(_resumeTempPlaylistIdsKey);
      }

      if (currentSong != null) {
        _lastPlayedSong = currentSong;
        unawaited(_saveLastPlayedSong(currentSong!));
      }
    } catch (e) {
      debugPrint('Error saving playback state: $e');
    }
  }

  /// Restore playback state from saved preferences
  Future<void> _restorePlaybackState() async {
    if (_hasRestoredState) return;
    _hasRestoredState = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      _shuffleEnabled = prefs.getBool(_resumeShuffleKey) ?? false;
      final loopName = prefs.getString(_resumeLoopModeKey);
      if (loopName != null) {
        _loopMode = PlaylistMode.values.firstWhere(
          (m) => m.name == loopName,
          orElse: () => PlaylistMode.none,
        );
      }

      _isUsingTempPlaylist =
          prefs.getBool(_resumeUsingTempPlaylistKey) ?? false;

      final savedIndex = prefs.getInt(_resumeIndexKey);
      final savedPosition = prefs.getInt(_resumePositionKey) ?? 0;

      if (_playlist.isNotEmpty &&
          savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _playlist.length) {
        _currentIndex = savedIndex;

        // Load audio source and seek to saved position, but do NOT auto-play
        if (_lastPlayedSong != null) {
          await _setAudioSource(_playlist[_currentIndex]);
          // Player.open() auto-plays in media_kit — pause immediately
          await _player.pause();
          await _player.seek(Duration(milliseconds: savedPosition));

          final song = _playlist[_currentIndex];
          requestThumbnail(song, priority: 0);
          notifyListeners();

          debugPrint('Restored playback position at index $_currentIndex, position ${Duration(milliseconds: savedPosition)} (paused)');
        }
      }
    } catch (e) {
      debugPrint('Error restoring playback state: $e');
    }
  }

  Future<void> _initialize() async {
    debugPrint('╔══════════════════════════════════════════╗');
    debugPrint('║  MusicProvider._initialize: START           ║');
    debugPrint('╚══════════════════════════════════════════╝');

    // Initialize audio notification service
    debugPrint('_initialize: About to init AudioNotificationService...');
    try {
      debugPrint('_initialize: Calling AudioNotificationService.init()...');
      await AudioNotificationService.init(
        player: _player,
        notificationColor: _notificationColor,
        onCurrentSongChanged: (song) {
          debugPrint('Notification song changed: ${song?.title}');
        },
        onPlaybackStateChanged: (isPlaying) {
          debugPrint('Notification playback state: $isPlaying');
        },
        onSkipToNext: () {
          debugPrint('Skip to next from notification');
          next();
        },
        onSkipToPrevious: () {
          debugPrint('Skip to previous from notification');
          previous();
        },
        onOnlineMediaChanged: (song, isPlaying) {
          HomeWidgetService.updatePlayerWidget(
            currentSong: null,
            isPlaying: false,
            isOnlinePlaying: true,
            onlineTitle: song.title,
            onlineAuthor: song.artists.isNotEmpty ? song.artists.first : '',
          );
        },
      );
      debugPrint(
        '_initialize: AudioNotificationService.init() returned handler=${AudioNotificationService.audioHandler}',
      );
    } on Exception catch (e, stackTrace) {
      debugPrint('╔══════════════════════════════════════════╗');
      debugPrint('║  _initialize: EXCEPTION CAUGHT             ║');
      debugPrint('║  Error: $e');
      debugPrint('╚══════════════════════════════════════════╝');
      debugPrint('Stack: $stackTrace');
    }

    // Initialize thumbnail service with lazy loading
    _initThumbnailService();

    // Load last played song for resume functionality
    debugPrint('_initialize: Loading last played song...');
    _lastPlayedSong = await _loadLastPlayedSong();
    if (_lastPlayedSong != null) {
      debugPrint(
        '_initialize: Last played song loaded: ${_lastPlayedSong!.title}',
      );
    }

    // Load the music library first to populate _songsMap
    debugPrint('_initialize: Loading local music...');
    await loadLocalMusic().catchError((e) {
      debugPrint('Error during initialization: $e');
    });

    // Then load Now Playing playlist (fills from _songsMap if DB is empty)
    debugPrint('_initialize: Loading Now Playing playlist...');
    await _loadNowPlayingPlaylist();

    // Restore playback state (position, index, shuffle, loop) and auto-resume
    debugPrint('_initialize: Restoring playback state...');
    await _restorePlaybackState();

    debugPrint('╔══════════════════════════════════════════╗');
    debugPrint('║  MusicProvider._initialize: END             ║');
    debugPrint('╚══════════════════════════════════════════╝');
  }

  // ===== THUMBNAIL SERVICE =====
  void _initThumbnailService() {
    _thumbnailService = ThumbnailService();
    _thumbnailService!.onThumbnailReady = (song, localPath) {
      final updated = song.copyWith(localThumbnailPath: localPath);
      _updateSongInPlace(updated);

      // Remove from loading tracking — could be youtubeId or artist key
      final ytId = song.youtubeId;
      if (ytId != null && ytId.isNotEmpty) {
        _thumbnailLoadingIds.remove(ytId);
      } else if (song.artists.isNotEmpty) {
        _thumbnailLoadingIds.remove('artist:${song.artists.first}');
      }

      _databaseHelper.updateThumbnailPath(song.id, localPath);

      debugPrint('Thumbnail ready for ${song.title}: $localPath');
    };
    _thumbnailService!.onThumbnailFailed = (song) {
      final ytId = song.youtubeId;
      if (ytId != null && ytId.isNotEmpty) {
        _thumbnailLoadingIds.remove(ytId);
      } else if (song.artists.isNotEmpty) {
        _thumbnailLoadingIds.remove('artist:${song.artists.first}');
      }
    };
  }

  void _updateSongInPlace(Song updated) {
    for (int i = 0; i < _playlist.length; i++) {
      if (_playlist[i].id == updated.id) {
        _playlist[i] = updated;
      }
    }
    for (int i = 0; i < _displayedSongs.length; i++) {
      if (_displayedSongs[i].id == updated.id) {
        _displayedSongs[i] = updated;
      }
    }
    if (_songsMap.containsKey(updated.url)) {
      _songsMap[updated.url] = updated;
    }
    notifyListeners();
  }

  bool isThumbnailLoading(Song song) {
    if (song.localThumbnailPath != null) return false;
    final ytId = song.youtubeId;
    if (ytId != null && ytId.isNotEmpty) {
      return _thumbnailLoadingIds.contains(ytId);
    }
    if (song.artists.isNotEmpty) {
      return _thumbnailLoadingIds.contains('artist:${song.artists.first}');
    }
    return false;
  }

  void requestThumbnail(Song song, {int priority = 2}) {
    if (song.localThumbnailPath != null) return;

    // Track by youtubeId if available, otherwise by artist key
    final ytId = song.youtubeId;
    if (ytId != null && ytId.isNotEmpty) {
      if (_thumbnailLoadingIds.contains(ytId)) return;
      _thumbnailLoadingIds.add(ytId);
    } else if (song.artists.isNotEmpty) {
      final artistKey = 'artist:${song.artists.first}';
      if (_thumbnailLoadingIds.contains(artistKey)) return;
      _thumbnailLoadingIds.add(artistKey);
    } else {
      return;
    }

    _thumbnailService?.requestThumbnail(song, priority: priority);
  }

  void _startBackgroundThumbnails() {
    if (_thumbnailBgStarted) return;
    _thumbnailBgStarted = true;

    Future.delayed(const Duration(seconds: 3), () {
      final songs = _songsMap.values
          .where(
            (s) =>
                s.youtubeId != null &&
                s.youtubeId!.isNotEmpty &&
                s.localThumbnailPath == null,
          )
          .toList();
      for (final song in songs) {
        final ytId = song.youtubeId;
        if (ytId != null && !_thumbnailLoadingIds.contains(ytId)) {
          _thumbnailLoadingIds.add(ytId);
        }
      }
      _thumbnailService?.requestThumbnailForAll(songs);

      // Also queue songs without youtubeId for artist thumbnail fallback
      final artistSongs = _songsMap.values
          .where(
            (s) =>
                (s.youtubeId == null || s.youtubeId!.isEmpty) &&
                s.localThumbnailPath == null &&
                s.artists.isNotEmpty,
          )
          .toList();
      if (artistSongs.isNotEmpty) {
        for (final song in artistSongs) {
          final artistKey = 'artist:${song.artists.first}';
          if (!_thumbnailLoadingIds.contains(artistKey)) {
            _thumbnailLoadingIds.add(artistKey);
          }
        }
        _thumbnailService?.requestThumbnailForAll(artistSongs);
      }
    });
  }

  // ===== PLAYBACK CONTROLS =====
  Future<void> play() async {
    // If no current song but have last played song, load it
    if (currentSong == null && _lastPlayedSong != null) {
      await playSong(_lastPlayedSong!);
      return;
    }

    if (_playlist.isEmpty) return;
    try {
      _isLoading = true;
      notifyListeners();
      final audioHandler = AudioNotificationService.audioHandler;
      if (audioHandler != null) {
        await audioHandler.play();
      } else {
        await _player.play();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      await audioHandler.pause();
    } else {
      await _player.pause();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      await audioHandler.stop();
    } else {
      await _player.stop();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      await audioHandler.seek(position);
    } else {
      await _player.seek(position);
    }
    notifyListeners();
  }

  Future<void> showTestNotification() async {
    try {
      final audioHandler = AudioNotificationService.audioHandler;
      if (audioHandler != null) {
        // Create a test song for notification
        final testSong = Song(
          id: 0,
          title: 'Test Notification',
          artists: ['TS Music'],
          url: 'test://notification',
          duration: 180000, // 3 minutes
        );

        // Use the proper method to set current song
        await setPlaylistAndPlay([testSong], 0);

        // Update notification via audio service
        await audioHandler.play();
      } else {
        debugPrint('No audio handler available for test notification');
      }
    } catch (e) {
      debugPrint('Error showing test notification: $e');
    }
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
        _displayedSongs.sort(
          (a, b) => _sortAscending
              ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
              : b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SongSortOption.artist:
        _displayedSongs.sort((a, b) {
          final artistA = a.artists.isNotEmpty
              ? a.artists.first.toLowerCase()
              : '';
          final artistB = b.artists.isNotEmpty
              ? b.artists.first.toLowerCase()
              : '';
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
        _displayedSongs.sort(
          (a, b) => _sortAscending
              ? a.duration.compareTo(b.duration)
              : b.duration.compareTo(a.duration),
        );
        break;
    }
  }

  Future<void> refreshSongs() async {
    debugPrint('MusicProvider: refreshSongs() called');
    try {
      // Reset thumbnail loading state so new songs get thumbnails
      _thumbnailBgStarted = false;
      _thumbnailLoadingIds.clear();
      _thumbnailService?.dispose();
      _thumbnailService = null;

      // Always clear static cache so a fresh DB query is performed
      _songsMap.clear();
      _playlist.clear();
      _displayedSongs.clear();

      // Re-initialize thumbnail service
      _initThumbnailService();

      // First load from database
      await _loadSongsFromDatabase();

      // Then scan for new music to find files in subdirectories
      await _scanLocalStorageForMusic();

      // Reload from database after scanning to include new songs
      _songsMap.clear();
      await _loadSongsFromDatabase();

      _applySorting();

      // Restore now-playing playlist from DB
      await _loadNowPlayingPlaylist();

      debugPrint(
        'MusicProvider: refreshSongs() completed - ${_songsMap.length} songs in library',
      );
    } catch (e) {
      debugPrint('Error refreshing songs: $e');
    }
  }

  /// Deletes a song from both the database and in-memory collections.
  Future<void> deleteSong(Song song, {bool deleteFile = true}) async {
    try {
      // Delete physical file if it's a local file
      if (deleteFile && song.url.isNotEmpty) {
        try {
          final file = File(song.url);
          if (await file.exists()) {
            await file.delete();
            debugPrint('🗑️ Deleted file: ${song.url}');
          } else {
            debugPrint('⚠️ File not found for deletion: ${song.url}');
          }
        } catch (e) {
          debugPrint('⚠️ Error deleting file ${song.url}: $e');
        }
      }

      // Remove from database first
      await _databaseHelper.deleteSong(song.id);

      // Remove from in-memory collections
      _playlist.removeWhere((s) => s.id == song.id);
      _displayedSongs.removeWhere((s) => s.id == song.id);
      _songsMap.remove(song.url);

      notifyListeners();
      debugPrint(
        '🗑️ MusicProvider: removed song "${song.title}" from memory and DB',
      );
    } catch (e) {
      debugPrint('Error deleting song: $e');
      rethrow;
    }
  }

  /// Adds a newly downloaded song directly to the in-memory library
  /// so the UI updates without requiring a full database reload.
  void addDownloadedSongToLibrary(Song song) {
    if (!_songsMap.containsKey(song.url)) {
      _songsMap[song.url] = song;
      _playlist.add(song);
      _displayedSongs.add(song);
      notifyListeners();
      debugPrint(
        '✅ MusicProvider: added downloaded song "${song.title}" to library',
      );
    } else {
      debugPrint(
        'ℹ️ MusicProvider: song "${song.title}" already in library, skipping add',
      );
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
      debugPrint(
        'MusicProvider: Error loading music (attempt ${_retryCount + 1}/$_maxRetries): $e',
      );
      _lastError = e.toString();

      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delaySeconds = _baseRetryDelay * _retryCount;

        _error =
            'Error: $_lastError\n\nRetrying in ${delaySeconds}s... (attempt $_retryCount/$_maxRetries)';
        notifyListeners();

        debugPrint('MusicProvider: Auto-retrying in $delaySeconds seconds...');
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
        song.toDbMap(),
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

      // Clear static cache AND in-memory collections so we always get fresh data
      _songsMap.clear();
      _playlist.clear();
      _displayedSongs.clear();

      // Load from database only
      await _loadSongsFromDatabase();

      // Restore now-playing playlist from DB or fill from library
      await _loadNowPlayingPlaylist();
      _isLoading = false;
      _loadingNotifier.value = false;

      if (_songsMap.isEmpty) {
        // If no songs in database, automatically scan for music
        debugPrint('No songs in database, scanning for music...');
        await _scanLocalStorageForMusic();
      } else {
        // Check for deleted files and scan for new files in background
        await _scanLocalStorageForMusic(background: true);
        _error = null;
      }

      notifyListeners();
    } catch (e) {
      _error = 'Error loading music from database: $e';
      _isLoading = false;
      _loadingNotifier.value = false;

      // Only set error if library is still empty
      if (_songsMap.isEmpty) {
        notifyListeners();
      } else {
        // If we have songs, clear error and notify anyway
        _error = null;
        notifyListeners();
      }
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

      // Clear only displayed songs, preserve playback queue
      _displayedSongs.clear();

      // If we have cached songs and not forcing rescan, use them
      if (_songsMap.isNotEmpty && !forceRescan) {
        _displayedSongs = _cachedSongs;

        // Ensure cached songs are also in database for consistency
        await _ensureCachedSongsInDatabase();

        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null;
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
      if (_songsMap.isNotEmpty) {
        _displayedSongs = _cachedSongs;
        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null;
        notifyListeners();

        // Check for new music in background
        unawaited(_checkForNewMusicInBackground());
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

      // Try to recover by forcing a rescan
      if (_songsMap.isEmpty) {
        await _scanLocalStorageForMusic();
      }
    } finally {
      _isLoading = false;
      _loadingNotifier.value = false;
      // Clear error if we have songs
      if (_songsMap.isNotEmpty) {
        _error = null;
      }
      notifyListeners();
    }
  }

  // ===== PLAYLIST MANAGEMENT =====
  Future<void> playSong(Song song) async {
    // Stop online player first to avoid double sound
    await _youTubeService?.stop();

    // Clear temp playlist mode if active
    _isUsingTempPlaylist = false;
    _tempPlaylist.clear();

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

      // Prioritize thumbnail for currently playing song
      requestThumbnail(song, priority: 0);

      // Save as last played song
      _lastPlayedSong = song;
      unawaited(_saveLastPlayedSong(song));

      notifyListeners();
    }
  }

  /// Play a song from library with entire library as queue (Now Playing)
  Future<void> playSongFromLibrary(Song song) async {
    // Stop online player first
    await _youTubeService?.stop();

    // Clear temp playlist mode if active
    _isUsingTempPlaylist = false;
    _tempPlaylist.clear();

    // Load entire library as queue
    _playlist
      ..clear()
      ..addAll(_songsMap.values);

    // Find the clicked song
    var index = _playlist.indexWhere((s) => s.id == song.id);
    if (index == -1) {
      // Song not in library yet, add it
      _addSongIfNotExists(song);
      index = _playlist.indexWhere((s) => s.id == song.id);
    }

    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      await _player.play();
      await _updateNotification();
      await _updateNowPlayingPlaylist();
      requestThumbnail(song, priority: 0);
      notifyListeners();
      debugPrint(
        'Playing from library: ${song.title}, queue size: ${_playlist.length}',
      );
    }
  }

  /// Play specific songs by replacing the current playlist (Now Playing).
  Future<void> playSongsFromList(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    // Stop online player first to avoid double sound
    await _youTubeService?.stop();

    // Clear temp playlist mode if active
    _isUsingTempPlaylist = false;
    _tempPlaylist.clear();

    _playlist
      ..clear()
      ..addAll(songs);
    _currentIndex = startIndex.clamp(0, _playlist.length - 1);

    final song = _playlist[_currentIndex];
    await _setAudioSource(song);
    await _player.play();
    await _updateNotification();
    await _updateNowPlayingPlaylist();
    requestThumbnail(song, priority: 0);

    // Save as last played song
    _lastPlayedSong = song;
    unawaited(_saveLastPlayedSong(song));

    notifyListeners();
    debugPrint(
      'Playing from list: ${song.title}, queue size: ${_playlist.length}',
    );
  }

  List<Song> _tempPlaylist = [];
  bool _isUsingTempPlaylist = false;

  List<Song> get tempPlaylist => _tempPlaylist;
  bool get isUsingTempPlaylist => _isUsingTempPlaylist;

  Future<void> setPlaylistAndPlay(List<Song> songs, int startIndex) async {
    if (songs.isEmpty || startIndex < 0 || startIndex >= songs.length) return;

    // Stop online player first to avoid double sound
    await _youTubeService?.stop();

    _tempPlaylist = List.from(songs);
    _isUsingTempPlaylist = true;
    _currentIndex = startIndex;
    await _setAudioSource(songs[startIndex]);
    await _player.play();
    await _updateNotification();
    requestThumbnail(songs[startIndex], priority: 0);
    notifyListeners();
  }

  void clearTempPlaylist() {
    _tempPlaylist = [];
    _isUsingTempPlaylist = false;
    notifyListeners();
  }

  Future<void> next() async {
    if (_youTubeService?.currentAudio != null) {
      final onlinePlaylist = _youTubeService!.onlinePlaylist;
      final currentIdx = _youTubeService!.onlinePlaylistIndex;
      if (onlinePlaylist.isNotEmpty && currentIdx < onlinePlaylist.length - 1) {
        await _youTubeService!.playOnlinePlaylistAt(currentIdx + 1);
        notifyListeners();
        return;
      }
      await _stopOnlineAndResumeLocal();
      return;
    }
    final List<Song> currentPlaylist = _isUsingTempPlaylist
        ? _tempPlaylist
        : _playlist;
    if (currentPlaylist.isEmpty) return;
    if (_shuffleEnabled) {
      int nextIndex = _currentIndex;
      final random = Random();
      while (nextIndex == _currentIndex && currentPlaylist.length > 1) {
        nextIndex = random.nextInt(currentPlaylist.length);
      }
      _currentIndex = nextIndex;
    } else {
      _currentIndex = (_currentIndex + 1) % currentPlaylist.length;
    }
    await _setAudioSource(currentPlaylist[_currentIndex]);
    await _player.play();
    await _updateNotification();
    if (!_isUsingTempPlaylist) {
      await _updateNowPlayingPlaylist();
    }
    requestThumbnail(currentPlaylist[_currentIndex], priority: 0);
    notifyListeners();
  }

  Future<void> previous() async {
    if (_youTubeService?.currentAudio != null) {
      final onlinePlaylist = _youTubeService!.onlinePlaylist;
      final currentIdx = _youTubeService!.onlinePlaylistIndex;
      if (onlinePlaylist.isNotEmpty && currentIdx > 0) {
        await _youTubeService!.playOnlinePlaylistAt(currentIdx - 1);
        notifyListeners();
        return;
      }
      await _stopOnlineAndResumeLocal();
      return;
    }
    final List<Song> currentPlaylist = _isUsingTempPlaylist
        ? _tempPlaylist
        : _playlist;
    if (currentPlaylist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % currentPlaylist.length;
    if (_currentIndex < 0) _currentIndex = currentPlaylist.length - 1;
    await _setAudioSource(currentPlaylist[_currentIndex]);
    await _player.play();
    await _updateNotification();
    if (!_isUsingTempPlaylist) {
      await _updateNowPlayingPlaylist();
    }
    requestThumbnail(currentPlaylist[_currentIndex], priority: 0);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      if (_player.state.playing) {
        await audioHandler.pause();
      } else {
        await audioHandler.play();
      }
    } else {
      if (_player.state.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    }
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
    for (final song in _songsMap.values) {
      if (song.album == albumName &&
          (artistName == null ||
              song.artists.any((artist) => artist == artistName))) {
        return song.albumArtUrl;
      }
    }
    return null;
  }

  List<Song> getSongsByArtist(String artistName) => _songsMap.values
      .where((song) => song.artists.any((artist) => artist == artistName))
      .toList();

  List<Song> getSongsByAlbum(String albumName, {String? artistName}) =>
      _songsMap.values
          .where(
            (song) =>
                song.album == albumName &&
                (artistName == null ||
                    song.artists.any((artist) => artist == artistName)),
          )
          .toList();

  List<String> getAlbumsByArtist(String artistName) {
    final albumSet = <String>{};
    for (final song in _songsMap.values) {
      if (song.artists.any((artist) => artist == artistName) &&
          song.album != null &&
          song.album!.isNotEmpty) {
        albumSet.add(song.album!);
      }
    }
    return albumSet.toList()..sort();
  }

  // ===== SORTING AND FILTERING =====
  Future<void> sortSongs({
    required SongSortOption sortBy,
    bool ascending = true,
  }) async {
    try {
      _currentSortOption = sortBy;
      _sortAscending = ascending;

      // Sort the songs
      final sortedSongs = _songsMap.values.toList()
        ..sort((a, b) {
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
            await txn.insert('playlist_songs', {
              'playlist_id': nowPlayingPlaylistId,
              'song_id': _playlist[i].id,
              'position': i,
            });
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
          final artists = artistsData
              .map((row) => row['name'] as String)
              .toList();

          searchedSongs.add(
            Song(
              id: songId,
              youtubeId: songData['youtube_id'] as String?,
              title: songData['title'] as String,
              url: songData['file_path'] as String,
              duration: songData['duration'] as int,
              artists: artists.isNotEmpty ? artists : ['Unknown Artist'],
              dateAdded: songData['created_at'] != null
                  ? DateTime.parse(songData['created_at'] as String)
                  : DateTime.now(),
            ),
          );
        }
        _displayedSongs = searchedSongs;
      } else {
        // Fallback to in-memory search if no results from database
        final lowerQuery = query.toLowerCase();
        _displayedSongs = _playlist
            .where(
              (song) =>
                  song.title.toLowerCase().contains(lowerQuery) ||
                  song.artists.any(
                    (artist) => artist.toLowerCase().contains(lowerQuery),
                  ) ||
                  (song.album?.toLowerCase().contains(lowerQuery) ?? false),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('Error searching songs: $e');
      // Fallback to in-memory search on error
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _playlist
          .where(
            (song) =>
                song.title.toLowerCase().contains(lowerQuery) ||
                song.artists.any(
                  (artist) => artist.toLowerCase().contains(lowerQuery),
                ) ||
                (song.album?.toLowerCase().contains(lowerQuery) ?? false),
          )
          .toList();
    }

    notifyListeners();
  }

  // ===== PRIVATE HELPER METHODS =====
  /// Load songs from database with optimized queries
  Future<void> _loadSongsFromDatabase() async {
    debugPrint(
      '🔍 _loadSongsFromDatabase called, _songsMap.isNotEmpty=${_songsMap.isNotEmpty}, _songsMap.length=${_songsMap.length}',
    );

    if (_songsMap.isNotEmpty) {
      _displayedSongs = _cachedSongs;
      debugPrint('⚡ Using cached songs: ${_songsMap.length} songs');
      return;
    }

    try {
      // Get all songs in a single query
      final db = await _databaseHelper.database;

      // First, just count total songs in database
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM ${DatabaseHelper.tableSongs}',
      );
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;
      debugPrint('📊 Total songs in database table: $totalCount');

      // Get all songs with their artists and genres in a single query
      final songsQuery =
          '''
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

      // Clear only library cache, not the playback queue
      _songsMap.clear();

      // Process all songs in a single batch
      for (final songData in songs) {
        try {
          // Parse artists
          final artistNamesString = songData['artist_names'] as String?;
          final artistNames =
              artistNamesString != null && artistNamesString.isNotEmpty
              ? artistNamesString
                    .split(',')
                    .where(
                      (name) => name.isNotEmpty && name != 'Unknown Artist',
                    )
                    .toSet()
                    .toList()
              : <String>[];

          final artists = artistNames.isNotEmpty
              ? artistNames
              : ['Unknown Artist'];

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
            // A song is considered downloaded if it carries the 'tsmusic' tag
            isDownloaded: tags.contains('tsmusic'),
            dateAdded: songData['created_at'] != null
                ? DateTime.parse(songData['created_at'] as String)
                : DateTime.now(),
          );

          // Use URL as key to prevent duplicates
          if (!_songsMap.containsKey(song.url)) {
            _songsMap[song.url] = song;
          }
        } catch (e) {
          debugPrint('Error loading song from database: $e');
        }
      }

      _displayedSongs = _cachedSongs;
      _startBackgroundThumbnails();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading songs from database: $e');
      rethrow;
    }
  }

  /// Load Now Playing playlist from database
  Future<void> _loadNowPlayingPlaylist() async {
    try {
      final songMaps = await _databaseHelper.getSongsInPlaylist(
        nowPlayingPlaylistId,
      );
      // Clear current playlist to restore from DB
      _playlist.clear();

      for (final songData in songMaps) {
        final songId = songData['id'] as int;
        final artistsData = await _databaseHelper.getArtistsForSong(songId);
        final artists = artistsData
            .map((row) => row['name'] as String)
            .toList();

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
        _playlist.add(song);
      }

      if (_playlist.isEmpty && _songsMap.isNotEmpty) {
        _playlist.addAll(_songsMap.values);
        await _updateNowPlayingPlaylist();
      }

      if (_currentIndex >= _playlist.length) {
        _currentIndex = 0;
      }

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
      final songIds = <int>[];
      for (final song in _playlist) {
        if (song.id > 0) {
          songIds.add(song.id);
        }
      }
      await _databaseHelper.updateNowPlayingPlaylist(songIds);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating Now Playing playlist: $e');
      }
    }
  }

  /// Helper method to add a song only if it doesn't exist
  void _addSongIfNotExists(Song song) {
    // Always add to _playlist (queue) for playback
    _playlist.add(song);
    // Only add to _songsMap if not exists (library cache)
    if (!_songsMap.containsKey(song.url)) {
      _songsMap[song.url] = song;
    }
  }

  /// Public method to add a song to playlist (used by DownloadsScreen)
  void addSongToPlaylist(Song song) {
    _addSongIfNotExists(song);
    notifyListeners();
  }

  /// Set audio source for playback via audio service (handles notification)
  Future<void> _setAudioSource(Song song) async {
    final audioHandler = AudioNotificationService.audioHandler;
    debugPrint('_setAudioSource: audioHandler=${audioHandler != null}');

    // Check if this is a local file that exists
    final isLocalFile = song.url.startsWith('/') || song.url.contains(':');
    bool fileExists = false;

    if (isLocalFile) {
      try {
        fileExists = await File(song.url).exists();
      } catch (e) {
        // If we can't check, assume it doesn't exist
        fileExists = false;
      }
    }

    // If local file doesn't exist, try YouTube fallback (search if no ID)
    if (isLocalFile && !fileExists && audioHandler != null) {
      debugPrint(
        '_setAudioSource: Local file not found, attempting YouTube fallback',
      );

      await audioHandler.stop();
      String? ytId = song.youtubeId?.isNotEmpty == true ? song.youtubeId : null;

      // No YouTube ID yet — search by title/artist + duration match
      if (ytId == null && _youTubeService != null) {
        ytId = await _searchYouTubeForSong(
          song.title,
          song.artists,
          song.duration,
        );
        if (ytId != null) {
          await _updateSongYouTubeId(song, ytId);
        }
      }

      if (ytId != null && _youTubeService != null) {
        debugPrint('_setAudioSource: Playing YouTube: $ytId');
        audioHandler.setOnlineMode(
          online: true,
          onPlay: () => unawaited(_youTubeService?.play()),
          onPause: () => unawaited(_youTubeService?.pause()),
          onStop: () => unawaited(_youTubeService?.stop()),
        );

        final ytSong = Song(
          id: -1,
          youtubeId: ytId,
          title: song.title,
          artists: song.artists.isNotEmpty ? song.artists : ['Unknown Artist'],
          album: 'YouTube',
          duration: song.duration,
          albumArtUrl: song.albumArtUrl,
          url: 'yt:$ytId',
          storageType: StorageType.remote,
        );
        audioHandler.setOnlineMedia(ytSong, isPlaying: true);
        await audioHandler.play();
        return;
      }
    }

    // Proceed with normal playback (either local file that exists, or YouTube wasn't available/failed, or no audio handler)
    if (audioHandler != null) {
      final mediaPath = song.url.startsWith('/')
          ? 'file://${song.url}'
          : song.url;
      debugPrint('_setAudioSource: Setting media for ${song.title}');
      await audioHandler.setMedia(Media(mediaPath), song: song);
      debugPrint('_setAudioSource: Media set successfully');
    } else {
      // Fallback: open directly in player if service not available
      debugPrint('_setAudioSource: Using fallback (no audioHandler)');
      final mediaPath = song.url.startsWith('/')
          ? 'file://${song.url}'
          : song.url;
      await _player.open(Media(mediaPath));
    }
  }

  /// Searches YouTube for a song by title/artist and matches by duration
  Future<String?> _searchYouTubeForSong(
    String title,
    List<String> artists,
    int targetDurationMs,
  ) async {
    if (_youTubeService == null) return null;

    try {
      final String artist = artists.isNotEmpty ? artists.first : 'Unknown Artist';
      final String query = '$title $artist';

      final List<YouTubeAudio> results = await _youTubeService!.searchAudio(query);

      if (results.isEmpty) return null;

      final double targetDurationSec = targetDurationMs / 1000.0;

      YouTubeAudio? bestMatch;
      double minDiff = double.infinity;

      for (final result in results) {
        if (result.duration != null) {
          final double diff =
              (result.duration!.inMilliseconds / 1000.0 - targetDurationSec)
                  .abs();
          if (diff < minDiff && diff <= 5.0) {
            minDiff = diff;
            bestMatch = result;
          }
        }
      }

      return bestMatch?.id;
    } catch (e) {
      debugPrint('Error searching YouTube for song: $e');
      return null;
    }
  }

  /// Updates a song's YouTube ID in the database and in-memory collections
  Future<void> _updateSongYouTubeId(Song song, String youtubeId) async {
    try {
      final db = await _databaseHelper.database;
      await db.update(
        'songs',
        {'youtube_id': youtubeId},
        where: 'file_path = ?',
        whereArgs: [song.url],
      );
      final updated = song.copyWith(youtubeId: youtubeId);
      _updateSongInPlace(updated);
    } catch (e) {
      debugPrint('Error updating YouTube ID: $e');
    }
  }

  /// Update notification state only (player already has media)
  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      // Only update playback state, don't reopen media
      if (_player.state.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  /// Save last played song to SharedPreferences
  Future<void> _saveLastPlayedSong(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPlayedSongKey, jsonEncode(song.toJson()));
      debugPrint('MusicProvider: Saved last played song: ${song.title}');
    } catch (e) {
      debugPrint('Error saving last played song: $e');
    }
  }

  /// Load last played song from SharedPreferences
  Future<Song?> _loadLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songJson = prefs.getString(_lastPlayedSongKey);
      if (songJson != null) {
        final song = Song.fromJson(jsonDecode(songJson));
        debugPrint('MusicProvider: Loaded last played song: ${song.title}');
        return song;
      }
    } catch (e) {
      debugPrint('Error loading last played song: $e');
    }
    return null;
  }

  /// Save songs to storage cache
  Future<void> _saveSongsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _songsKey,
      jsonEncode(_playlist.map((s) => s.toJson()).toList()),
    );
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
        debugPrint(
          '📊 ENSURING ${missingSongs.length} CACHED SONGS ARE IN DATABASE',
        );

        // Save missing songs to database
        await db.transaction((txn) async {
          for (final song in missingSongs) {
            try {
              // Insert song using database-compatible map
              final songId = await txn.insert(
                DatabaseHelper.tableSongs,
                song.toDbMap(),
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
              debugPrint(
                'Error saving cached song ${song.title} to database: $e',
              );
            }
          }
        });

        debugPrint(
          '✅ ENSURED ${missingSongs.length} CACHED SONGS ARE IN DATABASE',
        );
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

      // Clean up old duplicate files (with bitrate in filename)
      await _cleanupOldDuplicateFiles();

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

      debugPrint(
        '🔍 SCANNING ${musicDirectories.length} DIRECTORIES FOR MUSIC FILES',
      );
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
          debugPrint(
            '✅ FOUND ${alternativeFiles.length} FILES IN ALTERNATIVE LOCATIONS',
          );
        }
      }

      if (musicFiles.isEmpty) {
        // Only set error if there are no songs in database either
        final db = await _databaseHelper.database;
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM songs',
        );
        final count = countResult.first['count'] as int? ?? 0;

        if (count == 0) {
          _error = 'No music files found on device.';
        }
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
        // Only show error if both scanning found nothing AND database is empty
        final db = await _databaseHelper.database;
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM songs',
        );
        final count = countResult.first['count'] as int? ?? 0;

        if (_songsMap.isEmpty && count == 0) {
          _error =
              'No music found. Add music to your device or download from YouTube.';
        } else {
          _error = null;
          debugPrint(
            '✅ SUCCESSFULLY ADDED ${_songsMap.length} SONGS TO DATABASE',
          );
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ ERROR DURING MUSIC SCAN: $e');
      if (!background) {
        // Only show error if database is also empty
        final db = await _databaseHelper.database;
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM songs',
        );
        final count = countResult.first['count'] as int? ?? 0;

        if (count == 0) {
          _error =
              'Could not scan for music. Please check storage permissions.';
        }
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
        debugPrint(
          'Removing ${songsToRemove.length} deleted songs from database',
        );
        await db.delete(
          'songs',
          where: 'id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );

        await db.delete(
          'playlist_songs',
          where:
              'song_id IN (${List.filled(songsToRemove.length, '?').join(',')})',
          whereArgs: songsToRemove,
        );
      }
    } catch (e) {
      debugPrint('Error cleaning up deleted songs: $e');
    }
  }

  /// Clean up old duplicate files that have bitrate in filename
  /// These are from old downloads that used bitrate in filename
  Future<void> _cleanupOldDuplicateFiles() async {
    try {
      final musicDirectories = await _getAllMusicDirectories();

      for (final dirPath in musicDirectories) {
        try {
          final dir = Directory(dirPath);
          if (!await dir.exists()) continue;

          // Map of video ID -> list of files
          final Map<String, List<File>> videoIdFiles = {};

          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (audioExtensions.contains(ext)) {
                // Extract video ID from filename
                // Pattern: Title_VideoID.ext or Title_VideoID_bitrate.ext
                final fileName = path.basenameWithoutExtension(entity.path);
                final parts = fileName.split('_');

                if (parts.isNotEmpty) {
                  final lastPart = parts.last;
                  // Check if last part looks like a YouTube video ID (11 chars alphanumeric)
                  if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(lastPart)) {
                    videoIdFiles.putIfAbsent(lastPart, () => []).add(entity);
                  }
                }
              }
            }
          }

          // For each video ID, keep only the file without bitrate in name
          for (final entry in videoIdFiles.entries) {
            if (entry.value.length > 1) {
              File? bestFile;
              List<File> toDelete = [];

              for (final file in entry.value) {
                final fileName = path.basenameWithoutExtension(file.path);
                // File without bitrate: Title_VideoID
                // File with bitrate: Title_VideoID_128000
                if (RegExp(r'_[0-9]+$').hasMatch(fileName)) {
                  toDelete.add(file);
                } else {
                  bestFile = file;
                }
              }

              // Keep the one without bitrate, delete others
              if (bestFile == null && entry.value.isNotEmpty) {
                // If no clean file, keep the first one
                bestFile = entry.value.first;
                toDelete = entry.value.skip(1).toList();
              }

              for (final file in toDelete) {
                try {
                  await file.delete();
                  debugPrint('🗑️ Deleted old duplicate: ${file.path}');
                } catch (e) {
                  debugPrint('⚠️ Could not delete ${file.path}: $e');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error cleaning duplicates in $dirPath: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in cleanupOldDuplicateFiles: $e');
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
    // Only canonical paths - avoid duplicates from symlinks (/sdcard, /mnt/sdcard, /data/media/0 all point to same location)
    final standardPaths = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Android/data/com.veciata.tsmusic/files/Music',
      '/storage/emulated/0/Android/data/com.veciata.tsmusic/files/Download',
    ];

    musicDirectories.addAll(standardPaths);

    // Remove duplicates and filter out null/empty paths
    final uniquePaths = musicDirectories
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList();

    debugPrint('🔍 Final music directories to scan: $uniquePaths');

    return uniquePaths;
  }

  /// Scan all directories in parallel for maximum speed
  Future<Map<String, dynamic>> _scanAllDirectoriesParallel(
    List<String> directories,
  ) async {
    final List<File> allMusicFiles = [];
    final Set<String> processedPaths = {};
    int totalFilesFound = 0;

    // Process directories in batches to avoid overwhelming the system
    const batchSize = 5;

    for (int i = 0; i < directories.length; i += batchSize) {
      final endIndex = (i + batchSize < directories.length)
          ? i + batchSize
          : directories.length;
      final batch = directories.sublist(i, endIndex);

      // Process each directory in this batch
      final futures = batch
          .map((dirPath) => _scanSingleDirectory(dirPath, processedPaths))
          .toList();

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

    return {'files': allMusicFiles, 'totalFiles': totalFilesFound};
  }

  /// Scan a single directory for music files
  Future<Map<String, dynamic>?> _scanSingleDirectory(
    String dirPath,
    Set<String> processedPaths,
  ) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return null;

      final List<File> musicFiles = [];
      int fileCount = 0;

      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && !processedPaths.contains(entity.path)) {
          final ext = path.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            try {
              final stat = await entity.stat();
              // Lower minimum file size to catch more files
              if (stat.size > 512) {
                // Even smaller threshold
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

      return {'files': musicFiles, 'count': fileCount};
    } catch (e) {
      debugPrint('  ❌ Error scanning $dirPath: $e');
      return null;
    }
  }

  /// Scan alternative locations when standard scanning fails
  Future<List<File>> _scanAlternativeLocations() async {
    final List<File> alternativeFiles = [];

    // Try some additional locations
    final alternativePaths = ['/storage', '/mnt', '/data', '/system'];

    for (final basePath in alternativePaths) {
      try {
        final dir = Directory(basePath);
        if (await dir.exists()) {
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
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
  Future<void> _processAndAddAllSongs(
    List<File> musicFiles,
    bool background,
  ) async {
    debugPrint('🔄 PROCESSING ${musicFiles.length} MUSIC FILES...');

    // Clear only library cache, preserve playback queue
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
          // Insert song using database-compatible map
          final songId = await txn.insert(
            DatabaseHelper.tableSongs,
            song.toDbMap(),
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

    // Update in-memory library cache
    for (final song in validSongs) {
      if (!_songsMap.containsKey(song.url)) {
        _songsMap[song.url] = song;
      }
    }

    _displayedSongs = _cachedSongs;

    debugPrint('🎉 SUCCESSFULLY ADDED ${validSongs.length} SONGS TO DATABASE');

    // Ensure all songs are saved to database for consistency
    await _ensureCachedSongsInDatabase();
  }

  /// Helper method to get or create artist (case-insensitive)
  Future<int> _getOrCreateArtist(
    DatabaseExecutor txn,
    String artistName,
  ) async {
    final trimmedName = artistName.trim();
    if (trimmedName.isEmpty) {
      return 0;
    }

    final existingArtist = await txn.query(
      DatabaseHelper.tableArtists,
      where: 'LOWER(${DatabaseHelper.columnName}) = LOWER(?)',
      whereArgs: [trimmedName],
    );

    if (existingArtist.isNotEmpty) {
      return existingArtist.first[DatabaseHelper.columnId] as int;
    }

    return await txn.insert(DatabaseHelper.tableArtists, {
      'name': trimmedName,
      'created_at': DateTime.now().toIso8601String(),
    });
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

    return await txn.insert(DatabaseHelper.tableGenres, {
      'name': genreName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Process a single music file and extract metadata
  Future<Song?> _processMusicFile(File file) async {
    try {
      final fileName = path.basenameWithoutExtension(file.path);

      // Clean up filename
      String cleanFileName(String fileName) => fileName
          .replaceAll(
            RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(
              r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(
            RegExp(
              r'\b(official|music|video|lyrics|hd|clear|audio)\b',
              caseSensitive: false,
            ),
            '',
          )
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

        artistsList = mainArtist
            .split(RegExp(r'\s*(?:,|&|and|\+)\s*', caseSensitive: false))
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();

        // Handle featured artists
        String? featuredArtists;
        final featPattern = RegExp(
          r'^(.*?)\s*(?:ft\.?|feat\.?|featuring)\s+(.+)$',
          caseSensitive: false,
        );
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
            .replaceAll(
              RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false),
              '',
            )
            .replaceAll(
              RegExp(
                r'(?:ft\.?|feat\.?|featuring)\s+.+$',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(
              RegExp(
                r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps',
                caseSensitive: false,
              ),
              '',
            )
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
      final isTSMusic =
          file.path.toLowerCase().contains('music/tsmusic') ||
          file.path.toLowerCase().contains('tsmusic');

      final song = Song(
        id: file.path.hashCode,
        title: title.isNotEmpty
            ? title
            : path.basenameWithoutExtension(file.path),
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
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return Duration.zero;
      }

      final fileSize = await file.length();
      if (fileSize < 1024) {
        debugPrint(
          'File too small to be valid audio: $filePath ($fileSize bytes)',
        );
        return Duration.zero;
      }

      final extension = path.extension(filePath).toLowerCase();

      // Estimate duration based on file size and average bitrate
      // Common bitrates: MP3/M4A ~128-320kbps, OPUS ~96-160kbps
      int estimatedBitrate;
      if (extension == '.mp3') {
        estimatedBitrate = 128000; // 128 kbps
      } else if (extension == '.m4a' || extension == '.aac') {
        estimatedBitrate = 128000; // 128 kbps
      } else if (extension == '.opus') {
        estimatedBitrate = 96000; // 96 kbps
      } else if (extension == '.ogg' || extension == '.flac') {
        estimatedBitrate = 256000; // 256 kbps for FLAC/Ogg
      } else if (extension == '.wav') {
        estimatedBitrate = 1411200; // 1411 kbps (CD quality)
      } else {
        estimatedBitrate = 128000; // default
      }

      // Duration = (file size in bits) / bitrate
      final estimatedMs = (fileSize * 8 * 1000) / estimatedBitrate;

      // Reasonable duration check: between 10 seconds and 30 minutes
      if (estimatedMs < 10000 || estimatedMs > 1800000) {
        debugPrint(
          'Suspicious duration estimate for $filePath: ${Duration(milliseconds: estimatedMs.round())}, using default 3 minutes',
        );
        return const Duration(minutes: 3);
      }

      debugPrint(
        'Estimated duration for $filePath: ${Duration(milliseconds: estimatedMs.round())} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
      );
      return Duration(milliseconds: estimatedMs.round());
    } catch (e) {
      debugPrint('Error getting duration for $filePath: $e');
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
    final activePlaylist = _getActivePlaylist();
    if (oldIndex < 0 ||
        oldIndex >= activePlaylist.length ||
        newIndex < 0 ||
        newIndex >= activePlaylist.length) {
      return;
    }
    final song = activePlaylist.removeAt(oldIndex);
    activePlaylist.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
      _currentIndex++;
    }
    if (!_isUsingTempPlaylist) {
      _updateNowPlayingPlaylist();
    }
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    final activePlaylist = _getActivePlaylist();
    if (index >= 0 && index < activePlaylist.length) {
      _currentIndex = index;
      final song = activePlaylist[index];
      await _setAudioSource(song);
      await _player.play();
      await _updateNotification();
      _lastPlayedSong = song;
      unawaited(_saveLastPlayedSong(song));
      requestThumbnail(song, priority: 0);
      notifyListeners();
    }
  }

  Future<void> removeFromQueue(int index) async {
    final activePlaylist = _getActivePlaylist();
    if (index < 0 || index >= activePlaylist.length) return;

    final wasCurrentSong = index == _currentIndex;
    final playlistSizeBefore = activePlaylist.length;

    if (_isUsingTempPlaylist) {
      _tempPlaylist.removeAt(index);
    } else {
      _playlist.removeAt(index);
    }

    if (_currentIndex >= activePlaylist.length) {
      _currentIndex = activePlaylist.length - 1;
    } else if (wasCurrentSong && playlistSizeBefore > 1) {
      if (_currentIndex >= activePlaylist.length) {
        _currentIndex = activePlaylist.length - 1;
      }
      if (activePlaylist.isNotEmpty) {
        await _setAudioSource(activePlaylist[_currentIndex]);
        await _player.play();
        await _updateNotification();
      }
    }

    if (!_isUsingTempPlaylist) {
      await _updateNowPlayingPlaylist();
    }
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _playlist.clear();
    _tempPlaylist.clear();
    _isUsingTempPlaylist = false;
    _displayedSongs.clear();
    await _updateNowPlayingPlaylist();
    notifyListeners();
  }

  Future<int> addOnlineSongToPlaylist({
    required String youtubeId,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailUrl,
    required int playlistId,
  }) async {
    try {
      final songId = await _databaseHelper.addYouTubeSongToDatabase(
        youtubeId: youtubeId,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
      );
      if (songId > 0) {
        await _databaseHelper.addSongsToPlaylist(playlistId, [songId]);
      }
      notifyListeners();
      return songId;
    } catch (e) {
      debugPrint('Error adding online song to playlist: $e');
      rethrow;
    }
  }

  static bool isYouTubeOnlyUrl(String url) => url.startsWith('yt:');

  Future<int> addMixedSongToPlaylist(PlaylistItem item, int playlistId) async {
    try {
      if (item.songId != null) {
        await _databaseHelper.addSongsToPlaylist(playlistId, [item.songId!]);
        notifyListeners();
        return item.songId!;
      } else if (item.youtubeId != null) {
        return await addOnlineSongToPlaylist(
          youtubeId: item.youtubeId!,
          title: item.title ?? 'Unknown',
          artists: item.artists ?? ['Unknown Artist'],
          duration: item.duration ?? 0,
          thumbnailUrl: item.thumbnailUrl,
          playlistId: playlistId,
        );
      }
      return -1;
    } catch (e) {
      debugPrint('Error adding mixed song to playlist: $e');
      rethrow;
    }
  }

  Future<void> loadPlaylistAsQueue(int playlistId) async {
    try {
      final songMaps = await _databaseHelper.getSongsInPlaylist(playlistId);
      final songs = <Song>[];

      for (final songData in songMaps) {
        final songId = songData['id'] as int;
        final artistsData = await _databaseHelper.getArtistsForSong(songId);
        final artists = artistsData
            .map((row) => row['name'] as String)
            .toList();

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
        songs.add(song);
        if (!_songsMap.containsKey(song.url)) {
          _songsMap[song.url] = song;
        }
      }

      if (songs.isNotEmpty) {
        _tempPlaylist = songs;
        _isUsingTempPlaylist = true;
        _currentIndex = 0;
        await _setAudioSource(songs[0]);
        await _player.play();
        await _updateNotification();
      }

      notifyListeners();
      debugPrint(
        'Loaded playlist $playlistId with ${songs.length} songs as temp playlist',
      );
    } catch (e) {
      debugPrint('Error loading playlist as queue: $e');
      rethrow;
    }
  }
}
