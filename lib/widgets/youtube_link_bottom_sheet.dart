import 'package:flutter/material.dart';
import 'package:tsmusic/core/services/clipboard_service.dart';

enum YouTubeLinkAction { download, search }

void showYouTubeLinkBottomSheet(
  BuildContext context, {
  required YouTubeLinkResult link,
  required void Function(YouTubeLinkAction action) onSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              link.isPlaylist
                  ? 'YouTube Playlist Detected'
                  : 'YouTube Video Detected',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Download Track'),
            subtitle: Text(
              link.isPlaylist
                  ? 'Download all tracks from this playlist'
                  : 'Download audio from this video',
            ),
            onTap: () {
              Navigator.pop(ctx);
              onSelected(YouTubeLinkAction.download);
            },
          ),
          const Divider(indent: 72),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search in App'),
            subtitle: const Text('Look up this track in your library'),
            onTap: () {
              Navigator.pop(ctx);
              onSelected(YouTubeLinkAction.search);
            },
          ),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
        ],
      ),
    ),
  );
}
