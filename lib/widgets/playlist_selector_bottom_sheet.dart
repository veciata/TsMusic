import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/playlist_item.dart';
import 'package:tsmusic/models/storage_type.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/utils/playlist_boundary.dart';

class PlaylistSelectorBottomSheet extends StatefulWidget {
  final PlaylistItem? item;

  const PlaylistSelectorBottomSheet({super.key, this.item});

  @override
  State<PlaylistSelectorBottomSheet> createState() =>
      _PlaylistSelectorBottomSheetState();
}

class _PlaylistSelectorBottomSheetState
    extends State<PlaylistSelectorBottomSheet> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final playlists = await _db.getAllPlaylists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading playlists: $e')));
      }
    }
  }

  Future<void> _deletePlaylist(int playlistId, String name) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePlaylist),
        content: Text('${l10n.confirmDelete} "$name"?'),
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
        await _db.deletePlaylist(playlistId);
        await _loadPlaylists();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.playlistDeleted)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _showCreatePlaylistDialog() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createPlaylist),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.playlistName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                try {
                  await _db.createPlaylist(name);
                  await _loadPlaylists();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text(l10n.playlistCreated)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    this.context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  Future<void> _addToPlaylist(Map<String, dynamic> playlist) async {
    final playlistId = playlist['id'] as int;
    final item = widget.item;

    if (item?.youtubeId != null) {
      final playlistTypeStr =
          playlist['playlist_type'] as String? ?? 'local_only';
      final playlistType = playlistTypeStr == 'remote_compatible'
          ? PlaylistType.remoteCompatible
          : PlaylistType.localOnly;

      final warning = PlaylistBoundary.getWarningMessage(
        StorageType.remote,
        playlistType,
      );
      if (warning != null && mounted) {
        final proceed = await PlaylistBoundary.showWarningDialog(
          context,
          warning,
        );
        if (!proceed) return;
      }
    }

    try {
      if (item != null) {
        if (item.songId != null) {
          await _db.addSongsToPlaylist(playlistId, [item.songId!]);
        } else if (item.youtubeId != null) {
            if (!mounted) return;
            final musicProvider = context.read<music_provider.MusicProvider>();
          await musicProvider.addOnlineSongToPlaylist(
            youtubeId: item.youtubeId!,
            title: item.title ?? 'Unknown',
            artists: item.artists ?? ['Unknown Artist'],
            duration: item.duration ?? 0,
            thumbnailUrl: item.thumbnailUrl,
            playlistId: playlistId,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to "${playlist['name']}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addToNowPlaying() async {
    final item = widget.item;
    if (item == null) return;

    try {
      if (item.songId != null) {
        final musicProvider = context.read<music_provider.MusicProvider>();
        final song = musicProvider.librarySongs
            .where((s) => s.id == item.songId)
            .firstOrNull;
        if (song != null) {
          musicProvider.addSongToPlaylist(song);
        }
      } else if (item.youtubeId != null) {
        final musicProvider = context.read<music_provider.MusicProvider>();
        final songId = await musicProvider.addOnlineSongToPlaylist(
          youtubeId: item.youtubeId!,
          title: item.title ?? 'Unknown',
          artists: item.artists ?? ['Unknown Artist'],
          duration: item.duration ?? 0,
          thumbnailUrl: item.thumbnailUrl,
          playlistId: DatabaseHelper.nowPlayingPlaylistId,
        );
        if (songId > 0) {
          final song = musicProvider.librarySongs
              .where((s) => s.id == songId)
              .firstOrNull;
          if (song != null) {
            musicProvider.addSongToPlaylist(song);
          }
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to Now Playing')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final theme = Theme.of(context);
    final isAddMode = widget.item != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  isAddMode ? l10n.addToPlaylist : l10n.playlists,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: isAddMode
                      ? _showCreatePlaylistDialog
                      : _showCreatePlaylistDialog,
                  tooltip: l10n.createPlaylist,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isAddMode
                            ? Icons.playlist_add
                            : Icons.play_circle_filled,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      isAddMode ? 'Add to Now Playing' : l10n.nowPlaying,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${musicProvider.queue.length} ${l10n.songs.toLowerCase()}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: isAddMode
                        ? _addToNowPlaying
                        : () => Navigator.pop(context),
                  ),
                  const Divider(height: 1, indent: 72),
                  ..._playlists
                      .where(
                        (p) => p['id'] != DatabaseHelper.nowPlayingPlaylistId,
                      )
                      .map(
                        (playlist) => ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.queue_music,
                              color: theme.colorScheme.secondary,
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
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            if (isAddMode) {
                              _addToPlaylist(playlist);
                            } else {
                              final playlistId = playlist['id'] as int;
                              musicProvider.loadPlaylistAsQueue(playlistId);
                              if (mounted) {
                                Navigator.pop(context);
                              }
                            }
                          },
                          onLongPress: () {
                            _deletePlaylist(
                              playlist['id'] as int,
                              playlist['name'] ?? 'Unnamed',
                            );
                          },
                        ),
                      ),
                  if (isAddMode &&
                      _playlists
                          .where(
                            (p) =>
                                p['id'] != DatabaseHelper.nowPlayingPlaylistId,
                          )
                          .isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.noPlaylists,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

void showPlaylistSelector(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const PlaylistSelectorBottomSheet(),
  );
}

void showAddToPlaylistSheet(
  BuildContext context, {
  required PlaylistItem item,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PlaylistSelectorBottomSheet(item: item),
  );
}

void showAddYouTubeToPlaylistSheet(
  BuildContext context, {
  required String youtubeId,
  required String title,
  required List<String> artists,
  required int duration,
  String? thumbnailUrl,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PlaylistSelectorBottomSheet(
      item: PlaylistItem(
        youtubeId: youtubeId,
        title: title,
        artists: artists,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
      ),
    ),
  );
}
