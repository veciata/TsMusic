import 'dart:async';
import 'dart:io';

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
import 'package:tsmusic/widgets/sliding_text.dart';

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
  late final LRUCache<String, String> _artistImageCache;
  final Set<int> _selectedLocalSongs = {};
  bool _isMultiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _artistImageCache = LRUCache<String, String>(maxCapacity: 100);
    _youTubeService = context.read<YouTubeService>();
    _youtubePlayer = context.read<YouTubePlayerProvider>();
    _youtubePlayer.registerScreen('artist_screen');
    _tabController = TabController(length: 2, vsync: this);
    _loadYouTubeSongs();
    _scrollController.addListener(_onScroll);
    _fetchArtistImageIfNeeded();

    _checkConnectivity();
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

    final cachedUrl = _artistImageCache.get(widget.artistName);
    if (cachedUrl != null) {
      setState(() {
        widget.artistImageUrlNotifier.value = cachedUrl;
      });
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
          break;
        }
      }
    } catch (e) {
      debugPrint('Error fetching artist image: $e');
    }
  }

  Future<void> _loadYouTubeSongs() async {
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _youtubeSongs = [];
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
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
      }
      return;
    }

    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);
    try {
      final nextPage = await _youTubeService.searchAudioNextPage(widget.artistName);
      if (nextPage.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        setState(() {
          _youtubeSongs.addAll(nextPage);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _checkConnectivity() {
    Connectivity().checkConnectivity().then((result) {
      if (mounted) {
        setState(() {
          _isOffline = result == ConnectivityResult.none;
        });
      }
    });
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      await _youtubePlayer.playAudio(audio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    final settingsProvider = context.read<SettingsProvider>();
    await _youTubeService.downloadAudio(
      videoId: audio.id,
      preferredFormat: settingsProvider.audioFormat,
      downloadLocation: settingsProvider.downloadLocation,
    );
  }

  void _playAllLocalSongs(List<Song> songs) {
    final musicProvider = context.read<music_provider.MusicProvider>();
    if (songs.isNotEmpty) {
      musicProvider.playSong(songs.first);
    }
  }

  Future<void> _deleteSelectedLocalSongs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_selectedLocalSongs.length} songs?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isMultiSelectMode = false);
      final musicProvider =
          Provider.of<music_provider.MusicProvider>(context, listen: false);
      for (final songId in _selectedLocalSongs.toList()) {
        final song = musicProvider.librarySongs
            .cast<Song?>()
            .firstWhere(
                (s) => s?.id == songId,
                orElse: () => null,
            );
        if (song != null) {
          try {
            final file = File(song.url);
            if (await file.exists()) {
              await file.delete();
            }
            await musicProvider.deleteSong(song);
          } catch (e) {
            debugPrint('Error deleting song ${song.id}: $e');
          }
        }
      }
      _selectedLocalSongs.clear();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _connectivitySubscription?.cancel();
    _youtubePlayer.unregisterScreen('artist_screen');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.artistName),
              background: ValueListenableBuilder<String?>(
                valueListenable: widget.artistImageUrlNotifier,
                builder: (context, url, child) {
                  if (url != null) {
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.grey),
                      errorWidget: (context, url, error) =>
                          Container(color: Colors.grey),
                    );
                  }
                  return Container(color: Theme.of(context).primaryColor);
                },
              ),
            ),
          ),
          SliverPersistentHeader(
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.localSongs),
                  Tab(text: l10n.online),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLocalSongsTab(),
            _buildYouTubeTab(),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayerWidget(),
      floatingActionButton: _isMultiSelectMode
          ? FloatingActionButton(
              onPressed: _selectedLocalSongs.isEmpty
                  ? null
                  : () => _deleteSelectedLocalSongs(),
              backgroundColor: Colors.red,
              child: const Icon(Icons.delete),
            )
          : null,
    );
  }

  Widget _buildLocalSongsTab() {
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final l10n = AppLocalizations.of(context);

    final songs = musicProvider.librarySongs
        .where((song) => song.artists.any(
            (artist) => artist.toLowerCase() == widget.artistName.toLowerCase()))
        .toList();

    if (songs.isEmpty) {
      return Center(child: Text(l10n.noLocalSongsForArtist));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _playAllLocalSongs(songs),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('${l10n.playAll} (${songs.length})'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_isMultiSelectMode
                    ? Icons.close
                    : Icons.check_box_outlined),
                onPressed: () {
                  setState(() {
                    _isMultiSelectMode = !_isMultiSelectMode;
                    if (!_isMultiSelectMode) {
                      _selectedLocalSongs.clear();
                    }
                  });
                },
                tooltip: _isMultiSelectMode ? 'Cancel' : 'Select items',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrentSong = musicProvider.currentSong?.id == song.id;
              final isSelected = _selectedLocalSongs.contains(song.id);
              return ListTile(
                leading: _isMultiSelectMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedLocalSongs.add(song.id);
                            } else {
                              _selectedLocalSongs.remove(song.id);
                            }
                          });
                        },
                      )
                    : _buildSongThumbnail(song),
                title: SlidingText(
                  song.title,
                  style: TextStyle(
                      fontWeight: isCurrentSong
                          ? FontWeight.bold
                          : FontWeight.normal),
                ),
                subtitle: Text(song.album ?? l10n.unknownAlbum),
                trailing: _isMultiSelectMode
                    ? null
                    : Text(song.formattedDuration),
                onTap: _isMultiSelectMode
                    ? () {
                        setState(() {
                          if (_selectedLocalSongs.contains(song.id)) {
                            _selectedLocalSongs.remove(song.id);
                          } else {
                            _selectedLocalSongs.add(song.id);
                          }
                        });
                      }
                    : () => musicProvider.playSong(song),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongThumbnail(Song song) {
    if (song.localThumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: Image.file(
          File(song.localThumbnailPath!),
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.music_note, size: 50),
        ),
      );
    }

    if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: CachedNetworkImage(
          imageUrl: song.albumArtUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              const Icon(Icons.music_note, size: 50),
        ),
      );
    }

    return const Icon(Icons.music_note, size: 50);
  }

  Widget _buildYouTubeTab() {
    final l10n = AppLocalizations.of(context);
    if (_isLoading && _youtubeSongs.isEmpty)
      return const Center(child: CircularProgressIndicator());
    if (_youtubeSongs.isEmpty)
      return Center(child: Text(l10n.noOnlineSongsFound));

    return ListView.builder(
      controller: _scrollController,
      itemCount: _youtubeSongs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _youtubeSongs.length) return _buildLoadingIndicator();
        final audio = _youtubeSongs[index];
        return YouTubePlaybackWidget(
          audio: audio,
          onPlay: _playAudio,
          onDownload: _handleDownload,
        );
      },
    );
  }

  Widget _buildLoadingIndicator() => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
