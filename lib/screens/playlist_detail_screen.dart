import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/localization/app_localizations.dart';

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
  final DatabaseHelper _db = DatabaseHelper();
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
      final songMaps = await _db.getSongsInPlaylist(widget.playlistId);
      final songs = <Song>[];

      for (final songData in songMaps) {
        final songId = songData['id'] as int;
        final artistsData = await _db.getArtistsForSong(songId);
        final artists =
            artistsData.map((row) => row['name'] as String).toList();

        songs.add(Song(
          id: songId,
          youtubeId: songData['youtube_id'] as String?,
          title: songData['title'] as String? ?? 'Unknown Title',
          url: songData['file_path'] as String,
          duration: songData['duration'] as int? ?? 0,
          artists: artists.isNotEmpty ? artists : ['Unknown Artist'],
          dateAdded: songData['created_at'] != null
              ? DateTime.parse(songData['created_at'] as String)
              : DateTime.now(),
        ));
      }

      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading songs: $e')),
        );
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
        await _db.removeSongsFromPlaylist(widget.playlistId, [song.id]);
        await _loadSongs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Song removed from playlist')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _showAddSongsDialog() async {
    final l10n = AppLocalizations.of(context);
    final musicProvider =
        Provider.of<music_provider.MusicProvider>(context, listen: false);
    final allSongs = musicProvider.librarySongs;
    final selectedSongs = <int>{};

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.addSongs),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: allSongs.isEmpty
                ? Center(
                    child: Text(l10n.noMusicFound),
                  )
                : ListView.builder(
                    itemCount: allSongs.length,
                    itemBuilder: (context, index) {
                      final song = allSongs[index];
                      final isSelected = selectedSongs.contains(song.id);
                      final isAlreadyInPlaylist =
                          _songs.any((s) => s.id == song.id);

                      return CheckboxListTile(
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
                            color: isAlreadyInPlaylist ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          song.artists.join(' & '),
                          style: TextStyle(
                            color: isAlreadyInPlaylist ? Colors.grey : null,
                          ),
                        ),
                        secondary: isAlreadyInPlaylist
                            ? const Icon(Icons.check_circle, color: Colors.grey)
                            : null,
                      );
                    },
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
                        await _db.addSongsToPlaylist(
                            widget.playlistId, selectedSongs.toList());
                        await _loadSongs();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${selectedSongs.length} songs added to playlist'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
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

  Future<void> _playPlaylist() async {
    if (_songs.isEmpty) return;

    final musicProvider =
        Provider.of<music_provider.MusicProvider>(context, listen: false);
    await musicProvider.loadPlaylistAsQueue(widget.playlistId);
    Navigator.pop(context);
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
                      const Icon(
                        Icons.queue_music,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Playlist is empty',
                        style: theme.textTheme.titleLarge,
                      ),
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
                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final song = _songs.removeAt(oldIndex);
                    _songs.insert(newIndex, song);
                    setState(() {});
                    // TODO: Update positions in database
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
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.music_note),
                            ),
                      title: Text(song.title),
                      subtitle: Text(song.artists.join(' & ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatDuration(song.duration)),
                          if (_isEditMode)
                            const Icon(Icons.drag_handle, color: Colors.grey),
                        ],
                      ),
                      onTap: _isEditMode
                          ? null
                          : () {
                              final musicProvider = Provider.of<
                                      music_provider.MusicProvider>(
                                  context,
                                  listen: false);
                              musicProvider.playSong(song);
                            },
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
