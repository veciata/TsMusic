import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/services/youtube_client.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/models/audio_format.dart';
import 'package:tsmusic/models/download_result.dart';
import 'package:tsmusic/models/song.dart' as ts;
import 'package:tsmusic/utils/youtube_artist_parser.dart';
import 'package:tsmusic/utils/lru_cache.dart';
import 'package:tsmusic/services/download_notification_service.dart';
import 'package:tsmusic/services/download_queue.dart';
import 'package:tsmusic/core/services/error_tracking_service.dart';
import 'package:tsmusic/core/services/playback_diagnostics.dart';
import 'package:tsmusic/domain/playback/playback_end_signal.dart';

Map<String, String> _youtubePlaybackHttpHeaders() => {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
  'Cookie': 'CONSENT=YES+cb',
  'Accept': '*/*',
  'Accept-Language': 'en-US,en;q=0.5',
};
const _youtubeDownloadChunkSize = 1024 * 1024;
const _youtubeVisionosUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
const _youtubePlayerApiUrl =
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';
const _youtubeHlsConcurrentSegments = 6;

class HlsAudio {
  final List<String> segments;
  final int totalBytes;
  HlsAudio({required this.segments, required this.totalBytes});
}



class YouTubeAudio {
  final String id;
  final String title;
  final String author;
  final List<String> artists;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? audioUrl;
  YouTubeAudio({
    required this.id,
    required this.title,
    required this.author,
    required this.artists,
    this.duration,
    this.thumbnailUrl,
    this.audioUrl,
  });
  factory YouTubeAudio.fromVideo(Video video) {
    Duration? safeDuration;
    try {
      safeDuration =
          video.duration != null && video.duration!.inMilliseconds > 0
          ? video.duration
          : null;
    } catch (e) {
      safeDuration = null;
    }
    final artistList = YouTubeArtistParser.parseArtistName(
      video.title,
      video.author,
    );
    return YouTubeAudio(
      id: video.id.value,
      title: video.title,
      author: artistList.isNotEmpty ? artistList.first : video.author,
      artists: artistList,
      duration: safeDuration,
      thumbnailUrl: video.thumbnails.mediumResUrl,
    );
  }
}

class DownloadProgress {
  final String videoId;
  final String title;
  double progress;
  bool isDownloading;
  String? error;
  bool cancelRequested;
  bool failed;
  StreamSubscription<List<int>>? subscription;
  final Completer<void>? completer;
  DownloadProgress({
    required this.videoId,
    required this.title,
    this.progress = 0.0,
    this.isDownloading = true,
    this.error,
    this.cancelRequested = false,
    this.failed = false,
    this.subscription,
    this.completer,
  });
}

class YouTubeService with ChangeNotifier {
  static YouTubeService? _instance;
  final YoutubeExplode _yt;
  final http.Client _httpClient;
  final YoutubeHttpClient _ytHttpClient;
  final Player _player;
  final SongRepository _songRepository;
  final bool _ownsPlayer;
  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;
  bool _onlineSessionActive = false;
  final List<YouTubeAudio> _onlinePlaylist = [];
  int _onlinePlaylistIndex = -1;
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final Map<String, VideoSearchList> _searchPages = {};
  late final LRUCache<String, List<YouTubeAudio>> _searchResultsCache;
  late final LRUCache<String, String> _audioUrlCache;
  static const Duration _streamUrlCacheTtl = Duration(minutes: 2);
  final Map<String, int> _audioUrlFetchedAt = {};
  List<ts.Song> Function()? _getLocalSongs;
  bool _playingFromQueue = false;
  bool get playingFromQueue => _playingFromQueue;
  bool _autoSuggestEnabled = false;
  List<YouTubeAudio> _nextSuggestions = [];
  final Map<String, int> _streamFastFailRetries = {};

  /// Batch downloads that outlive the screen which started them.
  ///
  /// Owned here rather than by a dialog so the user can leave the playlist and
  /// watch the batch on the downloads page. Downloading one track at a time is
  /// deliberate: parallel HLS range requests to YouTube draw 403s, which is
  /// what the per-track download tests hit when they run live.
  late final DownloadQueue downloadQueue = DownloadQueue(
    download: (videoId, onProgress) => downloadAudio(
      videoId: videoId,
      onProgress: onProgress,
      preferredFormat: _queueAudioFormat,
      downloadLocation: _queueDownloadLocation,
    ),
    downloadedVideoIds: () => _songRepository.getDownloadedYouTubeIds(),
  );

  AudioFormat _queueAudioFormat = AudioFormat.auto;
  String _queueDownloadLocation = 'internal';

  /// Records the settings a new batch should use.
  ///
  /// Taken when the batch is queued rather than per track so a batch is not
  /// half-downloaded in one format and half in another if the user changes
  /// settings while it runs.
  void configureDownloadQueue({
    required AudioFormat audioFormat,
    required String downloadLocation,
  }) {
    _queueAudioFormat = audioFormat;
    _queueDownloadLocation = downloadLocation;
  }

  /// The YouTube ids already saved on the device, across every list.
  Future<Set<String>> downloadedVideoIds() =>
      _songRepository.getDownloadedYouTubeIds();

  final Map<String, ts.Song> _downloadedSongs = {};

  /// Whether [videoId] is already saved on the device.
  ///
  /// Backed by the database, not by whichever song list happens to be loaded.
  /// The in-memory lists only contain downloads made while that list was open,
  /// so checking them reported false negatives and re-downloaded tracks.
  bool isVideoDownloaded(String videoId) => _downloadedSongs.containsKey(videoId);

  /// The saved song for [videoId], or null if it is not on the device.
  ts.Song? downloadedSongFor(String videoId) => _downloadedSongs[videoId];

  /// Refreshes the in-memory view of what is on the device.
  ///
  /// Call after downloads finish so icons elsewhere (search results, the queue
  /// sheet) stop offering to re-download something that is already saved.
  Future<void> refreshDownloadedVideoIds() async {
    final songs = await _songRepository.getDownloadedYouTubeSongs();
    _downloadedSongs
      ..clear()
      ..addEntries(
        songs
            .where((song) => (song.youtubeId ?? '').isNotEmpty)
            .map((song) => MapEntry(song.youtubeId!, song)),
      );
    notifyListeners();
  }

  /// Per-HLS-segment progress for the current track, so a `completed` event
  /// can be judged against the track's real length.
  final TrackProgressAccumulator _onlineProgress = TrackProgressAccumulator();

  /// Detects an online track that stopped advancing before finishing.
  final PlaybackStallWatchdog _onlineStall = PlaybackStallWatchdog();
  Timer? _onlineStallTimer;
  int _onlineStallStartedAt = 0;
  static const Duration _streamFastFailRetryWindow = Duration(minutes: 5);

  /// Serialises every operation that drives the shared [Player].
  ///
  /// `stop -> open -> play` must never overlap with another cycle. mpv's core is
  /// torn down and rebuilt by each `open`, so two overlapping cycles use a core
  /// that is being replaced underneath them. Measured on a device, the service
  /// watchdog and the provider watchdog both fired on the same stall, each
  /// re-resolved the URL and re-entered [playAudio]; libmpv then died with
  /// SIGSEGV in its `mpv/mpv core` thread, killing the app partway through the
  /// track.
  Future<void> _playerOpQueue = Future<void>.value();

