import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/new_music_provider.dart' as music_provider;
import 'local_music_screen.dart';
import '../models/song.dart';
// Using built-in Flutter widgets for text scrolling

class HomeScreen extends StatelessWidget {
  final Function() onSettingsTap;

  const HomeScreen({
    super.key,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('TS Music'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: onSettingsTap,
          ),
        ],
      ),
      body: Consumer<music_provider.NewMusicProvider>(
        builder: (context, musicProvider, _) {
          if (musicProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (musicProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading music',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    musicProvider.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => musicProvider.loadLocalMusic(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (musicProvider.songs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No music found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add some music files to your device and refresh',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => musicProvider.loadLocalMusic(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // Sort button
                        PopupMenuButton<music_provider.SongSortOption>(
                          icon: Icon(Icons.sort, size: 20, color: Theme.of(context).primaryColor),
                          tooltip: 'Sort by',
                          onSelected: (option) {
                            final isSameOption = musicProvider.currentSortOption == option;
                            musicProvider.sortSongs(
                              sortBy: option,
                              ascending: isSameOption ? !musicProvider.sortAscending : true,
                            );
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: music_provider.SongSortOption.title,
                              child: const Text('Sort by Title'),
                            ),
                            PopupMenuItem(
                              value: music_provider.SongSortOption.artist,
                              child: const Text('Sort by Artist'),
                            ),
                            PopupMenuItem(
                              value: music_provider.SongSortOption.duration,
                              child: const Text('Sort by Duration'),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Your Music (${musicProvider.songs.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => musicProvider.loadLocalMusic(),
                      tooltip: 'Refresh music library',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: musicProvider.songs.length,
                  itemBuilder: (context, index) {
                    final song = musicProvider.songs[index];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.music_note, size: 24),
                      ),
                      title: SizedBox(
                        height: 24, // Same height as normal text
                        child: song.title.length > 20
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final textPainter = TextPainter(
                                    text: TextSpan(
                                      text: song.title,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    maxLines: 1,
                                    textDirection: TextDirection.ltr,
                                  )..layout();
                                  
                                  final isTextWider = textPainter.width > constraints.maxWidth;
                                  
                                  return isTextWider
                                      ? SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              Text(
                                                song.title,
                                                style: Theme.of(context).textTheme.titleMedium,
                                              ),
                                              const SizedBox(width: 20), // Add some space before repeating
                                              Text(
                                                song.title,
                                                style: Theme.of(context).textTheme.titleMedium,
                                              ),
                                            ],
                                          ),
                                        )
                                      : Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        );
                                },
                              )
                            : Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _formatDuration(song.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () => musicProvider.playSong(song),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
  
  String _getSortLabel(music_provider.NewMusicProvider musicProvider) {
    final sortOption = musicProvider.currentSortOption;
    final arrow = musicProvider.sortAscending ? '↑' : '↓';
    
    switch (sortOption) {
      case music_provider.SongSortOption.title:
        return 'Title $arrow';
      case music_provider.SongSortOption.artist:
        return 'Artist $arrow';
      case music_provider.SongSortOption.duration:
        return 'Duration $arrow';
      case music_provider.SongSortOption.dateAdded:
        return 'Date Added $arrow';
    }
  }
}
