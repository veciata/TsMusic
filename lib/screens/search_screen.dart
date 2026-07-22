import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/models/song.dart' as model;
import 'package:tsmusic/models/playlist_item.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/widgets/mini_player_widget.dart';
import 'package:tsmusic/widgets/playlist_selector_bottom_sheet.dart';
import 'package:tsmusic/widgets/youtube_playback_widget.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final YouTubeService _youTubeService;
  late final YouTubePlayerProvider _youtubePlayer;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  List<YouTubeAudio> _youtubeResults = [];
  bool _isSearchingYouTube = false;
  bool _isOffline = false;
  bool _hasFetchedYouTube = false;
  bool _hasMoreYouTubeResults = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _youtubePlayer = context.read<YouTubePlayerProvider>();
    _youtubePlayer.registerScreen('search_screen');
    _searchFocusNode.requestFocus();
    _scrollController.addListener(_onScroll);

    final initialQuery = widget.initialQuery;
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _debouncedSearch(initialQuery);
    }

    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      _checkConnectivity();
    });
  }

  @override
  void dispose() {
    _youtubePlayer.unregisterScreen('search_screen');
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchScrollController.dispose();
    _connectivitySubscription?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOffline = false;
        });
      }
    }
  }

  void _debouncedSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchYouTube(query);
    });
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      await _youtubePlayer.playAudio(audio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ses çalınamadı: $e'),
            action: SnackBarAction(
              label: 'Tekrar Dene',
              onPressed: () => _playAudio(audio),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    if (!mounted) return;

    final isDownloading = _youTubeService.activeDownloads.any(
      (d) => d.videoId == audio.id,
    );
    if (isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download already in progress')),
      );
      return;
    }

    try {
      final settingsProvider = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );
      final result = await _youTubeService.downloadAudio(
        videoId: audio.id,
        preferredFormat: settingsProvider.audioFormat,
        downloadLocation: settingsProvider.downloadLocation,
      );
      if (result != null && mounted) {
        Provider.of<music_provider.MusicProvider>(
          context,
          listen: false,
        ).addDownloadedSongToLibrary(result.song);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download completed: ${audio.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isHtmlError =
            errorStr.contains('youtube_html_error') ||
            errorStr.contains('html') ||
            errorStr.contains('ip') ||
            errorStr.contains('consent') ||
            errorStr.contains('blocked') ||
            errorStr.contains('unavailable');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isHtmlError
                        ? 'Download unavailable. Please try again later.'
                        : 'Download failed: $e',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_searchController.text.isNotEmpty &&
          !_isSearchingYouTube &&
          _hasMoreYouTubeResults) {
        _searchYouTube(_searchController.text, loadMore: true);
      }
    }
  }

  Future<void> _searchYouTube(String query, {bool loadMore = false}) async {
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isSearchingYouTube = false;
        });
      }
      return;
    }

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _youtubeResults.clear();
          _isSearchingYouTube = false;
          _hasMoreYouTubeResults = true;
          _hasFetchedYouTube = false;
        });
      }
      return;
    }

    if (loadMore && (_isSearchingYouTube || !_hasMoreYouTubeResults)) return;

    if (mounted) setState(() => _isSearchingYouTube = true);

    try {
      final List<YouTubeAudio> response = loadMore
          ? await _youTubeService.searchAudioNextPage(query)
          : await _youTubeService.searchAudio(query);

      if (mounted) {
        setState(() {
          if (loadMore) {
            _youtubeResults.addAll(response);
          } else {
            _youtubeResults = response;
          }
          _hasMoreYouTubeResults = response.isNotEmpty;
          _hasFetchedYouTube = true;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error searching YouTube'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _searchYouTube(query, loadMore: loadMore),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingYouTube = false);
    }
  }

  Widget _buildMixedResults(
    List<model.Song> localSongs,
    music_provider.MusicProvider provider,
    model.Song? currentSong,
    bool isPlaying,
  ) {
    final query = _searchController.text.toLowerCase();

    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for songs...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    final filteredLocalSongs = localSongs
        .where(
          (song) =>
              song.title.toLowerCase().contains(query) ||
              song.artists.any(
                (artist) => artist.toLowerCase().contains(query),
              ) ||
              (song.album?.toLowerCase().contains(query) ?? false),
        )
        .toList();

    final localYoutubeIds = localSongs
        .where((s) => s.youtubeId != null)
        .map((s) => s.youtubeId!)
        .toSet();
    final localTitleSet = localSongs
        .map((s) => s.title.toLowerCase().trim())
        .toSet();

    final filteredYouTubeResults = _youtubeResults.where((yt) {
      if (yt.id != null && localYoutubeIds.contains(yt.id)) return false;
      if (localTitleSet.contains(yt.title.toLowerCase().trim())) return false;
      return true;
    }).toList();

    final hasLocalResults = filteredLocalSongs.isNotEmpty;
    final hasOnlineResults = filteredYouTubeResults.isNotEmpty;

    return ListView(
      controller: _scrollController,
      children: [
        if (hasLocalResults) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Local Results (${filteredLocalSongs.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...filteredLocalSongs.map(
            (song) =>
                _buildLocalResultItem(song, provider, currentSong, isPlaying),
          ),
        ],
        if (!_isOffline && _hasFetchedYouTube && hasOnlineResults) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              filteredYouTubeResults.length < _youtubeResults.length
                  ? 'Online Results (${filteredYouTubeResults.length}/${_youtubeResults.length})'
                  : 'Online Results (${_youtubeResults.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...filteredYouTubeResults.map(_buildYouTubeResultItem),
          if (_hasMoreYouTubeResults && !_isSearchingYouTube)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
        if (!hasLocalResults &&
            !hasOnlineResults &&
            !_isSearchingYouTube &&
            _hasFetchedYouTube)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results found',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isSearchingYouTube)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_hasFetchedYouTube &&
            !_isSearchingYouTube &&
            query.isNotEmpty &&
            !_isOffline)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () => _searchYouTube(query),
                icon: const Icon(Icons.cloud),
                label: const Text('Search Online'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocalResultItem(
    model.Song song,
    music_provider.MusicProvider provider,
    model.Song? currentSong,
    bool isPlaying,
  ) {
    final isCurrent = provider.currentSong?.id == song.id;
    final isSongPlaying = provider.isPlaying && isCurrent;
    final l10n = AppLocalizations.of(context);

    return ListTile(
      leading: Icon(
        isCurrent && isSongPlaying ? Icons.play_arrow : Icons.music_note,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        song.title,
        style: TextStyle(
          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        song.artists.isNotEmpty ? song.artists.join(' & ') : 'Unknown Artist',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isCurrent && isSongPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () {
              if (isCurrent) {
                if (isSongPlaying) {
                  provider.pause();
                } else {
                  provider.play();
                }
              } else {
                provider.playSong(song);
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleSongAction(value, song, provider),
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
                    const Icon(Icons.delete_outline, color: Colors.red),
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
      onTap: () {
        if (isCurrent) {
          if (isSongPlaying) {
            provider.pause();
          } else {
            provider.play();
          }
        } else {
          provider.playSong(song);
        }
      },
    );
  }

  Future<void> _handleSongAction(
    String action,
    model.Song song,
    music_provider.MusicProvider provider,
  ) async {
    switch (action) {
      case 'add_to_playlist':
        showAddToPlaylistSheet(context, item: PlaylistItem(songId: song.id));
      case 'move':
        await _showMoveDialog(song);
      case 'delete':
        await _showDeleteConfirmation(song, provider);
    }
  }

  Future<void> _showMoveDialog(model.Song song) async {
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

  Future<void> _showDeleteConfirmation(
    model.Song song,
    music_provider.MusicProvider provider,
  ) async {
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
        await provider.deleteSong(song);
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

  Widget _buildYouTubeResultItem(YouTubeAudio audio) {
    final musicProvider = context.read<music_provider.MusicProvider>();
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
      onDelete: () async {
        final song = musicProvider.songs
            .where((s) => s.youtubeId == audio.id && s.tags.contains('tsmusic'))
            .firstOrNull;
        if (song != null) {
          await _showDeleteConfirmation(song, musicProvider);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.MusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;
    final localSongs = musicProvider.songs;

    return WillPopScope(
      onWillPop: () async {
        await _youtubePlayer.stop();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search songs...',
              border: InputBorder.none,
            ),
            onChanged: (value) {
              _hasFetchedYouTube = false;
              if (value.isNotEmpty && !_isOffline) {
                _debouncedSearch(value);
              }
              setState(() {});
            },
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _youtubePlayer.stop();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _buildMixedResults(
                localSongs,
                musicProvider,
                currentSong,
                isPlaying,
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
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
