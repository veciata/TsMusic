import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_provider.dart' as music_provider;
import '../providers/settings_provider.dart';
import '../models/song.dart' as model;
import '../services/youtube_service.dart';
import '../widgets/mini_player_widget.dart';

import 'downloads_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _searchFocusNode.requestFocus();
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
      // YouTube servisi üzerinden sadece sesi çal - timeout ekle
      await _youTubeService.playAudio(audio).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Bağlantı zaman aşımına uğradı');
        },
      );
      
      if (mounted) {
        setState(() => _loadingYouTubeId = null);
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      
      if (mounted) {
        setState(() => _loadingYouTubeId = null);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ses çalınamadı: $e'),
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
    if (!mounted) return;
    
    final isDownloading =
        _youTubeService.activeDownloads.any((d) => d.videoId == audio.id);
    if (isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download already in progress')),
      );
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
        // Add the downloaded song directly to the library so the icon updates
        // immediately without a full database reload.
        Provider.of<music_provider.MusicProvider>(context, listen: false)
            .addDownloadedSongToLibrary(result.song);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download completed: ${audio.title}')),
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

  
  


  Widget _buildSearchResults(List<model.Song> localSongs, music_provider.MusicProvider provider,
      model.Song? currentSong, bool isPlaying,) {
    if (_searchController.text.isEmpty) {
      return const Center(
        child: Text('Search for songs...'),
      );
    }

    final query = _searchController.text.toLowerCase();
    final filteredLocalSongs = localSongs.where((song) => song.title.toLowerCase().contains(query) ||
          song.artists.any((artist) => artist.toLowerCase().contains(query)) ||
          (song.album?.toLowerCase().contains(query) ?? false)).toList();

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
              subtitle: Text(song.artists.isNotEmpty ? song.artists.join(' & ') : 'Unknown Artist'),
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
                debugPrint('🔍 SearchScreen onTap: ${song.title}');
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
          }),
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
          ..._youtubeResults.map(_buildYouTubeResultItem),
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
    final isLoading = _loadingYouTubeId == audio.id;
    
    // Listen to YouTubeService for download changes
    final youTubeService = Provider.of<YouTubeService>(context);
    final isCurrent = youTubeService.currentAudio?.id == audio.id;
    final isPlaying = youTubeService.isPlaying && isCurrent;
    
    // Check if this audio is in the download queue
    final downloadProgress = youTubeService.activeDownloads
        .where((d) => d.videoId == audio.id)
        .firstOrNull;

    final musicProvider = Provider.of<music_provider.MusicProvider>(context);
    // isDownloaded is true when the 'tsmusic' tag is present (set during download
    // and persisted in the DB, so it survives app restarts).
    final isDownloaded = musicProvider.songs
        .any((s) => s.youtubeId == audio.id && s.tags.contains('tsmusic'));
    
    debugPrint('🔍 Icon check for ${audio.id}: isDownloaded=$isDownloaded, songs=${musicProvider.songs.length}, downloadProgress=$downloadProgress');

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
                  // Already downloading, do nothing
                  return;
                }
                // Start download and stay on search screen
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
    final musicProvider = Provider.of<music_provider.MusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;
    final localSongs = musicProvider.songs;

    return WillPopScope(
      onWillPop: () async {
        if (currentSong != null && currentSong.url.startsWith('http')) {
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
              if (currentSong != null && currentSong.url.startsWith('http')) {
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
            if (currentSong != null && currentSong.url.startsWith('http'))
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
                            currentSong.artists.isNotEmpty ? currentSong.artists.join(' & ') : 'Unknown Artist',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _youTubeService.isLoading,
                      builder: (context, isLoading, child) => IconButton(
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
                              (audio) => audio.id.hashCode == currentSong.id,
                                orElse: () => YouTubeAudio(
                                  id: currentSong.id.toString(),
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
                        ),
                    ),
                  ],
                ),
              ),
            // Always show mini player at bottom
            const MiniPlayerWidget(),
          ],
        ),
      ),
    );
  }
}
