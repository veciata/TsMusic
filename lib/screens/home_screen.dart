import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/models/playlist_item.dart';
import 'package:tsmusic/models/playlist.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/data/repositories/playlist_repository.dart';
import 'package:tsmusic/services/artist_image_cache.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/core/services/clipboard_service.dart';
import 'package:tsmusic/utils/format_utils.dart';
import 'package:tsmusic/widgets/song_thumbnail.dart';
import 'package:tsmusic/widgets/playlist_selector_bottom_sheet.dart';
import 'package:tsmusic/widgets/skeleton_widgets.dart';
import 'search_screen.dart';
import 'artist_detail_screen.dart';
import 'playlist_detail_screen.dart';
import 'package:tsmusic/widgets/sliding_text.dart';
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
  List<Playlist> _playlists = [];
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
      final playlists = await context.read<PlaylistRepository>().getAllPlaylists();
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
          String path = filePath
              .split('?')[0]
              .split('#')[0]
              .toLowerCase()
              .trim();
          const String emulatedPrefix = '/storage/emulated/0/';
          if (path.startsWith(emulatedPrefix)) {
            path = '/sdcard/${path.substring(emulatedPrefix.length)}';
          }
          final uri = Uri.file(path);
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          return '/${segments.join('/')}';
        } catch (e) {
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
          continue;
        }
      }
      final songs = uniqueSongs.values.toList()
        ..sort((a, b) {
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
      return [];
    }
  }
  String _getArtistsText(List<String> artists) {
    if (artists.isEmpty) return 'Unknown Artist';
    return artists.join(' & ');
  }
  Widget _buildFilterBar(
    music_provider.MusicProvider musicProvider,
    BuildContext context,
  ) {
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
                        Text(
                          l10n.sortByTitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.artist,
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          l10n.sortByArtist,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.dateAdded,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          l10n.sortByDate,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
            tooltip: musicProvider.sortAscending
                ? l10n.ascending
                : l10n.descending,
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
    final isSelected = _selectedSongs.contains(song.id);
    final l10n = AppLocalizations.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      musicProvider.requestThumbnail(song, priority: 1);
    });
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
          : SongThumbnail(song: song, size: 40),
      title: SlidingText(
        song.title.isNotEmpty ? song.title : l10n.unknownTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        _getArtistsText(song.artists),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
        ),
      ),
      trailing: _isMultiSelectMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatDurationFromMs(song.duration)),
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
                          Text(
                            l10n.delete,
                            style: const TextStyle(color: Colors.red),
                          ),
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
      onTap: _isMultiSelectMode
          ? () {
              setState(() {
                if (_selectedSongs.contains(song.id)) {
                  _selectedSongs.remove(song.id);
                } else {
                  _selectedSongs.add(song.id);
                }
              });
            }
          : () => musicProvider.playSongFromLibrary(song),
      onLongPress: () {
        if (!_isMultiSelectMode) {
          setState(() {
            _isMultiSelectMode = true;
            _selectedSongs.add(song.id);
          });
        }
      },
    );
  }
  PreferredSizeWidget _buildMultiSelectAppBar(AppLocalizations l10n) => AppBar(
    leading: IconButton(
      icon: const Icon(Icons.close),
      onPressed: () {
        setState(() {
          _isMultiSelectMode = false;
          _selectedSongs.clear();
        });
      },
    ),
    title: Text('${_selectedSongs.length} ${l10n.selected}'),
    actions: [
      IconButton(
        icon: const Icon(Icons.drive_file_move_outline),
        onPressed: _selectedSongs.isEmpty
            ? null
            : () => _moveSelectedSongs(context),
        tooltip: l10n.move,
      ),
      IconButton(
        icon: const Icon(Icons.playlist_add),
        onPressed: _selectedSongs.isEmpty
            ? null
            : () => showPlaylistSelector(context),
        tooltip: l10n.addToPlaylist,
      ),
      IconButton(
        icon: const Icon(Icons.delete),
        onPressed: _selectedSongs.isEmpty
            ? null
            : () => _deleteSelectedSongs(context),
        tooltip: l10n.delete,
        color: Colors.red,
      ),
    ],
  );
  Future<void> _deleteSelectedSongs(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(
          '${l10n.confirmDelete} ${_selectedSongs.length} ${l10n.songs}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      final musicProvider = Provider.of<music_provider.MusicProvider>(
        context,
        listen: false,
      );
      for (final id in _selectedSongs) {
        final song = musicProvider.songs.where((s) => s.id == id).firstOrNull;
        if (song != null) {
          await musicProvider.deleteSong(song);
        }
      }
      setState(() {
        _isMultiSelectMode = false;
        _selectedSongs.clear();
      });
    }
  }
  Future<void> _moveSelectedSongs(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final locations = [
      {
        'label': l10n.internalStorage,
        'path': '/storage/emulated/0/Music/tsmusic',
      },
      {'label': l10n.downloads, 'path': '/storage/emulated/0/Download'},
      {'label': l10n.musicFolder, 'path': '/storage/emulated/0/Music'},
    ];
    final musicProvider = Provider.of<music_provider.MusicProvider>(
      context,
      listen: false,
    );
    final selectedPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.moveTo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: locations
              .map(
                (loc) => ListTile(
                  title: Text(loc['label']!),
                  onTap: () => Navigator.pop(context, loc['path']),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selectedPath != null) {
      final targetDir = Directory(selectedPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      for (final id in _selectedSongs) {
        final song = musicProvider.songs.where((s) => s.id == id).firstOrNull;
        if (song != null) {
          try {
            final file = File(song.url);
            final newPath = path.join(selectedPath, path.basename(song.url));
            try {
              await file.rename(newPath);
            } on FileSystemException {
              await file.copy(newPath);
              await file.delete();
            }
            final updatedSong = song.copyWith(url: newPath);
            musicProvider.addSongToPlaylist(updatedSong);
          } catch (e) {
          }
        }
      }
      setState(() {
        _isMultiSelectMode = false;
        _selectedSongs.clear();
      });
      await musicProvider.refreshSongs();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedSongs.length} ${l10n.songsMoved}'),
          ),
        );
      }
    }
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
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(
                  milliseconds: 300 + (index * 50).clamp(0, 500),
                ),
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                ),
                child: _buildSongTile(song, musicProvider),
              );
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
                _ArtistTileAvatar(
                  artistName: artistName,
                  songs: artistSongs,
                  initialUrl: imageUrl,
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
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  void _showCreatePlaylistDialog() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final linkController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createPlaylist),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.playlistName,
                hintText: 'Optional when importing from a YouTube link',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: linkController,
              decoration: const InputDecoration(
                labelText: 'YouTube playlist link (optional)',
                hintText: 'https://www.youtube.com/playlist?list=…',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste a YouTube playlist (or video) link to create the '
              'playlist and import its songs.',
              style: TextStyle(fontSize: 12),
            ),
            ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              final link = linkController.text.trim();
              if (name.isEmpty && link.isEmpty) return;
              Navigator.pop(context);
              if (link.isNotEmpty) {
                _createPlaylistFromLink(name, link);
              } else {
                _createEmptyPlaylist(name);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
  Future<void> _createEmptyPlaylist(String name) async {
    final l10n = AppLocalizations.of(context);
    try {
      await context
          .read<PlaylistRepository>()
          .createPlaylist(name);
      await _loadPlaylists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.playlistCreated)),
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
  Future<void> _createPlaylistFromLink(String name, String link) async {
    final playlistRepository = context.read<PlaylistRepository>();
    final youTubeService = context.read<YouTubeService>();
    final musicProvider = context.read<music_provider.MusicProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final parsed = ClipboardService().parseYouTubeLink(link);
    if (parsed == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube link')),
      );
      return;
    }
    final isPlaylist = parsed.playlistId != null;
    final playlistUrl = isPlaylist
        ? 'https://www.youtube.com/playlist?list=${parsed.playlistId}'
        : link;
    var importedName = name.trim();
    final audios = <YouTubeAudio>[];
    var added = 0;
    var error = '';
    final progress = ValueNotifier<String>('Fetching playlist…');
    final finished = ValueNotifier<bool>(false);
    unawaited(() async {
      try {
        if (isPlaylist) {
          audios.addAll(await youTubeService.fetchPlaylist(playlistUrl));
          if (importedName.isEmpty) {
            final title = await youTubeService.fetchPlaylistTitle(playlistUrl);
            if (title != null && title.isNotEmpty) importedName = title;
          }
        } else if (parsed.videoId != null) {
          final audio = await youTubeService.getAudioByVideoId(parsed.videoId!);
          if (audio != null) {
            audios.add(audio);
            if (importedName.isEmpty && audio.title.isNotEmpty) {
              importedName = audio.title;
            }
          }
        }
        if (audios.isEmpty) {
          error = 'This playlist is empty or could not be read.';
          return;
        }
        final fallback = importedName.isEmpty ? 'YouTube playlist' : importedName;
        final playlistId = await playlistRepository.createPlaylist(
          fallback,
          description: playlistUrl,
        );
        for (final audio in audios) {
          progress.value = 'Adding ${added + 1}/${audios.length}: ${audio.title}';
          try {
            await musicProvider.addOnlineSongToPlaylist(
              youtubeId: audio.id,
              title: audio.title,
              artists: audio.artists.isNotEmpty ? audio.artists : [audio.author],
              duration: audio.duration?.inMilliseconds ?? 0,
              thumbnailUrl: audio.thumbnailUrl,
              playlistId: playlistId,
            );
            added++;
          } catch (_) {
          }
        }
      } catch (e) {
        error = e.toString();
      } finally {
        finished.value = true;
        progress.value = error.isEmpty ? 'Done' : 'Failed';
      }
    }());
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<String>(
        valueListenable: progress,
        builder: (dialogContext, message, _) {
          if (finished.value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            });
          }
          return AlertDialog(
            title: const Text('Importing playlist…'),
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(message)),
              ],
            ),
          );
        },
      ),
    );
    if (!context.mounted) return;
    await _loadPlaylists();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error.isNotEmpty
              ? '${l10n.error}: $error'
              : 'Created "$importedName" with $added song(s) from YouTube',
        ),
      ),
    );
  }
  Widget _buildPlaylistsTab(music_provider.MusicProvider musicProvider) {
    final l10n = AppLocalizations.of(context);
    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }
    final userPlaylists = _playlists
        .where((p) => p.id != PlaylistRepository.nowPlayingPlaylistId)
        .toList();
    return Column(
      children: [
        Expanded(
          child: userPlaylists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.queue_music,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noPlaylists,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You can also paste a YouTube playlist link to '
                        'import it as a playlist.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _showCreatePlaylistDialog,
                        icon: const Icon(Icons.link),
                        label: const Text('Import from YouTube link'),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.queue_music,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      title: Text(playlist.name),
                      subtitle: playlist.description != null
                          ? Text(
                              playlist.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          final playlistRepository =
                              context.read<PlaylistRepository>();
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l10n.deletePlaylist),
                              content: Text(
                                '${l10n.confirmDelete} "${playlist.name}"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l10n.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await playlistRepository.deletePlaylist(playlist.id);
                            await _loadPlaylists();
                          }
                        },
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlaylistDetailScreen(
                              playlistId: playlist.id,
                              playlistName: playlist.name,
                            ),
                          ),
                        );
                        unawaited(_loadPlaylists());
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
      return PopScope(
        canPop: !_isMultiSelectMode,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_isMultiSelectMode) {
            setState(() {
              _isMultiSelectMode = false;
              _selectedSongs.clear();
            });
          }
        },
        child: Scaffold(
          appBar: _isMultiSelectMode ? _buildMultiSelectAppBar(l10n) : null,
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
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: musicProvider.refreshSongs,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.tryAgain),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_isMultiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isMultiSelectMode) {
          setState(() {
            _isMultiSelectMode = false;
            _selectedSongs.clear();
          });
        }
      },
      child: Scaffold(
        appBar: _isMultiSelectMode ? _buildMultiSelectAppBar(l10n) : null,
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
        floatingActionButton: AnimatedBuilder(
          animation: _tabController.animation!,
          builder: (context, child) {
            final value = _tabController.animation!.value;
            if (value < 1.0) return const SizedBox.shrink();
            return Transform.scale(
              scale: (value - 1.0).clamp(0.0, 1.0),
              child: FloatingActionButton(
                onPressed: _showCreatePlaylistDialog,
                tooltip: l10n.createPlaylist,
                child: const Icon(Icons.add),
              ),
            );
          },
        ),
      ),
    );
  }
  Future<void> _handleSongAction(
    String action,
    Song song,
    music_provider.MusicProvider provider,
  ) async {
    switch (action) {
      case 'move':
        await _showMoveDialog(song);
        break;
      case 'delete':
        await _showDeleteConfirmation(song, provider);
        break;
      case 'add_to_playlist':
        showAddToPlaylistSheet(context, item: PlaylistItem(songId: song.id));
        break;
    }
  }
  Future<void> _showMoveDialog(Song song) async {
    final l10n = AppLocalizations.of(context);
    final locations = [
      {
        'label': l10n.internalStorage,
        'path': '/storage/emulated/0/Music/tsmusic',
      },
      {'label': l10n.downloads, 'path': '/storage/emulated/0/Download'},
      {'label': l10n.musicFolder, 'path': '/storage/emulated/0/Music/tsmusic'},
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
        try {
          await file.rename(newPath);
        } on FileSystemException {
          await file.copy(newPath);
          await file.delete();
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${l10n.move}: $selected')));
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
    Song song,
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
}
class _ArtistTileAvatar extends StatefulWidget {
  const _ArtistTileAvatar({
    required this.artistName,
    required this.songs,
    this.initialUrl,
  });
  final String artistName;
  final List<Song> songs;
  final String? initialUrl;
  @override
  State<_ArtistTileAvatar> createState() => _ArtistTileAvatarState();
}
class _ArtistTileAvatarState extends State<_ArtistTileAvatar> {
  String? _url;
  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    _resolve();
  }
  Future<void> _resolve() async {
    final cache = context.read<ArtistImageCache>();
    final cached = await cache.ensureArtistImage(
      widget.artistName,
      localSongs: widget.songs,
    );
    if (cached != null && mounted && cached != _url) {
      setState(() => _url = cached);
    }
  }
  ImageProvider<Object>? _imageProvider(String url) {
    if (!url.startsWith('http')) {
      final file = File(url);
      if (file.existsSync()) return FileImage(file);
      return null;
    }
    return NetworkImage(url);
  }
  @override
  Widget build(BuildContext context) {
    final provider = _url == null ? null : _imageProvider(_url!);
    return CircleAvatar(
      radius: 40,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.2),
      backgroundImage: provider,
      child: provider == null
          ? Icon(
              Icons.person,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }
}
