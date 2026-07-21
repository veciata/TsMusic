import 'package:flutter/material.dart';
import 'package:tsmusic/models/storage_type.dart';

enum PlaylistType { localOnly, remoteCompatible }

class PlaylistBoundary {
  static bool canAddToPlaylist(
    StorageType songType,
    PlaylistType playlistType,
  ) {
    switch (playlistType) {
      case PlaylistType.localOnly:
        return songType == StorageType.local;
      case PlaylistType.remoteCompatible:
        return true;
    }
  }

  static String? getWarningMessage(
    StorageType songType,
    PlaylistType playlistType,
  ) {
    if (canAddToPlaylist(songType, playlistType)) return null;
    return 'This playlist only supports local tracks. Remote (YouTube) tracks cannot be saved here.';
  }

  static Future<bool> showWarningDialog(
    BuildContext context,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('Playlist Boundary'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
