import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/new_music_provider.dart';
import 'artist_detail_screen.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isDragging = false;
  double _currentSliderValue = 0.0;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _startOrStopAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final musicProvider = context.watch<NewMusicProvider>();
    _positionSubscription?.cancel();
    _positionSubscription = musicProvider.positionStream.listen((_) {
      if (!_isDragging) {
        setState(() {
          _currentSliderValue = musicProvider.position.inSeconds.toDouble();
        });
      }
    });
  }

  void _startOrStopAnimation() {
    final musicProvider = context.read<NewMusicProvider>();
    if (musicProvider.isPlaying) {
      _animationController.repeat();
    } else {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _buildDefaultArt(ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  colorScheme.primaryContainer,
                  colorScheme.secondaryContainer,
                ]
              : [
                  colorScheme.primary.withOpacity(0.2),
                  colorScheme.secondary.withOpacity(0.2),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: 80,
        color: isDark 
            ? colorScheme.onPrimaryContainer.withOpacity(0.8)
            : colorScheme.primary.withOpacity(0.8),
      ),
    );
  }

  void _showSongOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_to_queue),
              title: const Text('Add to queue'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = context.watch<NewMusicProvider>();
    final currentSong = musicProvider.currentSong;
    if (currentSong == null) {
      return const Scaffold(
        body: Center(child: Text('No song playing')),
      );
    }

    final duration = musicProvider.duration;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8.0),
          child: CircleAvatar(
            backgroundColor: theme.colorScheme.onBackground.withOpacity(0.1),
            child: IconButton(
              icon: Icon(
                Icons.arrow_downward_rounded, 
                color: theme.colorScheme.onBackground.withOpacity(0.8),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.more_vert, 
              color: theme.colorScheme.onBackground.withOpacity(0.8),
            ),
            onPressed: _showSongOptions,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              theme.colorScheme.secondary.withOpacity(0.05),
              theme.colorScheme.background,
              theme.colorScheme.background,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.onBackground.withOpacity(0.2),
                    blurRadius: 25,
                    spreadRadius: 2,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (_, child) {
                      return Transform.rotate(
                        angle: _animationController.value * 2 * 3.14159 * (musicProvider.isPlaying ? 1 : 0),
                        child: Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.surface.withOpacity(0.3),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withOpacity(0.1), 
                              width: 12
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                              ),
                            ],
                            image: currentSong.albumArtUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(currentSong.albumArtUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: currentSong.albumArtUrl == null
                              ? _buildDefaultArt(theme)
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
              child: Column(
                children: [
                  Text(
                    currentSong.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

Wrap(
  alignment: WrapAlignment.center,
  children: currentSong.artists.map((artist) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailScreen(
              artistName: artist,
              artistImageUrl: currentSong.albumArtUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text(
          artist,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.secondary.withOpacity(0.9),
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.secondary.withOpacity(0.5),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }).toList()
)

                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  Slider(
                    value: _currentSliderValue,
                    min: 0.0,
                    max: duration.inSeconds.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _currentSliderValue = value;
                        _isDragging = true;
                      });
                    },
                    onChangeEnd: (value) {
                      musicProvider.seek(Duration(seconds: value.toInt()));
                      setState(() {
                        _isDragging = false;
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(Duration(seconds: _currentSliderValue.toInt())),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimary.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimary.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: musicProvider.shuffleEnabled
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.onPrimary.withOpacity(0.7),
                      size: 28,
                    ),
                    onPressed: musicProvider.toggleShuffle,
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_previous_rounded,
                        color: theme.colorScheme.onPrimary, size: 36),
                    onPressed: musicProvider.previous,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.secondary,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.secondary.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        musicProvider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: theme.colorScheme.onSecondary,
                        size: 48,
                      ),
                      onPressed: () {
                        if (musicProvider.isPlaying) {
                          musicProvider.pause();
                        } else {
                          musicProvider.play();
                        }
                        _startOrStopAnimation();
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next_rounded,
                        color: theme.colorScheme.onPrimary, size: 36),
                    onPressed: musicProvider.next,
                  ),
                  IconButton(
                    icon: Icon(
                      musicProvider.loopMode == LoopMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: musicProvider.loopMode == LoopMode.off
                          ? theme.colorScheme.onPrimary.withOpacity(0.7)
                          : theme.colorScheme.secondary,
                      size: 28,
                    ),
                    onPressed: musicProvider.cycleRepeatMode,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 32.0, left: 32.0, right: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Queue Button
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.3),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.queue_music_rounded,
                        color: theme.colorScheme.onSurface.withOpacity(0.9),
                        size: 28,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QueueScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
