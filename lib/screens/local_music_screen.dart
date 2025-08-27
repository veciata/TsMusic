import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../models/song.dart';

class LocalMusicScreen extends StatelessWidget {
  const LocalMusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Music'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => musicProvider.loadLocalMusic(),
          ),
        ],
      ),
      body: Consumer<music_provider.NewMusicProvider>(
        builder: (context, musicProvider, _) {
          // Load music when the screen is first built
          if (musicProvider.songs.isEmpty && !musicProvider.isLoading && musicProvider.error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              musicProvider.loadLocalMusic();
            });
          }
          if (musicProvider.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for music files...'),
                ],
              ),
            );
          }

          if (musicProvider.error != null) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 24),
                    Text(
                      musicProvider.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      onPressed: () => musicProvider.loadLocalMusic(),
                    ),
                  ],
                ),
              ),
            );
          }

          if (musicProvider.songs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_off,
                      size: 72,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No music files found',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Make sure you have music files in your device storage and tap the refresh button to scan again.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Scan for Music'),
                      onPressed: () => musicProvider.loadLocalMusic(),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: musicProvider.songs.length,
            itemBuilder: (context, index) {
              final song = musicProvider.songs[index];
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(song.title),
                subtitle: Text(song.artist),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => musicProvider.playSong(song),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => musicProvider.loadLocalMusic(),
        tooltip: 'Refresh music library',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
