import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../providers/theme_provider.dart' as theme_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'search_screen.dart';
import '../models/song.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsTap;

  const HomeScreen({
    super.key,
    this.onSettingsTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DraggableScrollableController _playerSheetController = DraggableScrollableController();
  double _playerSize = 0.12;
  bool _dragFromHandle = false;
  bool _showWelcome = false;
  bool _welcomeChecked = false;

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
    final provider = context.read<music_provider.NewMusicProvider>();
    await provider.loadLocalMusic();
    if (provider.songs.isEmpty) {
      debugPrint('No local music found on device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<music_provider.NewMusicProvider>();

    if (!_welcomeChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TS Music'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onSettingsTap,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMusic,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (musicProvider.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (musicProvider.songs.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No music found', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Add some music files to your device and refresh', style: Theme.of(context).textTheme.bodyMedium),
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
              itemCount: musicProvider.songs.length,
              padding: const EdgeInsets.only(bottom: 120),
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
                    child: const Icon(Icons.music_note),
                  ),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                      'Welcome! Tap to load local music',
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
                      final bool isMini = _playerSize <= 0.15;
                      final bool isMid = _playerSize > 0.15 && _playerSize < 1.0;
                      final tProvider = context.watch<theme_provider.ThemeProvider>();
                      final style = tProvider.playerStyle;
                      final bool showSlider = style != theme_provider.PlayerStyle.minimal;
                      final double artworkSize = style == theme_provider.PlayerStyle.compact ? 40 : 48;
                      final EdgeInsets contentPadding = style == theme_provider.PlayerStyle.compact
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

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
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onPanDown: (_) => _dragFromHandle = true,
                                  onPanEnd: (_) => _dragFromHandle = false,
                                  onPanCancel: () => _dragFromHandle = false,
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
                              if (showSlider)
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

  String _formatDuration(int durationMs) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final duration = Duration(milliseconds: durationMs);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
