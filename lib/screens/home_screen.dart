import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _showWelcome = true;
  bool _welcomeChecked = false;
  bool _isLoadingMusic = false;
  String? _loadingError;
  final int _visibleSongs = 5;
  final int _visibleArtists = 5;

  @override
  void initState() {
    super.initState();
    _initFirstLaunchAndLoad();
  }

  Future<void> _initFirstLaunchAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('tsmusic_welcome_done') ?? false;
    if (!mounted) return;
    setState(() {
      _showWelcome = !done;
      _welcomeChecked = true;
    });
    _loadMusic();
  }

  Future<void> _loadMusic() async {
    if (_isLoadingMusic) return;

    setState(() {
      _isLoadingMusic = true;
      _loadingError = null;
    });

    try {
      final provider = context.read<music_provider.MusicProvider>();

      // Load music from local storage with a timeout
      await provider.loadLocalMusic().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (mounted) {
            setState(() {
              _loadingError =
                  'Music loading is taking longer than expected. Please wait...';
            });
          }
          return Future.value();
        },
      );

      if (mounted) {
        setState(() {
          _isLoadingMusic = false;
          if (provider.allSongs.isEmpty) {
            _loadingError =
                'No music found. Try adding some music to your device.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMusic = false;
          _loadingError =
              'Failed to load music: ${e.toString().split('\n').first}';
        });
      }
    }
  }

  // Get top played songs
  List<Song> _getTopPlayedSongs(music_provider.MusicProvider provider) {
    try {
      // Use a case-insensitive map to track unique songs by their file path
      final Map<String, Song> uniqueSongs = {};

      // Track seen file paths for duplicate detection
      final Set<String> seenPaths = {};

      // Helper function to get a normalized file path for comparison
      String getNormalizedPath(String filePath) {
        try {
          // Convert to lowercase and remove any query parameters or fragments
          String path =
              filePath.split('?')[0].split('#')[0].toLowerCase().trim();

          // Handle different path formats that point to the same location
          const String emulatedPrefix = '/storage/emulated/0/';
          const String sdcardPrefix = '/sdcard/';

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
              print(
                  'Skipping duplicate song by path: ${song.title} (${song.url})');
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
        if (provider.currentSortOption == SongSortOption.title) {
          compare = a.title.compareTo(b.title);
        } else if (provider.currentSortOption == SongSortOption.artist) {
          final artistA = a.artists.isNotEmpty ? a.artists.join(' & ') : '';
          final artistB = b.artists.isNotEmpty ? b.artists.join(' & ') : '';
          compare = artistA.compareTo(artistB);
        } else if (provider.currentSortOption == SongSortOption.album) {
          compare = (a.album ?? '').compareTo(b.album ?? '');
        } else if (provider.currentSortOption == SongSortOption.duration) {
          compare = a.duration.compareTo(b.duration);
        } else if (provider.currentSortOption == SongSortOption.dateAdded) {
          compare = (a.dateAdded ?? DateTime.now())
              .compareTo(b.dateAdded ?? DateTime.now());
        } else {
          compare = 0;
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
    final sortedSongs = _getTopPlayedSongs(musicProvider);

    if (!_welcomeChecked || _isLoadingMusic) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_loadingError != null) {
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
                _loadingError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadMusic,
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

    if (_loadingError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_loadingError', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadMusic, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // AppBar kaldırıldı, arama butonu MainNavigationScreen'de
      body: Stack(
        children: [
          if (musicProvider.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (sortedSongs.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No music found',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Add some music files and refresh',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadMusic,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              itemCount: sortedSongs.length,
              padding: const EdgeInsets.only(bottom: 16),
              itemBuilder: (context, index) {
                final song = sortedSongs[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note),
                  ),
                  title: Text(
                      song.title.isNotEmpty ? song.title : 'Unknown Title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _getArtistsText(song.artists),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7)),
                  ),
                  trailing: Text(_formatDuration(song.duration)),
                  onTap: () => musicProvider.playSong(song),
                );
              },
            ),
          if (_showWelcome)
            Positioned.fill(
              child: GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('tsmusic_welcome_done', true);
                  setState(() => _showWelcome = false);
                  _loadMusic();
                },
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Text(
                      'Welcome to TS Music! Tap to load local music',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          // Music player has been removed as requested
        ],
      ),
    );
  }
}
