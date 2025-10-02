import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../models/song.dart';
import '../services/youtube_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late YouTubeService _youTubeService;
  final Map<String, double> _downloadProgress = {};
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Listen to YouTubeService changes to update the UI when downloads are removed
    _youTubeService = Provider.of<YouTubeService>(context, listen: false);
    _youTubeService.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    _youTubeService.removeListener(_onDownloadsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) {
      setState(() {}); // Trigger a rebuild when downloads change
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Downloading'),
            Tab(text: 'Downloaded'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDownloadingTab(),
          _buildDownloadedTab(),
        ],
      ),
    );
  }

  Widget _buildDownloadingTab() {
    return Consumer<YouTubeService>(
      builder: (context, youTubeService, _) {
        final activeDownloads = youTubeService.activeDownloads;
        
        if (activeDownloads.isEmpty) {
          return const Center(
            child: Text('No active downloads'),
          );
        }

        return ListView.builder(
          itemCount: activeDownloads.length,
          itemBuilder: (context, index) {
            final download = activeDownloads[index];
            return Card(
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
                        onPressed: () async {
                          final youTubeService = Provider.of<YouTubeService>(
                            context,
                            listen: false,
                          );
                          await youTubeService.cancelDownload(download.videoId);
                        },
                        tooltip: 'Cancel download',
                      ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
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
          },
        );
      },
    );
  }

  Widget _buildDownloadedTab() {
    return Consumer<music_provider.NewMusicProvider>(
      builder: (context, musicProvider, _) {
        // Filter songs by tsmusic tag
        final downloadedSongs = musicProvider.youtubeSongs;
        
        if (downloadedSongs.isEmpty) {
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
                  'No downloaded music yet',
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

        return ListView.builder(
          itemCount: downloadedSongs.length,
          itemBuilder: (context, index) {
            final song = downloadedSongs[index];
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
                trailing: Text(song.formattedDuration),
                onTap: () {
                  final musicProvider = Provider.of<music_provider.NewMusicProvider>(
                    context,
                    listen: false,
                  );
                  musicProvider.playSong(song);
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Call this method when starting a download
  void addDownload(String videoId, String title) {
    if (!_downloadProgress.containsKey(videoId)) {
      setState(() {
        _downloadProgress[videoId] = 0.0;
      });

      _youTubeService.downloadAudio(
        videoId,
        context: context,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress[videoId] = progress;
            });
          }
        },
      ).then((_) {
        if (mounted) {
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
