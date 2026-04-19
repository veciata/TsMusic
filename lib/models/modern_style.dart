import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';

Widget buildModernStyle({
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
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        if (albumArtUrl != null)
          Positioned.fill(
            child: Image.network(
              albumArtUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: theme.colorScheme.surface),
            ),
          )
        else
          Container(color: theme.colorScheme.surface),
        Container(color: Colors.black54),
        SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                header,
                const SizedBox(height: 20),
                albumArt,
                const SizedBox(height: 20),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Text(
                    currentSong.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                progressBar,
                playbackControls,
                bottomControls,
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
