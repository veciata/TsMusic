import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart' as music_provider;
import '../localization/app_localizations.dart';
import '../screens/now_playing_screen.dart';

/// Builds a route that slides up from the bottom and slides down on dismiss.
Route _slideUpRoute() => PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const NowPlayingScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // start from bottom
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

/// A compact "now playing" bar that should be visible at all times.
/// Place it between the main content and the bottom navigation bar.
class MiniPlayerWidget extends StatelessWidget {
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<music_provider.MusicProvider>(
      builder: (context, musicProv, _) {
        final currentSong = musicProv.currentSong;
        final l10n = AppLocalizations.of(context);

        return GestureDetector(
          onTap: () {
            if (currentSong != null) {
              Navigator.push(context, _slideUpRoute());
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
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Album art / icon
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.music_note, size: 26),
                ),
                const SizedBox(width: 12),
                // Title + artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        currentSong?.title ?? l10n.notPlaying,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentSong?.artists.isNotEmpty == true
                            ? currentSong!.artists.join(' & ')
                            : l10n.selectSongToPlay,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Play/Pause button
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: IconButton(
                    icon: Icon(
                      musicProv.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      if (musicProv.currentSong != null) {
                        musicProv.togglePlayPause();
                      }
                    },
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

