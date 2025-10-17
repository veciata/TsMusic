import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/theme_provider.dart';
import '../providers/music_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Use the same PlayerMode enum from music_provider
import '../providers/music_provider.dart' show PlayerMode;

class PlayerScreen extends StatefulWidget {
  final VoidCallback? onArtistTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<double>? onSeek;
  final bool isPlaying;

  const PlayerScreen({
    super.key,
    this.onArtistTap,
    this.onEqualizerTap,
    this.onPrevious,
    this.onNext,
    this.onSeek,
    this.isPlaying = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isFavorite = false;
  bool _isDownloaded = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  MusicFile? _currentSong;
  
  // Animation controllers
  late final AnimationController _progressController;
  late final AnimationController _albumArtController;
  
  @override
  void dispose() {
    _progressController.dispose();
    _albumArtController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Initialize with default values
    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    final musicProvider = context.read<MusicProvider>();
    
    // Listen to player state changes
    musicProvider.playbackStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _position = state.position;
          _duration = state.duration;
          _currentSong = musicProvider.currentSong;
        });
      }
    });
    
    // Initialize with current values
    if (musicProvider.currentSong != null) {
      _currentSong = musicProvider.currentSong;
    }
    _isPlaying = musicProvider.isPlaying;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  Widget _buildPlayerModeIcon(PlayerMode mode, ThemeData theme) {
    switch (mode) {
      case PlayerMode.repeatOne:
        return const Icon(Icons.repeat_one);
      case PlayerMode.repeatAll:
        return const Icon(Icons.repeat);
      case PlayerMode.playAll:
        return const Icon(Icons.playlist_play);
      case PlayerMode.playOne:
        return const Icon(Icons.play_arrow);
    }
  }

  String _getPlayerModeTooltip(PlayerMode mode) {
    switch (mode) {
      case PlayerMode.repeatOne:
        return 'Repeat One';
      case PlayerMode.repeatAll:
        return 'Repeat All';
      case PlayerMode.playAll:
        return 'Play All';
      case PlayerMode.playOne:
        return 'Play Once';
    }
  }
  
  Widget _buildDefaultAlbumArt() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: 100,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
  
  Widget _buildModernStyle(
    BuildContext context,
    MusicFile currentSong,
    bool isPlaying,
    MusicProvider musicProvider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Get song metadata
    final songTitle = currentSong.title;
    final artistName = currentSong.artist ?? 'Unknown Artist';
    final albumName = currentSong.album ?? 'Unknown Album';
    
    return SafeArea(
      child: Column(
        children: [
          // Album Art with Gradient Overlay
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Album Art Background
                currentSong.artworkPath != null
                    ? Image.file(
                        File(currentSong.artworkPath!), 
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildDefaultAlbumArt(),
                      )
                    : _buildDefaultAlbumArt(),
                
                // Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Text(
                            'NOW PLAYING',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_play, color: Colors.white),
                            onPressed: () => _showNowPlayingQueue(context, musicProvider),
                          ),
                        ],
                      ),
                      
                      const Spacer(),
                      
                      // Song Info
                      Text(
                        songTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: widget.onArtistTap,
                        child: Text(
                          artistName,
                          style: TextStyle(
                            color: colorScheme.primary.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              children: [
                // Progress Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    min: 0.0,
                    max: _duration.inMilliseconds.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _position = Duration(milliseconds: value.toInt());
                      });
                    },
                    onChangeEnd: (value) {
                      _seekTo(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),
                
                // Time Indicators
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Control Buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 30.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: musicProvider.isShuffleModeEnabled 
                        ? Colors.white 
                        : Colors.white70,
                    size: 24,
                  ),
                  onPressed: () {
                    musicProvider.toggleShuffleMode();
                  },
                ),
                
                // Previous
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 32, color: Colors.white),
                  onPressed: _playPrevious,
                ),
                
                // Play/Pause
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 36,
                      color: Colors.black87,
                    ),
                    onPressed: _playPause,
                  ),
                ),
                
                // Next
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 32, color: Colors.white),
                  onPressed: _playNext,
                ),
                
                // Repeat
                IconButton(
                  icon: Icon(
                    _playerMode == PlayerMode.repeatOne 
                        ? Icons.repeat_one 
                        : Icons.repeat,
                    color: _playerMode == PlayerMode.repeatOne || _playerMode == PlayerMode.repeatAll
                        ? Colors.white
                        : Colors.white70,
                    size: 24,
                  ),
                  onPressed: _cyclePlayerMode,
                ),
              ],
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              border: Border(
                top: BorderSide(color: Colors.white12, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Favorite Button
                IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : Colors.white70,
                    size: 24,
                  ),
                  onPressed: _toggleFavorite,
                ),
                
                // Equalizer Button
                IconButton(
                  icon: const Icon(Icons.equalizer, color: Colors.white70, size: 24),
                  onPressed: widget.onEqualizerTap,
                ),
                
                // Download Button
                IconButton(
                  icon: Icon(
                    _isDownloaded ? Icons.download_done : Icons.download,
                    color: _isDownloaded ? colorScheme.primary : Colors.white70,
                    size: 24,
                  ),
                  onPressed: _toggleDownload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite() {
    final musicProvider = context.read<MusicProvider>();
    if (musicProvider.currentSong != null) {
      musicProvider.toggleFavorite(musicProvider.currentSong!);
      setState(() {
        _isFavorite = !_isFavorite;
      });
    }
  }

  void _toggleDownload() {
    final musicProvider = context.read<MusicProvider>();
    if (musicProvider.currentSong != null) {
      setState(() {
        _isDownloaded = !_isDownloaded;
        // TODO: Implement download functionality in MusicProvider
      });
    }
  }

  void _playPause() {
    final musicProvider = context.read<MusicProvider>();
    if (widget.isPlaying) {
      musicProvider.pause();
    } else {
      musicProvider.play();
    }
  }

  void _playNext() {
    widget.onNext?.call();
  }

  void _playPrevious() {
    widget.onPrevious?.call();
  }

  void _seekTo(Duration position) {
    context.read<MusicProvider>().seek(position);
  }

  void _cyclePlayerMode() {
    final musicProvider = context.read<MusicProvider>();
    final currentMode = musicProvider.playerMode;
    final nextIndex = (currentMode.index + 1) % PlayerMode.values.length;
    musicProvider.setPlayMode(PlayerMode.values[nextIndex]);
  }

  void _showNowPlayingQueue(BuildContext context, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final songs = musicProvider.songs;
          final currentIndex = musicProvider.currentIndex;

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Now Playing Queue',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${songs.length} songs',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: songs.isEmpty
                    ? const Center(child: Text('No songs in queue'))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          final isCurrent = index == currentIndex;

                          return ListTile(
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Theme.of(context).primaryColor.withOpacity(0.2)
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: isCurrent
                                  ? Icon(
                                      Icons.music_note,
                                      color: Theme.of(context).primaryColor,
                                    )
                                  : const Icon(Icons.music_note_outlined),
                            ),
                            title: Text(
                              song.title,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                            subtitle: Text(
                              song.artist,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: isCurrent
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).hintColor,
                              ),
                            ),
                            trailing: Text(
                              song.duration.toString().split('.').first.padLeft(8, '0:') ?? '--:--',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            onTap: () {
                              musicProvider.playSong(song, index: index);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlayerContent(ThemeProvider themeProvider, MusicProvider musicProvider, ThemeData theme, ColorScheme colorScheme) {
    if (_currentSong == null) {
      return const Center(
        child: Text('No song is currently playing'),
      );
    }

    switch (themeProvider.playerStyle) {
      case PlayerStyle.classic:
        return _buildClassicStyle(context, _currentSong!, _isPlaying, musicProvider);
      case PlayerStyle.modern:
        return _buildModernStyle(context, _currentSong!, _isPlaying, musicProvider);
      case PlayerStyle.compact:
        return _buildCompactStyle(context, _currentSong!, _isPlaying, musicProvider);
      case PlayerStyle.minimal:
        return _buildMinimalStyle(context, _currentSong!, _isPlaying, musicProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, MusicProvider>(
      builder: (context, themeProvider, musicProvider, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        // Update local state from music provider
        if (musicProvider.currentSong != _currentSong) {
          _currentSong = musicProvider.currentSong;
          _isPlaying = musicProvider.isPlaying;
          _position = musicProvider.position;
          _duration = musicProvider.duration;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Now Playing'),
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_play),
                onPressed: () => _showNowPlayingQueue(context, musicProvider),
                tooltip: 'Now Playing Queue',
              ),
            ],
          ),
          body: _buildPlayerContent(themeProvider, musicProvider, theme, colorScheme),
        );
      },
    );
  }

  Widget _buildClassicStyle(
    BuildContext context,
    MusicFile currentSong,
    bool isPlaying,
    MusicProvider musicProvider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get song metadata
    final songTitle = currentSong.title;
    final artistName = currentSong.artist ?? 'Unknown Artist';
    final albumName = currentSong.album ?? 'Unknown Album';
    final duration = _duration;
    final position = _position;

    // Build album art widget
    Widget albumArt = Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.width * 0.8,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: currentSong.artworkPath != null
            ? Image.file(
                File(currentSong.artworkPath!), 
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildDefaultAlbumArt(),
              )
            : _buildDefaultAlbumArt(),
      ),
    );

    // Build progress bar
    Widget progressBar = Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: colorScheme.primary,
            inactiveTrackColor: colorScheme.surfaceContainerHighest,
            thumbColor: colorScheme.primary,
            overlayColor: colorScheme.primary.withOpacity(0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
          ),
          child: Slider(
            value: position.inMilliseconds.toDouble(),
            min: 0.0,
            max: duration.inMilliseconds.toDouble(),
            onChanged: (value) {
              // Update position while dragging
              setState(() {
                _position = Duration(milliseconds: value.toInt());
              });
            },
            onChangeEnd: (value) {
              // Seek to new position when user stops dragging
              _seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
      ],
    );

    // Build control buttons
    Widget controlButtons = Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle button
          IconButton(
            icon: Icon(
              Icons.shuffle,
              color: musicProvider.isShuffleModeEnabled 
                  ? colorScheme.primary 
                  : theme.iconTheme.color,
            ),
            onPressed: () {
              musicProvider.toggleShuffleMode();
            },
            tooltip: 'Shuffle',
          ),
          
          // Previous button
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 32),
            onPressed: _playPrevious,
            tooltip: 'Previous',
          ),
          
          // Play/Pause button
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                size: 40,
                color: colorScheme.onPrimary,
              ),
              onPressed: _playPause,
              tooltip: _isPlaying ? 'Pause' : 'Play',
            ),
          ),
          
          // Next button
          IconButton(
            icon: const Icon(Icons.skip_next, size: 32),
            onPressed: _playNext,
            tooltip: 'Next',
          ),
          
          // Repeat button
          StreamBuilder<PlayerMode>(
            stream: musicProvider.playerModeStream,
            builder: (context, snapshot) {
              final playerMode = snapshot.data ?? PlayerMode.playAll;
              return IconButton(
                icon: _buildPlayerModeIcon(playerMode, theme),
                onPressed: () {
                  final nextMode = PlayerMode.values[(playerMode.index + 1) % PlayerMode.values.length];
                  musicProvider.setPlayMode(nextMode);
                },
                tooltip: _getPlayerModeTooltip(playerMode),
              );
            },
          ),
        ],
      ),
    );

    // Build song info
    Widget songInfo = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Column(
        children: [
          // Song title with favorite button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  songTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  // Download button
                  IconButton(
                    icon: Icon(
                      _isDownloaded ? Icons.download_done : Icons.download,
                      color: _isDownloaded ? colorScheme.primary : null,
                    ),
                    onPressed: _toggleDownload,
                    tooltip: _isDownloaded ? 'Downloaded' : 'Download',
                  ),
                  // Favorite button
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? Colors.red : null,
                    ),
                    onPressed: _toggleFavorite,
                    tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
                  ),
                ],
              ),
            ],
          ),
          
          // Artist and album info
          const SizedBox(height: 8),
          Row(
            children: [
              // Artist button
              TextButton(
                onPressed: () {
                  // TODO: Navigate to artist page
                  if (widget.onArtistTap != null) {
                    widget.onArtistTap!();
                  }
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  artistName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Text(' • '),
              // Album name
              Expanded(
                child: Text(
                  albumName,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Main content
    return SafeArea(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight,
          ),
          child: Column(
            children: [
              // Album Art
              albumArt,
              
              // Song Info
              songInfo,
              
              // Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: progressBar,
              ),
              
              // Control Buttons
              controlButtons,
              
              // Additional Controls (if any)
              // ...
              
              // Equalizer Button at the bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
                child: IconButton(
                  icon: const Icon(Icons.equalizer, size: 28),
                  onPressed: widget.onEqualizerTap,
                  tooltip: 'Equalizer',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Style - Clean and minimal with gestures
  Widget _buildModernStyle(
    BuildContext context,
    ThemeProvider themeProvider,
    MusicProvider musicProvider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final currentSong = musicProvider.currentSong;
    if (currentSong == null) {
      return const Center(child: Text('No song selected'));
    }

    return SafeArea(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.topCenter,
            children: [
              // Album Art
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.width * 0.9,
                margin: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: (currentSong.artworkPath != null)
                      ? Image.file(
                          File(currentSong.artworkPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildDefaultAlbumArt(),
                        )
                      : _buildDefaultAlbumArt(),
                ),
              ),
              // Favorite and Download Buttons
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    // Favorite Button
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: _isFavorite ? Colors.red : Colors.white,
                        ),
                        onPressed: _toggleFavorite,
                      ),
                    ),
                    // Download Button
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isDownloaded ? Icons.download_done : Icons.download,
                          color: _isDownloaded ? colorScheme.primary : Colors.white,
                        ),
                        onPressed: _toggleDownload,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Song Info
          Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    children: [
                      Text(
                        currentSong.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Artist as Button
                      TextButton(
                        onPressed: widget.onArtistTap,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          currentSong.artist,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor: theme.disabledColor,
                          thumbColor: colorScheme.primary,
                          overlayColor: colorScheme.primary.withOpacity(0.2),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16.0,
                          ),
                        ),
                        child: Slider(
                          value: musicProvider.position.inMilliseconds.toDouble(),
                          min: 0,
                          max: musicProvider.duration.inMilliseconds > 0
                              ? musicProvider.duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: (value) {
                            if (widget.onSeek != null) {
                              widget.onSeek!(value);
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(musicProvider.position)),
                            Text(_formatDuration(musicProvider.duration)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Player Mode and Controls
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 32.0,
                  ),
                  child: Column(
                    children: [
                      // Player Mode
                      StreamBuilder<PlayerMode>(
                        stream: musicProvider.playerModeStream,
                        builder: (context, snapshot) {
                          final playerMode = snapshot.data ?? PlayerMode.playAll;
                          return IconButton(
                            icon: _buildPlayerModeIcon(playerMode, theme),
                            onPressed: () {
                              final nextMode = PlayerMode.values[(playerMode.index + 1) % PlayerMode.values.length];
                              musicProvider.setPlayMode(nextMode);
                            },
                            tooltip: _getPlayerModeTooltip(playerMode),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Playback Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Previous Button
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 36),
                            onPressed: widget.onPrevious,
                          ),
                          // Play/Pause Button
                          IconButton(
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              size: 64,
                              color: colorScheme.primary,
                            ),
                            onPressed: _playPause,
                          ),
                          // Next Button
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 36),
                            onPressed: widget.onNext,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16), // Add some bottom padding
              ],
            ),
          ),
        ),
      ),
    )
  }

// Modern Style - Clean and minimal with gestures
Widget _buildModernStyle(
  BuildContext context,
  ThemeProvider themeProvider,
  MusicProvider musicProvider,
  ThemeData theme,
  ColorScheme colorScheme,
) {
  final currentSong = musicProvider.currentSong;
  if (currentSong == null) {
    return const Center(child: Text('No song selected'));
  }
  
  return SafeArea(
    child: Column(
      children: [
        // App Bar
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_downward_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            children: [
              Text(
                'NOW PLAYING',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'From Your Library',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                // Show more options
              },
            ),
          ],
        ),
        
        // Album Art
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: currentSong.artworkPath != null
                      ? Image.file(
                          File(currentSong.artworkPath!), 
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildDefaultAlbumArt(),
                        )
                      : _buildDefaultAlbumArt(),
                ),
              ),
            ),
          ),
        ),
        
        // Song Info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
          child: Column(
            children: [
              Text(
                currentSong.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                currentSong.artist ?? 'Unknown Artist',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        
        // Progress Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
          child: Column(
            children: [
              // Progress Bar
              StreamBuilder<Duration>(
                stream: musicProvider.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration?>(
                    stream: musicProvider.durationStream,
                    builder: (context, snapshot) {
                      final duration = snapshot.data ?? Duration.zero;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor: colorScheme.onSurface.withOpacity(0.1),
                              thumbColor: colorScheme.primary,
                              overlayColor: colorScheme.primary.withOpacity(0.2),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                            ),
                            child: Slider(
                              value: position.inMilliseconds.toDouble(),
                              min: 0,
                              max: duration.inMilliseconds.toDouble(),
                              onChanged: (value) {
                                musicProvider.seek(Duration(milliseconds: value.toInt()));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  '-${_formatDuration(duration - position)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        
        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Shuffle Button
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: musicProvider.isShuffling 
                      ? colorScheme.primary 
                      : theme.iconTheme.color,
                ),
                onPressed: musicProvider.toggleShuffleMode,
                tooltip: 'Shuffle',
              ),
              
              // Previous Button
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 32),
                onPressed: musicProvider.hasPrevious ? musicProvider.previous : null,
                tooltip: 'Previous',
              ),
              
              // Play/Pause Button
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    musicProvider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 36,
                  ),
                  color: colorScheme.onPrimary,
                  onPressed: musicProvider.togglePlayPause,
                  tooltip: musicProvider.isPlaying ? 'Pause' : 'Play',
                ),
              ),
              
              // Next Button
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 32),
                onPressed: musicProvider.hasNext ? musicProvider.next : null,
                tooltip: 'Next',
              ),
              
              // Repeat Button
              StreamBuilder<PlayerMode>(
                stream: musicProvider.playerModeStream,
                builder: (context, snapshot) {
                  final mode = snapshot.data ?? PlayerMode.playAll;
                  return IconButton(
                    icon: _buildPlayerModeIcon(mode, theme),
                    onPressed: () {
                      final nextMode = PlayerMode.values[(musicProvider.playerMode.index + 1) % PlayerMode.values.length];
                      musicProvider.setPlayMode(nextMode);
                    },
                    tooltip: _getPlayerModeTooltip(mode),
                  );
                },
              ),
            ],
          ),
        ),
        
        // Bottom Bar
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              // Album Art Thumbnail
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: currentSong.artworkPath != null
                      ? DecorationImage(
                          image: FileImage(File(currentSong.artworkPath!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: currentSong.artworkPath == null
                    ? const Icon(Icons.music_note, size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              
              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentSong.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      currentSong.artist ?? 'Unknown Artist',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Controls
              Row(
                children: [
                  // Favorite Button
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? Colors.red : theme.iconTheme.color,
                    ),
                    onPressed: _toggleFavorite,
                    tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
                  ),
                  
                  // Queue Button
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded),
                    onPressed: () => _showNowPlayingQueue(context, musicProvider),
                    tooltip: 'Queue',
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Now Playing',
              style: theme.textTheme.titleMedium,
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.queue_music),
                onPressed: () => _showNowPlayingQueue(context, musicProvider),
                tooltip: 'Now Playing Queue',
              ),
            ],
          ),
          
          // Album Art
          Expanded(
            child: Center(
              child: Hero(
                tag: 'album_art_${currentSong.id}',
                child: Container(
                  width: 300,
                  height: 300,
                  margin: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10.0,
                        spreadRadius: 2.0,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: currentSong.artworkPath != null
                        ? Image.file(
                            File(currentSong.artworkPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _buildDefaultAlbumArt(),
                          )
                        : _buildDefaultAlbumArt(),
                  ),
                ),
              ),
            ),
          ),
          
          // Song Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              children: [
                Text(
                  currentSong.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8.0),
                GestureDetector(
                  onTap: widget.onArtistTap,
                  child: Text(
                    currentSong.artist ?? 'Unknown Artist',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.titleMedium?.color?.withOpacity(0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          
          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: theme.disabledColor,
                    thumbColor: colorScheme.primary,
                    overlayColor: colorScheme.primary.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16.0,
                    ),
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    min: 0,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (value) {
                      final position = Duration(milliseconds: value.toInt());
                      musicProvider.seek(position);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position)),
                      Text(_formatDuration(_duration)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                StreamBuilder<AudioProcessingState>(
                  stream: musicProvider.playbackStateStream,
                  builder: (context, snapshot) {
                    final isShuffling = musicProvider.isShuffling;
                    return IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: isShuffling ? colorScheme.primary : theme.iconTheme.color,
                      ),
                      onPressed: musicProvider.toggleShuffleMode,
                      tooltip: 'Shuffle',
                    );
                  },
                ),
                
                // Previous
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 36.0),
                  onPressed: musicProvider.hasPrevious ? _playPrevious : null,
                  tooltip: 'Previous',
                ),
                
                // Play/Pause
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8.0,
                        spreadRadius: 2.0,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: colorScheme.onPrimary,
                      size: 48.0,
                    ),
                    onPressed: _playPause,
                    tooltip: isPlaying ? 'Pause' : 'Play',
                  ),
                ),
                
                // Next
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 36.0),
                  onPressed: musicProvider.hasNext ? _playNext : null,
                  tooltip: 'Next',
                ),
                
                // Repeat
                StreamBuilder<AudioProcessingState>(
                  stream: musicProvider.playbackStateStream,
                  builder: (context, snapshot) {
                    final loopMode = _playerMode;
                    return IconButton(
                      icon: _buildPlayerModeIcon(loopMode, theme),
                      onPressed: _cyclePlayerMode,
                      tooltip: _getPlayerModeTooltip(loopMode),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10.0,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Favorite
                IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : theme.iconTheme.color,
                  ),
                  onPressed: _toggleFavorite,
                  tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
                ),
                
                // Equalizer
                IconButton(
                  icon: const Icon(Icons.equalizer),
                  onPressed: widget.onEqualizerTap,
                  tooltip: 'Equalizer',
                ),
                
                // Download
                IconButton(
                  icon: Icon(
                    _isDownloaded ? Icons.download_done : Icons.download,
                    color: _isDownloaded ? colorScheme.primary : theme.iconTheme.color,
                  ),
                  onPressed: _toggleDownload,
                  tooltip: _isDownloaded ? 'Downloaded' : 'Download',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }

