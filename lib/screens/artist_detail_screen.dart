import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/widgets/mini_player_widget.dart';
import 'package:tsmusic/widgets/youtube_playback_widget.dart';
import 'package:tsmusic/utils/lru_cache.dart';
import 'downloads_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final ValueNotifier<String?> artistImageUrlNotifier;

  ArtistDetailScreen({
    super.key,
    required this.artistName,
    ValueNotifier<String?>? artistImageUrl,
  }) : artistImageUrlNotifier = artistImageUrl ?? ValueNotifier<String?>(null);

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late YouTubeService _youTubeService;
  late YouTubePlayerProvider _youtubePlayer;
  List<YouTubeAudio> _youtubeSongs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isOffline = false;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  final ScrollController _scrollController = ScrollController();
  late final LRUCache<String, String> _artistImageCache; // LRU cache for artist images

  @override
  void initState() {
    super.initState();
    _artistImageCache = LRUCache<String, String>(maxCapacity: 100); // Max 100 artist images in cache
    _youTubeService = context.read<YouTubeService>();
    _youtubePlayer = context.read<YouTubePlayerProvider>();
    _youtubePlayer.registerScreen('artist_screen');
    _tabController = TabController(length: 2, vsync: this);
    _loadYouTubeSongs();
    _scrollController.addListener(_onScroll);
    _fetchArtistImageIfNeeded();
    
    // Check initial connectivity status
    _checkConnectivity();
    
    // Subscribe to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      _checkConnectivity();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreYouTubeSongs();
    }
  }

  Future<void> _fetchArtistImageIfNeeded() async {
    if (widget.artistImageUrlNotifier.value != null) return;
    
    // Check LRU cache first
    final cachedUrl = _artistImageCache.get(widget.artistName);
    if (cachedUrl != null) {
      setState(() {
        widget.artistImageUrlNotifier.value = cachedUrl;
      });
      debugPrint('✅ Using cached artist image for: ${widget.artistName}');
      return;
    }

    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      for (final song in results) {
        if (song.thumbnailUrl != null && song.thumbnailUrl!.isNotEmpty) {
          _artistImageCache.put(widget.artistName, song.thumbnailUrl!);
          setState(() {
            widget.artistImageUrlNotifier.value = song.thumbnailUrl;
          });
          debugPrint('💾 Cached artist image for: ${widget.artistName}');
          break;
        }
      }
    } catch (e) {
      debugPrint('Error fetching artist image: $e');
    }
  }

  Future<void> _loadYouTubeSongs() async {
    // Don't load YouTube songs if offline
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _youtubeSongs = []; // Clear results when offline
        });
      }
      return;
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      setState(() {
        _youtubeSongs = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading online songs: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreYouTubeSongs() async {
    // Don't load more YouTube songs if offline
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false; // No more results when offline
        });
      }
      return;
    }

    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);
    try {
      final results =
          await _youTubeService.searchAudioNextPage(widget.artistName);
      setState(() {
        _youtubeSongs.addAll(results);
        _isLoading = false;
        _hasMore = results.isNotEmpty;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading more songs: $e')),
        );
      }
    }
  }

  Future<void> _playAllLocalSongs(List<Song> songs) async {
    if (songs.isEmpty) return;
    final musicProvider =
        Provider.of<music_provider.MusicProvider>(context, listen: false);
    await musicProvider.setPlaylistAndPlay(songs, 0);
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      await _youtubePlayer.playAudio(audio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio could not be played: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _playAudio(audio),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    if (!mounted) return;

    final isDownloading =
        _youTubeService.activeDownloads.any((d) => d.videoId == audio.id);
    if (isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download already in progress')),
      );
      _navigateToDownloads();
      return;
    }

    try {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final result = await _youTubeService.downloadAudio(
        videoId: audio.id,
        preferredFormat: settingsProvider.audioFormat,
        downloadLocation: settingsProvider.downloadLocation,
      );
      if (result != null && mounted) {
        await Provider.of<music_provider.MusicProvider>(context, listen: false)
            .loadFromDatabaseOnly();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: ${audio.title}')),
        );
        _navigateToDownloads();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _navigateToDownloads() {
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  @override
  void dispose() {
    // Unregister screen and stop YouTube audio when leaving artist screen
    _youtubePlayer.unregisterScreen('artist_screen');
    _tabController.dispose();
    _scrollController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOffline = result == ConnectivityResult.none;
        });
      }
    } catch (e) {
      // Handle connectivity check errors (common on web)
      if (mounted) {
        setState(() {
          // Assume online if we can't determine connectivity
          _isOffline = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.MusicProvider>(context);
    final l10n = AppLocalizations.of(context);
    final localSongs = musicProvider.getSongsByArtist(widget.artistName);

    return WillPopScope(
      onWillPop: () async {
        await _youtubePlayer.stop();
        return true;
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar(
                      expandedHeight: 200.0,
                      pinned: true,
                      flexibleSpace: ValueListenableBuilder<String?>(
                        valueListenable: widget.artistImageUrlNotifier,
                        builder: (context, artistImageUrl, child) {
                          return FlexibleSpaceBar(
                            title: Text(
                              widget.artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            background: artistImageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: artistImageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, error) =>
                                        _buildPlaceholderImage(),
                                  )
                                : _buildPlaceholderImage(),
                          );
                        },
                      ),
                      bottom: TabBar(
                        controller: _tabController,
                        tabs: [
                          Tab(text: l10n.localSongs),
                          Tab(text: l10n.online),
                        ],
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocalSongsTab(localSongs, musicProvider),
                    _buildYouTubeTab(),
                  ],
                ),
              ),
            ),
            const MiniPlayerWidget(),
            if (_isOffline)
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[900],
                child: Center(
                  child: Text(
                    'Offline Mode - Showing local results only',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _normalizePath(String path) {
    try {
      String normalized = path.split('?')[0].split('#')[0].toLowerCase().trim();
      const String emulatedPrefix = '/storage/emulated/0/';
      if (normalized.startsWith(emulatedPrefix)) {
        normalized = '/sdcard/${normalized.substring(emulatedPrefix.length)}';
      }
      final uri = Uri.file(normalized);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return '/${segments.join('/')}';
    } catch (e) {
      if (kDebugMode) {
        print('Error normalizing path "$path": $e');
      }
      return path.toLowerCase();
    }
  }

  Widget _buildLocalSongsTab(
      List<Song> songs, music_provider.MusicProvider musicProvider) {
    final l10n = AppLocalizations.of(context);
    if (songs.isEmpty) return Center(child: Text(l10n.noLocalSongsForArtist));

    final Map<int, Song> uniqueSongs = {};
    final Set<String> seenPaths = {};

    for (final song in songs) {
      try {
        if (song.url.isEmpty) continue;

        final normalizedPath = _normalizePath(song.url);
        if (normalizedPath.isEmpty) continue;

        if (!seenPaths.contains(normalizedPath)) {
          seenPaths.add(normalizedPath);
          uniqueSongs[song.id] = song;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error processing song ${song.id}: $e');
        }
      }
    }

    final uniqueSongsList = uniqueSongs.values.toList();

    if (uniqueSongsList.isEmpty) {
      return Center(child: Text(l10n.noLocalSongsForArtist));
    }

    return ListView.builder(
      itemCount: uniqueSongsList.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () => _playAllLocalSongs(uniqueSongsList),
              icon: const Icon(Icons.play_arrow),
              label: Text('${l10n.playAll} (${uniqueSongsList.length})'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          );
        }
        final song = uniqueSongsList[index - 1];
        final isCurrentSong = musicProvider.currentSong?.id == song.id;
        return ListTile(
          leading: song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: CachedNetworkImage(
                    imageUrl: song.albumArtUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.music_note, size: 50),
                  ),
                )
              : const Icon(Icons.music_note, size: 50),
          title: Text(
            song.title,
            style: TextStyle(
                fontWeight:
                    isCurrentSong ? FontWeight.bold : FontWeight.normal),
          ),
          subtitle: Text(song.album ?? l10n.unknownAlbum),
          trailing: Text(song.formattedDuration),
          onTap: () => musicProvider.playSong(song),
        );
      },
    );
  }

  Widget _buildYouTubeTab() {
    final l10n = AppLocalizations.of(context);
    if (_isLoading && _youtubeSongs.isEmpty)
      return Center(child: CircularProgressIndicator());
    if (_youtubeSongs.isEmpty)
      return Center(child: Text(l10n.noOnlineSongsFound));

    return ListView.builder(
      controller: _scrollController,
      itemCount: _youtubeSongs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _youtubeSongs.length) return _buildLoadingIndicator();
        final audio = _youtubeSongs[index];
        return _buildOnlineResultItem(audio);
      },
    );
  }

  Widget _buildOnlineResultItem(YouTubeAudio audio) {
    return YouTubePlaybackWidget(
      audio: audio,
      onPlay: _playAudio,
      onDownload: _handleDownload,
    );
  }

  Widget _buildLoadingIndicator() => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _buildPlaceholderImage() => Container(
        color: Colors.grey[800],
        child: Center(
          child: Icon(Icons.person, size: 120, color: Colors.grey[600]),
        ),
      );
}
