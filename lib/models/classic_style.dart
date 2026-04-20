import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';

Widget buildClassicStyle({
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
    backgroundColor: theme.colorScheme.surface,
    body: SafeArea(
      child: Column(
        children: [
          header,
          Expanded(
            flex: 3,
            child: Center(child: albumArt),
          ),
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
                  children: currentSong.artists
                      .map((artist) => Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    theme.colorScheme.primary.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              artist,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          progressBar,
          playbackControls,
          bottomControls,
        ],
      ),
    ),
  );
}
