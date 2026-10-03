import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/data/repositories/playlist_repository.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/utils/format_utils.dart';
import 'package:tsmusic/utils/download_enqueue.dart';
import 'package:tsmusic/services/download_queue.dart';
class PlaylistDetailScreen extends StatefulWidget {
  final int playlistId;
  final String playlistName;
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}
class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistRepository _playlistRepository = PlaylistRepository();
  final SongRepository _songRepository = SongRepository();
  List<Song> _songs = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  @override
  void initState() {
    super.initState();
    _loadSongs();
  }
  Future<void> _loadSongs() async {
    setState(() => _isLoading = true);
    try {
      final songs = await _songRepository.getPlaylistSongs(widget.playlistId);
      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading songs: $e')));
      }
    }
  }
  Future<void> _removeSong(Song song) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeFromPlaylist),
        content: Text('Remove "${song.title}" from this playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _playlistRepository.removeSongsFromPlaylist(widget.playlistId, [
          song.id,
        ]);
        await _loadSongs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Song removed from playlist')),
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
  }
  Future<void> _showAddSongsDialog() async {
    final l10n = AppLocalizations.of(context);
    final musicProvider = Provider.of<music_provider.MusicProvider>(
      context,
      listen: false,
    );
    final youTubeService = context.read<YouTubeService>();
    final allSongs = musicProvider.librarySongs;
    final selectedSongs = <int>{};
    final tv = TextEditingController();
    var ytResults = <YouTubeAudio>[];
    var ytLoading = false;
    Future<void> addYouTubeTrack(YouTubeAudio audio) async {
      try {
        await musicProvider.addOnlineSongToPlaylist(
          youtubeId: audio.id,
          title: audio.title,
          artists: audio.artists.isNotEmpty
              ? audio.artists
              : [audio.author],
          duration: audio.duration?.inMilliseconds ?? 0,
          thumbnailUrl: audio.thumbnailUrl,
          playlistId: widget.playlistId,
        );
      } catch (e) {
        rethrow;
      }
    }
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.addSongs),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add from YouTube (no download)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tv,
                          decoration: const InputDecoration(
                            hintText: 'Search YouTube songs...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) async {
                            if (tv.text.trim().isEmpty) return;
                            setDialogState(() => ytLoading = true);
                            try {
                              final results = await youTubeService.searchAudio(
                                tv.text.trim(),
                              );
                              if (context.mounted) {
                                setDialogState(() => ytResults = results);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                setDialogState(
                                  () => ytResults = <YouTubeAudio>[],
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setDialogState(() => ytLoading = false);
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: ytLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        onPressed: ytLoading
                            ? null
                            : () async {
                                if (tv.text.trim().isEmpty) return;
                                setDialogState(() => ytLoading = true);
                                try {
                                  final results =
                                      await youTubeService.searchAudio(
                                    tv.text.trim(),
                                  );
                                  if (context.mounted) {
                                    setDialogState(
                                      () => ytResults = results,
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    setDialogState(
                                      () => ytResults = <YouTubeAudio>[],
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setDialogState(() => ytLoading = false);
                                  }
                                }
                              },
                      ),
                    ],
                  ),
                  if (ytResults.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'YouTube results',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: ytResults.length,
                        itemBuilder: (context, index) {
                          final audio = ytResults[index];
                          final alreadyInPlaylist = _songs.any(
                            (s) => s.youtubeId == audio.id,
                          );
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.play_circle_outline),
                            title: Text(
                              audio.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              audio.artists.isNotEmpty
                                  ? audio.artists.join(' & ')
                                  : audio.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                alreadyInPlaylist
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: alreadyInPlaylist
                                    ? Colors.grey
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: alreadyInPlaylist
                                  ? null
                                  : () async {
                                      try {
                                        await addYouTubeTrack(audio);
                                        await _loadSongs();
                                        if (context.mounted) {
                                          setDialogState(() {});
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Added "${audio.title}" to playlist',
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (_) {}
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  Text(
                    l10n.addSongs,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (allSongs.isEmpty)
                    Center(child: Text(l10n.noMusicFound))
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allSongs.length,
                        itemBuilder: (context, index) {
                          final song = allSongs[index];
                          final isSelected = selectedSongs.contains(song.id);
                          final isAlreadyInPlaylist = _songs.any(
                            (s) => s.id == song.id,
                          );
                          return CheckboxListTile(
                            dense: true,
                            value: isSelected,
                            onChanged: isAlreadyInPlaylist
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedSongs.add(song.id);
                                      } else {
                                        selectedSongs.remove(song.id);
                                      }
                                    });
                                  },
                            title: Text(
                              song.title,
                              style: TextStyle(
                                color: isAlreadyInPlaylist
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              song.artists.join(' & '),
                              style: TextStyle(
                                color: isAlreadyInPlaylist
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                            secondary: isAlreadyInPlaylist
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.grey,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: selectedSongs.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(context);
                      try {
                        await _playlistRepository.addSongsToPlaylist(
                          widget.playlistId,
                          selectedSongs.toList(),
                        );
                        await _loadSongs();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${selectedSongs.length} songs added to playlist',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              child: Text(l10n.add),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _startPlayback({
    int? startIndex,
    bool popAfter = false,
  }) async {
    final musicProvider = Provider.of<music_provider.MusicProvider>(
      context,
      listen: false,
    );
    try {
      await musicProvider.loadPlaylistAsQueue(
        widget.playlistId,
        startIndex: startIndex,
      );
      if (!mounted) return;
      if (popAfter) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start playback: $e')),
      );
    }
  }
  Future<void> _playPlaylist() async {
    if (_songs.isEmpty) return;
    await _startPlayback(popAfter: true);
  }
  int get _remoteSongCount => _songs
      .where(
        (s) =>
            s.url.startsWith('yt:') &&
            (s.youtubeId?.isNotEmpty ?? false),
      )
      .length;
  Future<void> _downloadAllRemoteSongs() async {
    if (_remoteSongCount == 0) return;
    final requests = _songs
        .where(
          (s) =>
              s.url.startsWith('yt:') &&
              (s.youtubeId?.isNotEmpty ?? false),
        )
        .map(
          (s) => DownloadRequest(videoId: s.youtubeId!, title: s.title),
        )
        .toList();
    await enqueueAllForDownload(
      context: context,
      requests: requests,
      youTubeService: context.read<YouTubeService>(),
      settings: context.read<SettingsProvider>(),
    );
    // No refresh here: the batch runs in the background and the library is
    // updated per track as it lands, so reloading now would just be a no-op
    // followed by another reload in a few seconds.
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _playPlaylist,
              tooltip: l10n.play,
            ),
          if (_remoteSongCount > 0)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: _downloadAllRemoteSongs,
              tooltip: 'Download all online songs',
            ),
          IconButton(
            icon: Icon(_isEditMode ? Icons.done : Icons.edit),
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
            tooltip: _isEditMode ? l10n.done : l10n.edit,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.queue_music, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('Playlist is empty', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Add songs to get started',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showAddSongsDialog,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addSongs),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              itemCount: _songs.length,
              onReorderItem: (oldIndex, newIndex) async {
                final song = _songs.removeAt(oldIndex);
                _songs.insert(newIndex, song);
                setState(() {});
              },
              itemBuilder: (context, index) {
                final song = _songs[index];
                return ListTile(
                  key: ValueKey(song.id),
                  leading: _isEditMode
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeSong(song),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: song.url.startsWith('yt:')
                                ? Colors.red.withValues(alpha: 0.15)
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            song.url.startsWith('yt:')
                                ? Icons.cloud
                                : Icons.music_note,
                            color: song.url.startsWith('yt:')
                                ? Colors.red
                                : null,
                          ),
                        ),
                  title: Text(song.title),
                  subtitle: Text(song.artists.join(' & ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatDurationFromMs(song.duration)),
                      if (_isEditMode)
                        const Icon(Icons.drag_handle, color: Colors.grey),
                    ],
                  ),
                  onTap: _isEditMode
                      ? null
                      : () => _startPlayback(startIndex: index),
                );
              },
            ),
      floatingActionButton: _songs.isNotEmpty && !_isEditMode
          ? FloatingActionButton(
              onPressed: _showAddSongsDialog,
              tooltip: 'Add Songs',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
