import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_provider.dart' as music_provider;
import '../models/song.dart';
import '../services/youtube_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  YouTubeService? _youTubeService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newService = Provider.of<YouTubeService>(context, listen: false);
    if (_youTubeService != newService) {
      _youTubeService?.removeListener(_onDownloadsChanged);
      _youTubeService = newService;
      _youTubeService?.addListener(_onDownloadsChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _youTubeService?.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    _youTubeService?.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_youTubeService == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Consumer2<YouTubeService, music_provider.MusicProvider>(
      builder: (context, youTubeService, musicProvider, _) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Downloads'),
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.downloading), text: 'Downloading'),
                  Tab(icon: Icon(Icons.music_note), text: 'Downloads'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildDownloadingTab(youTubeService),
                _buildDownloadsList(musicProvider, youTubeService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadsList(music_provider.MusicProvider musicProvider,
      YouTubeService youTubeService) {
    final activeDownloads = youTubeService.activeDownloads;
    final downloadedSongs =
        musicProvider.songs.where((s) => s.isDownloaded).toList();

    if (activeDownloads.isEmpty && downloadedSongs.isEmpty) {
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
          ...activeDownloads.map((download) => _buildDownloadItem(download)),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Downloaded',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
        ...downloadedSongs.map((song) => _buildSongItem(song)),
      ],
    );
  }

  Widget _buildDownloadingTab(YouTubeService youTubeService) {
    final activeDownloads = youTubeService.activeDownloads;
    
    Widget buildEmptyState() {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No active downloads'),
          ],
        ),
      );
    }

    if (activeDownloads.isEmpty) {
      return buildEmptyState();
    }

    return ListView.builder(
      key: const PageStorageKey('downloading_list'),
      itemCount: activeDownloads.length,
      itemBuilder: (context, index) {
        if (index >= activeDownloads.length) return const SizedBox.shrink();
        final download = activeDownloads[index];
        if (download == null) return const SizedBox.shrink();
        return _buildDownloadItem(download);
      },
    );
  }

  Widget _buildDownloadItem(dynamic download) {
    final isDownloading = download.isDownloading;
    final hasError = download.error != null;

    return ListTile(
      leading: const Icon(Icons.download_rounded),
      title: Text(download.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDownloading && !hasError)
            LinearProgressIndicator(
              value: download.progress,
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
                '${(download.progress * 100).toStringAsFixed(1)}%',
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
      trailing: !download.isDownloading && download.error == null
          ? const Icon(Icons.check_circle, color: Colors.green)
          : download.cancelRequested
              ? const Icon(Icons.cancel, color: Colors.orange)
              : null,
    );
  }

  Widget _buildSongItem(Song song) {
    return Card(
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
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(_formatDuration(song.duration)),
        onTap: () {
          final musicProvider = Provider.of<music_provider.MusicProvider>(
            context,
            listen: false,
          );
          musicProvider.playSong(song);
        },
      ),
    );
  }

  String _formatDuration(int durationMs) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
