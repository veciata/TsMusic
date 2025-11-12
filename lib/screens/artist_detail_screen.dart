import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_provider.dart' as music_provider;
import '../services/youtube_service.dart';
import '../models/song.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final ValueNotifier<String?> artistImageUrlNotifier;

  ArtistDetailScreen({
    Key? key,
    required this.artistName,
    ValueNotifier<String?>? artistImageUrl,
  }) : artistImageUrlNotifier = artistImageUrl ?? ValueNotifier<String?>(null), super(key: key);

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final YouTubeService _youTubeService = YouTubeService();
  List<Song> _youtubeSongs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _artistImageCache = {};

  @override
  void initState() {
    super.initState();
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
            widget.artistImageUrlNotifier.value = song.thumbnailUrl!;
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
        _youtubeSongs = results.map((audio) => Song(
          id: audio.id.hashCode,
          title: audio.title,
          artists: audio.artists.isNotEmpty ? audio.artists : ['Unknown Artist'],
          album: 'YouTube',
          albumArtUrl: audio.thumbnailUrl,
          url: audio.audioUrl ?? '',
          duration: audio.duration?.inMilliseconds ?? 0,
          tags: ['youtube'],
        )).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading YouTube songs: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreYouTubeSongs() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);
    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      setState(() {
        _youtubeSongs.addAll(results.map((audio) => Song(
          id: audio.id.hashCode,
          title: audio.title,
          artists: audio.artists.isNotEmpty ? audio.artists : ['Unknown Artist'],
          album: 'YouTube',
          albumArtUrl: audio.thumbnailUrl,
          url: audio.audioUrl ?? '',
          duration: audio.duration?.inMilliseconds ?? 0,
          tags: ['youtube'],
        )).toList());
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
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200.0,
              pinned: true,
              flexibleSpace: ValueListenableBuilder<String?>(
                valueListenable: widget.artistImageUrlNotifier,
                builder: (context, artistImageUrl, child) {
                  return FlexibleSpaceBar(
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
                  );
                },
              ),
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Local Songs'),
                  Tab(text: 'YouTube'),
                ],
              ),
            ),
          ];
        },
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

  // Helper function to normalize file paths for comparison
  String _normalizePath(String path) {
    try {
      // Convert to lowercase and remove any query parameters or fragments
      String normalized = path.split('?')[0].split('#')[0].toLowerCase().trim();
      
      // Handle different path formats that point to the same location
      const String emulatedPrefix = '/storage/emulated/0/';
      
      // Convert /storage/emulated/0/ to /sdcard/ for consistency
      if (normalized.startsWith(emulatedPrefix)) {
        normalized = '/sdcard/${normalized.substring(emulatedPrefix.length)}';
      }
      
      // Remove any redundant path segments
      final uri = Uri.file(normalized);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      
      // Rebuild path with normalized segments
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

    // Use a map to ensure unique songs by their normalized path
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
    if (_youtubeSongs.isEmpty) return const Center(child: Text('No YouTube songs found for this artist'));

    return ListView.builder(
      controller: _scrollController,
      itemCount: _youtubeSongs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _youtubeSongs.length) return _buildLoadingIndicator();
        final song = _youtubeSongs[index];

        return ListTile(
          leading: song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: CachedNetworkImage(
                    imageUrl: song.albumArtUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.music_video, size: 50),
                  ),
                )
              : const Icon(Icons.music_video, size: 50),
          title: Text(song.title),
          subtitle: const Text('YouTube'),
          trailing: IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Downloading ${song.title}')),
              );
            },
          ),
          onTap: () {
            final musicProvider = Provider.of<music_provider.MusicProvider>(context, listen: false);
            musicProvider.playSong(song);
          },
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Icon(Icons.person, size: 120, color: Colors.grey[600]),
      ),
    );
  }
}
