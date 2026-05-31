import 'package:flutter/material.dart';
import 'package:tsmusic/models/style_params.dart';

Widget buildMinimalStyle(StyleParams params) {
  final theme = params.theme;
  final musicProvider = params.musicProvider;
  final currentSong = params.currentSong;
  final albumArtUrl = params.albumArtUrl;
  final progressBar = params.progressBar;
  final togglePlay = params.togglePlay;
  final header = params.header;

  return Scaffold(
    backgroundColor: theme.colorScheme.surface,
    body: SafeArea(
      top: false, // Edge-to-edge at the top
      child: Column(
        children: [
          // Massive edge-to-edge album art
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (albumArtUrl != null)
                  Image.network(
                    albumArtUrl,
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    color: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.music_note,
                      size: 100,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                // Gradient for header text visibility
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: header,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Typography focus
                  Text(
                    currentSong.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentSong.artists.join(', '),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const Spacer(),
                  
                  // Stripped down progress bar
                  Theme(
                    data: theme.copyWith(
                      sliderTheme: SliderThemeData(
                        activeTrackColor: theme.colorScheme.onSurface,
                        inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.1),
                        thumbColor: theme.colorScheme.onSurface,
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                    ),
                    child: progressBar,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Just a massive play/pause button
                  GestureDetector(
                    onTap: togglePlay,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.onSurface,
                      ),
                      child: Icon(
                        musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 40,
                        color: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
