

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/widgets/skeleton_widgets.dart';

import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;

  const HomeScreen({super.key, this.onSettingsTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<int> _selectedSongs = {};
  bool _isMultiSelectMode = false;



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
            compare = a.dateAdded.compareTo(b.dateAdded);
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

  Widget _buildFilterBar(music_provider.MusicProvider musicProvider, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SongSortOption>(
                value: musicProvider.currentSortOption,
                isDense: true,
                icon: const Icon(Icons.sort, size: 20),
                items: [
                  DropdownMenuItem(
                    value: SongSortOption.title,
                    child: Row(
                      children: [
                        const Icon(Icons.sort_by_alpha, size: 18),
                        const SizedBox(width: 8),
                        Text('Sort by Title', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.artist,
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 18),
                        const SizedBox(width: 8),
                        Text('Sort by Artist', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SongSortOption.dateAdded,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text('Sort by Date', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    musicProvider.setSortOption(value);
                  }
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              musicProvider.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 20,
            ),
            onPressed: () => musicProvider.toggleSortDirection(),
            tooltip: musicProvider.sortAscending ? 'Ascending' : 'Descending',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => musicProvider.refreshSongs(),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Song song, music_provider.MusicProvider musicProvider) {
    final isLocal = song.url.startsWith('/storage/emulated/0') || song.url.startsWith('/data/user/');
    final isDownloaded = song.tags.contains('tsmusic');
    final isSelected = _selectedSongs.contains(song.id);
    
    return ListTile(
      leading: _isMultiSelectMode
          ? Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedSongs.add(song.id);
                  } else {
                    _selectedSongs.remove(song.id);
                  }
                });
              },
            )
          : Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isDownloaded 
                  ? const Icon(Icons.download_done, color: Colors.green)
                  : isLocal 
                      ? const Icon(Icons.folder, color: Colors.orange)
                      : const Icon(Icons.music_note),
            ),
      title: Text(
        song.title.isNotEmpty ? song.title : 'Unknown Title',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _getArtistsText(song.artists),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatDuration(song.duration)),
          PopupMenuButton<String>(
            onSelected: (value) => _handleSongAction(value, song, musicProvider),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'move',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_move_outline),
                    SizedBox(width: 8),
                    Text('Move'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add),
                    SizedBox(width: 8),
                    Text('Add to Playlist'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => musicProvider.playSong(song),
    );
  }

  Widget _buildNoMusicFound() => Center(
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

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<music_provider.MusicProvider>();
    final sortedSongs = _getSortedSongs(musicProvider);

    if (musicProvider.isLoading) {
      return const SkeletonHomeScreen();
    }

    if (musicProvider.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error loading music',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: Text(
                      musicProvider.error!,
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Colors.red.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: musicProvider.loadFromDatabaseOnly,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    // Clear error and go to empty state
                    musicProvider.refreshSongs();
                  },
                  child: const Text('Skip and continue'),
                ),
              ],
            ),
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
      body: Column(
        children: [
          // Sort and Filter Bar
          _buildFilterBar(musicProvider, context),
          // Song List
          Expanded(
            child: ListView.builder(
              itemCount: sortedSongs.length,
              itemBuilder: (context, index) {
                final song = sortedSongs[index];
                return _buildSongTile(song, musicProvider);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleSongAction(String action, Song song, music_provider.MusicProvider provider) async {
    switch (action) {
      case 'move':
        await _showMoveDialog(song);
        break;
      case 'delete':
        await _showDeleteConfirmation(song, provider);
        break;
      case 'add_to_playlist':
        await _showPlaylistDialog(song);
        break;
    }
  }

  Future<void> _showMoveDialog(Song song) async {
    final locations = [
      {'label': 'Internal Storage', 'path': '/storage/emulated/0/Music'},
      {'label': 'Downloads', 'path': '/storage/emulated/0/Download'},
      {'label': 'Music Folder', 'path': '/storage/emulated/0/Music'},
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: locations.map((loc) => ListTile(
            title: Text(loc['label']!),
            onTap: () => Navigator.pop(context, loc['path']),
          )).toList(),
        ),
      ),
    );

    if (selected != null) {
      try {
        final file = File(song.url);
        final newPath = path.join(selected, path.basename(song.url));
        await file.rename(newPath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to $selected')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error moving file: $e')),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation(Song song, music_provider.MusicProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Song'),
        content: Text('Are you sure you want to delete "${song.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(song.url);
        if (await file.exists()) {
          await file.delete();
        }
        await provider.refreshSongs();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Song deleted')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e')),
        );
      }
    }
  }

  Future<void> _showPlaylistDialog(Song song) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: const Text('Playlist feature coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
