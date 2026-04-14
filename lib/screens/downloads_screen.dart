import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_provider.dart' as music_provider;
import '../providers/settings_provider.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../widgets/bottom_navigation_widget.dart';
import '../utils/permission_helper.dart';

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
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
    final newSettingsProvider = Provider.of<SettingsProvider>(context);
    
    // Rescan if settings provider changed or location changed
    if (_localFiles.isEmpty || (_settingsProvider.downloadLocation != newSettingsProvider.downloadLocation)) {
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
  }

  @override
  void dispose() {
    _youTubeService.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) {
      setState(() {}); // Trigger a rebuild when downloads change
    }
  }


  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: _buildDownloadsList(),
      bottomNavigationBar: BottomNavigationWidget(
        currentIndex: 1,
        onTap: (index) {},
      ),
    );

  Widget _buildDownloadsList() => Consumer2<YouTubeService, music_provider.MusicProvider>(
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ...activeDownloads.map((download) => _buildDownloadItem(download)).toList(),
              const Divider(),
            ],
            if (allSongs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Downloaded', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                onPressed: () => _youTubeService.cancelDownload(download.videoId),
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
                  download.progress > 0 ? '${(download.progress * 100).toStringAsFixed(1)}%' : 'Downloading...',
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
                download.error!,
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
        leading: song.albumArtUrl?.isNotEmpty == true
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: song.albumArtUrl!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                    child: const Icon(Icons.music_note),
                  ),
                ),
              )
            : Container(
                width: 50,
                height: 50,
                color: Colors.grey[300],
                child: const Icon(Icons.music_note),
              ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          song.artists.isNotEmpty ? song.artists.join(' & ') : 'Unknown Artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
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
        onTap: () {
          final musicProvider = Provider.of<music_provider.MusicProvider>(
            context,
            listen: false,
          );
          musicProvider.playSong(song);
        },
      ),
    );



  Future<void> _scanLocalFiles() async {
    try {
      // Request necessary permissions first
      final hasPermission = await PermissionHelper.requestFileManagementPermission();
      if (!hasPermission) {
        debugPrint('File management permission not granted');
        return;
      }
      
      // Scan ALL locations, not just current one
      final locations = ['internal', 'downloads', 'music'];
      final List<Song> allSongs = [];
      
      for (final location in locations) {
        final dir = await _getMusicDirectory(location);
        if (!await dir.exists()) continue;
        
        final files = await dir.list().where((f) => f is File && 
          (f.path.endsWith('.m4a') || f.path.endsWith('.webm') || f.path.endsWith('.mp3') || f.path.endsWith('.opus'))
        ).toList();
        
        final songs = files.map((file) {
          final fileName = file.path.split('/').last;
          final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
          final parts = nameWithoutExt.split('_');
          final title = parts.first;
          return Song(
            id: 0,
            title: title,
            artists: ['Unknown'],
            url: file.path,
            duration: 0,
          );
        }).toList();
        
        allSongs.addAll(songs);
      }
      
      // Add scanned songs to MusicProvider playlist
      final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
      for (final song in allSongs) {
        musicProvider.addSongToPlaylist(song);
      }
      
      if (mounted) {
        setState(() => _localFiles = allSongs);
      }
    } catch (e) {
      debugPrint('Error scanning local files: $e');
    }
  }
  
  Future<Directory> _getMusicDirectory(String downloadLocation) async {
    if (downloadLocation == 'downloads') {
      return Directory('/storage/emulated/0/Download/tsmusic');
    } else if (downloadLocation == 'music') {
      return Directory('/storage/emulated/0/Music/tsmusic');
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      return Directory('${appDir.path}/tsmusic');
    }
  }
  
  Future<void> _showRelocateDialog(Song song) async {
    final locations = [
      {'value': 'internal', 'label': 'Internal Storage'},
      {'value': 'downloads', 'label': 'Downloads folder'},
      {'value': 'music', 'label': 'Music folder'},
    ];
    
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: locations.map((loc) => ListTile(
            title: Text(loc['label']!),
            onTap: () => Navigator.of(context).pop(loc['value']),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (selected != null) {
      await _relocateSong(song, selected);
    }
  }
  
  Future<void> _relocateSong(Song song, String targetLocation) async {
    try {
      final sourceFile = File(song.url);
      if (!await sourceFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Source file not found')),
        );
        return;
      }
      
      final targetDir = await _getMusicDirectory(targetLocation);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      final fileName = song.url.split('/').last;
      final targetFile = File('${targetDir.path}/$fileName');
      
      // Copy then delete source
      await sourceFile.copy(targetFile.path);
      await sourceFile.delete();
      
      // Update song in provider
      final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
      final updatedSong = song.copyWith(url: targetFile.path);
      musicProvider.addSongToPlaylist(updatedSong);
      
      // Refresh UI
      await _scanLocalFiles();
      
      final locationLabels = {'internal': 'Internal Storage', 'downloads': 'Downloads folder', 'music': 'Music folder'};
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
        
        // Refresh UI
        await _scanLocalFiles();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${song.title}" deleted')),
        );
      } catch (e) {
        debugPrint('Error deleting song: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
  
  void addDownload(String videoId, String title) {
    if (!_downloadProgress.containsKey(videoId)) {
      setState(() {
        _downloadProgress[videoId] = 0.0;
      });
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      _youTubeService.downloadAudio(
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
      ).then((result) async {
        if (result != null && mounted) {
          await Provider.of<music_provider.MusicProvider>(context, listen: false)
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $error')),
          );
        }
      });
    }
  }
}
