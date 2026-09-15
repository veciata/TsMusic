import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/services/youtube_client.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/audio_format.dart';
import 'package:tsmusic/models/song.dart' as ts;
import 'package:tsmusic/utils/youtube_artist_parser.dart';
import 'package:tsmusic/utils/lru_cache.dart';
import 'package:tsmusic/services/download_notification_service.dart';
import 'package:tsmusic/core/services/error_tracking_service.dart';

/// YouTube googlevideo akışları libmpv'nin varsayılan User-Agent'ı ile 403 döner;
/// tarayıcı benzeri başlıklar ve [Referer] gerekir (youtube_explode ile uyumlu).
Map<String, String> _youtubePlaybackHttpHeaders() => {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
  'Cookie': 'CONSENT=YES+cb',
  'Accept': '*/*',
  'Accept-Language': 'en-US,en;q=0.5',
};

/// Chunk size for audio downloads. YouTube's CDN throttles/stalls a single
/// full-file Range request for unsigned c=ANDROID streams, while small
/// (<=1 MiB) ranged requests succeed. Keep chunks well under the 2 MiB range
/// that starts getting rejected with HTTP 403.
const _youtubeDownloadChunkSize = 1024 * 1024;

/// YouTube inspects ranges of unsigned c=ANDROID DASH streams and refuses
/// anything past ~1 MiB on bot-checked networks, so the DASH downloader above
/// caps out there. The visionos player client instead provides VOD HLS (m3u8):
/// its audio is served as many small independent segments which download
/// reliably even under that same enforcement. These constants mirror what
/// yt-dlp uses for its working `visionos` player request.
const _youtubeVisionosUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
const _youtubePlayerApiUrl =
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

/// Resolved VOD-HLS audio for a video: the media segment URLs and the total
/// byte size of the chosen audio group (parsed from the playlist's clen).
class _HlsAudio {
  final List<String> segments;
  final int totalBytes;
  _HlsAudio({required this.segments, required this.totalBytes});
}

class DownloadResult {
  final String filePath;
  final ts.Song song;
  DownloadResult({required this.filePath, required this.song});
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

  final Map<String, DownloadProgress> _activeDownloads = {};
  YouTubeAudio? _currentAudio;

  final List<YouTubeAudio> _onlinePlaylist = [];
  int _onlinePlaylistIndex = -1;

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final Map<String, VideoSearchList> _searchPages = {};

  // Caches for performance optimization
  late final LRUCache<String, List<YouTubeAudio>>
  _searchResultsCache; // Cache search results
  late final LRUCache<String, String> _audioUrlCache; // Cache audio stream URLs

  Function()? _stopOtherPlayer;
  List<ts.Song> Function()? _getLocalSongs;

  // True when the current audio belongs to the main player queue (e.g. a
  // YouTube-only song stored in a playlist). In this mode the service does
  // not track the online playlist or auto-advance it.
  bool _playingFromQueue = false;

  bool get playingFromQueue => _playingFromQueue;

  // Auto-suggest state
  bool _autoSuggestEnabled = false;
  List<YouTubeAudio> _nextSuggestions = [];

  bool get autoSuggestEnabled => _autoSuggestEnabled;
  set autoSuggestEnabled(bool value) {
    _autoSuggestEnabled = value;
    notifyListeners();
  }

  List<YouTubeAudio> get nextSuggestions => List.unmodifiable(_nextSuggestions);

  set localSongsCallback(List<ts.Song> Function() callback) {
    _getLocalSongs = callback;
  }

  // Getters
  List<DownloadProgress> get activeDownloads =>
      _activeDownloads.values.toList();

  bool isDownloading(String videoId) {
    final d = _activeDownloads[videoId];
    return d != null && d.isDownloading && d.error == null;
  }

  YouTubeAudio? get currentAudio => _currentAudio;
  bool get isPlaying => _player.state.playing;
  Player get player => _player;

