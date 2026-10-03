import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/services/download_queue.dart';
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/services/download_notification_service.dart';
import 'package:tsmusic/widgets/sliding_text.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'search_screen.dart';
import 'package:animations/animations.dart';
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}
class _DownloadsScreenState extends State<DownloadsScreen> {
  late YouTubeService _youTubeService;
  late SettingsProvider _settingsProvider;
  final Map<String, double> _downloadProgress = {};
  List<Song> _localFiles = [];

  /// Everything downloaded from YouTube, read from the database.
  ///
  /// Kept as state rather than derived from the provider because the loaded
  /// song list changes with whichever playlist is open.
  List<Song> _downloadedSongs = [];
  bool _downloadsLoaded = false;
  String? _loadedForLocation;

  Future<void> _loadDownloadedSongs({bool force = false}) async {
    final location = _settingsProvider.downloadLocation;
    if (!force && _downloadsLoaded && _loadedForLocation == location) return;
    _loadedForLocation = location;
    _downloadsLoaded = false;
    final repository = context.read<SongRepository>();
    final songs = await repository.getDownloadedYouTubeSongs();
    if (!mounted) return;
    setState(() {
      _downloadedSongs = songs;
      _downloadsLoaded = true;
    });
  }
  final Set<int> _selectedSongs = {};
  bool _isMultiSelectMode = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
    final newSettingsProvider = Provider.of<SettingsProvider>(context);
    if (_localFiles.isEmpty ||
        (_settingsProvider.downloadLocation !=
            newSettingsProvider.downloadLocation)) {
      _settingsProvider = newSettingsProvider;
      _scanLocalFiles();
    } else {
      _settingsProvider = newSettingsProvider;
    }
    unawaited(_loadDownloadedSongs());
  }
  @override
  void initState() {
    super.initState();
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
    _youTubeService.addListener(_onDownloadsChanged);
    // Re-read the database whenever a batch finishes a track, so the list grows
    // as the batch runs instead of only on the next visit to this page.
    _youTubeService.downloadQueue.addListener(_onQueueChanged);
    DownloadNotificationService().isDownloadsScreenVisible = true;
  }

  /// True once the queue settles, so a burst of progress ticks does not cause a
  /// database read per frame.
  bool _queueWasBusy = false;

  void _onQueueChanged() {
    final busy = _youTubeService.downloadQueue.hasQueuedWork;
    if (busy == _queueWasBusy) return;
    _queueWasBusy = busy;
    if (busy) {
      setState(() {});
      return;
    }
    unawaited(_loadDownloadedSongs(force: true));
  }
  @override
  void dispose() {
    _youTubeService.removeListener(_onDownloadsChanged);
    _youTubeService.downloadQueue.removeListener(_onQueueChanged);
    DownloadNotificationService().isDownloadsScreenVisible = false;
    super.dispose();
  }
  void _onDownloadsChanged() {
    if (mounted) {
      setState(() {});
    }
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelectMode
            ? Text('${_selectedSongs.length} selected')
            : Text(l10n.downloads),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isMultiSelectMode = false;
                    _selectedSongs.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_isMultiSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  final allSongs = context
                      .read<music_provider.MusicProvider>()
                      .youtubeSongs;
                  if (_selectedSongs.length == allSongs.length) {
                    _selectedSongs.clear();
                  } else {
                    _selectedSongs.clear();
                    _selectedSongs.addAll(allSongs.map((s) => s.id));
                  }
                });
              },
              tooltip: l10n.selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedSongs.isEmpty ? null : _deleteSelected,
              color: Colors.red,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        FadeThroughTransition(
                          animation: animation,
                          secondaryAnimation: secondaryAnimation,
                          child: const SearchScreen(),
                        ),
                  ),
                );
              },
              tooltip: l10n.search,
            ),
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              onPressed: () {
                setState(() => _isMultiSelectMode = true);
              },
              tooltip: 'Select items',
            ),
          ],
        ],
      ),
      body: _buildDownloadsList(),
    );
  }
  Widget _buildDownloadsList() =>
      Consumer2<YouTubeService, music_provider.MusicProvider>(
        builder: (context, youTubeService, musicProvider, _) {
          final activeDownloads = youTubeService.activeDownloads;
          final queue = youTubeService.downloadQueue;
          final queued = queue.entries
              .where((e) => !e.isFinished || e.state == DownloadQueueState.done)
              .toList();
          // Read from the database rather than the loaded song list: the loaded
          // list changes with whatever playlist is open, which used to make
          // downloads vanish from this page.
          final downloadedSongs = _downloadedSongs;
          // Newest first. The database half arrives sorted; the scanned files
          // are merged in by date so the whole list reads chronologically
          // rather than as two unrelated blocks.
          final allSongs = [...downloadedSongs, ..._localFiles]..sort(
            (a, b) => b.dateAdded.compareTo(a.dateAdded),
          );
          if (activeDownloads.isEmpty &&
              queue.entries.isEmpty &&
              allSongs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_off,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No downloads yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Download songs from the search tab',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }
          return ListView(
            children: [
              if (queued.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Download queue',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (queue.isWorking)
                        TextButton.icon(
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          onPressed: () =>
                              queue.requestCancel(),
                        )
                      else if (queue.finishedEntries.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                          onPressed: () => queue.clearFinished(),
                        ),
                    ],
                  ),
                ),
                if (queue.isWorking)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${queue.completedCount + queue.failedCount} of ${queue.totalCount} done',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ...queued.map(_buildQueueItem),
                const Divider(),
              ],
              if (activeDownloads.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Downloading...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ...activeDownloads.map(_buildDownloadItem),
                const Divider(),
              ],
              if (allSongs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Downloaded',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ...allSongs.map(_buildSongItem),
              ],
            ],
          );
        },
      );
  Widget _buildQueueItem(DownloadQueueEntry entry) {
    final theme = Theme.of(context);
    final (icon, tint, trailing) = switch (entry.state) {
      DownloadQueueState.pending => (
        Icons.schedule,
        theme.disabledColor,
        const SizedBox.shrink(),
      ),
      DownloadQueueState.downloading => (
        Icons.downloading,
        theme.colorScheme.primary,
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      DownloadQueueState.done => (Icons.check_circle, Colors.green, null),
      DownloadQueueState.failed => (
        Icons.error_outline,
        theme.colorScheme.error,
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: () => _retryQueueEntry(entry),
        ),
      ),
      DownloadQueueState.cancelled => (
        Icons.cancel_outlined,
        theme.disabledColor,
        null,
      ),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: tint),
        title: Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: entry.state == DownloadQueueState.done ||
                  entry.state == DownloadQueueState.cancelled
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: entry.state == DownloadQueueState.downloading
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: entry.progress > 0 ? entry.progress : null,
                  minHeight: 3,
                ),
              )
            : entry.state == DownloadQueueState.failed &&
                  entry.error != null
            ? Text(
                entry.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: trailing,
      ),
    );
  }
  Future<void> _retryQueueEntry(DownloadQueueEntry entry) async {
    final result = await _youTubeService.downloadQueue.enqueueAll([
      DownloadRequest(videoId: entry.videoId, title: entry.title),
    ]);
    if (!mounted || result.added == 0) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Retrying ${entry.title}')));
  }
  Widget _buildDownloadItem(dynamic download) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: ListTile(
      leading: Icon(
        download.error != null ? Icons.error_outline : Icons.downloading,
        size: 32,
        color: download.error != null
            ? Theme.of(context).colorScheme.error
            : null,
      ),
      title: Text(download.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: download.error != null
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
              onPressed: () => _dismissFailedDownload(download.videoId),
            )
          : download.cancelRequested
          ? const Padding(
              padding: EdgeInsets.only(right: 12.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () => _youTubeService.cancelDownload(download.videoId),
              tooltip: 'Cancel download',
            ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (download.error == null)
            LinearProgressIndicator(
              value: download.progress > 0 ? download.progress : null,
              minHeight: 4,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                download.cancelRequested
                    ? Colors.orange
                    : Theme.of(context).primaryColor,
              ),
            ),
          if (download.error == null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  download.progress > 0
                      ? '${(download.progress * 100).toStringAsFixed(1)}%'
                      : 'Downloading...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (download.cancelRequested)
                  const Text(
                    'Canceling...',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ],
          if (download.error != null) ...[
            const SizedBox(height: 4),
            Text(
              download.error! == 'youtube_html_error'
                  ? 'Download unavailable. Please try again later.'
                  : download.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ),
  );
  void _dismissFailedDownload(String videoId) {
    _youTubeService.dismissDownload(videoId);
    setState(() {});
  }
  Widget _buildSongItem(Song song) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: ListTile(
      leading: _isMultiSelectMode
          ? Checkbox(
              value: _selectedSongs.contains(song.id),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedSongs.add(song.id);
                  } else {
                    _selectedSongs.remove(song.id);
                  }
                });
              },
            )
          : _buildThumbnail(song),
      title: SlidingText(
        song.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        song.artists.isNotEmpty ? song.artists.join(' & ') : 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _isMultiSelectMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(song.formattedDuration),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'relocate') {
                      _showRelocateDialog(song);
                    } else if (value == 'delete') {
                      _deleteSong(song);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'relocate',
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_move),
                          SizedBox(width: 8),
                          Text('Move to...'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      onTap: _isMultiSelectMode
          ? () {
              setState(() {
                if (_selectedSongs.contains(song.id)) {
                  _selectedSongs.remove(song.id);
                } else {
                  _selectedSongs.add(song.id);
                }
              });
            }
          : null,
    ),
  );
  Widget _buildThumbnail(Song song) {
    if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: song.albumArtUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(width: 50, height: 50, color: Colors.grey[300]),
          errorWidget: (context, url, error) =>
              Container(width: 50, height: 50, color: Colors.grey[300]),
        ),
      );
    }
    return Container(
      width: 50,
      height: 50,
      color: Colors.grey[300],
      child: const Icon(Icons.music_note),
    );
  }
  Future<void> _scanLocalFiles() async {
    try {
      final musicProvider = Provider.of<music_provider.MusicProvider>(
        context,
        listen: false,
      );
      final songs = musicProvider.youtubeSongs;
      final List<Song> localFiles = List.from(songs);
      if (mounted) {
        setState(() {
          _localFiles = localFiles;
        });
      }
    } catch (e) {
    }
  }
  Future<void> _showRelocateDialog(Song song) async {
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final currentLocation = settingsProvider.downloadLocation;
    final targetLocation = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to...'),
        children: [
          RadioGroup<String>(
            groupValue: currentLocation,
            onChanged: (value) {
              if (value != null) Navigator.pop(context, value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ['internal', 'downloads', 'music']
                  .where((loc) => loc != currentLocation)
                  .map(
                    (loc) => RadioListTile<String>(
                      title: Text(loc[0].toUpperCase() + loc.substring(1)),
                      value: loc,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (targetLocation == null) return;
    try {
      final sourceFile = File(song.url);
      if (!await sourceFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('File not found')));
        }
        return;
      }
      final targetDir = await _getMusicDirectory(targetLocation);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final fileName = song.url.split('/').last;
      final targetFile = File('${targetDir.path}/$fileName');
      await sourceFile.copy(targetFile.path);
      await sourceFile.delete();
      if (!mounted) return;
      final musicProvider = Provider.of<music_provider.MusicProvider>(
        context,
        listen: false,
      );
      final updatedSong = song.copyWith(url: targetFile.path);
      musicProvider.addSongToPlaylist(updatedSong);
      await _scanLocalFiles();
      final locationLabels = {
        'internal': 'Internal Storage',
        'downloads': 'Downloads folder',
        'music': 'Music folder',
      };
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to ${locationLabels[targetLocation]}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to move: $e')));
      }
    }
  }
  Future<void> _deleteSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Song?'),
        content: Text('Are you sure you want to delete "${song.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final file = File(song.url);
        if (await file.exists()) {
          await file.delete();
        }
        if (!mounted) return;
        final musicProvider = Provider.of<music_provider.MusicProvider>(
          context,
          listen: false,
        );
        await musicProvider.deleteSong(song);
        unawaited(_scanLocalFiles());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }
  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedSongs.length} songs?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isMultiSelectMode = false);
      for (final songId in _selectedSongs.toList()) {
        final song = _localFiles.cast<Song?>().firstWhere(
          (s) => s?.id == songId,
          orElse: () => null,
        );
        if (song != null) {
          try {
            final file = File(song.url);
            if (await file.exists()) {
              await file.delete();
            }
            if (!mounted) return;
            final musicProvider = Provider.of<music_provider.MusicProvider>(
              context,
              listen: false,
            );
            await musicProvider.deleteSong(song);
          } catch (e) {
          }
        }
      }
      _selectedSongs.clear();
      unawaited(_scanLocalFiles());
    }
  }
  Future<Directory> _getMusicDirectory(String downloadLocation) async {
    final baseDir = await getApplicationDocumentsDirectory();
    return Directory('${baseDir.path}/tsmusic');
  }
  Future<void> addDownload(String videoId, String title) async {
    if (!_downloadProgress.containsKey(videoId)) {
      setState(() {
        _downloadProgress[videoId] = 0.0;
      });
      final settingsProvider = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );
      unawaited(
        _youTubeService
            .downloadAudio(
              videoId: videoId,
              preferredFormat: settingsProvider.audioFormat,
              downloadLocation: settingsProvider.downloadLocation,
              onProgress: (progress) {
                if (mounted) {
                  setState(() {
                    _downloadProgress[videoId] = progress;
                  });
                }
              },
            )
            .then((result) async {
              if (result != null && mounted) {
                Provider.of<music_provider.MusicProvider>(
                  context,
                  listen: false,
                ).addDownloadedSongToLibrary(result.song);
                unawaited(_scanLocalFiles());
                setState(() {
                  _downloadProgress.remove(videoId);
                });
              }
            })
            .catchError((error) {
              if (mounted) {
                setState(() {
                  _downloadProgress.remove(videoId);
                });
                final errorStr = error.toString().toLowerCase();
                final isHtmlError =
                    errorStr.contains('youtube_html_error') ||
                    errorStr.contains('html') ||
                    errorStr.contains('ip') ||
                    errorStr.contains('consent') ||
                    errorStr.contains('blocked') ||
                    errorStr.contains('unavailable');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isHtmlError
                                ? 'Download unavailable. Please try again later.'
                                : 'Download failed: $error',
                          ),
                        ),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }),
      );
    }
  }
}
