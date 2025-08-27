import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/new_music_provider.dart' as music_provider;
import 'local_music_screen.dart';
import '../models/song.dart';

class HomeScreen extends StatelessWidget {
  final Function() onSettingsTap;

  const HomeScreen({
    super.key,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      'Your Music (${musicProvider.songs.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
}
