import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/song.dart' as ts;

class NowPlayingQueueBottomSheet extends StatelessWidget {
  const NowPlayingQueueBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final youTubeService = context.watch<YouTubeService>();
    final theme = Theme.of(context);
    final localQueue = musicProvider.queue;
    final localIndex = musicProvider.currentIndex ?? -1;
    final onlineSongs = musicProvider.onlinePlaylist;
    final onlineIndex = musicProvider.onlinePlaylistIndex;
    final hasLocal = localQueue.isNotEmpty;
    final hasOnline = onlineSongs.isNotEmpty;

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
              color: theme.colorScheme.onSurface.withAlpha(77),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  l10n.nowPlaying,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${localQueue.length + onlineSongs.length} ${l10n.songs.toLowerCase()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(179),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!hasLocal && !hasOnline)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: 48,
                      color: theme.colorScheme.onSurface.withAlpha(77),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noMusicFound,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(128),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: ListView(
                children: [
                  // Local section
                  if (hasLocal) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.album,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Local',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${localQueue.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...localQueue.asMap().entries.map((entry) {
                      final index = entry.key;
                      final song = entry.value;
                      final isCurrentSong = index == localIndex;

                      return Dismissible(
                        key: ValueKey('dismiss_local_${song.id}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          musicProvider.removeFromQueue(index);
                        },
                        child: ListTile(
                          key: ValueKey('tile_local_${song.id}_$index'),
                          dense: true,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrentSong
                                  ? theme.colorScheme.primary.withAlpha(51)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isCurrentSong
                                  ? Icons.play_circle
                                  : Icons.music_note,
                              size: 18,
                              color: isCurrentSong
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withAlpha(128),
                            ),
                          ),
                          title: Text(
                            song.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrentSong
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentSong
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.artists.isNotEmpty
                                ? song.artists.join(', ')
                                : l10n.unknownArtist,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isCurrentSong
                              ? Icon(
                                  Icons.equalizer,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                )
                              : ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle,
                                    size: 18,
                                    color: theme.colorScheme.onSurface
                                        .withAlpha(128),
                                  ),
                                ),
                          onTap: () {
                            musicProvider.playAt(index);
                            Navigator.pop(context);
                          },
                        ),
                      );
                    }),
                    const Divider(height: 1),
                  ],
                  // Online section
                  if (hasOnline) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Online',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _pastePlaylist(context),
                            child: Tooltip(
                              message: 'Add YouTube Playlist from Clipboard',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.tertiary.withAlpha(
                                      100,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.paste,
                                      size: 12,
                                      color: theme.colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Paste Playlist',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.tertiary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${onlineSongs.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...onlineSongs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final song = entry.value;
                      final isCurrentSong = index == onlineIndex;

                      return Dismissible(
                        key: ValueKey('dismiss_online_${song.id}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          youTubeService.removeFromOnlinePlaylist(index);
                        },
                        child: ListTile(
                          key: ValueKey('tile_online_${song.id}_$index'),
                          dense: true,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrentSong
                                  ? theme.colorScheme.tertiary.withAlpha(51)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isCurrentSong ? Icons.play_circle : Icons.cloud,
                              size: 18,
                              color: isCurrentSong
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.onSurface.withAlpha(128),
                            ),
                          ),
                          title: Text(
                            song.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrentSong
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentSong
                                  ? theme.colorScheme.tertiary
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.artists.isNotEmpty
                                ? song.artists.join(', ')
                                : l10n.unknownArtist,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _OnlineDownloadButton(
                                song: song,
                                youTubeService: youTubeService,
                                musicProvider: musicProvider,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.music_note,
                                size: 16,
                                color: theme.colorScheme.onSurface.withAlpha(
                                  77,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            youTubeService.playOnlinePlaylistAt(index);
                            Navigator.pop(context);
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

void showNowPlayingQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const NowPlayingQueueBottomSheet(),
  );
}

extension on BuildContext {
  YouTubeService get _youTubeService => read<YouTubeService>();
}

Future<void> _pastePlaylist(BuildContext context) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final rawText = data?.text;
  if (rawText == null || rawText.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
    }
    return;
  }

  final text = rawText.trim();
  // Accept full URLs or bare playlist IDs
  if (!text.contains('youtube') &&
      !text.contains('youtu.be') &&
      !RegExp(r'^[A-Za-z0-9_\-]{10,}$').hasMatch(text)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube playlist URL or ID')),
      );
    }
    return;
  }

  try {
    final yt = context._youTubeService;
    final count = await yt.fetchPlaylistAndAdd(text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $count songs from playlist')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load playlist: $e')));
    }
  }
}

class _OnlineDownloadButton extends StatefulWidget {
  final ts.Song song;
  final YouTubeService youTubeService;
  final music_provider.MusicProvider musicProvider;

  const _OnlineDownloadButton({
    required this.song,
    required this.youTubeService,
    required this.musicProvider,
  });

  @override
  State<_OnlineDownloadButton> createState() => _OnlineDownloadButtonState();
}

class _OnlineDownloadButtonState extends State<_OnlineDownloadButton> {
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  void _checkDownloaded() {
    _isDownloaded = widget.musicProvider.librarySongs.any(
      (s) => s.youtubeId == widget.song.youtubeId && s.isDownloaded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloadsList = widget.youTubeService.activeDownloads
        .where((d) => d.videoId == widget.song.youtubeId)
        .toList();
    final activeDownloads = activeDownloadsList.isNotEmpty
        ? activeDownloadsList.first
        : null;

    if (_isDownloaded) return const SizedBox.shrink();

    if (activeDownloads != null) {
      return SizedBox(
        width: 20,
        height: 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: activeDownloads.progress > 0
                    ? activeDownloads.progress
                    : null,
                strokeWidth: 2,
              ),
            ),
            Icon(
              Icons.download,
              size: 10,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      );
    }

    return IconButton(
      icon: Icon(
        Icons.download,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () async {
        try {
          await widget.youTubeService.downloadAudio(
            videoId: widget.song.youtubeId ?? widget.song.id.toString(),
          );
          if (mounted) {
            setState(_checkDownloaded);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
          }
        }
      },
      tooltip: 'Download',
    );
  }
}
