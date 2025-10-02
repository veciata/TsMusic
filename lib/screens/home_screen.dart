import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/providers/new_music_provider.dart' as music_provider;
import 'package:tsmusic/providers/theme_provider.dart' as theme_provider;
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;

  const HomeScreen({super.key, this.onSettingsTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DraggableScrollableController _playerSheetController = DraggableScrollableController();
  double _playerSize = 0.12;
  bool _showWelcome = true;
  bool _welcomeChecked = false;
  bool _isLoadingMusic = false;
  String? _loadingError;

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
      final provider = context.read<music_provider.NewMusicProvider>();
      
      // Load music from local storage
      await provider.loadLocalMusic();
      
      if (mounted) {
        // Check if we have any songs
        if (provider.allSongs.isEmpty) {
          // If no songs, try a full scan
          await provider.loadLocalMusic();
        }
        
        // Update UI
        setState(() {
          _isLoadingMusic = false;
          if (provider.allSongs.isEmpty) {
            _loadingError = 'No music found. Try adding some music to your device.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMusic = false;
          _loadingError = 'Failed to load music: $e';
        });
      }
    }
  }

  List<Song> _getSortedSongs(music_provider.NewMusicProvider provider) {
    final songs = List<Song>.from(provider.allSongs);

    songs.sort((a, b) {
      int compare;
      switch (provider.currentSortOption) {
        case SongSortOption.title:
          compare = a.title.compareTo(b.title);
          break;
        case SongSortOption.artist:
          final artistA = a.artists.join(' & ');
          final artistB = b.artists.join(' & ');
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

    return songs;
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
    final musicProvider = context.watch<music_provider.NewMusicProvider>();
    final sortedSongs = _getSortedSongs(musicProvider);

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
        appBar: AppBar(
          title: const Text('Music Player'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: widget.onSettingsTap,
            ),
          ],
        ),
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
      appBar: AppBar(
        title: const Text('TS Music'),
        centerTitle: true,
        actions: [
          PopupMenuButton<SongSortOption>(
            icon: const Icon(Icons.sort),
            onSelected: (option) {
              final isSameOption = musicProvider.currentSortOption == option;
              musicProvider.sortSongs(
                sortBy: option,
                ascending: isSameOption ? !musicProvider.sortAscending : true,
              );
            },
            itemBuilder: (context) => SongSortOption.values.map((option) {
              final isSelected = musicProvider.currentSortOption == option;
              final label = option.name[0].toUpperCase() + option.name.substring(1);
              return CheckedPopupMenuItem(
                value: option,
                checked: isSelected,
                child: Row(
                  children: [
                    Text(label),
                    if (isSelected)
                      Icon(
                        musicProvider.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMusic),
        ],
      ),
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
                  Text('No music found', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Add some music files and refresh', style: Theme.of(context).textTheme.bodyMedium),
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
              padding: const EdgeInsets.only(bottom: 120),
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
                  title: Text(song.title.isNotEmpty ? song.title : 'Unknown Title', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _getArtistsText(song.artists),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7)),
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
          Consumer<music_provider.NewMusicProvider>(
            builder: (context, provider, _) {
              final song = provider.currentSong;
              if (song == null) return const SizedBox.shrink();

              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() => _playerSize = notification.extent);
                  return false;
                },
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: DraggableScrollableSheet(
                    controller: _playerSheetController,
                    initialChildSize: 0.12,
                    minChildSize: 0.12,
                    maxChildSize: 1.0,
                    snap: true,
                    snapSizes: const [0.12, 0.5, 1.0],
                    builder: (context, scrollController) {
                      final theme = Theme.of(context);
                      final tProvider = context.watch<theme_provider.ThemeProvider>();
                      final style = tProvider.playerStyle;
                      final bool showSlider = style != theme_provider.PlayerStyle.minimal;
                      final double artworkSize = style == theme_provider.PlayerStyle.compact ? 40 : 48;
                      final EdgeInsets contentPadding = style == theme_provider.PlayerStyle.compact
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

                      final bool isMini = _playerSize <= 0.15;

                      return Material(
                        elevation: 12,
                        color: theme.colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Container(
                          padding: contentPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: theme.dividerColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  if (_playerSheetController.size <= 0.15) {
                                    _playerSheetController.animateTo(
                                      0.5,
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: artworkSize,
                                      height: artworkSize,
                                      decoration: BoxDecoration(
                                        color: theme.primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.music_note),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (style != theme_provider.PlayerStyle.minimal)
                                            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(provider.isPlaying ? Icons.pause : Icons.play_arrow),
                                      onPressed: () => provider.isPlaying ? provider.pause() : provider.play(),
                                    ),
                                  ],
                                ),
                              ),
                              if (showSlider && provider.duration.inSeconds > 0)
                                Slider(
                                  value: provider.position.inSeconds.toDouble().clamp(0.0, provider.duration.inSeconds.toDouble()),
                                  max: provider.duration.inSeconds.toDouble(),
                                  onChanged: (v) => provider.seek(Duration(seconds: v.toInt())),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _playerSheetController.dispose();
    super.dispose();
  }
}
