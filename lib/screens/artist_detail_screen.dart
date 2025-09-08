import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../services/youtube_service.dart';
import '../models/song.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  String? artistImageUrl;

  ArtistDetailScreen({
    Key? key,
    required this.artistName,
    this.artistImageUrl,
  }) : super(key: key);

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
    if (widget.artistImageUrl != null) return;
    if (_artistImageCache.containsKey(widget.artistName)) {
      setState(() {
        widget.artistImageUrl = _artistImageCache[widget.artistName];
      });
      return;
    }

    try {
      final results = await _youTubeService.searchAudio(widget.artistName);
      for (final song in results) {
        if (song.thumbnailUrl != null && song.thumbnailUrl!.isNotEmpty) {
          _artistImageCache[widget.artistName] = song.thumbnailUrl!;
          setState(() {
            widget.artistImageUrl = song.thumbnailUrl!;
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
          id: 'youtube_${audio.id}',
          title: audio.title,
          artist: audio.author,
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
          id: 'youtube_${audio.id}',
          title: audio.title,
          artist: audio.author,
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
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final localSongs = musicProvider.getSongsByArtist(widget.artistName);

    String? artistImageUrl = widget.artistImageUrl;
    if (artistImageUrl == null && localSongs.isNotEmpty) {
      for (final song in localSongs) {
        if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
          artistImageUrl = song.albumArtUrl;
          break;
        }
      }
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200.0,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
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

  Widget _buildLocalSongsTab(List<Song> songs, music_provider.NewMusicProvider musicProvider) {
    if (songs.isEmpty) return const Center(child: Text('No local songs found for this artist'));

    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrentSong = musicProvider.currentSong?.id == song.id;
        final isPlaying = isCurrentSong && musicProvider.isPlaying;

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
            final musicProvider = Provider.of<music_provider.NewMusicProvider>(context, listen: false);
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
