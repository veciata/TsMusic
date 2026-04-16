import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/widgets/skeleton_widgets.dart';
import 'package:tsmusic/widgets/playlist_selector_bottom_sheet.dart';
import 'package:tsmusic/localization/app_localizations.dart';

import 'search_screen.dart';
import 'artist_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;

  const HomeScreen({super.key, this.onSettingsTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final Set<int> _selectedSongs = {};
  bool _isMultiSelectMode = false;
  late TabController _tabController;
  List<Map<String, dynamic>> _playlists = [];
  bool _isLoadingPlaylists = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPlaylists();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoadingPlaylists = true);
    try {
      final playlists = await DatabaseHelper().getAllPlaylists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _isLoadingPlaylists = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPlaylists = false);
      }
    }
  }

  List<Song> _getSortedSongs(music_provider.MusicProvider provider) {
    try {
      final Map<int, Song> uniqueSongs = {};
      final Set<String> seenPaths = {};

      String getNormalizedPath(String filePath) {
        try {
          String path =
              filePath.split('?')[0].split('#')[0].toLowerCase().trim();
          const String emulatedPrefix = '/storage/emulated/0/';
          if (path.startsWith(emulatedPrefix)) {
            path = '/sdcard/${path.substring(emulatedPrefix.length)}';
          }
          final uri = Uri.file(path);
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          return '/${segments.join('/')}';
        } catch (e) {
          if (kDebugMode) {
            print('Error normalizing path "$filePath": $e');
          }
          return filePath.toLowerCase();
        }
      }

      for (final song in provider.librarySongs) {
        try {
          if (song.url.isEmpty) continue;
          final normalizedPath = getNormalizedPath(song.url);
          if (normalizedPath.isEmpty) continue;
          if (seenPaths.contains(normalizedPath)) continue;
          seenPaths.add(normalizedPath);
          uniqueSongs[song.id] = song;
        } catch (e) {
          if (kDebugMode) {
            print('Error processing song ${song.id}: $e');
          }
        }
      }

      final songs = uniqueSongs.values.toList();

      songs.sort((a, b) {
        int compare;
        switch (provider.currentSortOption) {
          case SongSortOption.title:
            compare = a.title.compareTo(b.title);
            break;
          case SongSortOption.artist:
            final artistA = a.artists.isNotEmpty ? a.artists.join(' & ') : '';
            final artistB = b.artists.isNotEmpty ? b.artists.join(' & ') : '';
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
        return provider.sortAscending ? compare : -compare;
      });

      return songs;
    } catch (e) {
      if (kDebugMode) {
        print('Error in _getSortedSongs: $e');
      }
      return [];
    }
  }

  String _getArtistsText(List<String> artists) {
    if (artists.isEmpty) return 'Unknown Artist';
    return artists.join(' & ');
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildFilterBar(
      music_provider.MusicProvider musicProvider, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SongSortOption>(
                value: musicProvider.currentSortOption,
                isDense: true,
                icon: const Icon(Icons.sort, size: 20),
                items: [
                  DropdownMenuItem(
                    value: SongSortOption.title,
                    child: Row(
                      children: [
                        const Icon(Icons.sort_by_alpha, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.sortByTitle,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.artist,
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.sortByArtist,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.dateAdded,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.sortByDate,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    musicProvider.setSortOption(value);
                  }
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              musicProvider.sortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 20,
            ),
            onPressed: () => musicProvider.toggleSortDirection(),
            tooltip:
                musicProvider.sortAscending ? l10n.ascending : l10n.descending,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => musicProvider.refreshSongs(),
            tooltip: l10n.refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Song song, music_provider.MusicProvider musicProvider) {
    final isLocal = song.url.startsWith('/storage/emulated/0') ||
        song.url.startsWith('/data/user/');
    final isDownloaded = song.tags.contains('tsmusic');
    final isSelected = _selectedSongs.contains(song.id);
    final l10n = AppLocalizations.of(context);

    return ListTile(
      leading: _isMultiSelectMode
          ? Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedSongs.add(song.id);
                  } else {
                    _selectedSongs.remove(song.id);
                  }
                });
              },
            )
          : Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isDownloaded
                  ? const Icon(Icons.download_done, color: Colors.green)
                  : isLocal
                      ? const Icon(Icons.folder, color: Colors.orange)
                      : const Icon(Icons.music_note),
            ),
      title: Text(
        song.title.isNotEmpty ? song.title : l10n.unknownTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _getArtistsText(song.artists),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.7),
            ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatDuration(song.duration)),
          PopupMenuButton<String>(
            onSelected: (value) =>
                _handleSongAction(value, song, musicProvider),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'move',
                child: Row(
                  children: [
                    const Icon(Icons.drive_file_move_outline),
                    const SizedBox(width: 8),
                    Text(l10n.move),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(l10n.delete,
                        style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
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
            ],
          ),
        ],
      ),
      onTap: () => musicProvider.playSong(song),
    );
  }

  Widget _buildNoMusicFound() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            l10n.noMusicFound,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(l10n.addMusicToDevice),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
            icon: const Icon(Icons.search),
            label: Text(l10n.searchAndDownload),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicTab(music_provider.MusicProvider musicProvider) {
    final sortedSongs = _getSortedSongs(musicProvider);

    if (sortedSongs.isEmpty) {
      return _buildNoMusicFound();
    }

    return Column(
      children: [
        _buildFilterBar(musicProvider, context),
        Expanded(
          child: ListView.builder(
            itemCount: sortedSongs.length,
            itemBuilder: (context, index) {
              final song = sortedSongs[index];
              return _buildSongTile(song, musicProvider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildArtistsTab(music_provider.MusicProvider musicProvider) {
    final l10n = AppLocalizations.of(context);
    final artists = musicProvider.artists;

    if (artists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.noArtists,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artistName = artists[index];
        final artistSongs = musicProvider.getSongsByArtist(artistName);
        final imageUrl = musicProvider.getArtistImageUrl(artistName);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ArtistDetailScreen(
                  artistName: artistName,
                  artistImageUrl: ValueNotifier<String?>(imageUrl),
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  backgroundImage:
                      imageUrl != null ? NetworkImage(imageUrl) : null,
                  child: imageUrl == null
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  artistName,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${artistSongs.length} ${l10n.songs.toLowerCase()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsTab(music_provider.MusicProvider musicProvider) {
    final l10n = AppLocalizations.of(context);

    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }

    final userPlaylists = _playlists
        .where((p) => p['id'] != DatabaseHelper.nowPlayingPlaylistId)
        .toList();

    return Column(
      children: [
        Expanded(
          child: userPlaylists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noPlaylists,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: userPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = userPlaylists[index];
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.queue_music,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      title: Text(playlist['name'] ?? 'Unnamed'),
                      subtitle: playlist['description'] != null
                          ? Text(
                              playlist['description']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l10n.deletePlaylist),
                              content: Text(
                                  '${l10n.confirmDelete} "${playlist['name']}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l10n.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await DatabaseHelper()
                                .deletePlaylist(playlist['id'] as int);
                            await _loadPlaylists();
                          }
                        },
                      ),
                      onTap: () async {
                        await musicProvider
                            .loadPlaylistAsQueue(playlist['id'] as int);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final l10n = AppLocalizations.of(context);

    if (musicProvider.isLoading) {
      return const SkeletonHomeScreen();
    }

    if (musicProvider.error != null && musicProvider.songs.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.music_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  l10n.noMusicFound,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Download music from YouTube',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => musicProvider.refreshSongs(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.tryAgain),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: l10n.music),
              Tab(text: l10n.artists),
              Tab(text: l10n.playlists),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMusicTab(musicProvider),
                _buildArtistsTab(musicProvider),
                _buildPlaylistsTab(musicProvider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleSongAction(
      String action, Song song, music_provider.MusicProvider provider) async {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case 'move':
        await _showMoveDialog(song);
        break;
      case 'delete':
        await _showDeleteConfirmation(song, provider);
        break;
      case 'add_to_playlist':
        showPlaylistSelector(context);
        break;
    }
  }

  Future<void> _showMoveDialog(Song song) async {
    final l10n = AppLocalizations.of(context);
    final locations = [
      {'label': l10n.internalStorage, 'path': '/storage/emulated/0/Music'},
      {'label': l10n.downloads, 'path': '/storage/emulated/0/Download'},
      {'label': l10n.musicFolder, 'path': '/storage/emulated/0/Music'},
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.moveTo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: locations
              .map((loc) => ListTile(
                    title: Text(loc['label']!),
                    onTap: () => Navigator.pop(context, loc['path']),
                  ))
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      try {
        final file = File(song.url);
        final newPath = path.join(selected, path.basename(song.url));
        try {
          await file.rename(newPath);
        } on FileSystemException {
          await file.copy(newPath);
          await file.delete();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.move}: $selected')),
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
      Song song, music_provider.MusicProvider provider) async {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.songDeleted)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.error}: $e')),
          );
        }
      }
    }
  }
}
