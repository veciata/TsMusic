import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart' as music_provider;
import '../screens/now_playing_screen.dart';
import '../screens/queue_screen.dart';

class NowPlayingBottomSheet extends StatelessWidget {
  const NowPlayingBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<music_provider.MusicProvider>(
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
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! > 0) {
                    Navigator.pop(context);
                  }
                },
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // Song info and controls
              GestureDetector(
                onTap: () {
                  // Navigate to full screen player
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NowPlayingScreen(),
                    ),
                  );
                },
                child: Row(
                  children: [
                    // Album art
                    Hero(
                      tag: 'album_art_${currentSong.id}',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          image: currentSong.albumArtUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(currentSong.albumArtUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: currentSong.albumArtUrl == null
                            ? const Icon(Icons.music_note, size: 30)
                            : null,
                      ),
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
                            currentSong.artists.isNotEmpty ? currentSong.artists.join(' & ') : 'Unknown Artist',
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
                    
                    // Play/Pause button
                    StreamBuilder<bool>(
                      stream: musicProvider.playingStream.distinct(),
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? musicProvider.isPlaying;
                        return IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              musicProvider.pause();
                            } else {
                              musicProvider.play();
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              // Progress bar
              const SizedBox(height: 16),
              StreamBuilder<Duration>(
                stream: musicProvider.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? musicProvider.position;
                  final duration = musicProvider.duration;
                  
                  return Column(
                    children: [
                      Slider(
                        value: position.inSeconds.toDouble(),
                        max: duration.inSeconds.toDouble(),
                        onChanged: (value) {
                          // Update UI immediately
                          musicProvider.seek(Duration(seconds: value.toInt()));
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${(position.inMinutes % 60).toString().padLeft(2, '0')}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              
              // Quick actions
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Favorite
                    IconButton(
                      icon: Icon(
                        musicProvider.isFavorite(currentSong.id.toString()) 
                            ? Icons.favorite 
                            : Icons.favorite_border,
                        color: musicProvider.isFavorite(currentSong.id.toString())
                            ? Colors.red
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      onPressed: () {
                        musicProvider.toggleFavorite(currentSong.id.toString());
                      },
                    ),
                    // Skip previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: musicProvider.previous,
                    ),
                    // Play/Pause
                    StreamBuilder<bool>(
                      stream: musicProvider.playingStream.distinct(),
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? musicProvider.isPlaying;
                        return IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              musicProvider.pause();
                            } else {
                              musicProvider.play();
                            }
                          },
                        );
                      },
                    ),
                    // Skip next
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: musicProvider.next,
                    ),
                    // Queue
                    IconButton(
                      icon: const Icon(Icons.queue_music),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QueueScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
