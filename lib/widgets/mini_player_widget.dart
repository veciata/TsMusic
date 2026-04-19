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

        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
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

class MiniPlayerWidget extends StatelessWidget {
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final youTubeService = Provider.of<YouTubeService>(context, listen: false);

    return Consumer<music_provider.MusicProvider>(
      builder: (context, musicProv, _) {
        final currentSong = musicProv.currentSong;
        final isOnlinePlaying = youTubeService.isPlaying;
        final currentOnlineAudio = youTubeService.currentAudio;
        final l10n = AppLocalizations.of(context);

        final String title;
        final String artist;
        final bool isPlaying;

        if (isOnlinePlaying && currentOnlineAudio != null) {
          title = currentOnlineAudio.title;
          artist = currentOnlineAudio.author ??
              currentOnlineAudio.artists.join(', ');
          isPlaying = true;
        } else if (currentSong != null) {
          title = currentSong.title;
          artist = currentSong.artists.isNotEmpty
              ? currentSong.artists.join(' & ')
              : l10n.selectSongToPlay;
          isPlaying = musicProv.isPlaying;
        } else {
          title = l10n.notPlaying;
          artist = l10n.selectSongToPlay;
          isPlaying = false;
        }

        return GestureDetector(
          onTap: () {
            if (currentSong != null || isOnlinePlaying) {
              final themeProvider =
                  Provider.of<ThemeProvider>(context, listen: false);
              if (themeProvider.playerStyle == PlayerStyle.minimal) {
                _showMinimalPlayer(context);
              } else {
                Navigator.push(context, _slideUpRoute());
              }
            }
          },
          child: Container(
            width: double.infinity,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: currentSong?.albumArtUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            currentSong!.albumArtUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          Icons.music_note,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        artist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isOnlinePlaying)
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        youTubeService.pause();
                      } else {
                        youTubeService.play();
                      }
                    },
                  )
                else
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
        );
      },
    );
  }
}
