import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/new_music_provider.dart' as music_provider;

class NowPlayingBottomSheet extends StatelessWidget {
  const NowPlayingBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<music_provider.NewMusicProvider>(
      builder: (context, musicProvider, _) {
        final currentSong = musicProvider.currentSong;
        if (currentSong == null) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Song info and controls
              Row(
                children: [
                  // Album art
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.music_note, size: 40),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentSong.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentSong.artist,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Play/pause button
                  IconButton(
                    icon: Icon(
                      musicProvider.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: musicProvider.togglePlayPause,
                  ),
                ],
              ),
              
              // Progress bar
              const SizedBox(height: 16),
              Column(
                children: [
                  Slider(
                    value: musicProvider.position.inSeconds.toDouble(),
                    max: musicProvider.duration.inSeconds.toDouble(),
                    onChanged: (value) {
                      musicProvider.seek(Duration(seconds: value.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(musicProvider.position)),
                        Text(_formatDuration(musicProvider.duration)),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Controls
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Previous button
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 30),
                    onPressed: musicProvider.previous,
                  ),
                  
                  // Play/pause button
                  IconButton(
                    icon: Icon(
                      musicProvider.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 50,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: musicProvider.togglePlayPause,
                  ),
                  
                  // Next button
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 30),
                    onPressed: musicProvider.next,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NowPlayingBottomSheet(),
    );
  }
}
