import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tsmusic/providers/music_provider.dart';
import 'package:tsmusic/providers/theme_provider.dart';
import 'package:tsmusic/models/player_styles.dart';
import 'package:tsmusic/models/style_params.dart';
import 'package:tsmusic/widgets/now_playing_queue_bottom_sheet.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/utils/format_utils.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  AnimationController? _albumArtController;
  double _currentPosition = 0.0;
  bool _isDragging = false;

  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _albumArtController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _startOrStopAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final musicProvider = context.watch<MusicProvider>();
    _positionSubscription?.cancel();
    _positionSubscription = musicProvider.positionStream.listen((position) {
      if (!_isDragging) {
        setState(() {
          _currentPosition = position.inSeconds.toDouble();
        });
      }
    });
  }

  void _startOrStopAnimation() {
    final musicProvider = context.read<MusicProvider>();
    if (musicProvider.isPlaying) {
      _albumArtController?.repeat();
    } else {
      _albumArtController?.stop();
    }
  }

  @override
  void dispose() {
    _albumArtController?.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  Widget _buildAlbumArt(
    ThemeData theme,
    String? albumArtUrl,
    String title, {
    bool circular = false,
    bool spin = true,
    double size = 280,
  }) {
    final Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
        image: albumArtUrl != null
            ? DecorationImage(
                image: NetworkImage(albumArtUrl),
                fit: BoxFit.cover,
              )
            : null,
        color: albumArtUrl == null ? theme.colorScheme.primaryContainer : null,
      ),
      child: albumArtUrl == null
          ? Center(
              child: Icon(
                Icons.music_note,
                size: 80,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );

    if (!spin) return content;

    return AnimatedBuilder(
      animation:
          _albumArtController ??
          AnimationController(
            vsync: this,
            duration: const Duration(seconds: 20),
          ),
      builder: (context, child) {
        final controller =
            _albumArtController ??
            AnimationController(
              vsync: this,
              duration: const Duration(seconds: 20),
            );
        return Transform.rotate(
          angle: controller.value * 2 * 3.14159,
          child: content,
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
    Color? color,
  }) => IconButton(
    icon: Icon(icon, size: size),
    color: color,
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = context.watch<MusicProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final currentSong = musicProvider.currentSong;
    final playerStyle = themeProvider.playerStyle;
    final l10n = AppLocalizations.of(context);

    if (currentSong == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.music_off,
                size: 80,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.notPlaying,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.selectSongToPlay,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final duration = musicProvider.duration.inSeconds;
    final albumArtUrl = currentSong.albumArtUrl;

    final header = _buildHeader(theme, l10n);
    final albumArt = _buildAlbumArt(
      theme,
      albumArtUrl,
      currentSong.title,
      circular: playerStyle == PlayerStyle.classic,
      spin: playerStyle == PlayerStyle.classic,
    );
    final progressBar = _buildProgressBar(theme, duration, musicProvider);
    final playbackControls = _buildPlaybackControls(theme, musicProvider);
    final bottomControls = _buildBottomControls(theme, musicProvider);

    final params = StyleParams(
      theme: theme,
      musicProvider: musicProvider,
      currentSong: currentSong,
      albumArtUrl: albumArtUrl,
      duration: duration,
      currentPosition: _currentPosition,
      onSeek: (value) {
        setState(() {
          _currentPosition = value;
          _isDragging = true;
        });
      },
      togglePlay: () {
        if (musicProvider.isPlaying) {
          musicProvider.pause();
        } else {
          musicProvider.play();
        }
        _startOrStopAnimation();
      },
      formatDuration: formatDurationFromSeconds,
      albumArt: albumArt,
      header: header,
      progressBar: progressBar,
      playbackControls: playbackControls,
      bottomControls: bottomControls,
    );

    Widget playerWidget;
    switch (playerStyle) {
      case PlayerStyle.classic:
        playerWidget = buildClassicStyle(params);
      case PlayerStyle.modern:
        playerWidget = buildModernStyle(params);
      case PlayerStyle.minimal:
        playerWidget = buildMinimalStyle(params);
      case PlayerStyle.square:
        playerWidget = buildSquareStyle(params);
      case PlayerStyle.glass:
        playerWidget = buildGlassStyle(params);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_downward),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.nowPlaying),
        centerTitle: true,
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return IconButton(
                icon: const Icon(Icons.palette),
                onPressed: () =>
                    _showStyleSelector(context, themeProvider, l10n),
              );
            },
          ),
        ],
      ),
      body: playerWidget,
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.all(16.0),
    child: Row(
      children: [
        const SizedBox(width: 48),
        const Spacer(),
        Text(
          l10n.nowPlaying,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    ),
  );

  Widget _buildProgressBar(
    ThemeData theme,
    int duration,
    MusicProvider musicProvider,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        Slider(
          value: _currentPosition,
          max: duration.toDouble(),
          onChanged: (value) {
            setState(() {
              _currentPosition = value;
              _isDragging = true;
            });
          },
          onChangeEnd: (value) {
            musicProvider.seek(Duration(seconds: value.toInt()));
            setState(() => _isDragging = false);
          },
          activeColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.onSurface.withOpacity(0.3),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDurationFromSeconds(_currentPosition.toInt())),
              Text(formatDurationFromSeconds(duration)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildPlaybackControls(
    ThemeData theme,
    MusicProvider musicProvider, {
    bool compact = false,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: 32, horizontal: compact ? 0 : 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: Icons.shuffle,
          onPressed: musicProvider.toggleShuffle,
          color: musicProvider.shuffleEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.7),
        ),
        _buildControlButton(
          icon: Icons.skip_previous,
          size: compact ? 28 : 32,
          onPressed: musicProvider.previous,
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
              size: compact ? 28 : 32,
            ),
            color: theme.colorScheme.onPrimary,
            onPressed: () {
              if (musicProvider.isPlaying) {
                musicProvider.pause();
              } else {
                musicProvider.play();
              }
              _startOrStopAnimation();
            },
          ),
        ),
        _buildControlButton(
          icon: Icons.skip_next,
          size: compact ? 28 : 32,
          onPressed: musicProvider.next,
        ),
        _buildControlButton(
          icon: musicProvider.loopMode == PlaylistMode.single
              ? Icons.repeat_one
              : Icons.repeat,
          onPressed: musicProvider.cycleRepeatMode,
          color: musicProvider.loopMode != PlaylistMode.none
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.7),
        ),
      ],
    ),
  );

  Widget _buildBottomControls(ThemeData theme, MusicProvider musicProvider) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.queue_music),
              onPressed: () {
                showNowPlayingQueue(context);
              },
              tooltip: AppLocalizations.of(context).queue,
            ),
          ],
        ),
      );

  void _showStyleSelector(
    BuildContext context,
    ThemeProvider themeProvider,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.playerStyle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...PlayerStyle.values.map((style) {
              final isSelected = style == themeProvider.playerStyle;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(style.displayName),
                onTap: () {
                  themeProvider.setPlayerStyle(style);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
