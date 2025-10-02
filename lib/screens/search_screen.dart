import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../models/song.dart' as model;
import '../services/youtube_service.dart';
import '../main.dart';
import 'downloads_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Helper method to navigate to downloads screen
  void _navigateToDownloads() {
    if (!mounted) return;
    
    // Navigate directly to DownloadsScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final YouTubeService _youTubeService;
  List<YouTubeAudio> _youtubeResults = [];
  bool _isSearchingYouTube = false;
  final Map<String, bool> _loadingStates = {};
  bool _hasMoreYouTubeResults = true;
  Timer? _debounceTimer;
  String? _loadingYouTubeId;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  bool _isLoadingMore = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _searchFocusNode.requestFocus();
  }

  void _setupScrollController() {
    _scrollController.addListener(_onScroll);
    _searchScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _searchScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    if (!mounted) return;
    
    setState(() => _loadingYouTubeId = audio.id);
    
    try {
      // YouTube servisi üzerinden sadece sesi çal
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
        
        // Kullanıcıya hata mesajı göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ses çalınamadı'),
            action: SnackBarAction(
              label: 'Tekrar Dene',
              onPressed: () => _playAudio(audio),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    final isDownloading =
        _youTubeService.activeDownloads.any((d) => d.videoId == audio.id);
    if (isDownloading && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download already in progress')),
      );
      return;
    }

    try {
      await _youTubeService.downloadAudio(audio.id, context: context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: ${audio.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _searchYouTube(String query, {bool loadMore = false}) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _youtubeResults.clear();
          _isSearchingYouTube = false;
          _hasMoreYouTubeResults = true;
        });
      }
      return;
    }

    if (loadMore && (_isSearchingYouTube || !_hasMoreYouTubeResults)) return;

    if (mounted) setState(() => _isSearchingYouTube = true);

    try {
      final List<YouTubeAudio> response = await _youTubeService.searchAudio(query);

      if (mounted) {
        setState(() {
          if (loadMore) {
            _youtubeResults.addAll(response);
          } else {
            _youtubeResults = response;
          }
          _hasMoreYouTubeResults = response.isNotEmpty;
          _lastQuery = query;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error searching YouTube'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _searchYouTube(query, loadMore: loadMore),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingYouTube = false);
    }
  }

  Future<void> _loadMoreYouTube() async {
    if (_isLoadingMore || !_hasMoreYouTubeResults || _lastQuery.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final List<YouTubeAudio> more = await _youTubeService.searchAudioNextPage(_lastQuery);
      if (!mounted) return;

      if (more.isEmpty) {
        setState(() {
          _hasMoreYouTubeResults = false;
          _isLoadingMore = false;
        });
        return;
      }

      setState(() {
        _youtubeResults.addAll(more);
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    const threshold = 300.0;
    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - threshold) {
      _loadMoreYouTube();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Widget _buildSearchResults(List<model.Song> localSongs, music_provider.NewMusicProvider provider, 
      model.Song? currentSong, bool isPlaying) {
    if (_searchController.text.isEmpty) {
      return const Center(
        child: Text('Search for songs...'),
      );
    }

    final query = _searchController.text.toLowerCase();
    final filteredLocalSongs = localSongs.where((song) {
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          (song.album?.toLowerCase().contains(query) ?? false);
    }).toList();

    final isLoadingYouTube = _isSearchingYouTube && _youtubeResults.isEmpty;
    final hasYouTubeResults = _youtubeResults.isNotEmpty;

    return ListView(
      controller: _scrollController,
      children: [
        // Local songs section
        if (filteredLocalSongs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Local Music',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...filteredLocalSongs.map((song) {
            final isCurrent = provider.currentSong?.id == song.id;
            final isSongPlaying = provider.isPlaying && isCurrent;
            
            return ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(song.title),
              subtitle: Text(song.artist),
              trailing: IconButton(
                icon: Icon(isCurrent && isSongPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (isCurrent) {
                    if (isSongPlaying) {
                      provider.pause();
                    } else {
                      provider.play();
                    }
                  } else {
                    provider.playSong(song);
                  }
                },
              ),
              onTap: () {
                if (isCurrent) {
                  if (isSongPlaying) {
                    provider.pause();
                  } else {
                    provider.play();
                  }
                } else {
                  provider.playSong(song);
                }
              },
            );
          }).toList(),
          const Divider(height: 1),
        ],
        
        // YouTube results section
        if (isLoadingYouTube) ...[
          const Center(child: CircularProgressIndicator()),
        ] else if (hasYouTubeResults) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Online Results',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._youtubeResults.map((audio) => _buildYouTubeResultItem(audio)).toList(),
        ] else if (_searchController.text.isNotEmpty && filteredLocalSongs.isEmpty) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No results found'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildYouTubeResultItem(YouTubeAudio audio) {
    final youTubeService = Provider.of<YouTubeService>(context);
    final isCurrent = youTubeService.currentAudio?.id == audio.id;
    final isPlaying = youTubeService.isPlaying && isCurrent;
    final isLoading = _loadingYouTubeId == audio.id;
    
    // Check if this audio is in the download queue
    final downloadProgress = youTubeService.activeDownloads
        .where((d) => d.videoId == audio.id)
        .firstOrNull;

    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context, listen: false);
    final isDownloaded = musicProvider.songs
        .any((s) => s.id == audio.id && s.isDownloaded);

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
                  // Already downloading, navigate to downloads screen
                  _navigateToDownloads();
                  return;
                }
                // Start download and navigate to downloads
                await _handleDownload(audio);
                if (mounted) {
                  _navigateToDownloads();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;
    final localSongs = musicProvider.songs;

    return WillPopScope(
      onWillPop: () async {
        if (currentSong != null && currentSong.id.startsWith('temp_')) {
          await musicProvider.stop();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search songs...',
              border: InputBorder.none,
            ),
            onChanged: (value) {
              _debounceTimer?.cancel();
              if (value.isNotEmpty) {
                setState(() => _isSearchingYouTube = true);
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  _searchYouTube(value);
                });
              } else {
                setState(() {
                  _youtubeResults.clear();
                  _isSearchingYouTube = false;
                });
              }
            },
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (currentSong != null && currentSong.id.startsWith('temp_')) {
                musicProvider.stop();
              }
              Navigator.of(context).pop();
            },
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _buildSearchResults(localSongs, musicProvider, currentSong, isPlaying),
            ),
            if (currentSong != null && currentSong.id.startsWith('temp_'))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.music_note),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSong.title,
                            style: Theme.of(context).textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            currentSong.artist,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _youTubeService.isLoading,
                      builder: (context, isLoading, child) {
                        return IconButton(
                          icon: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () async {
                            if (isLoading) return;
                            if (isPlaying) {
                              await musicProvider.pause();
                            } else {
                              // Find the YouTubeAudio from search results
                              final youtubeAudio = _youtubeResults.firstWhere(
                                (audio) => audio.id == currentSong.id.replaceFirst('temp_', ''),
                                orElse: () => YouTubeAudio(
                                  id: currentSong.id.replaceFirst('temp_', ''),
                                  title: currentSong.title,
                                  author: currentSong.artists.isNotEmpty ? currentSong.artists.first : 'Unknown Artist',
                                  artists: currentSong.artists.isNotEmpty ? currentSong.artists : ['Unknown Artist'],
                                  duration: Duration(milliseconds: currentSong.duration),
                                  thumbnailUrl: currentSong.albumArtUrl,
                                  audioUrl: currentSong.url,
                                ),
                              );
                              await _playAudio(youtubeAudio);
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
