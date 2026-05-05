import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';

Widget buildCompactStyle({
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
}) {
  return Scaffold(
    backgroundColor: theme.colorScheme.surfaceContainerHighest,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            header,
            const SizedBox(height: 12),
            // Horizontal layout with album art on left
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 80, height: 80, child: albumArt),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSong.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentSong.artists.join(', '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Time display
                      Row(
                        children: [
                          Text(
                            formatDuration(currentPosition.toInt()),
                            style: theme.textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Text(
                            formatDuration(duration),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Slider directly below info
            Theme(
              data: theme.copyWith(
                sliderTheme: SliderThemeData(
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor:
                      theme.colorScheme.primary.withValues(alpha: 0.2),
                  thumbColor: theme.colorScheme.primary,
                  overlayColor:
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                  trackHeight: 3,
                ),
              ),
              child: progressBar,
            ),
            const SizedBox(height: 8),
            // Compact playback controls
            Theme(
              data: theme.copyWith(
                iconTheme: theme.iconTheme.copyWith(
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              child: playbackControls,
            ),
            const Spacer(),
            bottomControls,
          ],
        ),
      ),
    ),
  );
}
