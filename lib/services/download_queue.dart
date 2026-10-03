import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/download_result.dart';

/// One track the user asked to have on the device.
class DownloadRequest {
  const DownloadRequest({required this.videoId, required this.title});

  final String videoId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is DownloadRequest &&
      other.videoId == videoId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(videoId, title);
}

/// Outcome of asking the queue to take on a batch of tracks.
class DownloadEnqueueResult {
  const DownloadEnqueueResult({
    required this.added,
    required this.alreadyDownloaded,
    required this.alreadyQueued,
  });

  /// Tracks newly accepted into the queue.
  final int added;

  /// Tracks skipped because they are already saved on the device.
  final int alreadyDownloaded;

  /// Tracks skipped because they are already waiting or running.
  final int alreadyQueued;

  int get skipped => alreadyDownloaded + alreadyQueued;
}

/// Where a queued track has got to.
enum DownloadQueueState {
  /// Waiting for the worker to pick it up.
  pending,

  /// Being fetched right now.
  downloading,

  /// Saved, and already recorded in the library.
  done,

  /// The download gave up; [DownloadQueueEntry.error] says why.
  failed,

  /// Stopped at the user's request.
  cancelled,
}

/// A queued track together with the download that is servicing it.
class _QueueSlot {
  _QueueSlot(this.entry);

  final DownloadQueueEntry entry;

  /// True when the queue's own worker is fetching it, false when some other
  /// caller started the download directly.
  bool ownedByQueue = true;
}

/// A track in the queue.
class DownloadQueueEntry {
  DownloadQueueEntry(this.request);

  final DownloadRequest request;

  DownloadQueueState state = DownloadQueueState.pending;
  double progress = 0;
  String? error;

  String get videoId => request.videoId;
  String get title => request.title;
  bool get isFinished => state == DownloadQueueState.done ||
      state == DownloadQueueState.failed ||
      state == DownloadQueueState.cancelled;

  /// Whether this track has already been saved on the device.
  ///
  /// Used to strike through rows in the queue so it is obvious what is being
  /// skipped rather than silently dropped.
  bool alreadyOnDevice = false;
}

/// A batch download queue that outlives the screen that started it.
///
/// Deliberately not a dialog: tapping "download all" on a playlist must not
/// trap the user behind a modal, and the batch must keep running after they
/// navigate to the downloads page to watch it. The queue lives in memory only,
/// so a killed app loses it -- downloads already written to disk are safe, and
/// the files are reconciled from the database on next launch.
class DownloadQueue with ChangeNotifier {
  DownloadQueue({
    required this.download,
    required this.downloadedVideoIds,
    this.onEntryFinished,
  });

  /// Performs the actual fetch, reporting 0..1 progress.
  final Future<DownloadResult?> Function(
    String videoId,
    void Function(double) onProgress,
  ) download;

  /// The authoritative set of videoIds already saved on the device.
  final Future<Set<String>> Function() downloadedVideoIds;

  /// Called after each track settles, so the caller can refresh the library.
  ///
  /// Mutable rather than constructor-injected because the library provider is
  /// built after this service and attaches itself once it exists.
  void Function(DownloadQueueEntry entry, DownloadResult? result)? onEntryFinished;

  final List<DownloadQueueEntry> _entries = [];
  final Map<String, _QueueSlot> _slots = {};

  bool _workerRunning = false;
  bool _cancelRequested = false;

  /// Every entry, in the order they were accepted.
  List<DownloadQueueEntry> get entries => List.unmodifiable(_entries);

  List<DownloadQueueEntry> get pendingEntries => _entries
      .where((e) => e.state == DownloadQueueState.pending)
      .toList(growable: false);

  List<DownloadQueueEntry> get activeEntries => _entries
      .where((e) => e.state == DownloadQueueState.downloading)
      .toList(growable: false);

  List<DownloadQueueEntry> get finishedEntries =>
      _entries.where((e) => e.isFinished).toList(growable: false);

  bool get isWorking =>
      _workerRunning || _entries.any((e) => !e.isFinished);

  bool get hasQueuedWork => _entries.any((e) => !e.isFinished);

  int get totalCount => _entries.length;

  int get completedCount => _entries
      .where((e) => e.state == DownloadQueueState.done)
      .length;

  int get failedCount => _entries
      .where((e) => e.state == DownloadQueueState.failed)
      .length;

  DownloadQueueEntry? get current =>
      _entries.where((e) => e.state == DownloadQueueState.downloading).firstOrNull;

