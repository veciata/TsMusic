import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_provider.dart' as music_provider;
import '../providers/settings_provider.dart';
import '../services/youtube_service.dart';
import '../models/song.dart';
import 'downloads_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final ValueNotifier<String?> artistImageUrlNotifier;

  ArtistDetailScreen({
    super.key,
    required this.artistName,
    ValueNotifier<String?>? artistImageUrl,
  }) : artistImageUrlNotifier = artistImageUrl ?? ValueNotifier<String?>(null);

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late YouTubeService _youTubeService;
  List<YouTubeAudio> _youtubeSongs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _artistImageCache = {};
  String? _loadingYouTubeId;

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _tabController = TabController(length: 2, vsync: this);
    _loadYouTubeSongs();
    _scrollController.addListener(_onScroll);
    _fetchArtistImageIfNeeded();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreYouTubeSongs();
    }
  }

  Future<void> _fetchArtistImageIfNeeded() async {
    if (widget.artistImageUrlNotifier.value != null) return;
    if (_artistImageCache.containsKey(widget.artistName)) {
      setState(() {
        widget.artistImageUrlNotifier.value = _artistImageCache[widget.artistName];
      });
      return;
    }

    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      for (final song in results) {
        if (song.thumbnailUrl != null && song.thumbnailUrl!.isNotEmpty) {
          _artistImageCache[widget.artistName] = song.thumbnailUrl!;
          setState(() {
            widget.artistImageUrlNotifier.value = song.thumbnailUrl;
          });
          break;
        }
      }
    } catch (e) {
      debugPrint('Error fetching artist image: $e');
    }
  }

  Future<void> _loadYouTubeSongs() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      setState(() {
        _youtubeSongs = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading online songs: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreYouTubeSongs() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);
    try {
      final results = await _youTubeService.searchAudioNextPage(widget.artistName);
      setState(() {
        _youtubeSongs.addAll(results);
        _isLoading = false;
        _hasMore = results.isNotEmpty;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading more songs: $e')),
        );
      }
    }
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    if (!mounted) return;
    
    setState(() => _loadingYouTubeId = audio.id);
    
    try {
      await _youTubeService.playAudio(audio);
      
      if (mounted) {
        setState(() {
          _loadingYouTubeId = null;
        });
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      
      if (mounted) {
        setState(() => _loadingYouTubeId = null);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Audio could not be played'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _playAudio(audio),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    if (!mounted) return;
    
    final isDownloading =
        _youTubeService.activeDownloads.any((d) => d.videoId == audio.id);
    if (isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download already in progress')),
      );
      _navigateToDownloads();
      return;
    }

    try {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final result = await _youTubeService.downloadAudio(
        videoId: audio.id,
        preferredFormat: settingsProvider.audioFormat,
        downloadLocation: settingsProvider.downloadLocation,
      );
      if (result != null && mounted) {
        await Provider.of<music_provider.MusicProvider>(context, listen: false)
            .loadFromDatabaseOnly();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: ${audio.title}')),
        );
        _navigateToDownloads();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _navigateToDownloads() {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.MusicProvider>(context);
    final localSongs = musicProvider.getSongsByArtist(widget.artistName);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 200.0,
              pinned: true,
              flexibleSpace: ValueListenableBuilder<String?>(
                valueListenable: widget.artistImageUrlNotifier,
                builder: (context, artistImageUrl, child) => FlexibleSpaceBar(
                    title: Text(
                      widget.artistName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))],
                      ),
                    ),
                    background: artistImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: artistImageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.grey[800]),
                            errorWidget: (context, url, error) => _buildPlaceholderImage(),
                          )
                        : _buildPlaceholderImage(),
                  ),
              ),
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Local Songs'),
                  Tab(text: 'Online'),
                ],
              ),
            ),
          ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLocalSongsTab(localSongs, musicProvider),
            _buildYouTubeTab(),
          ],
        ),
      ),
    );
  }

  String _normalizePath(String path) {
    try {
      String normalized = path.split('?')[0].split('#')[0].toLowerCase().trim();
      const String emulatedPrefix = '/storage/emulated/0/';
      if (normalized.startsWith(emulatedPrefix)) {
        normalized = '/sdcard/${normalized.substring(emulatedPrefix.length)}';
      }
      final uri = Uri.file(normalized);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return '/${segments.join('/')}';
    } catch (e) {
      if (kDebugMode) {
        print('Error normalizing path "$path": $e');
      }
      return path.toLowerCase();
    }
  }

  Widget _buildLocalSongsTab(List<Song> songs, music_provider.MusicProvider musicProvider) {
    if (songs.isEmpty) return const Center(child: Text('No local songs found for this artist'));

    final Map<int, Song> uniqueSongs = {};
    final Set<String> seenPaths = {};
    
    for (final song in songs) {
      try {
        if (song.url.isEmpty) continue;
        
        final normalizedPath = _normalizePath(song.url);
        if (normalizedPath.isEmpty) continue;
        
        if (!seenPaths.contains(normalizedPath)) {
          seenPaths.add(normalizedPath);
          uniqueSongs[song.id] = song;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error processing song ${song.id}: $e');
        }
      }
    }
    
    final uniqueSongsList = uniqueSongs.values.toList();
    
    if (uniqueSongsList.isEmpty) {
      return const Center(child: Text('No valid songs found for this artist'));
    }

    return ListView.builder(
      itemCount: uniqueSongsList.length,
      itemBuilder: (context, index) {
        final song = uniqueSongsList[index];
        final isCurrentSong = musicProvider.currentSong?.id == song.id;
        return ListTile(
          leading: song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: CachedNetworkImage(
                    imageUrl: song.albumArtUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 50),
                  ),
                )
              : const Icon(Icons.music_note, size: 50),
          title: Text(
            song.title,
            style: TextStyle(fontWeight: isCurrentSong ? FontWeight.bold : FontWeight.normal),
          ),
          subtitle: Text(song.album ?? 'Unknown Album'),
          trailing: Text(song.formattedDuration),
          onTap: () => musicProvider.playSong(song),
        );
      },
    );
  }

  Widget _buildYouTubeTab() {
    if (_isLoading && _youtubeSongs.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_youtubeSongs.isEmpty) return const Center(child: Text('No online songs found for this artist'));

    return ListView.builder(
      controller: _scrollController,
      itemCount: _youtubeSongs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _youtubeSongs.length) return _buildLoadingIndicator();
        final audio = _youtubeSongs[index];
        return _buildOnlineResultItem(audio);
      },
    );
  }

  Widget _buildOnlineResultItem(YouTubeAudio audio) {
    final youTubeService = Provider.of<YouTubeService>(context);
    final isCurrent = youTubeService.currentAudio?.id == audio.id;
    final isPlaying = youTubeService.isPlaying && isCurrent;
    final isLoading = _loadingYouTubeId == audio.id;
    
    final downloadProgress = youTubeService.activeDownloads
        .where((d) => d.videoId == audio.id)
        .firstOrNull;

    final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
    final isDownloaded = musicProvider.songs
        .any((s) => s.id == audio.id.hashCode && s.isDownloaded);

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
              const LinearProgressIndicator(),
            if (downloadProgress != null)
              LinearProgressIndicator(value: downloadProgress.progress),
            if (isDownloaded) const Text('Downloaded'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => _playAudio(audio),
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
                  _navigateToDownloads();
                  return;
                }
                await _handleDownload(audio);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() => const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: CircularProgressIndicator()),
    );

  Widget _buildPlaceholderImage() => Container(
      color: Colors.grey[800],
      child: Center(
        child: Icon(Icons.person, size: 120, color: Colors.grey[600]),
      ),
    );
}
