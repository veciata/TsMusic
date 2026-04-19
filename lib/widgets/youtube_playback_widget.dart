import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/services/youtube_service.dart';

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
    // Listen to YouTubePlayerProvider for playback changes
    final youtubePlayer = Provider.of<YouTubePlayerProvider>(context);
    final isLoading = youtubePlayer.isLoadingAudio(audio.id);
    final isCurrent = youtubePlayer.isCurrentAudio(audio.id);
    final isPlaying = youtubePlayer.isPlaying && isCurrent;
    
        
    // Listen to YouTubeService for download changes
    final youTubeService = Provider.of<YouTubeService>(context);

    final downloadProgress = youTubeService.activeDownloads
        .where((d) => d.videoId == audio.id)
        .firstOrNull;

    final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
    final isDownloaded = musicProvider.songs
        .any((s) => s.youtubeId == audio.id && s.tags.contains('tsmusic'));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: audio.thumbnailUrl?.isNotEmpty == true
            ? ClipRRect(
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
              )
            : Container(
                width: 60,
                height: 60,
                color: Colors.grey[300],
                child: const Icon(Icons.music_video),
              ),
        title: Text(
          audio.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
            IconButton(
              icon: Icon(
                isDownloaded
                    ? Icons.check_circle
                    : (downloadProgress != null ? Icons.downloading : Icons.download),
              ),
              onPressed: () async {
                if (isDownloaded) {
                  return;
                }
                if (downloadProgress != null) {
                  return;
                }
                await onDownload(audio);
              },
            ),
          ],
        ),
      ),
    );
  }
}
