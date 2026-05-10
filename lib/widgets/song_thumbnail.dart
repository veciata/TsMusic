import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';

class SongThumbnail extends StatelessWidget {
  final Song song;
  final double size;
  final double borderRadius;

  const SongThumbnail({
    super.key,
    required this.song,
    this.size = 50,
    this.borderRadius = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    if (song.localThumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          File(song.localThumbnailPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallback(context),
        ),
      );
    }

    if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          song.albumArtUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallback(context),
        ),
      );
    }

    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
