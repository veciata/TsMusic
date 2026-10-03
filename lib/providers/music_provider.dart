import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/data/repositories/playlist_repository.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/models/playlist_item.dart';
import 'package:tsmusic/models/storage_type.dart';
import 'package:tsmusic/providers/library_view_model.dart';
import 'package:tsmusic/core/services/error_tracking_service.dart';
import 'package:tsmusic/core/services/playback_diagnostics.dart';
import 'package:tsmusic/domain/playback/online_progress_display.dart';
import 'package:tsmusic/domain/playback/playback_end_signal.dart';
import 'package:tsmusic/services/audio_notification_service.dart';
import 'package:tsmusic/services/home_widget_service.dart';
import 'package:tsmusic/services/playback_resume_state.dart';
import 'package:tsmusic/services/youtube_service.dart';

class MusicProvider extends ChangeNotifier with WidgetsBindingObserver {
  final Player _player;
  YouTubeService? _youTubeService;
  final SongRepository _songRepository;
  final PlaylistRepository _playlistRepository;
  final LibraryViewModel _library;
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
    _youTubeService = service
      ..addListener(_onYouTubeServiceStateChanged)
      ..localSongsCallback = () => librarySongs;

    // Each track in a batch download is written to the database by the service
    // and then handed back here, so the library and the downloads page update
    // as the batch runs rather than only at the end.
    service.downloadQueue.onEntryFinished = (entry, result) {
      final song = result?.song;
      if (song != null) _library.addSongToLibrary(song);
      notifyListeners();
    };
    unawaited(service.refreshDownloadedVideoIds());
  }

  void _reportCompletionDispatch(String branch) {
    final index = _currentIndex;
    final active = _getActivePlaylist();
    final title = (index >= 0 && index < active.length)
        ? active[index].title
        : '<none>';
    ErrorTrackingService().recordError(
      '[completed] $branch idx=$index of ${active.length} playingFromQueue='
      '${_youTubeService?.playingFromQueue} "$title"',
      StackTrace.current,
      context: 'MusicProvider.completed',
    );
  }

  Future<void> _onYouTubeQueueSongCompleted() async {
    if (_mixSession) return;
    if (!_isCurrentSongYouTubeOnly()) return;
    final activePlaylist = _getActivePlaylist();
    if (activePlaylist.isEmpty) return;
    final song = activePlaylist[_currentIndex];
    final yt = _youTubeService;
    if (yt == null) return;
    final state = yt.player.state;
    final duration = state.duration;
    final position = state.position;
    final videoId = song.youtubeId;
    final expected = Duration(milliseconds: song.duration);

    // `completed` fires once per HLS segment, so position/duration describe
    // only that segment. Judge the track against its own length plus the
    // progress banked from earlier segments. A boundary can say "track over"
    // or "keep going", but it cannot say "stream died" -- that needs the
    // watchdog, which watches for position to stop advancing.
    final signal = PlaybackEndSignal(
      position: position,
      expectedDuration: expected,
      progressBeforeEvent: _onlineProgress.banked,
      isPlaying: state.playing,
    );
    final verdict = signal.classify();

    PlaybackDiagnostics.trackCompleted(
      videoId: videoId ?? '<no-yt-id>',
      positionMs: position.inMilliseconds,
      expectedDurationMs: song.duration,
      playerDurationMs: duration.inMilliseconds,
      branch: 'queue-${signal.label}',
      retries: _ytFastFailRetries.length,
    );

    switch (verdict) {
      case TrackEndVerdict.continueTrack:
        // Normal segment boundary: bank the progress and keep playing. The
        // player is still advancing, so there is nothing to recover from.
        _onlineProgress.bank(position);
        return;

      case TrackEndVerdict.finished:
        _onlineProgress.reset();
    }

    // Only report once the track is genuinely over. This handler runs on every
    // HLS segment boundary -- roughly 50 times per track -- and a full error
    // report with a stack trace per boundary buries the log.
    _reportCompletionDispatch('yt-queue');
    _ytFastFailRetries.remove(videoId);
    if (_loopMode == PlaylistMode.single) {
      await _setAudioSource(song);
      return;
    }
    await next();
  }

  /// Restarts the current online track once, after the watchdog reports that
  /// playback stopped advancing partway through.
  ///
  /// Called from [_watchForOnlineStalls], which is the only thing allowed to
  /// conclude that a stream died.
  Future<void> _retryStalledOnlineTrack() async {
    final song = _getActivePlaylist().elementAtOrNull(_currentIndex);
    if (song == null || !_isYouTubeOnlySong(song)) return;
    final videoId = song.youtubeId;
    if (videoId == null) return;
    if (_ytFastFailRetries.containsKey(videoId)) return;

    _ytFastFailRetries[videoId] = DateTime.now().millisecondsSinceEpoch;
    _youTubeService?.invalidateStreamCache(videoId);
    _onlineProgress.reset();
    _onlineStall.reset();
    PlaybackDiagnostics.playbackFailed(
      videoId: videoId,
      error: 'stalled partway through track',
      origin: 'queue-watchdog',
    );
    // Retry the same format on a fresh URL. Switching to DASH does not help:
    // measured on this network it buffers indefinitely (0ms after 120s).
    await _setAudioSource(song, automaticRetry: true);
  }

  /// Watches the current online track and retries it if playback stops
  /// advancing before the track reaches its real length.
  void _watchForOnlineStalls() {
    _onlineStallTimer?.cancel();
    final yt = _youTubeService;
    if (yt == null) return;
    _onlineStallTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isCurrentSongYouTubeOnly()) {
        _onlineStallTimer?.cancel();
        return;
      }
      final song = _getActivePlaylist().elementAtOrNull(_currentIndex);
      if (song == null) return;
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - _onlineStallStartedAt;
      // Observe accumulated progress, not the raw player position: for HLS the
      // player position resets at every segment boundary, so watching it
      // directly would read each boundary as a stall.
      final detected = _onlineStall.observe(
        Duration(milliseconds: elapsed),
        _onlineProgress.banked + yt.player.state.position,
        isBuffering: yt.player.state.buffering,
      );
      if (!detected) return;
      if (!_onlineStall.isTruncated(
        expectedDuration: Duration(milliseconds: song.duration),
        banked: _onlineProgress.banked,
      )) {
        return;
      }
      await _retryStalledOnlineTrack();
    });
  }

  void _onYouTubeServiceStateChanged() {
    final service = _youTubeService;
    if (service != null && !service.playingFromQueue && service.isPlaying) {
      _mixSession = false;
    }
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
      audioHandler.setOnlineMedia(song, isPlaying: isOnlinePlaying);
    } else if (currentSong != null) {
      _updateNotification();
      HomeWidgetService.updatePlayerWidget(
        currentSong: currentSong,
        isPlaying: _player.state.playing,
        isOnlinePlaying: false,
      );
    }
  }

  Future<void> _stopOnlineAndResumeLocal() async {
    if (_mixSession) {
      _mixSession = false;
      await _youTubeService?.stop();
      notifyListeners();
      return;
    }
    await _youTubeService?.stop();
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

  List<Song> _playlist = [];
  int _currentIndex = 0;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _playbackStateSaveTimer;
  final Completer<void> _initialization = Completer<void>();
  final bool _isEnriching = false;
  final int _enrichedCount = 0;
  bool _shuffleEnabled = false;
  PlaylistMode _loopMode = PlaylistMode.none;
  Song? _lastPlayedSong;
  static const String _lastPlayedSongKey = 'last_played_song';
  bool _hasRestoredState = false;
  bool _handlingQueueCompletion = false;
  bool _settingAudioSource = false;
  Song? _pendingAudioSourceSong;
  final List<Completer<void>> _audioSourceSetWaiters = [];
  final Map<String, int> _ytFastFailRetries = {};

  /// Accumulates per-HLS-segment progress so a `completed` event can be
  /// classified against the track's real length. See [PlaybackEndSignal].
  final TrackProgressAccumulator _onlineProgress = TrackProgressAccumulator();

  /// Detects an online track that stopped advancing before finishing.
  final PlaybackStallWatchdog _onlineStall = PlaybackStallWatchdog();
  Timer? _onlineStallTimer;
  int _onlineStallStartedAt = 0;
  List<Song> get librarySongs => _library.librarySongs;
  List<Song> get songs => _library.songs;
  List<Song> get filteredSongs => _library.filteredSongs;
  bool get isEnriching => _isEnriching;
  int get enrichedCount => _enrichedCount;
  bool get shuffleEnabled => _shuffleEnabled;
  PlaylistMode get loopMode => _loopMode;
  /// Playback position, smoothed so it never runs backwards within a track.
  ///
  /// The player reports a per-segment position for online (HLS) tracks: it
  /// restarts at every segment boundary, roughly 43 times on a 4-minute song.
  /// Handing that straight to the UI makes the elapsed counter and the seek
  /// bar snap back to ~0 every few seconds. [positionStream] emits this value
  /// on every player tick instead of the raw one.
  Stream<Duration> get positionStream => _displayPosition.stream;

  late final StreamController<Duration> _displayPosition =
      StreamController<Duration>.broadcast(
        onListen: _startPositionFeed,
        onCancel: _stopPositionFeed,
      );

  StreamSubscription<Duration>? _positionFeed;

  void _startPositionFeed() {
    _positionFeed ??= _player.stream.position.listen((_) {
      if (!_displayPosition.isClosed) _displayPosition.add(position);
    });
  }

  void _stopPositionFeed() {
    _positionFeed?.cancel();
    _positionFeed = null;
  }

  Stream<bool> get playingStream => _player.stream.playing;
  bool get isPlaying {
    if (_isOnlineNow()) {
      return _youTubeService?.isPlaying ?? false;
    }
    return _player.state.playing;
  }

  Duration get position {
    if (_isOnlineNow()) {
      final yt = _youTubeService;
      if (yt == null) return Duration.zero;
      return onlineDisplayPosition(
        banked: _onlineProgress.banked,
        segmentPosition: yt.player.state.position,
        trackDuration: _onlineTrackDuration,
      );
    }
    return _player.state.position;
  }

  /// Length of the online track being played.
  Duration get _onlineTrackDuration {
    final yt = _youTubeService;
    if (yt == null) return Duration.zero;
    final songMillis = activeSong?.duration;
    return resolveOnlineTrackDuration(
      metadataDuration: songMillis == null
          ? Duration.zero
          : Duration(milliseconds: songMillis),
      segmentDuration: yt.player.state.duration,
    );
  }

  Duration get duration {
    if (_isOnlineNow()) return _onlineTrackDuration;
    return _player.state.duration;
  }

  bool _isOnlineNow() {
    if (_isCurrentSongYouTubeOnly()) return true;
    return _isOnlineOnlySession;
  }

  Song? get activeSong {
    if (_isOnlineNow()) {
      final yt = _youTubeService;
      final audio = yt?.currentAudio;
      if (yt != null && audio != null) {
        final online = onlinePlaylist;
        if (online.isNotEmpty &&
            onlinePlaylistIndex >= 0 &&
            onlinePlaylistIndex < online.length) {
          return online[onlinePlaylistIndex];
        }
        return Song(
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
      }
    }
    return currentSong;
  }

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

  List<String> get artists => _library.artists;
  SongSortOption get currentSortOption => _library.currentSortOption;
  bool get sortAscending => _library.sortAscending;
  bool get isLoading => _library.isLoading;
  ValueNotifier<bool> get loadingNotifier => _library.loadingNotifier;
  String? get error => _library.error;
  final Color? _notificationColor;
  MusicProvider({
    Color? notificationColor,
    SongRepository? songRepository,
    PlaylistRepository? playlistRepository,
    LibraryViewModel? libraryViewModel,
    Player? player,
  }) : // ignore: prefer_initializing_formals - this._notificationColor would make the param private
       _notificationColor = notificationColor,
       _player = player ?? Player(),
       _songRepository = songRepository ?? SongRepository(),
       _playlistRepository = playlistRepository ?? PlaylistRepository(),
       _library = libraryViewModel ?? LibraryViewModel() {
    WidgetsBinding.instance.addObserver(this);
    _library.addListener(notifyListeners);
    _library.onSongUpdated = _syncQueueSong;
    _library.onLibraryCacheCleared = () {
      _playlist.clear();
    };
    _library.onNowPlayingReloadRequested = _loadNowPlayingPlaylist;
    _library.onQueuePersistenceRequested = _ensureCachedSongsInDatabase;
    _player.stream.playlistMode.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });
    _player.stream.playing.listen((_) {
      notifyListeners();
    });
    _player.stream.completed.listen((completed) async {
      if (!completed || _settingAudioSource) return;
      if (_isCurrentSongYouTubeOnly()) {
        if (_handlingQueueCompletion) return;
        _handlingQueueCompletion = true;
        try {
          await _onYouTubeQueueSongCompleted();
        } finally {
          _handlingQueueCompletion = false;
        }
      } else {
        _reportCompletionDispatch('local-queue');
        await _onPlaybackCompleted();
      }
    });
    _initialize().whenComplete(() {
      if (!_initialization.isCompleted) _initialization.complete();
    });
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
    if (_isCurrentSongYouTubeOnly()) return;
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
  bool _isYouTubeOnlySong(Song song) =>
      song.url.startsWith('yt:') && (song.youtubeId?.isNotEmpty ?? false);

  /// Emits a [PlaybackDiagnostics.queueLoaded] snapshot for [queue].
  ///
  /// `onlineMissingDuration` is the field that matters most: an online track
  /// whose persisted duration is 0 disables the premature-end detector, which
  /// is one of the reasons online tracks inside a mixed queue can stop early.
  void _diagnoseQueue(String source, List<Song> queue, {int? startIndex}) {
    PlaybackDiagnostics.queueLoaded(
      source: source,
      length: queue.length,
      onlineCount: queue.where(_isYouTubeOnlySong).length,
      missingDurationCount: queue
          .where((s) => _isYouTubeOnlySong(s) && s.duration <= 0)
          .length,
      startIndex: startIndex ?? _currentIndex,
    );
  }

  bool _isCurrentSongYouTubeOnly() {
    final activePlaylist = _getActivePlaylist();
    if (activePlaylist.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= activePlaylist.length) {
      return false;
    }
    return _isYouTubeOnlySong(activePlaylist[_currentIndex]);
  }

  bool get _isOnlineOnlySession =>
      _mixSession ||
      (_youTubeService?.currentAudio != null &&
          _playlist.isEmpty &&
          _tempPlaylist.isEmpty);
  Future<void> _savePlaybackState() async {
    if (_playlist.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _playlist.length) {
      return;
    }
    try {
      final activePlaylist = _getActivePlaylist();
      final state = PlaybackResumeState(
        index: _currentIndex,
        positionMs: _player.state.position.inMilliseconds,
        shuffleEnabled: _shuffleEnabled,
        loopModeName: _loopMode.name,
        isUsingTempPlaylist: _isUsingTempPlaylist,
        playlistIds: activePlaylist.map((s) => s.id).join(','),
        tempPlaylistIds: _isUsingTempPlaylist
            ? _tempPlaylist.map((s) => s.id).join(',')
            : null,
      );
      await state.save();
      final song = currentSong;
      if (song != null) {
        _lastPlayedSong = song;
        unawaited(_saveLastPlayedSong(song));
      }
      await HomeWidgetService.updateResumeData(
        index: _currentIndex,
        positionMs: _player.state.position.inMilliseconds,
      );
    } catch (e) {}
  }

  Future<void> _restorePlaybackState({bool force = false}) async {
    if (_hasRestoredState && !force) return;
    _hasRestoredState = true;
    try {
      final state = await PlaybackResumeState.load();
      _shuffleEnabled = state?.shuffleEnabled ?? false;
      if (state != null && state.loopModeName.isNotEmpty) {
        _loopMode = PlaylistMode.values.firstWhere(
          (m) => m.name == state.loopModeName,
          orElse: () => PlaylistMode.none,
        );
      }
      _isUsingTempPlaylist = state?.isUsingTempPlaylist ?? false;
      final savedIndex = state?.index;
      final savedPosition = state?.positionMs ?? 0;
      if (state != null &&
          _playlist.isNotEmpty &&
          savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _playlist.length) {
        _currentIndex = savedIndex;
        if (_lastPlayedSong != null) {
          await _setAudioSource(_playlist[_currentIndex]);
          await _player.seek(Duration(milliseconds: savedPosition));
          await _ensureRestoredPaused();
          final song = _playlist[_currentIndex];
          requestThumbnail(song, priority: 0);
          notifyListeners();
        }
      }
    } catch (e) {}
  }

  Future<void> resumeFromLauncher() async {
    if (_player.state.playing) return;
    try {
      await _initialization.future;
      if (currentSong == null) {
        await _restorePlaybackState(force: true);
      }
      if (_playlist.isNotEmpty &&
          _currentIndex >= 0 &&
          _currentIndex < _playlist.length) {
        if (!_player.state.playing) await play();
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> _ensureRestoredPaused() async {
    final song = currentSong;
    if (song != null && _isYouTubeOnlySong(song)) {
      await _youTubeService?.pause();
      return;
    }
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      if (_youTubeService?.playingFromQueue ?? false) {
        await _youTubeService?.pause();
      } else {
        await audioHandler.pause();
      }
    } else {
      await _player.pause();
    }
  }

  Future<void> _initialize() async {
    try {
      await AudioNotificationService.init(
        player: _player,
        notificationColor: _notificationColor,
        onCurrentSongChanged: (song) {},
        onPlaybackStateChanged: (isPlaying) {},
        onSkipToNext: () {
          next();
        },
        onSkipToPrevious: () {
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
    } on Exception catch (e, stackTrace) {
      ErrorTrackingService().recordError(
        e,
        stackTrace,
        context: 'MusicProvider._loadNowPlayingPlaylist',
      );
    }
    _library.initThumbnailService();
    _lastPlayedSong = await _loadLastPlayedSong();
    if (_lastPlayedSong != null) {}
    await _library.loadLocalMusic().catchError((e) {});
    await _loadNowPlayingPlaylist();
    await _restorePlaybackState();
    _playbackStateSaveTimer?.cancel();
    _playbackStateSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _savePlaybackState(),
    );
  }

  bool isThumbnailLoading(Song song) => _library.isThumbnailLoading(song);
  void requestThumbnail(Song song, {int priority = 2}) {
    _library.requestThumbnail(song, priority: priority);
  }

  void _syncQueueSong(Song updated) {
    for (int i = 0; i < _playlist.length; i++) {
      if (_playlist[i].id == updated.id) {
        _playlist[i] = updated;
      }
    }
  }

  Future<void> play() async {
    if (_isOnlineNow()) {
      await _youTubeService?.play();
      notifyListeners();
      return;
    }
    if (currentSong == null && _lastPlayedSong != null) {
      await playSong(_lastPlayedSong!);
      return;
    }
    if (_playlist.isEmpty) return;
    try {
      notifyListeners();
      final audioHandler = AudioNotificationService.audioHandler;
      if (audioHandler != null) {
        await audioHandler.play();
      } else {
        await _player.play();
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_isOnlineNow()) {
      await _youTubeService?.pause();
      notifyListeners();
      return;
    }
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      await audioHandler.pause();
    } else {
      await _player.pause();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _mixSession = false;
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null) {
      await audioHandler.stop();
    } else {
      await _player.stop();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_isOnlineNow() && _youTubeService != null) {
      await _youTubeService!.player.seek(position);
      notifyListeners();
      return;
    }
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
        final testSong = Song(
          id: 0,
          title: 'Test Notification',
          artists: ['TS Music'],
          url: 'test://notification',
          duration: 180000,
        );
        await setPlaylistAndPlay([testSong], 0);
        await audioHandler.play();
      } else {}
    } catch (e) {}
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  void cycleRepeatMode() {
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

  void setSortOption(SongSortOption option) {
    _library.setSortOption(option);
  }

  void toggleSortDirection() {
    _library.toggleSortDirection();
  }

  Future<void> sortSongs({
    required SongSortOption sortBy,
    bool ascending = true,
  }) async {
    try {
      final sortedSongs = _library.sortLibrary(
        sortBy: sortBy,
        ascending: ascending,
      );
      _playlist = sortedSongs;
      try {
        final songIds = <int>[];
        for (final song in _playlist) {
          if (song.id > 0) {
            songIds.add(song.id);
          }
        }
        await _playlistRepository.reorderNowPlayingPlaylist(songIds);
      } catch (e) {}
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refreshSongs() async {
    await _library.refreshSongs();
  }

  Future<void> deleteSong(Song song, {bool deleteFile = true}) async {
    try {
      if (deleteFile && song.url.isNotEmpty) {
        try {
          final file = File(song.url);
          if (await file.exists()) {
            await file.delete();
          } else {}
        } catch (e) {}
      }
      await _songRepository.deleteSong(song.id);
      _playlist.removeWhere((s) => s.id == song.id);
      _library.removeSongFromLibrary(song);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  void addDownloadedSongToLibrary(Song song) {
    if (_library.librarySongs.any((s) => s.url == song.url)) {
      return;
    }
    _library.addSongToLibrary(song);
    _playlist.add(song);
    notifyListeners();
  }

  Future<void> loadLocalMusicWithRetry({bool forceRescan = false}) async {
    await _library.loadLocalMusicWithRetry(forceRescan: forceRescan);
  }

  Future<void> retryLoading() async {
    await _library.retryLoading();
  }

  Future<void> addSong(Song song) async {
    final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _playlist[existingIndex] = song;
      _library.setDisplayedSongs(_playlist);
      await _saveSongsToStorage();
      notifyListeners();
      return;
    }
    if (await _songRepository.existsById(song.id)) return;
    _addSongIfNotExists(song);
    _library.setDisplayedSongs(_playlist);
    await _songRepository.saveSong(song);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> loadFromDatabaseOnly() async {
    await _library.loadFromDatabaseOnly();
  }

  Future<void> loadLocalMusic({bool forceRescan = false}) async {
    await _library.loadLocalMusic(forceRescan: forceRescan);
  }

  Future<void> playSong(Song song) async {
    _mixSession = false;
    await _youTubeService?.stop();
    _isUsingTempPlaylist = false;
    _tempPlaylist.clear();
    var index = _playlist.indexWhere((s) => s.id == song.id);
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
      requestThumbnail(song, priority: 0);
      _lastPlayedSong = song;
      unawaited(_saveLastPlayedSong(song));
      notifyListeners();
    }
  }

  Future<void> playSongFromLibrary(Song song) async {
    _mixSession = false;
    await _youTubeService?.stop();
    _isUsingTempPlaylist = false;
    _tempPlaylist.clear();
    _playlist.clear();
    _playlist.addAll(_library.librarySongs);
    var index = _playlist.indexWhere((s) => s.id == song.id);
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
      requestThumbnail(song, priority: 0);
      notifyListeners();
    }
  }

  Future<void> playSongsFromList(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;
    _mixSession = false;
    await _youTubeService?.stop();
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
    _lastPlayedSong = song;
    unawaited(_saveLastPlayedSong(song));
    notifyListeners();
  }

  List<Song> _tempPlaylist = [];
  bool _isUsingTempPlaylist = false;
  List<Song> get tempPlaylist => _tempPlaylist;
  bool get isUsingTempPlaylist => _isUsingTempPlaylist;
  bool _mixSession = false;
  bool get isMixSession => _mixSession;
  Future<void> setPlaylistAndPlay(List<Song> songs, int startIndex) async {
    if (songs.isEmpty || startIndex < 0 || startIndex >= songs.length) return;
    _mixSession = false;
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

  Future<int> startMixFromSeeds(
    List<Song> seeds, {
    int perSeed = 2,
    int maxTracks = 12,
  }) async {
    final service = _youTubeService;
    if (service == null || seeds.isEmpty) return 0;
    final mixSongs = <Song>[];
    final seen = <String>{};
    for (final seed in seeds.take(maxTracks)) {
      if (mixSongs.length >= maxTracks) break;
      try {
        final results = await service.searchAudio(seed.title);
        var addedFromSeed = 0;
        for (final yt in results) {
          if (seen.add(yt.id)) {
            mixSongs.add(
              Song(
                id: -1,
                youtubeId: yt.id,
                title: yt.title,
                artists: yt.artists.isNotEmpty ? yt.artists : [yt.author],
                album: 'YouTube Mix',
                duration: yt.duration?.inMilliseconds ?? 0,
                albumArtUrl: yt.thumbnailUrl,
                url: 'yt:${yt.id}',
                storageType: StorageType.remote,
              ),
            );
            addedFromSeed++;
            if (mixSongs.length >= maxTracks) break;
          }
          if (addedFromSeed >= perSeed) break;
        }
      } catch (e) {}
    }
    if (mixSongs.isEmpty) return 0;
    await _youTubeService?.stop();
    _tempPlaylist = mixSongs;
    _isUsingTempPlaylist = true;
    _currentIndex = 0;
    await _setAudioSource(mixSongs[0]);
    if (!_isYouTubeOnlySong(mixSongs[0])) {
      await _player.play();
    }
    await _updateNotification();
    requestThumbnail(mixSongs[0], priority: 0);
    notifyListeners();
    return mixSongs.length;
  }

  Future<int> startCuratedMix(String topic, {int maxTracks = 20}) async {
    final service = _youTubeService;
    if (service == null) return 0;
    final List<YouTubeAudio> audios;
    try {
      audios = await service.searchPlaylists(topic, limit: maxTracks);
    } catch (e) {
      return 0;
    }
    if (audios.isEmpty) return 0;
    _mixSession = true;
    await service.playOnlinePlaylist(audios);
    final first = audios.first;
    requestThumbnail(
      Song(
        id: -1,
        youtubeId: first.id,
        title: first.title,
        artists: first.artists.isNotEmpty ? first.artists : [first.author],
        album: 'YouTube Mix',
        duration: first.duration?.inMilliseconds ?? 0,
        albumArtUrl: first.thumbnailUrl,
        url: 'yt:${first.id}',
        storageType: StorageType.remote,
      ),
      priority: 0,
    );
    await _updateNotification();
    notifyListeners();
    return audios.length;
  }

  Future<int> saveTempQueueAsPlaylist(
    String name, {
    String? description,
  }) async {
    final List<Song> localQueue = _isUsingTempPlaylist
        ? _tempPlaylist
        : _playlist;
    final List<Song> queue;
    if (_mixSession && _youTubeService != null) {
      queue = _youTubeService!.onlinePlaylist
          .map(
            (a) => Song(
              id: -1,
              youtubeId: a.id,
              title: a.title,
              artists: a.artists.isNotEmpty ? a.artists : [a.author],
              album: 'YouTube Mix',
              duration: a.duration?.inMilliseconds ?? 0,
              albumArtUrl: a.thumbnailUrl,
              url: 'yt:${a.id}',
              storageType: StorageType.remote,
            ),
          )
          .toList();
    } else {
      queue = localQueue;
    }
    if (queue.isEmpty) return -1;
    final playlistId = await _playlistRepository.createPlaylist(
      name,
      description: description,
    );
    for (final song in queue) {
      try {
        if (song.id > 0) {
          await _songRepository.addToPlaylist(playlistId, [song.id]);
        } else if (song.youtubeId != null) {
          final songId = await _songRepository.addYouTubeSong(
            youtubeId: song.youtubeId!,
            title: song.title,
            artists: song.artists,
            duration: song.duration,
            thumbnailUrl: song.albumArtUrl,
          );
          if (songId > 0) {
            await _songRepository.addToPlaylist(playlistId, [songId]);
          }
        }
      } catch (e) {}
    }
    notifyListeners();
    return playlistId;
  }

  Future<void> next() async {
    if (_isOnlineOnlySession) {
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
    final nextSong = currentPlaylist[_currentIndex];
    _diagnoseQueue('next', currentPlaylist);
    await _setAudioSource(nextSong);
    if (!_isYouTubeOnlySong(nextSong)) {
      await _player.play();
    }
    await _updateNotification();
    if (!_isUsingTempPlaylist) {
      await _updateNowPlayingPlaylist();
    }
    requestThumbnail(nextSong, priority: 0);
    notifyListeners();
  }

  Future<void> previous() async {
    if (_isOnlineOnlySession) {
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
    final prevSong = currentPlaylist[_currentIndex];
    await _setAudioSource(prevSong);
    if (!_isYouTubeOnlySong(prevSong)) {
      await _player.play();
    }
    await _updateNotification();
    if (!_isUsingTempPlaylist) {
      await _updateNowPlayingPlaylist();
    }
    requestThumbnail(prevSong, priority: 0);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isCurrentSongYouTubeOnly() && _youTubeService != null) {
      if (_youTubeService!.isPlaying) {
        await _youTubeService!.pause();
      } else {
        await _youTubeService!.play();
      }
      notifyListeners();
      return;
    }
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

  String? getArtistImageUrl(String artistName) =>
      _library.getArtistImageUrl(artistName);
  String? getAlbumArtUrl(String albumName, {String? artistName}) =>
      _library.getAlbumArtUrl(albumName, artistName: artistName);
  List<Song> getSongsByArtist(String artistName) =>
      _library.getSongsByArtist(artistName);
  List<Song> getSongsByAlbum(String albumName, {String? artistName}) =>
      _library.getSongsByAlbum(albumName, artistName: artistName);
  List<String> getAlbumsByArtist(String artistName) =>
      _library.getAlbumsByArtist(artistName);
  Future<void> filterSongs(String query) async {
    await _library.filterSongs(query);
  }

  Future<void> _loadNowPlayingPlaylist() async {
    try {
      final playlistSongs = await _songRepository.getPlaylistSongs(
        PlaylistRepository.nowPlayingPlaylistId,
      );
      _playlist
        ..clear()
        ..addAll(playlistSongs);
      if (_playlist.isEmpty && _library.librarySongs.isNotEmpty) {
        _playlist.addAll(_library.librarySongs);
        await _updateNowPlayingPlaylist();
      }
      if (_currentIndex >= _playlist.length) {
        _currentIndex = 0;
      }
      notifyListeners();
    } catch (e) {
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'MusicProvider.persistQueueOrder',
      );
    }
  }

  Future<void> _updateNowPlayingPlaylist() async {
    try {
      final songIds = <int>[];
      for (final song in _playlist) {
        if (song.id > 0) {
          songIds.add(song.id);
        }
      }
      await _playlistRepository.updateNowPlayingPlaylist(songIds);
    } catch (e) {
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'MusicProvider.updateNowPlayingPlaylist',
      );
    }
  }

  void _addSongIfNotExists(Song song) {
    _playlist.add(song);
    _library.addSongToLibrary(song);
  }

  void addSongToPlaylist(Song song) {
    _addSongIfNotExists(song);
    notifyListeners();
  }

  Future<void> _setAudioSource(
    Song song, {
    bool automaticRetry = false,
    bool forceDash = false,
  }) async {
    if (_settingAudioSource) {
      _pendingAudioSourceSong = song;
      final waiter = Completer<void>();
      _audioSourceSetWaiters.add(waiter);
      await waiter.future;
      return;
    }
    _settingAudioSource = true;
    Object? failure;
    try {
      await _setAudioSourceUnchecked(
        song,
        automaticRetry: automaticRetry,
        forceDash: forceDash,
      );
    } catch (e) {
      failure = e;
    } finally {
      _settingAudioSource = false;
    }
    if (failure != null) {
      final failed = List<Completer<void>>.of(_audioSourceSetWaiters);
      _audioSourceSetWaiters.clear();
      for (final waiter in failed) {
        if (!waiter.isCompleted) waiter.completeError(failure);
      }
      throw failure;
    }
    final pending = _pendingAudioSourceSong;
    if (pending != null) {
      _pendingAudioSourceSong = null;
      await _setAudioSource(pending);
    }
    final waiters = List<Completer<void>>.of(_audioSourceSetWaiters);
    _audioSourceSetWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _playYouTubeSong(Song song, {bool forceDash = false}) async {
    final yt = _youTubeService;
    if (yt == null) return;
    final ytAudio = YouTubeAudio(
      id: song.youtubeId ?? song.url.replaceFirst('yt:', ''),
      title: song.title,
      author: song.artists.isNotEmpty ? song.artists.first : 'Unknown Artist',
      artists: song.artists,
      duration: Duration(milliseconds: song.duration),
      thumbnailUrl: song.albumArtUrl,
    );
    await yt.playAudio(ytAudio, trackOnline: false, forceDash: forceDash);
    // New track: discard the previous track's progress and restart the stall
    // watchdog, so the new track gets a full stall budget.
    _onlineProgress.reset();
    _onlineStall.reset();
    _onlineStallStartedAt = DateTime.now().millisecondsSinceEpoch;
    _watchForOnlineStalls();
  }

  Future<void> _setAudioSourceUnchecked(
    Song song, {
    bool automaticRetry = false,
    bool forceDash = false,
  }) async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (!automaticRetry) {
      await _library.recordPlay(song);
    }
    if (!_isYouTubeOnlySong(song) &&
        (_youTubeService?.playingFromQueue ?? false)) {
      await _youTubeService?.stop();
    }
    final isLocalFile = song.url.startsWith('/') || song.url.contains(':');
    bool fileExists = false;
    if (isLocalFile) {
      try {
        fileExists = await File(song.url).exists();
      } catch (e) {
        fileExists = false;
      }
    }
    if (_isYouTubeOnlySong(song) && _youTubeService != null) {
      await audioHandler?.stop();
      await _playYouTubeSong(song, forceDash: forceDash);
      return;
    }
    if (isLocalFile && !fileExists && audioHandler != null) {
      await audioHandler.stop();
      String? ytId = song.youtubeId?.isNotEmpty == true ? song.youtubeId : null;
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
        await _playYouTubeSong(ytSong, forceDash: forceDash);
        return;
      }
    }
    _youTubeService?.markLocalPlaybackStarted();
    if (audioHandler != null) {
      final mediaPath = song.url.startsWith('/')
          ? 'file://${song.url}'
          : song.url;
      await audioHandler.setMedia(Media(mediaPath), song: song);
    } else {
      final mediaPath = song.url.startsWith('/')
          ? 'file://${song.url}'
          : song.url;
      await _player.open(Media(mediaPath));
    }
  }

  Future<String?> _searchYouTubeForSong(
    String title,
    List<String> artists,
    int targetDurationMs,
  ) async {
    if (_youTubeService == null) return null;
    try {
      final artist = artists.isNotEmpty ? artists.first : 'Unknown Artist';
      final query = '$title $artist';
      final results = await _youTubeService!.searchAudio(query);
      if (results.isEmpty) return null;
      final targetDurationSec = targetDurationMs / 1000.0;
      YouTubeAudio? bestMatch;
      double minDiff = double.infinity;
      for (var result in results) {
        if (result.duration != null) {
          final diff =
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
      return null;
    }
  }

  Future<void> _updateSongYouTubeId(Song song, String youtubeId) async {
    try {
      await _songRepository.updateYouTubeId(
        filePath: song.url,
        youtubeId: youtubeId,
      );
      final updated = song.copyWith(youtubeId: youtubeId);
      _library.updateSongInPlace(updated);
    } catch (e) {}
  }

  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      if (_player.state.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  Future<void> _saveLastPlayedSong(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPlayedSongKey, jsonEncode(song.toJson()));
    } catch (e) {}
  }

  Future<Song?> _loadLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songJson = prefs.getString(_lastPlayedSongKey);
      if (songJson != null) {
        final song = Song.fromJson(jsonDecode(songJson));
        return song;
      }
    } catch (e) {}
    return null;
  }

  Future<void> _saveSongsToStorage() => _library.saveSongsToCache();
  Future<void> _ensureCachedSongsInDatabase() async {
    try {
      await _songRepository.ensureSongsInDatabase(_playlist);
    } catch (e) {}
  }

  Future<void> setCurrentSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      notifyListeners();
    }
  }

  Future<void> updateSong(Song updatedSong) async {
    final index = _playlist.indexWhere((song) => song.id == updatedSong.id);
    if (index != -1) {
      _playlist[index] = updatedSong;
      _library.updateSongInPlace(updatedSong);
      await _saveSongsToStorage();
      await _updateNowPlayingPlaylist();
      notifyListeners();
    }
  }

  Future<void> scanForNewMusic() async {
    await _library.scanForNewMusic();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _stopPositionFeed();
    _displayPosition.close();
    _playbackStateSaveTimer?.cancel();
    if (!_initialization.isCompleted) _initialization.complete();
    AudioNotificationService.dispose();
    _player.dispose();
    super.dispose();
  }

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
    _library.clearDisplayedSongs();
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
      final songId = await _songRepository.addYouTubeSong(
        youtubeId: youtubeId,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
      );
      if (songId > 0) {
        await _songRepository.addToPlaylist(playlistId, [songId]);
      }
      notifyListeners();
      return songId;
    } catch (e) {
      rethrow;
    }
  }

  static bool isYouTubeOnlyUrl(String url) => url.startsWith('yt:');
  Future<int> addMixedSongToPlaylist(PlaylistItem item, int playlistId) async {
    try {
      if (item.songId != null) {
        await _songRepository.addToPlaylist(playlistId, [item.songId!]);
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
      rethrow;
    }
  }

  Future<void> loadPlaylistAsQueue(int playlistId, {int? startIndex}) async {
    try {
      final playlistSongs = await _songRepository.getPlaylistSongs(playlistId);
      final songs = <Song>[];
      for (final song in playlistSongs) {
        songs.add(song);
        if (!_isYouTubeOnlySong(song)) {
          _library.addSongToLibrary(song);
        }
      }
      if (songs.isNotEmpty) {
        var targetIndex = startIndex?.clamp(0, songs.length - 1).toInt() ?? 0;
        if (startIndex == null) {
          for (var i = 0; i < songs.length; i++) {
            if (_isYouTubeOnlySong(songs[i])) {
              targetIndex = i;
              break;
            }
          }
        }
        final safeStart = targetIndex.clamp(0, songs.length - 1).toInt();
        _tempPlaylist = songs;
        _isUsingTempPlaylist = true;
        _currentIndex = safeStart;
        _diagnoseQueue('playlist:$playlistId', songs, startIndex: safeStart);
        final startSong = songs[safeStart];
        await _setAudioSource(startSong);
        if (!_isYouTubeOnlySong(startSong)) {
          await _player.play();
        }
        await _updateNotification();
      }
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
