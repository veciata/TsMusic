import 'package:flutter/material.dart';
import 'package:tsmusic/models/style_params.dart';

Widget buildSquareStyle(StyleParams params) {
  final theme = params.theme;
  final currentSong = params.currentSong;
  final albumArtUrl = params.albumArtUrl;
  final header = params.header;
  final progressBar = params.progressBar;
  final playbackControls = params.playbackControls;
  final bottomControls = params.bottomControls;

  return Scaffold(
    backgroundColor: theme.colorScheme.surface,
    body: SafeArea(
      child: Column(
        children: [
          header,
          const SizedBox(height: 16),
          // Massive Square Art
          Expanded(
            flex: 3,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                      image: albumArtUrl != null
                          ? DecorationImage(
                              image: NetworkImage(albumArtUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: albumArtUrl == null
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: albumArtUrl == null
                        ? Center(
                            child: Icon(
                              Icons.music_note,
                              size: 120,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Left-aligned Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentSong.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSong.artists.join(', '),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          progressBar,

          Expanded(child: playbackControls),

          bottomControls,
        ],
      ),
    ),
  );
}
