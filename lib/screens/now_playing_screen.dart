import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/music_provider.dart';
import 'artist_detail_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> 
    with SingleTickerProviderStateMixin {
  AnimationController? _albumArtController;
  double _currentPosition = 0.0;
  bool _isDragging = false;
  double _volume = 0.7;
  bool _showVolumeSlider = false;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _albumArtController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _startOrStopAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final musicProvider = context.watch<MusicProvider>();
    _positionSubscription?.cancel();
    _positionSubscription = musicProvider.positionStream.listen((position) {
      if (!_isDragging) {
        setState(() {
          _currentPosition = position.inSeconds.toDouble();
        });
      }
    });
  }

  void _startOrStopAnimation() {
    final musicProvider = context.read<MusicProvider>();
    if (musicProvider.isPlaying) {
      _albumArtController?.repeat();
    } else {
      _albumArtController?.stop();
    }
  }

  @override
  void dispose() {
    _albumArtController?.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  Widget _buildAlbumArt(ThemeData theme, String? albumArtUrl, String title) {
    return AnimatedBuilder(
      animation: _albumArtController ?? AnimationController(vsync: this, duration: const Duration(seconds: 20)),
      builder: (context, child) {
        final controller = _albumArtController ?? AnimationController(vsync: this, duration: const Duration(seconds: 20));
        return Transform.rotate(
          angle: controller.value * 2 * 3.14159,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
              image: albumArtUrl != null
                  ? DecorationImage(
                      image: NetworkImage(albumArtUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: albumArtUrl == null ? theme.colorScheme.primaryContainer : null,
            ),
            child: albumArtUrl == null
                ? Center(
                    child: Icon(
                      Icons.music_note,
                      size: 80,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: size),
      color: color,
      onPressed: onPressed,
    );
  }

  Widget _buildVolumeControl(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _showVolumeSlider ? 200 : 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: _showVolumeSlider
          ? Row(
              children: [
                IconButton(
                  icon: Icon(
                    _volume == 0 
                      ? Icons.volume_off
                      : _volume < 0.5 
                        ? Icons.volume_down
                        : Icons.volume_up,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _showVolumeSlider = false),
                ),
                Expanded(
                  child: Slider(
                    value: _volume,
                    onChanged: (value) => setState(() => _volume = value),
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                  ),
                ),
              ],
            )
          : IconButton(
              icon: Icon(
                Icons.volume_up,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => setState(() => _showVolumeSlider = true),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = context.watch<MusicProvider>();
    final currentSong = musicProvider.currentSong;

    if (currentSong == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.music_off,
                size: 80,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 20),
              Text(
                'No Song Playing',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Select a song to start playing',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final duration = musicProvider.duration.inSeconds;
    final albumArtUrl = currentSong.albumArtUrl;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'Now Playing',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      // Show song options
                    },
                  ),
                ],
              ),
            ),

            // Album Art
            Expanded(
              flex: 3,
              child: Center(
                child: _buildAlbumArt(theme, albumArtUrl, currentSong.title),
              ),
            ),

            // Song Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                children: [
                  Text(
                    currentSong.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
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
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            artist,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary.withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Slider(
                    value: _currentPosition,
                    min: 0,
                    max: duration.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _currentPosition = value;
                        _isDragging = true;
                      });
                    },
                    onChangeEnd: (value) {
                      musicProvider.seek(Duration(seconds: value.toInt()));
                      setState(() => _isDragging = false);
                    },
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_currentPosition.toInt())),
                        Text(_formatDuration(duration)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Control Buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Shuffle
                  _buildControlButton(
                    icon: Icons.shuffle,
                    onPressed: musicProvider.toggleShuffle,
                    color: musicProvider.shuffleEnabled 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),

                  // Previous
                  _buildControlButton(
                    icon: Icons.skip_previous,
                    size: 32,
                    onPressed: musicProvider.previous,
                  ),

                  // Play/Pause
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        musicProvider.isPlaying 
                            ? Icons.pause 
                            : Icons.play_arrow,
                        size: 32,
                      ),
                      color: theme.colorScheme.onPrimary,
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

                  // Next
                  _buildControlButton(
                    icon: Icons.skip_next,
                    size: 32,
                    onPressed: musicProvider.next,
                  ),

                  // Repeat
                  _buildControlButton(
                    icon: musicProvider.loopMode == LoopMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    onPressed: musicProvider.cycleRepeatMode,
                    color: musicProvider.loopMode != LoopMode.off
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ],
              ),
            ),

            // Bottom Controls
            Padding(
              padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildVolumeControl(theme),
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () {
                      // Show queue
                    },
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