  /// Runs [action] after every previously queued player operation has settled.
  Future<T> _withPlayerLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _playerOpQueue;
    _playerOpQueue = () async {
      try {
        await previous;
      } catch (_) {
        // A failed predecessor must not wedge the queue.
      }
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    }();
    return completer.future;
  }

  bool get autoSuggestEnabled => _autoSuggestEnabled;
  set autoSuggestEnabled(bool value) {
    _autoSuggestEnabled = value;
    notifyListeners();
  }

  List<YouTubeAudio> get nextSuggestions => List.unmodifiable(_nextSuggestions);
  set localSongsCallback(List<ts.Song> Function() callback) {
    _getLocalSongs = callback;
  }

  List<DownloadProgress> get activeDownloads =>
      _activeDownloads.values.toList();
  bool isDownloading(String videoId) {
    final d = _activeDownloads[videoId];
    return d != null && d.isDownloading && d.error == null;
  }

  YouTubeAudio? get currentAudio => _currentAudio;
  bool get isPlaying => _player.state.playing;
  Player get player => _player;
  List<YouTubeAudio> get onlinePlaylist => List.unmodifiable(_onlinePlaylist);
  int get onlinePlaylistIndex => _onlinePlaylistIndex;
  static YouTubeService? get instance => _instance;
  YouTubeService({
    YoutubeExplode? yt,
    http.Client? httpClient,
    Player? player,
    SongRepository? songRepository,
  }) : _yt =
           yt ??
           YoutubeExplode(httpClient: ModernUserAgentHttpClient(httpClient)),
       _httpClient = httpClient ?? http.Client(),
       _ytHttpClient = YoutubeHttpClient(httpClient),
       _player = player ?? Player(),
       _ownsPlayer = player == null,
       _songRepository = songRepository ?? SongRepository() {
    _instance = this;
    _searchResultsCache = LRUCache<String, List<YouTubeAudio>>(
      maxCapacity: 100,
    );
    _audioUrlCache = LRUCache<String, String>(maxCapacity: 200);
    _init();
  }
  Future<StreamManifest> _getManifestWithFallbacks(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(videoId);
    } catch (e) {
      return _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: const [YoutubeApiClient.androidVr, YoutubeApiClient.tv],
      );
    }
  }

  void _init() {
    _player.stream.playing.listen((playing) {
      notifyListeners();
    });
    _player.stream.completed.listen((completed) async {
      if (!completed) return;
      if (_onlinePlaylist.isNotEmpty &&
          !_playingFromQueue &&
          _onlineSessionActive) {
        final state = _player.state;
        final duration = state.duration;
        final position = state.position;
        if (_onlinePlaylistIndex < 0 ||
            _onlinePlaylistIndex >= _onlinePlaylist.length) {
          return;
        }
        final audio = _onlinePlaylist[_onlinePlaylistIndex];
        // `completed` fires once per HLS segment, so position/duration cover
        // only that segment. Judge against the track length plus the progress
        // already banked. A boundary can say "track over" or "keep going"; it
        // cannot say "stream died", since mpv also reports a short position
        // and `playing == false` at every healthy boundary.
        final signal = PlaybackEndSignal(
          position: position,
          expectedDuration: audio.duration ?? Duration.zero,
          progressBeforeEvent: _onlineProgress.banked,
          isPlaying: state.playing,
        );
        final verdict = signal.classify();

        PlaybackDiagnostics.trackCompleted(
          videoId: audio.id,
          positionMs: position.inMilliseconds,
          expectedDurationMs: audio.duration?.inMilliseconds,
          playerDurationMs: duration.inMilliseconds,
          branch: 'service-${signal.label}',
          retries: _streamFastFailRetries.length,
        );

        switch (verdict) {
          case TrackEndVerdict.continueTrack:
            // Segment boundary, not the end of the track. Keep playing.
            _onlineProgress.bank(position);
            return;

          case TrackEndVerdict.finished:
            _onlineProgress.reset();
            _stopStallWatch();
        }
        _streamFastFailRetries.remove(audio.id);
        final nextIndex = _onlinePlaylistIndex + 1;
        if (nextIndex < _onlinePlaylist.length) {
          await playOnlinePlaylistAt(nextIndex);
        } else if (_autoSuggestEnabled) {
          unawaited(_updateSuggestions());
        }
      }
      if (completed) {
        unawaited(_updateSuggestions());
      }
    });
  }

  /// Starts watching [audio] for a stall, retrying it once on a fresh URL if
  /// playback stops advancing partway through.
  ///
  /// This is the only place allowed to conclude that an online stream died. A
  /// `completed` boundary cannot: at every healthy boundary mpv reports a short
  /// position and briefly reports `playing == false` while handing off to the
  /// next segment, which made a boundary-based check misread 23 of 43
  /// boundaries on a track that played to 221s of its 239s.
  void _startStallWatch(YouTubeAudio audio) {
    _stopStallWatch();
    _onlineStallTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // During queue playback the provider owns stall recovery. Both watchdogs
      // watch the same signal with the same timeouts, so they fire on the same
      // tick; letting both recover means two concurrent re-resolves and two
      // concurrent opens of the same track on the shared player.
      if (_playingFromQueue) return;
      // Observe accumulated progress, not the raw player position: for HLS the
      // player position resets at every segment boundary, so watching it
      // directly would read each boundary as a stall.
      final detected = _onlineStall.observe(
        Duration(
          milliseconds:
              DateTime.now().millisecondsSinceEpoch - _onlineStallStartedAt,
        ),
        _onlineProgress.banked + _player.state.position,
        isBuffering: _player.state.buffering,
      );
      if (!detected) return;
      if (!_onlineStall.isTruncated(
        expectedDuration: audio.duration ?? Duration.zero,
        banked: _onlineProgress.banked,
      )) {
        return;
      }
      final retryAt = _streamFastFailRetries[audio.id];
      final alreadyRetried =
          retryAt != null &&
          DateTime.now().millisecondsSinceEpoch - retryAt <
              _streamFastFailRetryWindow.inMilliseconds;
      if (alreadyRetried) return;
      _streamFastFailRetries[audio.id] = DateTime.now().millisecondsSinceEpoch;
      invalidateStreamCache(audio.id);
      PlaybackDiagnostics.playbackFailed(
        videoId: audio.id,
        error: 'stalled partway through track',
        origin: 'service-watchdog',
      );
      await _retryFailedStream(audio);
    });
  }

  /// Cancels the stall watchdog, if running.
  void _stopStallWatch() {
    _onlineStallTimer?.cancel();
    _onlineStallTimer = null;
  }

  Future<void> _retryFailedStream(YouTubeAudio audio) async {
    try {
      // Deliberately no forceDash: the DASH path buffers indefinitely on this
      // network (measured 0ms after 120s), so retrying HLS on a fresh URL is
      // the only recovery that can work.
      await playAudio(audio);
    } catch (e) {
      final nextIndex = _onlinePlaylistIndex + 1;
      if (nextIndex >= 0 && nextIndex < _onlinePlaylist.length) {
        await playOnlinePlaylistAt(nextIndex);
      }
    }
  }

  Future<void> _updateSuggestions() async {
    try {
      final suggestion = await _suggestNextSong();
      _nextSuggestions = [suggestion];
      notifyListeners();
    } catch (_) {
      _nextSuggestions = [];
      notifyListeners();
    }
  }

  void playSuggestion(YouTubeAudio audio) {
    addToOnlinePlaylist(audio);
    if (!isPlaying) {
      playOnlinePlaylistAt(_onlinePlaylist.length - 1);
    }
  }

  void addToOnlinePlaylist(YouTubeAudio audio) {
    _onlinePlaylist.add(audio);
    notifyListeners();
  }

  void removeFromOnlinePlaylist(int index) {
    if (index < 0 || index >= _onlinePlaylist.length) return;
    _onlinePlaylist.removeAt(index);
    if (_onlinePlaylistIndex >= _onlinePlaylist.length) {
      _onlinePlaylistIndex = _onlinePlaylist.length - 1;
    }
    if (_onlinePlaylist.isEmpty) {
      _onlinePlaylistIndex = -1;
    }
    notifyListeners();
  }

  void clearOnlinePlaylist() {
    _onlinePlaylist.clear();
    _onlinePlaylistIndex = -1;
    notifyListeners();
  }

  Future<void> playOnlinePlaylist(
    List<YouTubeAudio> audios, {
    int startIndex = 0,
  }) async {
    _onlinePlaylist
      ..clear()
      ..addAll(audios);
    _onlinePlaylistIndex = -1;
    notifyListeners();
    if (audios.isEmpty) return;
    final int index = startIndex < 0
        ? 0
        : startIndex >= audios.length
        ? audios.length - 1
        : startIndex;
    await playOnlinePlaylistAt(index);
  }

  Future<int> fetchPlaylistAndAdd(String playlistUrl) async {
    try {
      final audios = await _fetchPlaylist(playlistUrl);
      _onlinePlaylist.addAll(audios);
      notifyListeners();
      return audios.length;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YouTubeAudio>> fetchPlaylist(String playlistUrl) async {
    try {
      return await _fetchPlaylist(playlistUrl);
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> fetchPlaylistTitle(String playlistUrl) async {
    try {
      final playlist = await _yt.playlists.get(playlistUrl);
      return playlist.title.isNotEmpty ? playlist.title : null;
    } catch (e) {
      return null;
    }
  }

  Future<YouTubeAudio?> getAudioByVideoId(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return YouTubeAudio.fromVideo(video);
    } catch (e) {
      return null;
    }
  }

  static final RegExp _videoIdRegExp = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static final RegExp _ytInitDataRegExp = RegExp(
    r'var ytInitialData = (\{.*?\});</script>',
  );
  Future<List<YouTubeAudio>> _fetchPlaylist(
    String playlistUrl, {
    int? maxItems,
  }) async {
    final playlistId = PlaylistId(playlistUrl).value;
    final audios = <YouTubeAudio>[];
    final seenIds = <String>{};
    bool reachedMax() => maxItems != null && audios.length >= maxItems;
    final raw = await _ytHttpClient.getString(
      'https://www.youtube.com/playlist?list=$playlistId&hl=en&persist_hl=1',
    );
    final initMatch = _ytInitDataRegExp.firstMatch(raw);
    if (initMatch != null) {
      final initial = json.decode(initMatch.group(1)!) as Map<String, dynamic>;
      await _parsePlaylistPage(initial, audios, seenIds);
      var token = _findContinuationToken(initial);
      final visitedTokens = <String>{};
      while (token != null && visitedTokens.add(token) && !reachedMax()) {
        final next = await _ytHttpClient.sendContinuation(
          'browse',
          token,
          headers: {'x-youtube-client-name': '1'},
        );
        await _parsePlaylistPage(next, audios, seenIds);
        final nextToken = _findContinuationToken(next);
        if (nextToken == null || nextToken == token) break;
        token = nextToken;
      }
    }
    if (audios.isEmpty) {
      try {
        final videos = await _yt.playlists.getVideos(playlistId).toList();
        for (final video in videos) {
          if (!seenIds.add(video.id.value)) continue;
          audios.add(YouTubeAudio.fromVideo(video));
        }
      } catch (e) {}
    }
    return audios;
  }

  Future<void> _parsePlaylistPage(
    Map<String, dynamic> page,
    List<YouTubeAudio> audios,
    Set<String> seenIds,
  ) async {
    final lockups = <dynamic>[];
    _collectLockups(page, lockups);
    for (final entry in lockups) {
      final id = _string(entry, 'contentId');
      if (id == null || !_videoIdRegExp.hasMatch(id) || !seenIds.add(id)) {
        continue;
      }
      final lmv = entry['metadata']?['lockupMetadataViewModel'];
      final titleNode = _read(lmv, 'title');
      final rawTitle = _string(titleNode, 'content');
      final title = (rawTitle ?? '').trim();
      if (title.isEmpty) continue;
      final author = _parseLockupAuthor(lmv);
      final artistList = YouTubeArtistParser.parseArtistName(title, author);
      audios.add(
        YouTubeAudio(
          id: id,
          title: title,
          author: artistList.isNotEmpty ? artistList.first : author,
          artists: artistList,
          thumbnailUrl:
              _parseLockupThumbnail(entry) ??
              'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        ),
      );
    }
  }

  void _collectLockups(dynamic node, List<dynamic> out) {
    if (node is Map<String, dynamic>) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map<String, dynamic>) {
        out.add(lockup);
      }
      for (final v in node.values) {
        _collectLockups(v, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collectLockups(v, out);
      }
    }
  }

  String? _findContinuationToken(dynamic node) {
    if (node is Map<String, dynamic>) {
      final cc = node['continuationCommand'];
      if (cc is Map<String, dynamic> && cc['token'] is String) {
        return cc['token'] as String;
      }
      for (final v in node.values) {
        final token = _findContinuationToken(v);
        if (token != null) return token;
      }
    } else if (node is List) {
      for (final v in node) {
        final token = _findContinuationToken(v);
        if (token != null) return token;
      }
    }
    return null;
  }

  Object? _read(dynamic map, String key) =>
      map is Map<String, dynamic> ? map[key] : null;
  String? _string(dynamic map, String key) {
    final value = _read(map, key);
    return value is String ? value : null;
  }

  String _parseLockupAuthor(dynamic lmv) {
    final metadata = _read(lmv, 'metadata');
    final viewModel = _read(metadata, 'contentMetadataViewModel');
    final rows = _read(viewModel, 'metadataRows');
    if (rows is List && rows.isNotEmpty) {
      final parts = _read(rows.first, 'metadataParts');
      if (parts is List && parts.isNotEmpty) {
        final text = _read(parts.first, 'text');
        return _string(text, 'content') ?? '';
      }
    }
    return '';
  }

  String? _parseLockupThumbnail(dynamic lockup) {
    final contentImage = lockup['contentImage'];
    final thumb = _read(contentImage, 'thumbnailViewModel');
    final image = _read(thumb, 'image');
    final sources = _read(image, 'sources');
    if (sources is List && sources.isNotEmpty) {
      final url = _string(sources.first, 'url');
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  Future<void> playOnlinePlaylistAt(int index) async {
    if (index < 0 || index >= _onlinePlaylist.length) return;
    _onlinePlaylistIndex = index;
    await playAudio(_onlinePlaylist[index]);
  }

  ts.Song? _findLocalMatch(YouTubeAudio audio) {
    final localSongs = _getLocalSongs?.call() ?? [];
    if (localSongs.isEmpty) return null;
    final byYtId = localSongs.cast<ts.Song?>().firstWhere(
      (s) => s!.youtubeId == audio.id,
      orElse: () => null,
    );
    if (byYtId != null) return byYtId;
    final title = audio.title.toLowerCase().trim();
    final artist = audio.artists.isNotEmpty
        ? audio.artists.first.toLowerCase().trim()
        : '';
    for (final s in localSongs) {
      final stitle = s.title.toLowerCase().trim();
      final sartist = s.artists.isNotEmpty
          ? s.artists.first.toLowerCase().trim()
          : '';
      if (stitle == title && sartist == artist) {
        return s;
      }
    }
    return null;
  }

  Future<YouTubeAudio> _suggestNextSong() async {
    final localSongs = _getLocalSongs?.call() ?? [];
    if (localSongs.isNotEmpty) {
      final random = Random();
      final song = localSongs[random.nextInt(localSongs.length)];
      return YouTubeAudio(
        id: song.youtubeId ?? song.title,
        title: song.title,
        author: song.artist,
        artists: song.artists,
        duration: song.durationObject,
        thumbnailUrl: song.albumArtUrl,
      );
    }
    if (_onlinePlaylist.length > 1) {
      return _onlinePlaylist[0];
    }
    throw Exception('No songs available for suggestion');
  }

  /// Opens [audio] and starts playback, serialised against every other player
  /// operation. See [_withPlayerLock] for why this must not be reentrant.
  Future<void> playAudio(
    YouTubeAudio audio, {
    bool trackOnline = true,
    bool forceDash = false,
  }) => _withPlayerLock(
    () =>
        _playAudioLocked(audio, trackOnline: trackOnline, forceDash: forceDash),
  );

  Future<void> _playAudioLocked(
    YouTubeAudio audio, {
    bool trackOnline = true,
    bool forceDash = false,
  }) async {
    try {
      _currentAudio = audio;
      _playingFromQueue = !trackOnline;
      if (trackOnline) {
        final existingIndex = _onlinePlaylist.indexWhere(
          (a) => a.id == audio.id,
        );
        if (existingIndex >= 0) {
          _onlinePlaylistIndex = existingIndex;
        } else {
          _onlinePlaylist.add(audio);
          _onlinePlaylistIndex = _onlinePlaylist.length - 1;
        }
      }
      isLoading.value = true;
      notifyListeners();
      await _player.stop();
      final localMatch = _findLocalMatch(audio);
      if (localMatch != null && File(localMatch.url).existsSync()) {
        await _player.open(Media(localMatch.url));
        _onlineSessionActive = true;
        await _player.play();
        _currentAudio = YouTubeAudio(
          id: audio.id,
          title: audio.title,
          author: audio.author,
          artists: audio.artists,
          duration: audio.duration,
          thumbnailUrl: audio.thumbnailUrl,
          audioUrl: localMatch.url,
        );
        notifyListeners();
        isLoading.value = false;
        return;
      }
      final String? audioUrl = await _getAudioStream(
        audio.id,
        forceDash: forceDash,
      );
      if (audioUrl == null) {
        throw Exception(
          'Ses akışı alınamadı. Lütfen daha sonra tekrar deneyin.',
        );
      }
      try {
        final headers = _youtubePlaybackHttpHeaders();
        await _player.open(Media(audioUrl, httpHeaders: headers));
        _onlineSessionActive = true;
        await _player.play();
      } catch (e) {
        PlaybackDiagnostics.playbackFailed(
          videoId: audio.id,
          error: e,
          origin: trackOnline ? 'search' : 'queue',
        );
        throw Exception('Ses çalınamadı: ${e.toString()}');
      }
      PlaybackDiagnostics.trackOpened(
        videoId: audio.id,
        origin: trackOnline ? 'search' : 'queue',
        expectedDurationMs: audio.duration?.inMilliseconds,
        playerDurationMs: _player.state.duration.inMilliseconds,
        fromQueue: !trackOnline,
      );
      // New track: discard the previous track's progress and restart the watchdog.
      _onlineProgress.reset();
      _onlineStall.reset();
      _onlineStallStartedAt = DateTime.now().millisecondsSinceEpoch;
      _startStallWatch(audio);
      _currentAudio = YouTubeAudio(
        id: audio.id,
        title: audio.title,
        author: audio.author,
        artists: audio.artists,
        duration: audio.duration,
        thumbnailUrl: audio.thumbnailUrl,
        audioUrl: audioUrl,
      );
      notifyListeners();
    } catch (e) {
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<String?> _getAudioStream(
    String videoId, {
    bool forceDash = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    var fromCache = false;
    try {
      final cached = _audioUrlCache.get(videoId);
      final fetchedAt = _audioUrlFetchedAt[videoId];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (cached != null &&
          fetchedAt != null &&
          nowMs - fetchedAt <= _streamUrlCacheTtl.inMilliseconds) {
        fromCache = true;
        PlaybackDiagnostics.resolved(
          videoId: videoId,
          resolver: 'cache',
          url: cached,
          fromCache: true,
          resolveDuration: stopwatch.elapsed,
        );
        return cached;
      }
      _audioUrlCache.remove(videoId);
      _audioUrlFetchedAt.remove(videoId);
      // No automatic DASH fallback, deliberately.
      //
      // When HLS resolution fails -- and it does fail for real reasons, e.g. a
      // DNS lookup returning "No address associated with hostname" -- falling
      // back to DASH looks like recovery but is not: measured on this network
      // the DASH stream buffers at 0ms indefinitely (still 0ms after 120s), so
      // the track silently never starts. That converts a clear, reportable
      // failure into an indefinite hang, which is precisely the symptom users
      // describe as "the song won't play". Retrying HLS and reporting a real
      // error is strictly better than hanging on a format that cannot play.
      if (forceDash) {
        final dash = await _getDashStreamUrl(videoId);
        if (dash != null) {
          _audioUrlCache.put(videoId, dash);
          _audioUrlFetchedAt[videoId] = DateTime.now().millisecondsSinceEpoch;
          PlaybackDiagnostics.resolved(
            videoId: videoId,
            resolver: 'dash-forced',
            url: dash,
            fromCache: fromCache,
            resolveDuration: stopwatch.elapsed,
          );
          return dash;
        }
      }
      final hls = await _resolveHlsWithRetry(videoId);
      if (hls != null) {
        _audioUrlCache.put(videoId, hls.url);
        _audioUrlFetchedAt[videoId] = DateTime.now().millisecondsSinceEpoch;
        PlaybackDiagnostics.resolved(
          videoId: videoId,
          resolver: 'hls',
          url: hls.url,
          fromCache: fromCache,
          resolveDuration: stopwatch.elapsed,
        );
        return hls.url;
      }
      PlaybackDiagnostics.resolveFailed(
        videoId: videoId,
        reason: 'hls unavailable after retries',
      );
      return null;
    } catch (e) {
      PlaybackDiagnostics.resolveFailed(videoId: videoId, reason: e.toString());
      return null;
    }
  }

  void invalidateStreamCache(String videoId) {
    _audioUrlCache.remove(videoId);
    _audioUrlFetchedAt.remove(videoId);
  }

  /// Resolves the HLS media playlist, retrying with a short backoff.
  ///
  /// Resolution talks to youtube.com by hostname, and a single failed lookup is
  /// enough to lose the track: the device in testing is configured with Private
  /// DNS over TLS to 8.8.8.8 and intermittently returns
  /// `No address associated with hostname (errno = 7)`. Retrying turns that blip
  /// into a resolved stream instead of a dead track.
  Future<({String url, int totalBytes})?> _resolveHlsWithRetry(
    String videoId,
  ) async {
    const backoff = [Duration(seconds: 2), Duration(seconds: 5)];
    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      final hls = await getHlsPlaylistUrl(videoId, forceRetry: attempt > 0);
      if (hls != null) return hls;
      if (attempt < backoff.length) {
        PlaybackDiagnostics.resolved(
          videoId: videoId,
          resolver: 'hls-retry-${attempt + 1}',
          url: '',
          fromCache: false,
          resolveDuration: Duration.zero,
        );
        await Future<void>.delayed(backoff[attempt]);
      }
    }
    return null;
  }

  Future<String?> _getDashStreamUrl(String videoId) async {
    try {
      final manifest = await _getManifestWithFallbacks(videoId);
      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        return null;
      }
      final m4aStreams = audioStreams
          .where((s) => s.container.name == 'mp4')
          .toList();
      final StreamInfo streamInfo = m4aStreams.isNotEmpty
          ? m4aStreams.reduce(
              (a, b) =>
                  a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
            )
          : audioStreams.reduce(
              (a, b) =>
                  a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
            );
      final streamUrl = streamInfo.url.toString();
      return streamUrl;
    } catch (e) {
      return null;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> play() async {
    if (_currentAudio != null) {
      await _player.play();
      notifyListeners();
    }
  }

  Future<void> stop() => _withPlayerLock(() async {
    _stopStallWatch();
    PlaybackDiagnostics.stopSampling();
    await _player.stop();
    _currentAudio = null;
    _onlineSessionActive = false;
    _onlinePlaylistIndex = -1;
    _playingFromQueue = false;
    notifyListeners();
  });

  void markLocalPlaybackStarted() {
    // A local file is about to be opened on the same shared player, so the
    // service must not start an online open on top of it.
    _stopStallWatch();
    if (!_onlineSessionActive) return;
    _onlineSessionActive = false;
    notifyListeners();
  }

  void _notifyProgressUpdate() {
    notifyListeners();
  }

  void _addActiveDownload(String videoId, String title) {
    _activeDownloads[videoId] = DownloadProgress(
      videoId: videoId,
      title: title,
      completer: Completer<void>(),
    );
    // Mirror into the queue so single-track downloads show on the downloads
    // page next to batch ones. The download itself is unchanged.
    downloadQueue.beginExternalDownload(videoId, title);
    _notifyProgressUpdate();
  }

  void _updateDownloadProgress(String videoId, double progress) {
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!
        ..progress = progress
        ..isDownloading = progress < 1.0;
      downloadQueue.reportExternalProgress(videoId, progress);
      _notifyProgressUpdate();
      final downloadNotification = DownloadNotificationService();
      if (progress > 0 && progress < 1.0) {
        final totalDownloads = _activeDownloads.length;
        downloadNotification.showDownloadProgress(
          title: download.title,
          progress: progress,
          totalDownloads: totalDownloads,
        );
      }
    }
  }

  void _completeDownload(String videoId) {
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!;
      final title = download.title;
      if (!download.completer!.isCompleted) {
        download.completer!.complete();
      }
      _activeDownloads.remove(videoId);
      downloadQueue.endExternalDownload(videoId);
      _notifyProgressUpdate();
      final downloadNotification = DownloadNotificationService();
      if (_activeDownloads.isEmpty) {
        downloadNotification.cancelDownloadNotification();
      }
      downloadNotification.showDownloadComplete(title: title);
    }
  }

  Future<bool> cancelDownload(String videoId) async {
    final d = _activeDownloads[videoId];
    if (d == null) return false;
    d
      ..cancelRequested = true
      ..isDownloading = false;
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();
    unawaited(
      Future.microtask(() async {
        try {
          await d.subscription?.cancel();
        } catch (e) {}
      }),
    );
    return true;
  }

  void dismissDownload(String videoId) {
    if (!_activeDownloads.containsKey(videoId)) return;
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();
  }

  Future<List<YouTubeAudio>> searchAudio(String query) async {
    try {
      final cached = _searchResultsCache.get(query);
      if (cached != null) {
        return cached;
      }
      final searchResults = await _yt.search.search(query);
      _searchPages[query] = searchResults;
      final videos = searchResults.whereType<Video>().toList();
      final audioList = videos.map(YouTubeAudio.fromVideo).toList();
      _searchResultsCache.put(query, audioList);
      return audioList;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YouTubeAudio>> searchAudioNextPage(String query) async {
    try {
      final VideoSearchList? current = _searchPages[query];
      if (current == null) return [];
      final VideoSearchList? next = await current.nextPage();
      if (next == null) return [];
      _searchPages[query] = next;
      final videos = next.whereType<Video>().toList();
      return videos.map(YouTubeAudio.fromVideo).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YouTubeAudio>> searchPlaylists(String query, {int? limit}) async {
    final page = await _yt.search.searchContent(
      query,
      filter: TypeFilters.playlist,
    );
    final playlists = page.whereType<SearchPlaylist>().toList();
    if (playlists.isEmpty) {
      return searchAudio('$query mix');
    }
    final seenIds = <String>{};
    final audios = <YouTubeAudio>[];
    for (final playlist in playlists) {
      try {
        final fetched = await _fetchPlaylist(
          'https://www.youtube.com/playlist?list=${playlist.id}',
          maxItems: limit,
        );
        for (final audio in fetched) {
          if (seenIds.add(audio.id)) audios.add(audio);
          if (limit != null && audios.length >= limit) return audios;
        }
      } catch (e) {}
    }
    return audios;
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streams = manifest.audioOnly;
      if (streams.isNotEmpty) {
        return streams.withHighestBitrate().url.toString();
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<DownloadResult?> downloadAudio({
    required String videoId,
    void Function(double)? onProgress,
    AudioFormat preferredFormat = AudioFormat.auto,
    String downloadLocation = 'internal',
  }) async {
    if (_activeDownloads.containsKey(videoId) && isDownloading(videoId)) {
      return null;
    }
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();
    Video video;
    try {
      video = await _yt.videos.get(videoId);
    } catch (e) {
      _addActiveDownload(videoId, 'Unknown');
      final failed = _activeDownloads[videoId];
      if (failed != null) {
        failed
          ..error = 'Failed to fetch video information'
          ..isDownloading = false
          ..failed = true;
      }
      downloadQueue.endExternalDownload(
        videoId,
        error: 'Failed to fetch video information',
      );
      _notifyProgressUpdate();
      unawaited(DownloadNotificationService().cancelDownloadNotification());
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'YouTube download: fetch video info failed',
        extras: {'videoId': videoId},
      );
      throw Exception('youtube_html_error');
    }
    _addActiveDownload(videoId, video.title);
    try {
      StreamManifest manifest;
      try {
        manifest = await _getManifestWithFallbacks(videoId);
      } catch (e) {
        throw Exception('youtube_html_error');
      }
      StreamInfo streamInfo;
      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        throw Exception('No audio streams available for video $videoId');
      }
      StreamInfo? selectedStream;
      if (preferredFormat == AudioFormat.m4a) {
        final m4aStreams = audioStreams
            .where((s) => s.container.name == 'mp4')
            .toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
        }
      } else if (preferredFormat == AudioFormat.opus) {
        final opusStreams = audioStreams
            .where((s) => s.container.name == 'webm')
            .toList();
        if (opusStreams.isNotEmpty) {
          selectedStream = opusStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
        }
      } else if (preferredFormat == AudioFormat.mp3) {
        final mp3Streams = audioStreams
            .where(
              (s) => s.container.name == 'mp4' || s.container.name == 'webm',
            )
            .toList();
        if (mp3Streams.isNotEmpty) {
          selectedStream = mp3Streams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
        }
      }
      if (selectedStream == null) {
        final m4aStreams = audioStreams
            .where((s) => s.container.name == 'mp4')
            .toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
        } else {
          selectedStream = audioStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
        }
      }
      streamInfo = selectedStream;
      final musicDir = await _getMusicDirectory(downloadLocation);
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      String audioExtension;
      if (streamInfo.container.name == 'mp4') {
        audioExtension = 'm4a';
      } else if (streamInfo.container.name == 'webm') {
        audioExtension = 'opus';
      } else {
        audioExtension = streamInfo.container.name;
      }
      final existingSong = await _songRepository.getSongByYouTubeId(videoId);
      if (existingSong != null) {
        final existingPath = existingSong.url;
        final existingFile = File(existingPath);
        if (await existingFile.exists()) {
          _completeDownload(videoId);
          return DownloadResult(
            filePath: existingPath,
            song: await _addDownloadedSongToLibrary(
              videoId: videoId,
              filePath: existingPath,
              title: video.title,
              artists: YouTubeArtistParser.parseArtistName(
                video.title,
                video.author,
              ),
              duration: video.duration?.inMilliseconds ?? 0,
              thumbnailUrl: video.thumbnails.mediumResUrl,
            ),
          );
        }
      }
      final finalFile = File(
        path.join(musicDir.path, '$safeTitle.$audioExtension'),
      );
      if (await finalFile.exists()) {
        final fileSize = await finalFile.length();
        if (fileSize > 0) {
          _completeDownload(videoId);
          return DownloadResult(
            filePath: finalFile.path,
            song: await _addDownloadedSongToLibrary(
              videoId: videoId,
              filePath: finalFile.path,
              title: video.title,
              artists: YouTubeArtistParser.parseArtistName(
                video.title,
                video.author,
              ),
              duration: video.duration?.inMilliseconds ?? 0,
              thumbnailUrl: video.thumbnails.mediumResUrl,
            ),
          );
        } else {
          await finalFile.delete();
        }
      }
      final downloadProgress = _activeDownloads[videoId];
      if (audioExtension == 'm4a') {
        try {
          final hls = await fetchHlsAudioSegments(videoId);
          if (hls != null) {
            await downloadHlsSegments(
              videoId: videoId,
              segmentUrls: hls.segments,
              file: finalFile,
              totalBytes: hls.totalBytes,
              onProgress: onProgress,
            );
            if (downloadProgress?.cancelRequested == true) {
              if (await finalFile.exists()) {
                await finalFile.delete();
              }
              _completeDownload(videoId);
              return null;
            }
            _updateDownloadProgress(videoId, 1.0);
            _completeDownload(videoId);
            return DownloadResult(
              filePath: finalFile.path,
              song: await _addDownloadedSongToLibrary(
                videoId: videoId,
                filePath: finalFile.path,
                title: video.title,
                artists: YouTubeArtistParser.parseArtistName(
                  video.title,
                  video.author,
                ),
                duration: video.duration?.inMilliseconds ?? 0,
                thumbnailUrl: video.thumbnails.mediumResUrl,
              ),
            );
          }
        } catch (e) {
          if (await finalFile.exists()) {
            await finalFile.delete();
          }
        }
      }
      final contentLength = streamInfo.size.totalBytes;
      var receivedBytes = 0;
      var lastProgressUpdate = DateTime.now();
      const stallTimeout = Duration(seconds: 30);
      const maxStreamAttempts = 2;
      var streamInfoForAttempt = streamInfo;
      for (var attempt = 1; attempt <= maxStreamAttempts; attempt++) {
        if (attempt > 1) {
          try {
            final retryManifest = await _getManifestWithFallbacks(videoId);
            final retryStreams = retryManifest.audioOnly.toList();
            if (retryStreams.isEmpty) {
              throw Exception('youtube_html_error');
            }
            streamInfoForAttempt = retryStreams.reduce(
              (a, b) =>
                  a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
            );
          } catch (e) {
            throw Exception('youtube_html_error');
          }
        }
        try {
          final sink = finalFile.openWrite();
          var activeStreamInfo = streamInfoForAttempt;
          var offset = 0;
          var consecutiveChunkFailures = 0;
          const maxChunkFailures = 3;
          while (offset < contentLength) {
            if (downloadProgress?.cancelRequested == true) break;
            final chunkEnd = min(
              offset + _youtubeDownloadChunkSize - 1,
              contentLength - 1,
            );
            try {
              final request = http.Request('GET', activeStreamInfo.url)
                ..headers.addAll(_youtubePlaybackHttpHeaders())
                ..headers['Range'] = 'bytes=$offset-$chunkEnd';
              final response = await _httpClient
                  .send(request)
                  .timeout(stallTimeout);
              if (response.statusCode == 200 || response.statusCode == 206) {
                await for (final chunk in response.stream.timeout(
                  const Duration(seconds: 60),
                )) {
                  if (downloadProgress?.cancelRequested == true) break;
                  sink.add(chunk);
                  receivedBytes += chunk.length;
                  final now = DateTime.now();
                  if (now.difference(lastProgressUpdate).inMilliseconds > 100 &&
                      contentLength > 0) {
                    lastProgressUpdate = now;
                    final progress = receivedBytes / contentLength;
                    _updateDownloadProgress(videoId, progress);
                    onProgress?.call(progress);
                  }
                }
                offset = chunkEnd + 1;
                consecutiveChunkFailures = 0;
              } else {
                throw HttpException(
                  'Chunk rejected with HTTP ${response.statusCode}',
                );
              }
            } catch (e) {
              consecutiveChunkFailures++;
              if (consecutiveChunkFailures >= maxChunkFailures) {
                rethrow;
              }
              final retryManifest = await _getManifestWithFallbacks(videoId);
              final retryStreams = retryManifest.audioOnly.toList();
              if (retryStreams.isEmpty) {
                throw Exception('youtube_html_error');
              }
              activeStreamInfo = retryStreams.reduce(
                (a, b) =>
                    a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
              );
            }
          }
          await sink.flush();
          await sink.close();
          break;
        } on Exception {
          if (await finalFile.exists()) {
            await finalFile.delete();
          }
          if (attempt == maxStreamAttempts) {
            rethrow;
          }
        }
      }
      if (downloadProgress?.cancelRequested == true) {
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        _completeDownload(videoId);
        return null;
      }
      final song = await _addDownloadedSongToLibrary(
        videoId: videoId,
        filePath: finalFile.path,
        title: video.title,
        artists: YouTubeArtistParser.parseArtistName(video.title, video.author),
        duration: video.duration?.inMilliseconds ?? 0,
        thumbnailUrl: video.thumbnails.mediumResUrl,
      );
      _updateDownloadProgress(videoId, 1.0);
      _completeDownload(videoId);
      return DownloadResult(filePath: finalFile.path, song: song);
    } catch (e) {
      final download = _activeDownloads[videoId];
      final errorStr = e.toString().toLowerCase();
      final isHtmlError =
          errorStr.contains('youtube_html_error') ||
          errorStr.contains('html') ||
          errorStr.contains('ip') ||
          errorStr.contains('consent') ||
          errorStr.contains('blocked') ||
          errorStr.contains('unavailable');
      ErrorTrackingService().recordError(
        e,
        StackTrace.current,
        context: 'YouTube download failed: $videoId',
        extras: {
          'videoId': videoId,
          'title': download?.title,
          'isHtmlError': isHtmlError,
        },
      );
      if (download != null) {
        download
          ..isDownloading = false
          ..failed = true
          ..error = isHtmlError
              ? 'youtube_html_error'
              : (download.cancelRequested ? 'Canceled' : 'Download failed');
      }
      downloadQueue.endExternalDownload(
        videoId,
        error: isHtmlError
            ? 'youtube_html_error'
            : (download?.cancelRequested == true
                  ? 'Canceled'
                  : 'Download failed'),
      );
      _notifyProgressUpdate();
      unawaited(DownloadNotificationService().cancelDownloadNotification());
      rethrow;
    } finally {}
  }

  /// Visitor data for the visionOS InnerTube client.
  ///
  /// Cached, because [getHlsPlaylistUrl] needs it on *every* stream resolve and
  /// each uncached call re-downloads the entire youtube.com homepage. That is a
  /// multi-hundred-kilobyte request per track, which is what pushes the client
  /// into YouTube's rate limiting: measured on a device after a session of
  /// repeated resolves, HLS resolution started failing outright and playback
  /// silently fell back to the DASH stream, which buffers indefinitely on this
  /// network. One fetch per session is plenty.
  /// Static because it is a property of the device, not of one service instance:
  /// re-creating the service must not re-download the homepage.
  static String? _visitorDataCache;
  static DateTime? _visitorDataFetchedAt;

  /// How long a good visitorData value stays usable.
  static const Duration _visitorDataTtl = Duration(hours: 6);

  /// How long to wait before re-attempting after a failed fetch, so a blocked
  /// client retries at a human pace instead of once per track.
  static const Duration _visitorDataRetryDelay = Duration(minutes: 2);

  /// In-flight fetch, so concurrent resolves share one request instead of each
  /// downloading the ~890KB homepage. Four `playAudio` calls racing on a queue
  /// used to fire four simultaneous homepage downloads.
  static Future<String?>? _visitorDataInFlight;

  /// [forceRetry] bypasses the negative cache, so an intentional backoff retry
  /// actually reaches the network instead of being short-circuited by the
  /// cooldown meant for unrelated rapid calls.
  Future<String?> _fetchVisionosVisitorData({bool forceRetry = false}) async {
    final cached = _visitorDataCache;
    final fetchedAt = _visitorDataFetchedAt;
    if (cached != null && fetchedAt != null) {
      final age = DateTime.now().difference(fetchedAt);
      if (age < _visitorDataTtl) return cached;
    } else if (fetchedAt != null && !forceRetry) {
      // A previous attempt failed; don't hammer youtube.com again immediately.
      final sinceFailure = DateTime.now().difference(fetchedAt);
      if (sinceFailure < _visitorDataRetryDelay) return null;
    }
    final inFlight = _visitorDataInFlight;
    if (inFlight != null) return inFlight;

    final future = _doFetchVisionosVisitorData();
    _visitorDataInFlight = future;
    try {
      return await future;
    } finally {
      _visitorDataInFlight = null;
    }
  }

  Future<String?> _doFetchVisionosVisitorData() async {
    final cached = _visitorDataCache;
    final fetchedAt = _visitorDataFetchedAt;
    if (cached != null && fetchedAt != null) {
      final age = DateTime.now().difference(fetchedAt);
      if (age < _visitorDataTtl) return cached;
    } else if (fetchedAt != null) {
      // A previous attempt failed; don't hammer youtube.com again immediately.
      final sinceFailure = DateTime.now().difference(fetchedAt);
      if (sinceFailure < _visitorDataRetryDelay) return null;
    }
    // Two attempts: the homepage fetch is the single point of failure for all
    // online playback, and it intermittently comes back without VISITOR_DATA (a
    // throttled or variant response). One retry turns a transient miss into a
    // success without meaningfully adding request volume.
    String? lastReason;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      try {
        final response = await _httpClient
            .get(
              Uri.parse('https://www.youtube.com/'),
              headers: {
                'User-Agent': _youtubeVisionosUserAgent,
                // The rest of the client already sends these; matching them here
                // keeps the homepage response on the same non-consent variant.
                ..._youtubePlaybackHttpHeaders(),
              },
            )
            .timeout(const Duration(seconds: 15));
        final match = RegExp(
          r'"VISITOR_DATA":"([^"]+)"',
        ).firstMatch(response.body);
        final value = match?.group(1);
        if (value != null && value.isNotEmpty) {
          _visitorDataCache = value;
          _visitorDataFetchedAt = DateTime.now();
          return value;
        }
        lastReason =
            'http ${response.statusCode} bytes=${response.body.length} '
            'no VISITOR_DATA';
      } catch (e) {
        lastReason = '$e';
      }
    }
    _visitorDataFetchedAt = DateTime.now();
    PlaybackDiagnostics.resolveFailed(
      videoId: '<visitor-data>',
      reason: 'visitorData fetch failed: $lastReason',
    );
    return null;
  }

  Future<({String url, int totalBytes})?> getHlsPlaylistUrl(
    String videoId, {
    bool forceRetry = false,
  }) async {
    try {
      final visitorData = await _fetchVisionosVisitorData(
        forceRetry: forceRetry,
      );
      if (visitorData == null || visitorData.isEmpty) {
        PlaybackDiagnostics.resolveFailed(
          videoId: videoId,
          reason: 'no visitorData',
        );
        return null;
      }
      final payload = {
        'context': {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '1.02',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice17,1',
            'userAgent': _youtubeVisionosUserAgent,
            'osName': 'visionOS',
            'osVersion': '26.5.23O471',
            'visitorData': visitorData,
            'hl': 'en',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
        'videoId': videoId,
      };
      final playerResponse = await _httpClient
          .post(
            Uri.parse(_youtubePlayerApiUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _youtubeVisionosUserAgent,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      if (playerResponse.statusCode != 200) {
        PlaybackDiagnostics.resolveFailed(
          videoId: videoId,
          reason: 'player api http ${playerResponse.statusCode}',
        );
        return null;
      }
      final player = jsonDecode(playerResponse.body) as Map<String, dynamic>;
      final status = player['playabilityStatus']?['status'];
      if (status != 'OK') {
        PlaybackDiagnostics.resolveFailed(
          videoId: videoId,
          reason:
              'playability=$status ${player['playabilityStatus']?['reason']}',
        );
        return null;
      }
      final streaming = player['streamingData'] as Map<String, dynamic>?;
      final hlsManifestUrl = streaming?['hlsManifestUrl'] as String?;
      if (hlsManifestUrl == null || hlsManifestUrl.isEmpty) {
        return null;
      }
      final headers = {
        ..._youtubePlaybackHttpHeaders(),
        'User-Agent': _youtubeVisionosUserAgent,
      };
      final masterResponse = await _httpClient
          .get(Uri.parse(hlsManifestUrl), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (masterResponse.statusCode != 200) return null;
      String? bestAudioUrl;
      var bestBytes = -1;
      for (final line in masterResponse.body.split('\n')) {
        if (!line.startsWith('#EXT-X-MEDIA:') || !line.contains('TYPE=AUDIO')) {
          continue;
        }
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (uriMatch == null) continue;
        var bytes = -1;
        final byteMatch = RegExp(
          r'clen(?:%3D|=)(\d+)',
        ).firstMatch(uriMatch.group(1)!);
        if (byteMatch != null) {
          bytes = int.tryParse(byteMatch.group(1)!) ?? -1;
        }
        if (bytes > bestBytes) {
          bestBytes = bytes;
          bestAudioUrl = uriMatch.group(1);
        }
      }
      if (bestAudioUrl == null) {
        PlaybackDiagnostics.resolveFailed(
          videoId: videoId,
          reason: 'no audio rendition in master playlist',
        );
        return null;
      }
      return (url: bestAudioUrl, totalBytes: bestBytes);
    } catch (e) {
      PlaybackDiagnostics.resolveFailed(videoId: videoId, reason: '$e');
      return null;
    }
  }

  Future<HlsAudio?> fetchHlsAudioSegments(String videoId) async {
    try {
      final playlist = await getHlsPlaylistUrl(videoId);
      if (playlist == null) return null;
      final bestAudioUrl = playlist.url;
      final headers = {
        ..._youtubePlaybackHttpHeaders(),
        'User-Agent': _youtubeVisionosUserAgent,
      };
      final mediaResponse = await _httpClient
          .get(Uri.parse(bestAudioUrl), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (mediaResponse.statusCode != 200) return null;
      final baseUrl = bestAudioUrl.substring(
        0,
        bestAudioUrl.lastIndexOf('/') + 1,
      );
      final segmentUrls = <String>[];
      for (final line in mediaResponse.body.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        segmentUrls.add(
          trimmed.startsWith('http') || trimmed.startsWith('https')
              ? trimmed
              : baseUrl + trimmed,
        );
      }
      if (segmentUrls.isEmpty) return null;
      return HlsAudio(segments: segmentUrls, totalBytes: playlist.totalBytes);
    } catch (e) {
      return null;
    }
  }

  Future<int> downloadHlsSegments({
    required String videoId,
    required List<String> segmentUrls,
    required File file,
    required int totalBytes,
    void Function(double)? onProgress,
  }) async {
    final downloadProgress = _activeDownloads[videoId];
    const segmentTimeout = Duration(seconds: 30);
    const bodyTimeout = Duration(seconds: 60);
    const maxAttempts = 3;
    Future<Uint8List> fetchSegment(int index, String url) async {
      var attempts = 0;
      while (true) {
        attempts++;
        try {
          final request = http.Request('GET', Uri.parse(url))
            ..headers.addAll(_youtubePlaybackHttpHeaders())
            ..headers['User-Agent'] = _youtubeVisionosUserAgent;
          final response = await _httpClient
              .send(request)
              .timeout(segmentTimeout);
          if (response.statusCode == 200 || response.statusCode == 206) {
            final builder = BytesBuilder(copy: false);
            await for (final chunk in response.stream.timeout(bodyTimeout)) {
              if (downloadProgress?.cancelRequested == true) break;
              builder.add(chunk);
            }
            return builder.takeBytes();
          }
          if (attempts >= maxAttempts) {
            throw HttpException(
              'HLS segment $index rejected with HTTP '
              '${response.statusCode}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 800));
        } catch (e) {
          if (attempts >= maxAttempts) rethrow;
        }
      }
    }

    final results = <int, Uint8List>{};
    var receivedBytes = 0;
    var nextIndex = 0;
    var lastProgressUpdate = DateTime.now();
    final errors = <Object>[];
    Future<void> worker() async {
      while (nextIndex < segmentUrls.length &&
          errors.isEmpty &&
          !(downloadProgress?.cancelRequested == true)) {
        final index = nextIndex++;
        try {
          final bytes = await fetchSegment(index, segmentUrls[index]);
          results[index] = bytes;
          receivedBytes += bytes.length;
          final now = DateTime.now();
          if (now.difference(lastProgressUpdate).inMilliseconds > 100 &&
              totalBytes > 0) {
            lastProgressUpdate = now;
            final progress = (receivedBytes / totalBytes)
                .clamp(0.0, 1.0)
                .toDouble();
            _updateDownloadProgress(videoId, progress);
            onProgress?.call(progress);
          }
        } catch (e) {
          errors.add(e);
        }
      }
    }

    final workerCount = min(_youtubeHlsConcurrentSegments, segmentUrls.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    if (errors.isNotEmpty) {
      throw errors.first;
    }
    if (downloadProgress?.cancelRequested == true) {
      return receivedBytes;
    }
    final sink = file.openWrite();
    try {
      for (var i = 0; i < segmentUrls.length; i++) {
        final bytes = results[i];
        if (bytes != null) sink.add(bytes);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }
    onProgress?.call(1.0);
    return receivedBytes;
  }

  Future<Directory> _getMusicDirectory(String downloadLocation) async {
    if (kIsWeb) {
      throw UnsupportedError('Downloads are not supported on Web.');
    }
    Directory? baseDir;
    if (Platform.isAndroid) {
      if (downloadLocation == 'downloads') {
        baseDir = Directory('/storage/emulated/0/Download');
      } else if (downloadLocation == 'music') {
        baseDir = Directory('/storage/emulated/0/Music');
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else if (Platform.isIOS) {
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getDownloadsDirectory();
      if (baseDir == null) {
        throw Exception('Could not get downloads directory.');
      }
    }
    final musicDir = Directory(path.join(baseDir.path, 'tsmusic'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<ts.Song> _addDownloadedSongToLibrary({
    required String videoId,
    required String filePath,
    required String title,
    required List<String> artists,
    required int duration,
    String? thumbnailUrl,
  }) async {
    try {
      String? thumbnailPath;
      if (thumbnailUrl != null) {
        thumbnailPath = await _downloadThumbnail(videoId, thumbnailUrl);
      }
      final song = await _songRepository.addSongFromYouTube(
        videoId: videoId,
        filePath: filePath,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailPath: thumbnailPath,
      );
      // The track is on the device now, so every "is this downloaded?" check
      // must start saying yes. The batch queue reads this cache before it
      // downloads, so leaving it stale would re-fetch the same track.
      _downloadedSongs[videoId] = song;
      return song;
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> _downloadThumbnail(
    String videoId,
    String thumbnailUrl,
  ) async {
    try {
      final musicDir = await _getMusicDirectory('internal');
      final thumbnailFile = File(
        path.join(musicDir.path, '${videoId}_thumb.jpg'),
      );
      if (await thumbnailFile.exists()) {
        return thumbnailFile.path;
      }
      final response = await _httpClient
          .get(Uri.parse(thumbnailUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await thumbnailFile.writeAsBytes(response.bodyBytes);
        return thumbnailFile.path;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    for (final download in _activeDownloads.values) {
      download.completer?.completeError('Service disposed');
    }
    _activeDownloads.clear();
    if (_ownsPlayer) _player.dispose();
    _httpClient.close();
    isLoading.dispose();
    super.dispose();
  }
}
