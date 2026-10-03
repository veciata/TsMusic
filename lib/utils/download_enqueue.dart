import 'package:flutter/material.dart';
import 'package:tsmusic/main.dart';
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/services/download_queue.dart';
import 'package:tsmusic/services/youtube_service.dart';

/// Puts every online track on the download queue and steps aside.
///
/// Tapping "download all" must not trap the user behind a dialog, so this only
/// enqueues and reports. The batch then runs on [YouTubeService.downloadQueue]
/// and can be watched on the downloads page.
///
/// Tracks already saved on the device are dropped before anything is fetched.
/// The check reads the database, so a track downloaded from a *different*
/// playlist is still recognised rather than fetched twice.
Future<DownloadEnqueueResult> enqueueAllForDownload({
  required BuildContext context,
  required List<DownloadRequest> requests,
  required YouTubeService youTubeService,
  required SettingsProvider settings,
}) async {
  if (requests.isEmpty) {
    return const DownloadEnqueueResult(
      added: 0,
      alreadyDownloaded: 0,
      alreadyQueued: 0,
    );
  }

  youTubeService.configureDownloadQueue(
    audioFormat: settings.audioFormat,
    downloadLocation: settings.downloadLocation,
  );

  final result = await youTubeService.downloadQueue.enqueueAll(requests);

  if (!context.mounted) return result;

  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final added = result.added;
  final skipped = result.skipped;

  if (added == 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.alreadyQueued > 0
              ? 'Already in the download queue'
              : 'All of these are already downloaded',
        ),
      ),
    );
    return result;
  }

  final plural = added == 1 ? '' : 's';
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        skipped > 0
            ? 'Queued $added track$plural, skipped $skipped already on device'
            : 'Downloading $added track$plural',
      ),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'View',
        // Offered rather than imposed: the batch is already running, so there
        // is no need to yank the user off the playlist they are looking at.
        onPressed: () => mainNavKey.currentState?.goToDownloads(),
      ),
    ),
  );
  return result;
}
