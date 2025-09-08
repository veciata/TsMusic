import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../main.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final YouTubeService _youTubeService;
  List<YouTubeAudio> _youtubeResults = [];
  bool _isSearchingYouTube = false;
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
    _scrollController.addListener(_onScroll);
    _searchScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _searchScrollController.dispose();
    super.dispose();
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    if (!mounted) return;
    setState(() => _loadingYouTubeId = audio.id);

    final streamUrl = await _youTubeService.getStreamUrl(audio.id);
    if (streamUrl != null && mounted) {
      final musicProvider =
          Provider.of<music_provider.NewMusicProvider>(context, listen: false);

      final tempSong = Song(
        id: 'temp_${audio.id}',
        title: audio.title,
        artist: audio.author,
        album: 'YouTube Audio',
        url: streamUrl,
        duration: audio.duration?.inMilliseconds ?? 0,
        isDownloaded: false,
      );

      musicProvider.playSong(tempSong);

      if (mounted) setState(() => _loadingYouTubeId = null);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load audio')),
      );
      setState(() => _loadingYouTubeId = null);
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

  Widget _buildYouTubeResultItem(YouTubeAudio audio) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final isCurrent = musicProvider.currentSong?.id == 'temp_${audio.id}';
    final hasDuration = isCurrent
        ? (musicProvider.duration.inMilliseconds > 0)
        : ((audio.duration?.inMilliseconds ?? 0) > 0);
    final playbackProgress = isCurrent && hasDuration
        ? (musicProvider.position.inMilliseconds /
            musicProvider.duration.inMilliseconds)
        : null;

    final downloadProgress =
        _youTubeService.activeDownloads.where((d) => d.videoId == audio.id).firstOrNull;

    final isDownloaded = musicProvider.songs
        .any((s) => s.id.contains(audio.id) && s.isDownloaded);

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
            Text(audio.author, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (isCurrent && playbackProgress != null)
              LinearProgressIndicator(value: playbackProgress.clamp(0.0, 1.0)),
            if (downloadProgress != null)
              LinearProgressIndicator(value: downloadProgress.progress),
            if (isDownloaded) const Text('Downloaded'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(isCurrent && musicProvider.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow),
              onPressed: () {
                if (isCurrent) {
                  if (musicProvider.isPlaying) {
                    musicProvider.pause();
                  } else {
                    musicProvider.play();
                  }
                } else {
                  _playAudio(audio);
                }
              },
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
                  // Navigate to downloads screen
                  if (mainNavKey.currentState != null) {
                    // Find the BottomNavigationBar in the widget tree and trigger a tap on the downloads tab
                    final bottomNavBar = mainNavKey.currentContext?.findAncestorWidgetOfExactType<BottomNavigationBar>();
                    if (bottomNavBar?.onTap != null) {
                      bottomNavBar!.onTap!(1);
                    }
                  }
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

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;

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
              musicProvider.filterSongs(value);
              _debounceTimer?.cancel();
              if (value.isNotEmpty) {
                setState(() => _isSearchingYouTube = true);
                _debounceTimer =
                    Timer(const Duration(milliseconds: 500), () {
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
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _youtubeResults.length,
                itemBuilder: (context, index) {
                  return _buildYouTubeResultItem(_youtubeResults[index]);
                },
              ),
            ),
            if (currentSong != null && currentSong.id.startsWith('temp_'))
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(currentSong.title),
                  subtitle: Text(currentSong.artist),
                  trailing: IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      if (isPlaying) {
                        musicProvider.pause();
                      } else {
                        musicProvider.play();
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
