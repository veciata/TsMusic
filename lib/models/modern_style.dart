import 'package:flutter/material.dart';
import 'package:tsmusic/models/style_params.dart';

Widget buildModernStyle(StyleParams params) {
  final theme = params.theme;
  final currentSong = params.currentSong;
  final albumArtUrl = params.albumArtUrl;
  final header = params.header;
  final progressBar = params.progressBar;
  final playbackControls = params.playbackControls;

  return Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        // Full-screen blurred album art background
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

        // Dark overlay with gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.3),
                Colors.black.withValues(alpha: 0.7),
                Colors.black.withValues(alpha: 0.9),
              ],
            ),
          ),
        ),

        // Glassmorphic content
        SafeArea(
          child: Column(
            children: [
              header,
              const Spacer(),

              // Song info with glow effect
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      currentSong.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentSong.artists.join(', '),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Progress bar with theme accent
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Theme(
                  data: theme.copyWith(
                    progressIndicatorTheme: ProgressIndicatorThemeData(
                      color: theme.colorScheme.primary,
                      linearTrackColor:
                          theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: progressBar,
                ),
              ),

              const SizedBox(height: 16),

              // Playback controls with accent color
              Theme(
                data: theme.copyWith(
                  iconTheme: theme.iconTheme.copyWith(
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                ),
                child: playbackControls,
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    ),
  );
}