  // Online playlist
  List<YouTubeAudio> get onlinePlaylist => List.unmodifiable(_onlinePlaylist);
  int get onlinePlaylistIndex => _onlinePlaylistIndex;

  static YouTubeService? get instance => _instance;

  set stopOtherPlayerCallback(Function() callback) {
    _stopOtherPlayer = callback;
  }

  // Public constructor
  YouTubeService({YoutubeExplode? yt, http.Client? httpClient, Player? player})
    : _yt =
          yt ??
          YoutubeExplode(httpClient: ModernUserAgentHttpClient(httpClient)),
      _httpClient = httpClient ?? http.Client(),
      _ytHttpClient = YoutubeHttpClient(httpClient),
      _player = player ?? Player() {
    _instance = this;
    // Initialize caches with max capacity
    _searchResultsCache = LRUCache<String, List<YouTubeAudio>>(
      maxCapacity: 100,
    );
    _audioUrlCache = LRUCache<String, String>(maxCapacity: 200);
    _init();
  }

  // Manifest strategy for youtube_explode_dart 3.1.0. Passing an explicit
  // list disables the package's own client selection, so don't hardcode one:
  // the old androidVr/tv chain is now rejected by YouTube's bot-check ("The
  // page needs to be reloaded"), while the package defaults (androidSdkless,
  // retrying with tv) still work. Try defaults first, then an explicit pair
  // as a last resort.
  Future<StreamManifest> _getManifestWithFallbacks(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(videoId);
    } catch (e) {
      debugPrint(
        'Package-default manifest clients failed ($e); retrying with '
        'explicit clients.',
      );
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
      if (completed && _onlinePlaylist.isNotEmpty && !_playingFromQueue) {
        final nextIndex = _onlinePlaylistIndex + 1;
        if (nextIndex < _onlinePlaylist.length) {
          await playOnlinePlaylistAt(nextIndex);
        } else if (_autoSuggestEnabled) {
          // Queue exhausted and auto-suggest on: suggest next
          unawaited(_updateSuggestions());
        }
      }
      if (completed) {
        unawaited(_updateSuggestions());
      }
    });
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

  // ===== ONLINE PLAYLIST MANAGEMENT =====
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

  Future<int> fetchPlaylistAndAdd(String playlistUrl) async {
    try {
      final audios = await _fetchPlaylist(playlistUrl);
      _onlinePlaylist.addAll(audios);
      notifyListeners();
      return audios.length;
    } catch (e) {
      debugPrint('Error fetching playlist: $e');
      rethrow;
    }
  }

  /// Fetches a YouTube playlist's videos without touching the online playlist.
  Future<List<YouTubeAudio>> fetchPlaylist(String playlistUrl) async {
    try {
      return await _fetchPlaylist(playlistUrl);
    } catch (e) {
      debugPrint('Error fetching playlist: $e');
      rethrow;
    }
  }

  static final RegExp _videoIdRegExp = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static final RegExp _ytInitDataRegExp = RegExp(
    r'var ytInitialData = (\{.*?\});</script>',
  );

  /// Fetches a YouTube playlist's videos. Handles both the new `lockupViewModel`
  /// layout (videos not filtered out when the channel id is missing) and falls
  /// back to the classic playlist API when the new layout isn't present.
  Future<List<YouTubeAudio>> _fetchPlaylist(String playlistUrl) async {
    final playlistId = PlaylistId(playlistUrl).value;
    final audios = <YouTubeAudio>[];
    final seenIds = <String>{};

    final raw = await _ytHttpClient.getString(
      'https://www.youtube.com/playlist?list=$playlistId&hl=en&persist_hl=1',
    );
    final initMatch = _ytInitDataRegExp.firstMatch(raw);
    if (initMatch != null) {
      final initial = json.decode(initMatch.group(1)!) as Map<String, dynamic>;
      await _parsePlaylistPage(initial, audios, seenIds);

      // Follow pagination until there are no more items.
      var token = _findContinuationToken(initial);
      final visitedTokens = <String>{};
      while (token != null && visitedTokens.add(token)) {
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

    // Fallback for the classic layout / mixes that don't use lockupViewModels.
    if (audios.isEmpty) {
      try {
        final videos = await _yt.playlists.getVideos(playlistId).toList();
        for (final video in videos) {
          if (!seenIds.add(video.id.value)) continue;
          audios.add(YouTubeAudio.fromVideo(video));
        }
      } catch (e) {
        debugPrint('Classic playlist fallback failed: $e');
      }
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

  /// Extracts the first metadata row's first part as the artist name.
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

    // First try matching by youtubeId
    final byYtId = localSongs.cast<ts.Song?>().firstWhere(
      (s) => s!.youtubeId == audio.id,
      orElse: () => null,
    );
    if (byYtId != null) return byYtId;

    // Fallback: match by title + first artist
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
    // Fallback: pick from online playlist history
    if (_onlinePlaylist.length > 1) {
      return _onlinePlaylist[0];
    }
    throw Exception('No songs available for suggestion');
  }

  // Play audio from YouTube (or local file if matching song exists)
  Future<void> playAudio(YouTubeAudio audio, {bool trackOnline = true}) async {
    try {
      _stopOtherPlayer?.call();

      _currentAudio = audio;
      _playingFromQueue = !trackOnline;

      if (trackOnline) {
        // Track in online playlist
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

      // Check for local match first
      final localMatch = _findLocalMatch(audio);
      if (localMatch != null && File(localMatch.url).existsSync()) {
        debugPrint('🎵 Playing local file: ${localMatch.url}');
        await _player.open(Media(localMatch.url));
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

      final String? audioUrl = await _getAudioStream(audio.id);

      if (audioUrl == null) {
        throw Exception(
          'Ses akışı alınamadı. Lütfen daha sonra tekrar deneyin.',
        );
      }

      debugPrint('Playing audio from URL: $audioUrl');

      try {
        final headers = _youtubePlaybackHttpHeaders();
        await _player.open(Media(audioUrl, httpHeaders: headers));
        await _player.play();
        debugPrint('✅ Audio playback started successfully');
      } catch (e) {
        debugPrint('❌ Error setting audio source: $e');
        throw Exception('Ses çalınamadı: ${e.toString()}');
      }

      // Update the current audio with the latest info
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
      debugPrint('Error playing YouTube audio: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  /// İndirme ile aynı mantık: önce androidVr, sonra varsayılan; mümkünse m4a (mp4).
  Future<String?> _getAudioStream(String videoId) async {
    try {
      // Check cache first
      final cached = _audioUrlCache.get(videoId);
      if (cached != null) {
        debugPrint('✅ Using cached stream URL for videoId: $videoId');
        return cached;
      }

      debugPrint('🔧 Getting YouTube stream URL: $videoId');

      final manifest = await _getManifestWithFallbacks(videoId);

      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        debugPrint('❌ Ses akışı yok');
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
      debugPrint('✅ Got YouTube stream URL (${streamInfo.container.name})');

      // Cache the stream URL
      _audioUrlCache.put(videoId, streamUrl);

      return streamUrl;
    } catch (e) {
      debugPrint('❌ Stream extraction failed: $e');
      return null;
    }
  }

  // Pause audio
  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  // Resume audio
  Future<void> play() async {
    if (_currentAudio != null) {
      await _player.play();
      notifyListeners();
    }
  }

  // Stop audio
  Future<void> stop() async {
    await _player.stop();
    _currentAudio = null;
    _onlinePlaylistIndex = -1;
    _playingFromQueue = false;
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
    _notifyProgressUpdate();
  }

  void _updateDownloadProgress(String videoId, double progress) {
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!
        ..progress = progress
        ..isDownloading = progress < 1.0;
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
    debugPrint('_completeDownload: Completing download for videoId: $videoId');
    if (_activeDownloads.containsKey(videoId)) {
      final download = _activeDownloads[videoId]!;
      final title = download.title;
      if (!download.completer!.isCompleted) {
        download.completer!.complete();
      }
      _activeDownloads.remove(videoId);
      _notifyProgressUpdate();
      debugPrint(
        '_completeDownload: Download for videoId: $videoId completed and removed from active list.',
      );

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

    // Immediately remove from the list to update UI
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();

    // Background cancellation
    unawaited(
      Future.microtask(() async {
        try {
          await d.subscription?.cancel();
          debugPrint('cancelDownload: Subscription cancelled for $videoId');
        } catch (e) {
          debugPrint('Error during background subscription cancellation: $e');
        }
      }),
    );

    return true;
  }

  /// Removes a finished/failed download entry from the active list so the
  /// user can clear an error from the downloads screen.
  void dismissDownload(String videoId) {
    if (!_activeDownloads.containsKey(videoId)) return;
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();
  }

  Future<List<YouTubeAudio>> searchAudio(String query) async {
    try {
      // Check cache first
      final cached = _searchResultsCache.get(query);
      if (cached != null) {
        debugPrint('✅ Using cached search results for: "$query"');
        return cached;
      }

      debugPrint('🔍 Fetching fresh search results for: "$query"');
      final searchResults = await _yt.search.search(query);
      _searchPages[query] = searchResults;
      final videos = searchResults.whereType<Video>().toList();
      final audioList = videos.map(YouTubeAudio.fromVideo).toList();

      // Cache the results
      _searchResultsCache.put(query, audioList);

      return audioList;
    } catch (e) {
      debugPrint('Error searching YouTube: $e');
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
      debugPrint('Error loading next page for "$query": $e');
      rethrow;
    }
  }

  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streams = manifest.audioOnly;
      if (streams.isNotEmpty) {
        return streams.withHighestBitrate().url.toString();
      }
      // Audio-only streams required - no video fallback
      debugPrint(
        'getAudioStreamUrl: No audio-only streams available for videoId: $videoId',
      );
      return null;
    } catch (e) {
      debugPrint('Error getting audio stream URL: $e');
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
      debugPrint(
        'downloadAudio: Download for videoId: $videoId is already in progress. Ignoring duplicate request.',
      );
      return null;
    }

    // A previous attempt ended in failure/cancel. Remove its stale entry so
    // the retry can start cleanly and show progress again.
    _activeDownloads.remove(videoId);
    _notifyProgressUpdate();

    Video video;
    try {
      video = await _yt.videos.get(videoId);
    } catch (e) {
      debugPrint('downloadAudio: Failed to fetch video info: $e');
      _addActiveDownload(videoId, 'Unknown');
      final failed = _activeDownloads[videoId];
      if (failed != null) {
        failed
          ..error = 'Failed to fetch video information'
          ..isDownloading = false
          ..failed = true;
      }
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
    debugPrint('downloadAudio: Starting download for videoId: $videoId');

    try {
      StreamManifest manifest;
      try {
        // Fetch the manifest with a client strategy that matches what
        // streaming uses (package defaults first).
        manifest = await _getManifestWithFallbacks(videoId);
      } catch (e) {
        debugPrint('Failed to get manifest for video $videoId: $e');
        throw Exception('youtube_html_error');
      }

      // Select stream based on preferred format
      StreamInfo streamInfo;
      final audioStreams = manifest.audioOnly.toList();

      if (audioStreams.isEmpty) {
        throw Exception('No audio streams available for video $videoId');
      }

      // Select format based on user preference
      StreamInfo? selectedStream;

      if (preferredFormat == AudioFormat.m4a) {
        // User wants M4A - find best m4a stream
        final m4aStreams = audioStreams
            .where((s) => s.container.name == 'mp4')
            .toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
          debugPrint('downloadAudio: Selected m4a format as requested');
        }
      } else if (preferredFormat == AudioFormat.opus) {
        // User wants OPUS - find best webm/opus stream
        final opusStreams = audioStreams
            .where((s) => s.container.name == 'webm')
            .toList();
        if (opusStreams.isNotEmpty) {
          selectedStream = opusStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
          debugPrint('downloadAudio: Selected opus format as requested');
        }
      } else if (preferredFormat == AudioFormat.mp3) {
        // MP3 typically comes as m4a container or webm
        final mp3Streams = audioStreams
            .where(
              (s) => s.container.name == 'mp4' || s.container.name == 'webm',
            )
            .toList();
        if (mp3Streams.isNotEmpty) {
          selectedStream = mp3Streams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
          debugPrint('downloadAudio: Selected stream for MP3 preference');
        }
      }

      // Auto mode or fallback: prefer m4a for Android compatibility, then highest bitrate
      if (selectedStream == null) {
        final m4aStreams = audioStreams
            .where((s) => s.container.name == 'mp4')
            .toList();
        if (m4aStreams.isNotEmpty) {
          selectedStream = m4aStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
          debugPrint(
            'downloadAudio: Auto mode - selected m4a for Android compatibility',
          );
        } else {
          // Fallback to highest bitrate available
          selectedStream = audioStreams.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b,
          );
          debugPrint(
            'downloadAudio: Auto mode - using highest bitrate ${selectedStream.container.name}',
          );
        }
      }

      streamInfo = selectedStream;

      final musicDir = await _getMusicDirectory(downloadLocation);
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      // Use proper audio extension based on container format
      String audioExtension;
      if (streamInfo.container.name == 'mp4') {
        audioExtension = 'm4a';
      } else if (streamInfo.container.name == 'webm') {
        audioExtension = 'opus';
      } else {
        audioExtension = streamInfo.container.name;
      }

      // Check if this video is already downloaded (check by youtube_id in database)
      final db = await DatabaseHelper().database;
      final existingByVideoId = await db.query(
        'songs',
        where: 'youtube_id = ?',
        whereArgs: [videoId],
      );

      if (existingByVideoId.isNotEmpty) {
        final existingPath = existingByVideoId.first['file_path'] as String;
        final existingFile = File(existingPath);
        if (await existingFile.exists()) {
          debugPrint(
            'downloadAudio: Video $videoId already downloaded at $existingPath',
          );
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

      // Simple filename: Title.extension (video ID stored in metadata, not filename)
      final finalFile = File(
        path.join(musicDir.path, '$safeTitle.$audioExtension'),
      );

      if (await finalFile.exists()) {
        final fileSize = await finalFile.length();
        if (fileSize > 0) {
          debugPrint(
            'downloadAudio: File already exists and is valid: ${finalFile.path}. Skipping.',
          );
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
          debugPrint(
            'downloadAudio: Empty file found: ${finalFile.path}. Deleting and re-downloading.',
          );
          await finalFile.delete();
        }
      }

      final downloadProgress = _activeDownloads[videoId];

      // HLS (m3u8) downloads bypass the CDN's ~1 MiB Range cap on unsigned
      // DASH streams, so prefer them whenever we expect an m4a (AAC) output.
      // This mirrors the (working) yt-dlp visionos flow: fresh visitorData ->
      // visionos player request -> master playlist -> best audio group.
      // Falls back to the DASH chunked downloader below when unavailable.
      if (audioExtension == 'm4a') {
        try {
          final hls = await _fetchHlsAudioSegments(videoId);
          if (hls != null) {
            debugPrint(
              'downloadAudio: Using HLS path for $videoId '
              '(${hls.segments.length} segments, ${hls.totalBytes} bytes)',
            );
            await _downloadHlsSegments(
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
            final hlsSize = await finalFile.length();
            debugPrint('downloadAudio: HLS download completed: $hlsSize bytes');
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
          debugPrint(
            'downloadAudio: HLS not available for $videoId; falling back to DASH',
          );
        } catch (e) {
          debugPrint(
            'downloadAudio: HLS download failed ($e); falling back to DASH',
          );
          if (await finalFile.exists()) {
            await finalFile.delete();
          }
        }
      }

      debugPrint('downloadAudio: Getting stream for videoId: $videoId');

      // Download via http-package ranged chunks below.
      final contentLength = streamInfo.size.totalBytes;
      debugPrint(
        'downloadAudio: Expected content length: $contentLength bytes',
      );

      var receivedBytes = 0;
      var lastProgressUpdate = DateTime.now();

      // HARDENING: YouTube's unsigned bot-check sometimes hands out a usable
      // manifest but then throttles the CDN stream so no bytes ever arrive,
      // which made downloads hang at 0% indefinitely. Watch for silence with
      // a stall timeout, and retry once with a freshly fetched stream URL (the
      // original URL is tokenized and single-use) before failing cleanly.
      const stallTimeout = Duration(seconds: 30);
      const maxStreamAttempts = 2;
      var streamInfoForAttempt = streamInfo;

      for (var attempt = 1; attempt <= maxStreamAttempts; attempt++) {
        if (attempt > 1) {
          debugPrint(
            'downloadAudio: Stream stalled, re-fetching manifest for videoId: $videoId',
          );
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
            debugPrint('downloadAudio: Retry manifest fetch failed: $e');
            throw Exception('youtube_html_error');
          }
        }

        try {
          // Create a custom sink to track progress
          final sink = finalFile.openWrite();

          // Chunked ranged download via the http package (more reliable than
          // the package stream client: the fallback path is a single full-file
          // request that the CDN throttles into a 30s hang).
          //
          // YouTube's unsigned bot-check sometimes hands out a usable
          // manifest but then throttles the CDN stream; a full-range GET can
          // then stall forever. Each chunk below is a fresh small Range
          // request; if a chunk is rejected or stalls, we re-fetch the
          // manifest for a fresh single-use URL (physical bytes are discarded
          // after headers) and retry from the same offset.
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

                  // Update progress every 100ms to avoid flooding
                  final now = DateTime.now();
                  if (now.difference(lastProgressUpdate).inMilliseconds > 100 &&
                      contentLength > 0) {
                    lastProgressUpdate = now;
                    final progress = receivedBytes / contentLength;
                    _updateDownloadProgress(videoId, progress);
                    onProgress?.call(progress);
                    debugPrint(
                      'downloadAudio: Progress ${(progress * 100).toStringAsFixed(1)}%',
                    );
                  }
                }
                offset = chunkEnd + 1;
                consecutiveChunkFailures = 0;
              } else {
                debugPrint(
                  'downloadAudio: Chunk rejected with HTTP ${response.statusCode} at offset $offset; refreshing stream URL',
                );
                throw HttpException(
                  'Chunk rejected with HTTP ${response.statusCode}',
                );
              }
            } catch (e) {
              consecutiveChunkFailures++;
              debugPrint(
                'downloadAudio: Chunk failed at offset $offset '
                '(failure $consecutiveChunkFailures/$maxChunkFailures): $e',
              );
              if (consecutiveChunkFailures >= maxChunkFailures) {
                rethrow;
              }
              // The googlevideo URL is single-use; refresh it for the next
              // attempt before retrying the same offset.
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
        } on Exception catch (e) {
          debugPrint('downloadAudio: Stream failed (attempt $attempt): $e');
          // Clean up partial file before a fresh retry (manifest re-fetch).
          if (await finalFile.exists()) {
            await finalFile.delete();
          }
          if (attempt == maxStreamAttempts) {
            rethrow;
          }
        }
      }

      final finalFileSize = await finalFile.length();
      debugPrint(
        'downloadAudio: Download completed. Final file size: $finalFileSize bytes',
      );

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
      debugPrint('downloadAudio: Download $videoId failed with error: $e');

      // Classify the error FIRST while the download entry still exists so the
      // failure is preserved and shown in the UI instead of silently vanishing.
      final download = _activeDownloads[videoId];
      final errorStr = e.toString().toLowerCase();
      final isHtmlError =
          errorStr.contains('youtube_html_error') ||
          errorStr.contains('html') ||
          errorStr.contains('ip') ||
          errorStr.contains('consent') ||
          errorStr.contains('blocked') ||
          errorStr.contains('unavailable');

      // Report to error tracking so download failures are collectable.
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
        // Mark the failure but KEEP the entry in _activeDownloads so the
        // downloads screen shows the error rather than the item vanishing.
        download
          ..isDownloading = false
          ..failed = true
          ..error = isHtmlError
              ? 'youtube_html_error'
              : (download.cancelRequested ? 'Canceled' : 'Download failed');
      }
      _notifyProgressUpdate();

      // Never fire the "Download Complete" notification on a failure.
      unawaited(DownloadNotificationService().cancelDownloadNotification());
      rethrow;
    } finally {
      debugPrint('downloadAudio: Exiting download for videoId: $videoId');
    }
  }

  /// Harvests a fresh anonymous visitorData from the YouTube homepage. The
  /// visionos player request is rejected with LOGIN_REQUIRED without one.
  Future<String?> _fetchVisionosVisitorData() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('https://www.youtube.com/'),
            headers: {'User-Agent': _youtubeVisionosUserAgent},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final match = RegExp(
        r'"VISITOR_DATA":"([^"]+)"',
      ).firstMatch(response.body);
      return match?.group(1);
    } catch (e) {
      debugPrint('fetchVisitorData failed: $e');
      return null;
    }
  }

  /// Requests the video with the YouTube visionos player client (as used by
  /// yt-dlp) and resolves the VOD-HLS audio: the best-audio media playlist and
  /// its segment URLs. Returns null when HLS is not available for the video.
  Future<_HlsAudio?> _fetchHlsAudioSegments(String videoId) async {
    try {
      final visitorData = await _fetchVisionosVisitorData();
      if (visitorData == null || visitorData.isEmpty) {
        debugPrint('HLS: no visitorData available');
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
        debugPrint('HLS: player request HTTP ${playerResponse.statusCode}');
        return null;
      }
      final player = jsonDecode(playerResponse.body) as Map<String, dynamic>;
      if (player['playabilityStatus']?['status'] != 'OK') {
        debugPrint('HLS: player not OK for $videoId');
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

      // The hlsManifestUrl is a master playlist; audio renditions live in
      // EXT-X-MEDIA groups (e.g. 233 = low, 234 = itag 140 high quality).
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
        debugPrint('HLS: no audio group found in master playlist');
        return null;
      }

      // The group URI is the media playlist; collect its segment URLs.
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

      debugPrint(
        'HLS: resolved ${segmentUrls.length} audio segments '
        '($bestBytes target bytes)',
      );
      return _HlsAudio(segments: segmentUrls, totalBytes: bestBytes);
    } catch (e) {
      debugPrint('HLS: resolution failed: $e');
      return null;
    }
  }

  /// Downloads the HLS audio segments into [file], reporting progress against
  /// [totalBytes]. Returns the number of bytes written. Throws when a segment
  /// keeps failing, so callers can fall back to the DASH path.
  Future<int> _downloadHlsSegments({
    required String videoId,
    required List<String> segmentUrls,
    required File file,
    required int totalBytes,
    void Function(double)? onProgress,
  }) async {
    final downloadProgress = _activeDownloads[videoId];
    final sink = file.openWrite();
    var receivedBytes = 0;
    var lastProgressUpdate = DateTime.now();
    const segmentTimeout = Duration(seconds: 30);
    const bodyTimeout = Duration(seconds: 60);

    try {
      for (final segmentUrl in segmentUrls) {
        if (downloadProgress?.cancelRequested == true) break;

        var attempts = 0;
        while (true) {
          attempts++;
          try {
            final request = http.Request('GET', Uri.parse(segmentUrl))
              ..headers.addAll(_youtubePlaybackHttpHeaders())
              ..headers['User-Agent'] = _youtubeVisionosUserAgent;
            final response = await _httpClient
                .send(request)
                .timeout(segmentTimeout);
            if (response.statusCode == 200 || response.statusCode == 206) {
              await for (final chunk in response.stream.timeout(bodyTimeout)) {
                if (downloadProgress?.cancelRequested == true) break;
                sink.add(chunk);
                receivedBytes += chunk.length;

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
              }
              break;
            }
            if (attempts >= 3) {
              throw HttpException(
                'HLS segment rejected with HTTP ${response.statusCode}',
              );
            }
            debugPrint(
              'downloadAudio: HLS segment HTTP ${response.statusCode} '
              '(attempt $attempts); retrying',
            );
            await Future<void>.delayed(const Duration(milliseconds: 800));
          } catch (e) {
            if (attempts >= 3) rethrow;
            debugPrint(
              'downloadAudio: HLS segment failed (attempt $attempts): $e',
            );
          }
        }
      }

      await sink.flush();
      await sink.close();
      return receivedBytes;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Directory> _getMusicDirectory(String downloadLocation) async {
    if (kIsWeb) {
      throw UnsupportedError('Downloads are not supported on Web.');
    }

    Directory? baseDir;

    if (Platform.isAndroid) {
      if (downloadLocation == 'downloads') {
        // Use public Downloads folder
        baseDir = Directory('/storage/emulated/0/Download');
      } else if (downloadLocation == 'music') {
        // Use public Music folder
        baseDir = Directory('/storage/emulated/0/Music');
      } else {
        // internal - use app documents directory
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else if (Platform.isIOS) {
      // iOS only supports internal app storage
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      // Desktop platforms
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
      final dbHelper = DatabaseHelper();

      // Download thumbnail if URL is provided
      String? thumbnailPath;
      if (thumbnailUrl != null) {
        thumbnailPath = await _downloadThumbnail(videoId, thumbnailUrl);
      }

      return await dbHelper.addSongFromYouTube(
        videoId: videoId,
        filePath: filePath,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailPath: thumbnailPath,
      );
    } catch (e) {
      debugPrint('Error adding downloaded song to library: $e');
      rethrow;
    }
  }

  /// Downloads a thumbnail image and saves it locally
  Future<String?> _downloadThumbnail(
    String videoId,
    String thumbnailUrl,
  ) async {
    try {
      final musicDir = await _getMusicDirectory('internal');
      final thumbnailFile = File(
        path.join(musicDir.path, '${videoId}_thumb.jpg'),
      );

      // Check if thumbnail already exists
      if (await thumbnailFile.exists()) {
        debugPrint('Thumbnail already exists: ${thumbnailFile.path}');
        return thumbnailFile.path;
      }

      final response = await _httpClient
          .get(Uri.parse(thumbnailUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await thumbnailFile.writeAsBytes(response.bodyBytes);
        debugPrint('Thumbnail downloaded: ${thumbnailFile.path}');
        return thumbnailFile.path;
      } else {
        debugPrint('Failed to download thumbnail: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading thumbnail: $e');
      return null;
    }
  }

  @override
  void dispose() {
    for (final download in _activeDownloads.values) {
      download.completer?.completeError('Service disposed');
    }
    _activeDownloads.clear();
    _player.dispose();
    _httpClient.close(); // Close the http client
    isLoading.dispose();
    super.dispose();
  }
}
