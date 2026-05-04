import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/youtube_service.dart';
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
  }

  @override
  void initState() {
    super.initState();
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
    _youTubeService.addListener(_onDownloadsChanged);
    DownloadNotificationService().isDownloadsScreenVisible = true;
  }

  @override
  void dispose() {
    _youTubeService.removeListener(_onDownloadsChanged);
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
              onPressed:
                  _selectedSongs.isEmpty ? null : () => _deleteSelected(),
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
          final downloadedSongs = musicProvider.youtubeSongs;
          final allSongs = {...downloadedSongs, ..._localFiles}.toList();

          if (activeDownloads.isEmpty && allSongs.isEmpty) {
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
              if (activeDownloads.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Downloading...',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ...activeDownloads
                    .map((download) => _buildDownloadItem(download))
                    .toList(),
                const Divider(),
              ],
              if (allSongs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Downloaded',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ...allSongs.map((song) => _buildSongItem(song)).toList(),
              ],
            ],
          );
        },
      );

  Widget _buildDownloadItem(dynamic download) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: const Icon(Icons.downloading, size: 32),
          title: Text(
            download.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: download.cancelRequested
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
                  onPressed: () =>
                      _youTubeService.cancelDownload(download.videoId),
                  tooltip: 'Cancel download',
                ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
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
                    Text(
                      'Canceling...',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
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
            song.artists.isNotEmpty
                ? song.artists.join(' & ')
                : 'Unknown Artist',
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
                              Text('Delete',
                                  style: TextStyle(color: Colors.red)),
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
      final musicProvider =
          Provider.of<music_provider.MusicProvider>(context, listen: false);
      final songs = musicProvider.youtubeSongs;
      final List<Song> localFiles = List.from(songs);

      if (mounted) {
        setState(() {
          _localFiles = localFiles;
        });
      }
    } catch (e) {
      debugPrint('Error scanning local files: $e');
    }
  }

  Future<void> _showRelocateDialog(Song song) async {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final currentLocation = settingsProvider.downloadLocation;

    final targetLocation = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to...'),
        children: ['internal', 'downloads', 'music']
            .where((loc) => loc != currentLocation)
            .map((loc) => RadioListTile<String>(
                  title: Text(loc[0].toUpperCase() + loc.substring(1)),
                  value: loc,
                  groupValue: null,
                  onChanged: (value) => Navigator.pop(context, value),
                ))
            .toList(),
      ),
    );

    if (targetLocation == null) return;

    try {
      final sourceFile = File(song.url);
      if (!await sourceFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found')),
        );
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

      final musicProvider =
          Provider.of<music_provider.MusicProvider>(context, listen: false);
      final updatedSong = song.copyWith(url: targetFile.path);
      musicProvider.addSongToPlaylist(updatedSong);

      await _scanLocalFiles();

      final locationLabels = {
        'internal': 'Internal Storage',
        'downloads': 'Downloads folder',
        'music': 'Music folder'
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved to ${locationLabels[targetLocation]}')),
      );
    } catch (e) {
      debugPrint('Error relocating song: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to move: $e')),
      );
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
        final musicProvider = Provider.of<music_provider.MusicProvider>(
          context,
          listen: false,
        );
        await musicProvider.deleteSong(song);
        _scanLocalFiles();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
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
        final song = _localFiles
            .cast<Song?>()
            .firstWhere(
                (s) => s?.id == songId,
                orElse: () => null,
            );
        if (song != null) {
          try {
            final file = File(song.url);
            if (await file.exists()) {
              await file.delete();
            }
            final musicProvider = Provider.of<music_provider.MusicProvider>(
              context,
              listen: false,
            );
            await musicProvider.deleteSong(song);
          } catch (e) {
            debugPrint('Error deleting song ${song.id}: $e');
          }
        }
      }
      _selectedSongs.clear();
      _scanLocalFiles();
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
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
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
          await Provider.of<music_provider.MusicProvider>(context,
                  listen: false)
              .loadFromDatabaseOnly();
          _scanLocalFiles();
          setState(() {
            _downloadProgress.remove(videoId);
          });
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _downloadProgress.remove(videoId);
          });
          final errorStr = error.toString().toLowerCase();
          final isHtmlError = errorStr.contains('youtube_html_error') ||
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
      });
    }
  }
}