  /// Adds tracks to the queue, dropping any that are already on the device.
  ///
  /// The "already on device" test reads the database rather than whatever list
  /// is currently loaded, so a track downloaded from a different playlist is
  /// correctly recognised and not fetched again.
  Future<DownloadEnqueueResult> enqueueAll(
    List<DownloadRequest> requests, {
    void Function(DownloadQueueEntry entry)? onProgressChanged,
  }) async {
    if (requests.isEmpty) {
      return const DownloadEnqueueResult(
        added: 0,
        alreadyDownloaded: 0,
        alreadyQueued: 0,
      );
    }

    // One query for the whole batch rather than one per track.
    final Set<String> onDevice = await downloadedVideoIds();

    var added = 0;
    var alreadyDownloaded = 0;
    var alreadyQueued = 0;

    for (final request in requests) {
      if (request.videoId.isEmpty) continue;
      if (onDevice.contains(request.videoId)) {
        alreadyDownloaded++;
        continue;
      }
      if (_slots.containsKey(request.videoId)) {
        alreadyQueued++;
        continue;
      }
      final entry = DownloadQueueEntry(request);
      _entries.add(entry);
      _slots[request.videoId] = _QueueSlot(entry);
      added++;
      onProgressChanged?.call(entry);
    }

    notifyListeners();
    unawaited(_runWorker());
    return DownloadEnqueueResult(
      added: added,
      alreadyDownloaded: alreadyDownloaded,
      alreadyQueued: alreadyQueued,
    );
  }

  /// Stops the queue once the track in flight finishes.
  void requestCancel() {
    _cancelRequested = true;
    notifyListeners();
  }

  /// Drops finished entries so a new batch starts from a clean list.
  ///
  /// Cleared ids are released from the de-duplication set, so a track that
  /// failed can be retried by queueing it again.
  void clearFinished() {
    _entries.removeWhere((e) {
      if (!e.isFinished) return false;
      if (e.state != DownloadQueueState.done) {
        _slots.remove(e.videoId);
      }
      return true;
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Downloads started elsewhere
  //
  // The single-track buttons (search results, an artist page, the queue sheet)
  // already work and call [downloadAudio] directly. Rather than route them
  // through the queue -- which would mean rewriting each button's progress
  // handling -- the queue mirrors them, so those downloads appear on the
  // downloads page alongside batch ones.
  // ---------------------------------------------------------------------

  /// Records that [videoId] is being downloaded by another caller.
  ///
  /// Idempotent: a batch download already holding the slot keeps ownership, so
  /// its worker finishes the entry rather than this call ending it early.
  void beginExternalDownload(String videoId, String title) {
    if (videoId.isEmpty) return;
    final existing = _slots[videoId];
    if (existing != null) {
      if (existing.entry.state == DownloadQueueState.pending) {
        existing.entry.state = DownloadQueueState.downloading;
      }
      return;
    }
    final entry = DownloadQueueEntry(
      DownloadRequest(videoId: videoId, title: title),
    )..state = DownloadQueueState.downloading;
    final slot = _QueueSlot(entry)..ownedByQueue = false;
    _slots[videoId] = slot;
    _entries.add(entry);
    notifyListeners();
  }

  /// Mirrors progress for a download started elsewhere.
  void reportExternalProgress(String videoId, double progress) {
    final entry = _slots[videoId]?.entry;
    if (entry == null || entry.state != DownloadQueueState.downloading) return;
    entry.progress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Settles a download started elsewhere.
  ///
  /// Does nothing for a slot the queue's own worker owns: that worker decides
  /// the outcome once the fetch resolves.
  void endExternalDownload(String videoId, {String? error}) {
    final slot = _slots[videoId];
    if (slot == null || slot.ownedByQueue) return;
    final entry = slot.entry;
    if (error != null) {
      entry
        ..state = DownloadQueueState.failed
        ..error = error;
    } else {
      entry
        ..state = DownloadQueueState.done
        ..progress = 1;
    }
    notifyListeners();
  }

  Future<void> _runWorker() async {
    if (_workerRunning) return;
    _workerRunning = true;
    _cancelRequested = false;
    try {
      while (true) {
        final entry = _entries
            .where((e) => e.state == DownloadQueueState.pending)
            .firstOrNull;
        if (entry == null) return;

        if (_cancelRequested) {
          _markRemainingCancelled();
          return;
        }

        entry.state = DownloadQueueState.downloading;
        entry.progress = 0;
        notifyListeners();

        DownloadResult? result;
        try {
          result = await download(entry.videoId, (progress) {
            entry.progress = progress.clamp(0.0, 1.0);
            notifyListeners();
          });
          // A null result means downloadAudio declined because this videoId is
          // already being fetched elsewhere; there is nothing left to do.
          entry.state = DownloadQueueState.done;
          if (result != null) entry.progress = 1;
        } catch (error) {
          entry.state = DownloadQueueState.failed;
          entry.error = error.toString();
        } finally {
          final slot = _slots[entry.videoId];
          if (slot != null && slot.ownedByQueue) {
            _slots.remove(entry.videoId);
          }
          notifyListeners();
          onEntryFinished?.call(entry, result);
        }
      }
    } finally {
      _workerRunning = false;
      notifyListeners();
    }
  }

  /// Only touches the queue's own work: a single-track download started
  /// elsewhere keeps running when the user stops the batch.
  void _markRemainingCancelled() {
    final toCancel = _slots.values
        .where((slot) => slot.ownedByQueue && !slot.entry.isFinished)
        .toList(growable: false);
    for (final slot in toCancel) {
      slot.entry.state = DownloadQueueState.cancelled;
      _slots.remove(slot.entry.videoId);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _entries.clear();
    _slots.clear();
    super.dispose();
  }
}