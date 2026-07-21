import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/music_provider.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/models/song.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing Queue'),
        actions: [
          Consumer2<MusicProvider, YouTubeService>(
            builder: (context, musicProvider, youTubeService, _) =>
                PopupMenuButton<String>(
                  tooltip: 'Clear queue',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == 'clear_local') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear Local Queue?'),
                          content: const Text(
                            'This will remove all local songs from the queue.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await musicProvider.clearQueue();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Local queue cleared'),
                            ),
                          );
                        }
                      }
                    } else if (value == 'clear_online') {
                      youTubeService.clearOnlinePlaylist();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Online queue cleared')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    if (musicProvider.queue.isNotEmpty)
                      const PopupMenuItem(
                        value: 'clear_local',
                        child: Text('Clear Local Queue'),
                      ),
                    if (youTubeService.onlinePlaylist.isNotEmpty)
                      const PopupMenuItem(
                        value: 'clear_online',
                        child: Text('Clear Online Queue'),
                      ),
                  ],
                ),
          ),
        ],
      ),
      body: Consumer2<MusicProvider, YouTubeService>(
        builder: (context, musicProvider, youTubeService, _) {
          final localQueue = musicProvider.queue;
          final localIndex = musicProvider.currentIndex ?? -1;
          final onlineSongs = musicProvider.onlinePlaylist;
          final onlineIndex = musicProvider.onlinePlaylistIndex;
          final hasLocal = localQueue.isNotEmpty;
          final hasOnline = onlineSongs.isNotEmpty;

          if (!hasLocal && !hasOnline) {
            return const Center(child: Text('Queue is empty'));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Local playlist section
              if (hasLocal) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.album,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Local Playlist',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${localQueue.length} songs',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                ...localQueue.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;
                  final isCurrent = localIndex == index;

                  return _buildQueueTile(
                    context: context,
                    theme: theme,
                    song: song,
                    index: index,
                    isCurrent: isCurrent,
                    isOnline: false,
                    onTap: () => musicProvider.playAt(index),
                    onRemove: () => musicProvider.removeFromQueue(index),
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex--;
                      musicProvider.moveInQueue(oldIndex, newIndex);
                    },
                  );
                }),
                const Divider(height: 24),
              ],
              // Online playlist section
              if (hasOnline) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud,
                        size: 18,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Online Playlist',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${onlineSongs.length} songs',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                ...onlineSongs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;
                  final isCurrent = onlineIndex == index;

                  return _buildQueueTile(
                    context: context,
                    theme: theme,
                    song: song,
                    index: index,
                    isCurrent: isCurrent,
                    isOnline: true,
                    onTap: () => youTubeService.playOnlinePlaylistAt(index),
                    onRemove: () =>
                        youTubeService.removeFromOnlinePlaylist(index),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildQueueTile({
    required BuildContext context,
    required ThemeData theme,
    required Song song,
    required int index,
    required bool isCurrent,
    required bool isOnline,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    void Function(int, int)? onReorder,
  }) {
    return Dismissible(
      key: ValueKey('queue_${isOnline ? 'yt_' : ''}${song.id}_$index'),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        onRemove();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Removed: ${song.title}')));
      },
      child: ListTile(
        tileColor: isCurrent
            ? (isOnline
                  ? theme.colorScheme.tertiaryContainer.withOpacity(0.3)
                  : theme.colorScheme.primaryContainer.withOpacity(0.5))
            : null,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCurrent
                ? (isOnline
                      ? theme.colorScheme.tertiary.withOpacity(0.2)
                      : theme.colorScheme.primary.withOpacity(0.2))
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: isCurrent
              ? Icon(
                  Icons.equalizer,
                  color: isOnline
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                )
              : Icon(
                  isOnline ? Icons.cloud : Icons.music_note,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isCurrent
              ? TextStyle(
                  color: isOnline
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                )
              : null,
        ),
        subtitle: Row(
          children: [
            if (isOnline)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.cloud,
                  size: 12,
                  color: theme.colorScheme.tertiary.withOpacity(0.6),
                ),
              ),
            Expanded(
              child: Text(
                song.artists.isNotEmpty
                    ? song.artists.join(' & ')
                    : 'Unknown Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Icon(
          isOnline ? Icons.music_note : Icons.drag_handle,
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
        onTap: onTap,
      ),
    );
  }
}
