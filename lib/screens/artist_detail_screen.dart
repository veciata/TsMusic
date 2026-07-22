import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/models/playlist_item.dart';
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
import 'package:tsmusic/widgets/song_thumbnail.dart';
import 'package:tsmusic/widgets/playlist_selector_bottom_sheet.dart';

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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
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

    // First try local song thumbnails / album art
    final musicProvider = context.read<music_provider.MusicProvider>();
    final localSongs = musicProvider.librarySongs
        .where(
          (s) => s.artists.any(
            (a) => a.toLowerCase() == widget.artistName.toLowerCase(),
          ),
        )
        .toList();
    for (final song in localSongs) {
      if (song.localThumbnailPath != null) {
        _artistImageCache.put(widget.artistName, song.localThumbnailPath!);
        setState(() {
          widget.artistImageUrlNotifier.value = song.localThumbnailPath;
        });
        return;
      }
      if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
        _artistImageCache.put(widget.artistName, song.albumArtUrl!);
        setState(() {
          widget.artistImageUrlNotifier.value = song.albumArtUrl;
        });
        return;
      }
    }

    // Fallback to YouTube search
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
      final nextPage = await _youTubeService.searchAudioNextPage(
        widget.artistName,
      );
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
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none);
        });
      }
    });
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      await _youtubePlayer.playAudio(audio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing audio: $e')));
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    final settingsProvider = context.read<SettingsProvider>();
    final result = await _youTubeService.downloadAudio(
      videoId: audio.id,
      preferredFormat: settingsProvider.audioFormat,
      downloadLocation: settingsProvider.downloadLocation,
    );
    if (result != null && mounted) {
      context.read<music_provider.MusicProvider>().addDownloadedSongToLibrary(
        result.song,
      );
    }
  }

  Future<void> _deleteLocalSong(Song song) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSong),
        content: Text('${l10n.confirmDelete} "${song.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (!mounted) return;
        await context.read<music_provider.MusicProvider>().deleteSong(song);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.songDeleted)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${l10n.error}: $e')));
        }
      }
    }
  }

  void _playAllLocalSongs(
    List<Song> songs, {
    int startIndex = 0,
    bool shuffle = false,
  }) {
    final musicProvider = context.read<music_provider.MusicProvider>();
    if (songs.isEmpty) return;
    if (shuffle) {
      final shuffled = List<Song>.from(songs)..shuffle();
      musicProvider.playSongsFromList(shuffled);
    } else {
      musicProvider.playSongsFromList(songs, startIndex: startIndex);
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
      if (!mounted) return;
      final musicProvider = Provider.of<music_provider.MusicProvider>(
        context,
        listen: false,
      );
      for (final songId in _selectedLocalSongs.toList()) {
        final song = musicProvider.librarySongs.cast<Song?>().firstWhere(
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
    }
  }

  Future<void> _showMoveDialog(Song song) async {
    final l10n = AppLocalizations.of(context);
    final locations = [
      {
        'label': l10n.musicFolder,
        'path': '/storage/emulated/0/Music/tsmusic',
      },
      {
        'label': l10n.downloads,
        'path': '/storage/emulated/0/Download/tsmusic',
      },
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.moveTo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: locations
              .map(
                (loc) => ListTile(
                  title: Text(loc['label']!),
                  subtitle: Text(loc['path']!),
                  onTap: () => Navigator.pop(context, loc['path']),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      try {
        final targetDir = Directory(selected);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final file = File(song.url);
        final newPath = path.join(selected, path.basename(song.url));

        if (file.path == newPath) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File is already in this location')),
            );
          }
          return;
        }

        final targetFile = File(newPath);
        if (await targetFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File already exists at target')),
            );
          }
          return;
        }

        try {
          await file.rename(newPath);
        } on FileSystemException {
          await file.copy(newPath);
          await file.delete();
        }

        final musicProvider = context.read<music_provider.MusicProvider>();
        final updatedSong = song.copyWith(url: newPath);
        await musicProvider.updateSong(updatedSong);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.move}: ${path.basename(newPath)}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.errorMovingFile}: $e')),
          );
        }
      }
    }
  }

  Widget _buildArtistInitialFallback() => Container(
      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Text(
        widget.artistName.isNotEmpty ? widget.artistName[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.bold,
          color: Colors.white54,
        ),
      ),
    );

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
                      placeholder: (context, url) =>
                          _buildArtistInitialFallback(),
                      errorWidget: (context, url, error) =>
                          _buildArtistInitialFallback(),
                    );
                  }
                  return _buildArtistInitialFallback();
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
          children: [_buildLocalSongsTab(), _buildYouTubeTab()],
        ),
      ),
      bottomNavigationBar: const MiniPlayerWidget(),
      floatingActionButton: _isMultiSelectMode
          ? FloatingActionButton(
              onPressed: _selectedLocalSongs.isEmpty
                  ? null
                  : _deleteSelectedLocalSongs,
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
        .where(
          (song) => song.artists.any(
            (artist) => artist.toLowerCase() == widget.artistName.toLowerCase(),
          ),
        )
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
              ElevatedButton(
                onPressed: () => _playAllLocalSongs(songs, shuffle: true),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                child: const Icon(Icons.shuffle),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _isMultiSelectMode ? Icons.close : Icons.check_box_outlined,
                ),
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
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.read<music_provider.MusicProvider>().requestThumbnail(
                  song,
                  priority: 1,
                );
              });
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
                    : SongThumbnail(song: song),
                title: SlidingText(
                  song.title,
                  style: TextStyle(
                    fontWeight: isCurrentSong
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(song.album ?? l10n.unknownAlbum),
                trailing: _isMultiSelectMode
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(song.formattedDuration),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'add_to_playlist':
                                  showAddToPlaylistSheet(
                                    context,
                                    item: PlaylistItem(songId: song.id),
                                  );
                                case 'move':
                                  _showMoveDialog(song);
                                case 'delete':
                                  _deleteLocalSong(song);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'add_to_playlist',
                                child: Row(
                                  children: [
                                    const Icon(Icons.playlist_add),
                                    const SizedBox(width: 8),
                                    Text(l10n.addToPlaylist),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'move',
                                child: Row(
                                  children: [
                                    const Icon(Icons.drive_file_move_outline),
                                    const SizedBox(width: 8),
                                    Text(l10n.moveTo),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.delete,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
                    : () => _playAllLocalSongs(songs, startIndex: index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYouTubeTab() {
    final l10n = AppLocalizations.of(context);
    if (_isLoading && _youtubeSongs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_youtubeSongs.isEmpty) {
      return Center(child: Text(l10n.noOnlineSongsFound));
    }

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
          onAddToPlaylist: () => showAddYouTubeToPlaylistSheet(
            context,
            youtubeId: audio.id,
            title: audio.title,
            artists: audio.artists,
            duration: audio.duration?.inMilliseconds ?? 0,
            thumbnailUrl: audio.thumbnailUrl,
          ),
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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: tabBar,
  );

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
