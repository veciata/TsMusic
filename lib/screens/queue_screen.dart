import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/new_music_provider.dart';
import '../models/song.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing Queue'),
        actions: [
          Consumer<NewMusicProvider>(
            builder: (context, musicProvider, _) => IconButton(
              tooltip: 'Clear queue',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: musicProvider.queue.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear Queue?'),
                          content: const Text('This will remove all songs from the queue.'),
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
                            const SnackBar(content: Text('Queue cleared')),
                          );
                        }
                      }
                    },
            ),
          ),
        ],
      ),
      body: Consumer<NewMusicProvider>(
        builder: (context, musicProvider, _) {
          final List<Song> queue = musicProvider.queue;
          final int? currentIndex = musicProvider.currentIndex;

          if (queue.isEmpty) {
            return const Center(child: Text('Queue is empty'));
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: queue.length,
            onReorder: (oldIndex, newIndex) {
              musicProvider.moveInQueue(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final song = queue[index];
              final isCurrent = currentIndex == index;

              return Dismissible(
                key: ValueKey('queue_${song.id}'),
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
                onDismissed: (_) async {
                  await musicProvider.removeFromQueue(index);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed: ${song.title}')),
                  );
                },
                child: ListTile(
                  tileColor: isCurrent
                      ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                      : null,
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: isCurrent
                        ? Icon(Icons.equalizer, color: theme.colorScheme.primary)
                        : const Icon(Icons.music_note),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isCurrent
                        ? TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.drag_handle),
                  onTap: () => musicProvider.playAt(index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
