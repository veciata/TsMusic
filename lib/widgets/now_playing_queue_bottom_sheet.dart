import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/localization/app_localizations.dart';

class NowPlayingQueueBottomSheet extends StatelessWidget {
  const NowPlayingQueueBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final theme = Theme.of(context);
    final queue = musicProvider.queue;
    final currentIndex = musicProvider.currentIndex ?? -1;

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
                  '${queue.length} ${l10n.songs.toLowerCase()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(179),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (queue.isEmpty)
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
              child: ReorderableListView.builder(
                itemCount: queue.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  musicProvider.moveInQueue(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrentSong = index == currentIndex;

                  return Dismissible(
                    key: ValueKey('dismiss_${song.id}_$index'),
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
                      key: ValueKey('tile_${song.id}_$index'),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isCurrentSong
                              ? theme.colorScheme.primary.withAlpha(51)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isCurrentSong ? Icons.play_circle : Icons.music_note,
                          color: isCurrentSong
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withAlpha(128),
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          fontWeight: isCurrentSong
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color:
                              isCurrentSong ? theme.colorScheme.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artists.isNotEmpty
                            ? song.artists.join(', ')
                            : l10n.unknownArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isCurrentSong
                          ? Icon(
                              Icons.equalizer,
                              color: theme.colorScheme.primary,
                            )
                          : ReorderableDragStartListener(
                              index: index,
                              child: Icon(
                                Icons.drag_handle,
                                color:
                                    theme.colorScheme.onSurface.withAlpha(128),
                              ),
                            ),
                      onTap: () {
                        musicProvider.playAt(index);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
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
