import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/providers/music_provider.dart';

class StyleParams {
  final ThemeData theme;
  final MusicProvider musicProvider;
  final Song currentSong;
  final String? albumArtUrl;
  final int duration;
  final double currentPosition;
  final Function(double) onSeek;
  final VoidCallback togglePlay;
  final String Function(int) formatDuration;
  final Widget albumArt;
  final Widget header;
  final Widget progressBar;
  final Widget playbackControls;
  final Widget bottomControls;
  final VoidCallback? onQueuePressed;

  const StyleParams({
    required this.theme,
    required this.musicProvider,
    required this.currentSong,
    required this.albumArtUrl,
    required this.duration,
    required this.currentPosition,
    required this.onSeek,
    required this.togglePlay,
    required this.formatDuration,
    required this.albumArt,
    required this.header,
    required this.progressBar,
    required this.playbackControls,
    required this.bottomControls,
    this.onQueuePressed,
  });
}
