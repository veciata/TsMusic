import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/main.dart';
import 'package:tsmusic/widgets/sliding_text.dart';

/// Reusable YouTube audio playback widget
/// Used in search and artist screens to display YouTube results with playback status
class YouTubePlaybackWidget extends StatelessWidget {
  final YouTubeAudio audio;
  final Future<void> Function(YouTubeAudio) onPlay;
  final Future<void> Function(YouTubeAudio) onDownload;

  const YouTubePlaybackWidget({
    super.key,
    required this.audio,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final youtubePlayer = Provider.of<YouTubePlayerProvider>(context);
    final isLoading = youtubePlayer.isLoadingAudio(audio.id);
    final isCurrent = youtubePlayer.isCurrentAudio(audio.id);
    final isPlaying = youtubePlayer.isPlaying && isCurrent;

    final youTubeService = Provider.of<YouTubeService>(context);

    final downloadProgress = youTubeService.activeDownloads
        .where((d) => d.videoId == audio.id)
        .firstOrNull;

    final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
    final downloadedSong = musicProvider.songs
        .where((s) => s.youtubeId == audio.id && s.tags.contains('tsmusic'))
        .firstOrNull;
    final isDownloaded = downloadedSong != null;

    final localThumbnailPath = downloadedSong?.localThumbnailPath;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildThumbnail(context, localThumbnailPath),
        title: SlidingText(
          audio.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(audio.artists.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (isCurrent && isPlaying)
              Container(
                margin: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.play_arrow, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('Playing...', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
            if (downloadProgress != null)
              LinearProgressIndicator(value: downloadProgress.progress),
            if (isDownloaded)
              Container(
                margin: const EdgeInsets.only(top: 2),
                child: const Text('Downloaded', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              IconButton(
                icon: Icon(Icons.stop, color: Theme.of(context).colorScheme.primary),
                onPressed: () => youtubePlayer.stop(),
                tooltip: 'Stop/Kill',
              )
            else if (isCurrent && isPlaying)
              IconButton(
                icon: Icon(Icons.stop, color: Theme.of(context).colorScheme.primary),
                onPressed: () => youtubePlayer.stop(),
                tooltip: 'Stop/Kill',
              )
            else
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => onPlay(audio),
              ),
            SizedBox(
              width: 24,
              height: 24,
              child: downloadProgress != null
                  ? GestureDetector(
                      onTap: () {
                        mainNavKey.currentState?.goToDownloads();
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              value: downloadProgress.progress > 0
                                  ? downloadProgress.progress
                                  : null,
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Icon(Icons.download, size: 12),
                        ],
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        isDownloaded
                            ? Icons.check_circle
                            : Icons.download,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        if (isDownloaded) {
                          return;
                        }
                        await onDownload(audio);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, String? localThumbnailPath) {
    if (localThumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(localThumbnailPath),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Container(width: 60, height: 60, color: Colors.grey[300]),
        ),
      );
    }

    if (audio.thumbnailUrl?.isNotEmpty == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: audio.thumbnailUrl!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(width: 60, height: 60, color: Colors.grey[300]),
          errorWidget: (context, url, error) =>
              Container(width: 60, height: 60, color: Colors.grey[300]),
        ),
      );
    }

    return Container(
      width: 60,
      height: 60,
      color: Colors.grey[300],
      child: const Icon(Icons.music_video),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
