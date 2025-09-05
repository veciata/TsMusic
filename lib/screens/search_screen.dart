import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/new_music_provider.dart' as music_provider;
import '../models/song.dart';
import '../services/youtube_service.dart';

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
  Timer? _debounceTimer;
  String? _loadingYouTubeId;

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    // Don't dispose the YouTube service here - it's managed at the app level
    super.dispose();
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      // Show loading spinner on the tapped item
      if (mounted) {
        setState(() => _loadingYouTubeId = audio.id);
      }

      // Get the streaming URL
      final streamUrl = await _youTubeService.getStreamUrl(audio.id);

      if (streamUrl != null) {
        final musicProvider = Provider.of<music_provider.NewMusicProvider>(
          context,
          listen: false,
        );

        // Create a temporary song for playback
        final tempSong = Song(
          id: 'temp_${audio.id}',
          title: audio.title,
          artist: audio.author,
          album: 'YouTube Audio',
          url: streamUrl,
          duration: audio.duration?.inMilliseconds ?? 0,
          isDownloaded: false,
        );

        // Play the audio
        musicProvider.playSong(tempSong);
        
        // Clear per-item loading when playback starts
        if (mounted) {
          setState(() => _loadingYouTubeId = null);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load audio')),
          );
          setState(() => _loadingYouTubeId = null);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error playing audio')),
        );
        setState(() => _loadingYouTubeId = null);
      }
    }
  }

  Future<void> _handleDownload(YouTubeAudio audio) async {
    final youTubeService = context.read<YouTubeService>();

    // Check if already downloading
    final isDownloading =
        youTubeService.activeDownloads.any((d) => d.videoId == audio.id);
    if (isDownloading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download already in progress')),
        );
      }
      return;
    }

    // Start download
    try {
      // Start download - the YouTubeService will handle progress tracking
      await _youTubeService.downloadAudio(
        audio.id,
        context: context,
      );

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download started: ${audio.title}')),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _searchYouTube(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _youtubeResults.clear();
          _isSearchingYouTube = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isSearchingYouTube = true);
    }

    try {
      debugPrint('🔍 [SearchScreen] Searching YouTube for: "$query"');
      final results = await _youTubeService.searchAudio(query);
      debugPrint('✅ [SearchScreen] Received ${results.length} results');

      if (mounted) {
        setState(() => _youtubeResults = results);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SearchScreen] Error searching YouTube: $e');
      debugPrint('📜 [SearchScreen] Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error searching YouTube'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _searchYouTube(query),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingYouTube = false);
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  Widget _buildYouTubeResults() {
    if (_youtubeResults.isEmpty) return const SizedBox.shrink();

    return Consumer2<YouTubeService, music_provider.NewMusicProvider>(
      builder: (context, youTubeService, musicProvider, _) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _youtubeResults.length,
          itemBuilder: (context, index) {
            final audio = _youtubeResults[index];
            final isCurrent =
                musicProvider.currentSong?.id == 'temp_${audio.id}';
            final hasDuration = isCurrent
                ? (musicProvider.duration.inMilliseconds > 0)
                : ((audio.duration?.inMilliseconds ?? 0) > 0);
            final playbackProgress = isCurrent && hasDuration
                ? (musicProvider.position.inMilliseconds /
                    musicProvider.duration.inMilliseconds)
                : null;
            final downloadProgress = youTubeService.activeDownloads
                .where((d) => d.videoId == audio.id)
                .firstOrNull;

            // Check if already downloaded
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
                          placeholder: (context, url) => Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[300],
                            child: const Center(
                                child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[300],
                            child: const Icon(Icons.music_video),
                          ),
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
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audio.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isCurrent && playbackProgress != null) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: playbackProgress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDuration(musicProvider.position)} / ${_formatDuration(musicProvider.duration)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (downloadProgress != null) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: downloadProgress.progress,
                        minHeight: 4,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${(downloadProgress.progress * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton.icon(
                            onPressed: () {
                              context.read<YouTubeService>().cancelDownload(audio.id);
                            },
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Cancel'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (downloadProgress.error != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          downloadProgress.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ] else if (isDownloaded) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Downloaded',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent && hasDuration)
                      Text(
                        _formatDuration(musicProvider.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else if (audio.duration != null)
                      Text(
                        _formatDuration(audio.duration!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(width: 8),
                    if (_loadingYouTubeId == audio.id) ...[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ] else ...[
                      IconButton(
                        icon: Icon(
                          isCurrent && musicProvider.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
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
                        tooltip:  musicProvider.isPlaying
                            ? 'Pause'
                            : 'Play',
                      ),
                    ],
                    // Keep trailing compact: download/cancel controls are shown in subtitle
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<music_provider.NewMusicProvider>(context);
    final currentSong = musicProvider.currentSong;
    final isPlaying = musicProvider.isPlaying;

    return WillPopScope(
      onWillPop: () async {
        final provider =
            Provider.of<music_provider.NewMusicProvider>(context, listen: false);
        final current = provider.currentSong;
        if (current != null && current.id.startsWith('temp_')) {
          await provider.stop();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search songs...',
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withOpacity(0.7),
              ),
            ),
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            onChanged: (value) {
              musicProvider.filterSongs(value);

              // Cancel any previous debounce timer
              _debounceTimer?.cancel();

              if (value.isNotEmpty) {
                // Show loading indicator immediately for YouTube section
                setState(() => _isSearchingYouTube = true);

                // Debounce YouTube search regardless of local results
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  _searchYouTube(value);
                });
              } else {
                // Clear results if search is empty
                if (mounted) {
                  setState(() {
                    _youtubeResults.clear();
                    _isSearchingYouTube = false;
                  });
                }
              }
            },
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              final musicProvider =
                  Provider.of<music_provider.NewMusicProvider>(context, listen: false);
              final current = musicProvider.currentSong;
              if (current != null && current.id.startsWith('temp_')) {
                musicProvider.stop();
              }
              Navigator.of(context).pop();
            },
          ),
        ),
      body: Column(
        children: [
          // Search results (scrollable)
          Expanded(
            child: Consumer<music_provider.NewMusicProvider>(
              builder: (context, musicProvider, _) {
                final results = musicProvider.filteredSongs;

                if (_searchController.text.isEmpty) {
                  return const Center(
                    child: Text('Type to search for songs'),
                  );
                }

                if (results.isEmpty &&
                    _youtubeResults.isEmpty &&
                    !_isSearchingYouTube) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No local results found\nfor "${_searchController.text}"',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _searchYouTube(_searchController.text),
                          icon: const Icon(Icons.search),
                          label: const Text('Search on YouTube'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  children: [
                    // Local results
                    if (results.isNotEmpty) ...[
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Local Music',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      ...results.map((song) => ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.music_note, size: 24),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              musicProvider.playSong(song);
                              Navigator.pop(context);
                            },
                          )),
                      const SizedBox(height: 16),
                    ],

                    // YouTube loading indicator
                    if (_isSearchingYouTube)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),

                    // YouTube audio results
                    if (_youtubeResults.isNotEmpty) ...[
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Online Music',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      _buildYouTubeResults(),
                    ],
                  ],
                );
              },
            ),
          ),

          // Bottom player for currently playing song (fixed at bottom)
          if (currentSong != null && currentSong.id.startsWith('temp_'))
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1.0,
                  ),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.music_note),
                ),
                title: Text(
                  currentSong.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Text(
                  currentSong.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          musicProvider.pause();
                        } else {
                          musicProvider.play();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
