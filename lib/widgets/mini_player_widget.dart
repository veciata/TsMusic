import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/theme_provider.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/screens/now_playing_screen.dart';
import 'package:tsmusic/models/player_styles.dart';

Route _slideUpRoute() => PageRouteBuilder(
  pageBuilder: (context, animation, secondaryAnimation) =>
      const NowPlayingScreen(),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;

    final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

    return SlideTransition(position: animation.drive(tween), child: child);
  },
  transitionDuration: const Duration(milliseconds: 350),
);

void _showMinimalPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SizedBox(
      width: double.infinity,
      height: MediaQuery.of(sheetContext).size.height * 0.5,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: const NowPlayingScreen(),
        ),
      ),
    ),
  );
}

class MiniPlayerWidget extends StatefulWidget {
  const MiniPlayerWidget({super.key});

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  StreamSubscription? _positionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _positionSubscription?.cancel();
    final musicProv = context.read<music_provider.MusicProvider>();
    _positionSubscription = musicProv.positionStream.listen((position) {
      final duration = musicProv.duration;
      if (duration.inMilliseconds > 0) {
        setState(() {
          _progress = position.inMilliseconds / duration.inMilliseconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final youTubeService = Provider.of<YouTubeService>(context, listen: false);
    final theme = Theme.of(context);

    return Consumer<music_provider.MusicProvider>(
      builder: (context, musicProv, _) {
        final currentSong = musicProv.currentSong;
        final isOnlinePlaying = youTubeService.isPlaying;
        final currentOnlineAudio = youTubeService.currentAudio;
        final l10n = AppLocalizations.of(context);

        final String title;
        final String artist;
        final bool isPlaying;
        final String? albumArtUrl;

        if (isOnlinePlaying && currentOnlineAudio != null) {
          title = currentOnlineAudio.title;
          artist = currentOnlineAudio.author;
          isPlaying = true;
          albumArtUrl = currentOnlineAudio.thumbnailUrl;
        } else if (currentSong != null) {
          title = currentSong.title;
          artist = currentSong.artists.isNotEmpty
              ? currentSong.artists.join(' & ')
              : l10n.selectSongToPlay;
          isPlaying = musicProv.isPlaying;
          albumArtUrl = currentSong.albumArtUrl;
        } else {
          title = l10n.notPlaying;
          artist = l10n.selectSongToPlay;
          isPlaying = false;
          albumArtUrl = null;
        }

        final bool hasTrack = currentSong != null || isOnlinePlaying;

        return GestureDetector(
          onTap: () {
            if (hasTrack) {
              final themeProvider = Provider.of<ThemeProvider>(
                context,
                listen: false,
              );
              if (themeProvider.playerStyle == PlayerStyle.minimal) {
                _showMinimalPlayer(context);
              } else {
                Navigator.push(context, _slideUpRoute());
              }
            }
          },
          child: Container(
            width: double.infinity,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                _ProgressBar(
                  progress: _progress,
                  isPlaying: isPlaying,
                  color: theme.colorScheme.primary,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _AlbumArt(
                          albumArtUrl: albumArtUrl,
                          size: 48,
                          isPlaying: isPlaying,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  title,
                                  key: ValueKey('mini_title_$title'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  artist,
                                  key: ValueKey('mini_artist_$artist'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isOnlinePlaying)
                          _PlayButton(
                            isPlaying: isPlaying,
                            color: theme.colorScheme.primary,
                            onPressed: () {
                              if (isPlaying) {
                                youTubeService.pause();
                              } else {
                                youTubeService.play();
                              }
                            },
                          )
                        else
                          _PlayButton(
                            isPlaying: isPlaying,
                            color: theme.colorScheme.primary,
                            onPressed: () {
                              if (isPlaying) {
                                musicProv.pause();
                              } else {
                                musicProv.play();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final Color color;

  const _ProgressBar({
    required this.progress,
    required this.isPlaying,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, _) => Container(
        height: 3,
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              gradient: isPlaying
                  ? LinearGradient(
                      colors: [color.withValues(alpha: 0.6), color],
                    )
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AlbumArt extends StatelessWidget {
  final String? albumArtUrl;
  final double size;
  final bool isPlaying;

  const _AlbumArt({
    required this.albumArtUrl,
    required this.size,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.primaryContainer,
        boxShadow: albumArtUrl != null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: albumArtUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                albumArtUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.music_note,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            )
          : Center(
              child: Icon(Icons.music_note, color: theme.colorScheme.primary),
            ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final Color color;
  final VoidCallback onPressed;

  const _PlayButton({
    required this.isPlaying,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey('play_$isPlaying'),
          size: 26,
        ),
      ),
      color: color,
      onPressed: onPressed,
      splashRadius: 22,
    ),
  );
}
