import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';

Widget buildMinimalStyle({
  required ThemeData theme,
  required MusicProvider musicProvider,
  required Song currentSong,
  required String? albumArtUrl,
  required int duration,
  required double currentPosition,
  required Function(double) onSeek,
  required VoidCallback togglePlay,
  required String Function(int) formatDuration,
  required Widget albumArt,
  required Widget header,
  required Widget progressBar,
  required Widget playbackControls,
  required Widget bottomControls,
  VoidCallback? onQueuePressed,
}) {
  return Material(
    color: Colors.transparent,
    child: Stack(
      children: [
        // Full album art as background
        Positioned.fill(child: albumArt),

        // Gradient overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black87,
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),

        // Bottom sheet with minimal controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.95),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Song info with accent color
                  Text(
                    currentSong.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSong.artists.join(', '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // Minimal progress bar
                  Theme(
                    data: theme.copyWith(
                      progressIndicatorTheme: ProgressIndicatorThemeData(
                        color: theme.colorScheme.primary,
                        linearTrackColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: progressBar,
                  ),

                  const SizedBox(height: 12),

                  // Minimal playback controls (just play/pause)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          musicProvider.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: togglePlay,
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  bottomControls,
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
