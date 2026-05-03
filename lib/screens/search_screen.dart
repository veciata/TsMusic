import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:tsmusic/providers/music_provider.dart' as music_provider;
import 'package:tsmusic/providers/settings_provider.dart';
import 'package:tsmusic/providers/youtube_player_provider.dart';
import 'package:tsmusic/models/song.dart' as model;
import 'package:tsmusic/services/youtube_service.dart';
import 'package:tsmusic/widgets/mini_player_widget.dart';
import 'package:tsmusic/widgets/youtube_playback_widget.dart';


class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final YouTubeService _youTubeService;
  late final YouTubePlayerProvider _youtubePlayer;
  List<YouTubeAudio> _youtubeResults = [];
  bool _isSearchingYouTube = false;
  bool _isOffline = false;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  bool _hasMoreYouTubeResults = true;
  Timer? _debounceTimer;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _youTubeService = context.read<YouTubeService>();
    _youtubePlayer = context.read<YouTubePlayerProvider>();
    _youtubePlayer.registerScreen('search_screen');
    _searchFocusNode.requestFocus();
    _scrollController.addListener(_onScroll);
    
    // Check initial connectivity status
    _checkConnectivity();
    
    // Subscribe to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      _checkConnectivity();
    });
  }



  @override
  void dispose() {
    _youtubePlayer.unregisterScreen('search_screen');
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchScrollController.dispose();
    _debounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOffline = result == ConnectivityResult.none;
        });
      }
    } catch (e) {
      // Handle connectivity check errors (common on web)
      if (mounted) {
        setState(() {
          // Assume online if we can't determine connectivity
          _isOffline = false;
        });
      }
    }
  }

  Future<void> _playAudio(YouTubeAudio audio) async {
    try {
      await _youtubePlayer.playAudio(audio);
    } catch (e) {
      if (mounted) {
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
        final errorStr = e.toString().toLowerCase();
        final isHtmlError = errorStr.contains('youtube_html_error') ||
            errorStr.contains('html') ||
            errorStr.contains('ip') ||
            errorStr.contains('consent') ||
            errorStr.contains('blocked') ||
            errorStr.contains('unavailable');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isHtmlError
                        ? 'Download unavailable. Please try again later.'
                        : 'Download failed: $e',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_searchController.text.isNotEmpty && !_isSearchingYouTube && _hasMoreYouTubeResults) {
        _searchYouTube(_searchController.text, loadMore: true);
      }
    }
  }

  Future<void> _searchYouTube(String query, {bool loadMore = false}) async {
    // Don't search YouTube if offline
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _isSearchingYouTube = false;
        });
      }
      return;
    }
    
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
      final List<YouTubeAudio> response = loadMore 
          ? await _youTubeService.searchAudioNextPage(query)
          : await _youTubeService.searchAudio(query);

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
                debugPrint('🔍 SearchScreen onTap: ${song.title} (URL: ${song.url})');
                if (isCurrent) {
                  if (isSongPlaying) {
                    debugPrint('🔍 SearchScreen: Pausing current song');
                    provider.pause();
                  } else {
                    debugPrint('🔍 SearchScreen: Resuming current song');
                    provider.play();
                  }
                } else {
                  debugPrint('🔍 SearchScreen: Playing new song');
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
          if (_hasMoreYouTubeResults && !_isSearchingYouTube)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
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
    return YouTubePlaybackWidget(
      audio: audio,
      onPlay: _playAudio,
      onDownload: _handleDownload,
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
        // Stop YouTube player when leaving search screen
        await _youtubePlayer.stop();
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
              // Stop YouTube player when going back
              _youtubePlayer.stop();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _buildSearchResults(localSongs, musicProvider, currentSong, isPlaying),
            ),
            // Always show mini player at bottom
            const MiniPlayerWidget(),
            // Show offline status if applicable
            if (_isOffline)
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[900],
                child: Center(
                  child: Text(
                    'Offline Mode - Showing local results only',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
