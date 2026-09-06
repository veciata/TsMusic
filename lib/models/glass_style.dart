import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:tsmusic/models/style_params.dart';

Widget buildGlassStyle(StyleParams params) {
  final theme = params.theme;
  final currentSong = params.currentSong;
  final albumArtUrl = params.albumArtUrl;
  final header = params.header;
  final progressBar = params.progressBar;
  final playbackControls = params.playbackControls;
  final bottomControls = params.bottomControls;

  return Scaffold(
    body: Stack(
      children: [
        // Background art heavily blurred
        if (albumArtUrl != null)
          Positioned.fill(child: Image.network(albumArtUrl, fit: BoxFit.cover))
        else
          Container(color: theme.colorScheme.primaryContainer),

        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              header,
              const SizedBox(height: 20),

              // Glass Art Container
              Expanded(
                flex: 3,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: albumArtUrl != null
                                  ? Image.network(
                                      albumArtUrl,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: 0.5),
                                      child: const Icon(
                                        Icons.music_note,
                                        size: 80,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Glass Controls Panel
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSong.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentSong.artists.join(', '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          Theme(
                            data: theme.copyWith(
                              sliderTheme: SliderThemeData(
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                thumbColor: Colors.white,
                              ),
                              textTheme: theme.textTheme.copyWith(
                                bodySmall: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            child: progressBar,
                          ),

                          Theme(
                            data: theme.copyWith(
                              iconTheme: theme.iconTheme.copyWith(
                                color: Colors.white,
                              ),
                              colorScheme: theme.colorScheme.copyWith(
                                primary: Colors.white,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: playbackControls,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottomControls,
            ],
          ),
        ),
      ],
    ),
  );
}
