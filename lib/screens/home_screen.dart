

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;

import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;

  const HomeScreen({super.key, this.onSettingsTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {


  @override
  void initState() {
    super.initState();
    // Music is already loaded by MainNavigationScreen, no need to load here
  }

  List<Song> _getSortedSongs(music_provider.MusicProvider provider) {
    try {
      // Use a case-insensitive map to track unique songs by their file path
      final Map<int, Song> uniqueSongs = {};
      
      // Track seen file paths for duplicate detection
      final Set<String> seenPaths = {};
      
      // Helper function to get a normalized file path for comparison
      String getNormalizedPath(String filePath) {
        try {
          // Convert to lowercase and remove any query parameters or fragments
          String path = filePath.split('?')[0].split('#')[0].toLowerCase().trim();
          
          // Handle different path formats that point to the same location
          const String emulatedPrefix = '/storage/emulated/0/';
          
          // Convert /storage/emulated/0/ to /sdcard/ for consistency
          if (path.startsWith(emulatedPrefix)) {
            path = '/sdcard/${path.substring(emulatedPrefix.length)}';
          }
          
          // Remove any redundant path segments
          final uri = Uri.file(path);
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          
          // Rebuild path with normalized segments
          return '/${segments.join('/')}';
        } catch (e) {
          if (kDebugMode) {
            print('Error normalizing path "$filePath": $e');
          }
          return filePath.toLowerCase();
        }
      }
      
      // Process each song
      for (final song in provider.allSongs) {
        try {
          if (song.url.isEmpty) continue;
          
          final normalizedPath = getNormalizedPath(song.url);
          if (normalizedPath.isEmpty) continue;
          
          // Skip if we've already seen this exact path
          if (seenPaths.contains(normalizedPath)) {
            if (kDebugMode) {
              print('Skipping duplicate song by path: ${song.title} (${song.url})');
            }
            continue;
          }
          
          // Add to our unique songs and seen paths
          uniqueSongs[song.id] = song;
          seenPaths.add(normalizedPath);
          
          if (kDebugMode) {
            print('Adding song to UI: ${song.title} (${song.url})');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error processing song ${song.id}: $e');
          }
        }
      }
      
      // Convert to list and sort
      final songs = uniqueSongs.values.toList();
      
      songs.sort((a, b) {
        int compare;
        switch (provider.currentSortOption) {
          case SongSortOption.title:
            compare = a.title.compareTo(b.title);
            break;
          case SongSortOption.artist:
            final artistA = a.artists.isNotEmpty ? a.artists.join(' & ') : '';
            final artistB = b.artists.isNotEmpty ? b.artists.join(' & ') : '';
            compare = artistA.compareTo(artistB);
            break;
          case SongSortOption.album:
            compare = (a.album ?? '').compareTo(b.album ?? '');
            break;
          case SongSortOption.duration:
            compare = a.duration.compareTo(b.duration);
            break;
          case SongSortOption.dateAdded:
            compare = (a.dateAdded ?? DateTime.now()).compareTo(b.dateAdded ?? DateTime.now());
            break;
        }
        return provider.sortAscending ? compare : -compare;
      });
      
      if (kDebugMode) {
        print('Displaying ${songs.length} unique songs in UI');
        // Print first few songs for verification
        final count = songs.length > 5 ? 5 : songs.length;
        for (var i = 0; i < count; i++) {
          print('Song ${i + 1}: ${songs[i].title} (${songs[i].url})');
        }
      }
      
      return songs;
    } catch (e) {
      if (kDebugMode) {
        print('Error in _getSortedSongs: $e');
      }
      // Return empty list on error to prevent crashes
      return [];
    }
  }

  String _getArtistsText(List<String> artists) {
    if (artists.isEmpty) return 'Unknown Artist';
    return artists.join(' & ');
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildNoMusicFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No music found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Add music to your device or download some'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
            icon: const Icon(Icons.search),
            label: const Text('Search and Download Music'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final sortedSongs = _getSortedSongs(musicProvider);

    if (musicProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (musicProvider.error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading music',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                musicProvider.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Reload from database only
                  musicProvider.loadFromDatabaseOnly();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (sortedSongs.isEmpty) {
      return Scaffold(
        body: _buildNoMusicFound(),
      );
    }

    return Scaffold(
      // AppBar kaldırıldı, arama butonu MainNavigationScreen'de
      body: musicProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : sortedSongs.isEmpty
              ? _buildNoMusicFound()
              : ListView.builder(
                  itemCount: sortedSongs.length,
                  itemBuilder: (context, index) {
                    final song = sortedSongs[index];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.music_note),
                      ),
                      title: Text(song.title.isNotEmpty ? song.title : 'Unknown Title',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _getArtistsText(song.artists),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7)),
                      ),
                      trailing: Text(_formatDuration(song.duration)),
                      onTap: () => musicProvider.playSong(song),
                    );
                  },
                ),
    );
  }
}
