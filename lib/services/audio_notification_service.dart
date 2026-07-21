import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/notification_settings.dart';
import 'package:flutter/services.dart';

/// Audio handler that integrates MediaKit with audio_service for system notifications
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final Player _player;
  final Function(Song?) onCurrentSongChanged;
  final Function(bool) onPlaybackStateChanged;
  final Function()? onSkipToNext;
  final Function()? onSkipToPrevious;
  final Function(Song, bool)? onOnlineMediaChanged;
  Song? _currentSong;

  bool _isOnlineMode = false;
  VoidCallback? _onOnlinePlay;
  VoidCallback? _onOnlinePause;
  Function()? _onOnlineStop;

  AudioPlayerHandler(
    this._player,
    this.onCurrentSongChanged,
    this.onPlaybackStateChanged, {
    this.onSkipToNext,
    this.onSkipToPrevious,
    this.onOnlineMediaChanged,
  }) : super() {
    _init();
  }

  bool get isOnlineMode => _isOnlineMode;

  void setOnlineMode({
    required bool online,
    VoidCallback? onPlay,
    VoidCallback? onPause,
    Function()? onStop,
  }) {
    _isOnlineMode = online;
    if (online) {
      _onOnlinePlay = onPlay;
      _onOnlinePause = onPause;
      _onOnlineStop = onStop;
    } else {
      _onOnlinePlay = null;
      _onOnlinePause = null;
      _onOnlineStop = null;
    }
    if (!online) {
      _updatePlaybackState(_player.state.playing);
    }
  }

  void setOnlineMedia(Song song, {required bool isPlaying}) {
    _currentSong = song;

    // Update the system notification with online song info
    final duration = song.duration > 0
        ? Duration(milliseconds: song.duration)
        : Duration.zero;
    final item = _createOnlineMediaItem(song, duration);
    mediaItem.add(item);
    queue.add([item]);

    _updatePlaybackState(isPlaying);

    onOnlineMediaChanged?.call(song, isPlaying);
  }

  void _init() {
    _player.stream.playing.listen((isPlaying) {
      if (!_isOnlineMode) {
        _updatePlaybackState(isPlaying);
      }
    });
    _player.stream.position.listen(_updatePosition);
    _player.stream.duration.listen(_updateDuration);
    _player.stream.buffer.listen(_updateBuffer);

    _updatePlaybackState(_player.state.playing);
  }

  @override
  Future<void> play() async {
    if (_isOnlineMode && _onOnlinePlay != null) {
      _onOnlinePlay!();
      return;
    }
    await _player.play();
    onPlaybackStateChanged(true);
  }

  @override
  Future<void> pause() async {
    if (_isOnlineMode && _onOnlinePause != null) {
      _onOnlinePause!();
      return;
    }
    await _player.pause();
    onPlaybackStateChanged(false);
  }

  @override
  Future<void> stop() async {
    if (_isOnlineMode && _onOnlineStop != null) {
      _onOnlineStop!();
      return;
    }
    await _player.stop();
    onPlaybackStateChanged(false);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_isOnlineMode && _onOnlineStop != null) {
      _onOnlineStop!();
      return;
    }
    if (onSkipToNext != null) {
      onSkipToNext!();
    } else {
      onCurrentSongChanged(null);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_isOnlineMode && _onOnlineStop != null) {
      _onOnlineStop!();
      return;
    }
    if (onSkipToPrevious != null) {
      onSkipToPrevious!();
    } else {
      onCurrentSongChanged(null);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  void _updatePlaybackState(bool isPlaying) {
    final controls = _isOnlineMode
        ? [
            isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.stop,
          ]
        : [
            isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.skipToPrevious,
            MediaControl.stop,
          ];
    final compactIndices = const [0, 1];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: compactIndices,
        processingState: _mapProcessingState(),
        playing: isPlaying,
        updatePosition: _isOnlineMode ? Duration.zero : _player.state.position,
        bufferedPosition: _isOnlineMode ? Duration.zero : _player.state.buffer,
        speed: _player.state.rate,
        queueIndex: 0,
      ),
    );
  }

  void _updatePosition(Duration position) {
    if (_isOnlineMode) return;
    final state = playbackState.value;
    playbackState.add(state.copyWith(updatePosition: position));
  }

  void _updateDuration(Duration? duration) {
    if (_isOnlineMode) return;
    if (duration != null && _currentSong != null) {
      mediaItem.add(_createMediaItem(_currentSong!, duration));
    }
  }

  void _updateBuffer(Duration buffer) {
    if (_isOnlineMode) return;
    final state = playbackState.value;
    playbackState.add(state.copyWith(bufferedPosition: buffer));
  }

  AudioProcessingState _mapProcessingState() {
    if (_player.state.buffering) {
      return AudioProcessingState.buffering;
    }
    if (mediaItem.value != null) {
      return AudioProcessingState.ready;
    }
    return AudioProcessingState.idle;
  }

  /// Set media and update notification with song info
  Future<void> setMedia(Media media, {Song? song}) async {
    _currentSong = song;
    await _player.open(media);

    if (song != null) {
      try {
        final duration = song.duration > 0
            ? Duration(milliseconds: song.duration)
            : _player.state.duration;

        mediaItem.add(_createMediaItem(song, duration));
        queue.add([_createMediaItem(song, duration)]);
        onCurrentSongChanged(song);
      } catch (e) {
        debugPrint('Error setting media item: $e');
      }
    }
  }

  MediaItem _createMediaItem(Song song, Duration? duration) {
    final artUri = song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
        ? Uri.parse(song.albumArtUrl!)
        : null;

    return MediaItem(
      id: song.id.toString(),
      title: song.title.isNotEmpty ? song.title : 'Unknown Title',
      artist: song.artists.isNotEmpty
          ? song.artists.join(', ')
          : 'Unknown Artist',
      album: song.album,
      artUri: artUri,
      duration: duration,
    );
  }

  MediaItem _createOnlineMediaItem(Song song, Duration? duration) {
    final artUri = song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
        ? Uri.parse(song.albumArtUrl!)
        : null;

    return MediaItem(
      id: 'yt:${song.youtubeId ?? song.id.toString()}',
      title: song.title.isNotEmpty ? song.title : 'Unknown Title',
      artist: song.artists.isNotEmpty
          ? song.artists.join(', ')
          : 'Unknown Artist',
      album: 'YouTube Music',
      artUri: artUri,
      duration: duration,
    );
  }

  Future<void> disposePlayer() async {
    await _player.dispose();
  }
}

/// Service to initialize and manage the audio notification
class AudioNotificationService {
  static AudioPlayerHandler? _audioHandler;
  static AudioPlayerHandler? get audioHandler => _audioHandler;

  /// Initialize audio service with MediaKit integration
  static Future<AudioPlayerHandler?> init({
    required Player player,
    required Function(Song?) onCurrentSongChanged,
    required Function(bool) onPlaybackStateChanged,
    Function()? onSkipToNext,
    Function()? onSkipToPrevious,
    Color? notificationColor,
    Function(Song, bool)? onOnlineMediaChanged,
  }) async {
    debugPrint('AudioNotificationService: init() called');
    try {
      debugPrint('AudioNotificationService: Getting audio session...');
      final session = await AudioSession.instance;
      debugPrint('AudioNotificationService: Got session, configuring...');
      await session.configure(const AudioSessionConfiguration.music());
      debugPrint('AudioNotificationService: Audio session configured');

      debugPrint('AudioNotificationService: Calling AudioService.init()...');
      // Initialize audio service with detailed error handling
      try {
        _audioHandler = await AudioService.init(
          builder: () => AudioPlayerHandler(
            player,
            onCurrentSongChanged,
            onPlaybackStateChanged,
            onSkipToNext: onSkipToNext,
            onSkipToPrevious: onSkipToPrevious,
            onOnlineMediaChanged: onOnlineMediaChanged,
          ),
          config: getNotificationSettings(
            notificationColor: notificationColor,
            fontSize: null, // Reserved for future implementation
          ),
        );
        debugPrint(
          'AudioNotificationService: AudioService.init() returned handler=$_audioHandler',
        );

        if (_audioHandler == null) {
          debugPrint('AudioNotificationService: WARNING - handler is null!');
          throw Exception('AudioService.init() returned null');
        }

        return _audioHandler;
      } catch (e) {
        debugPrint(
          'AudioNotificationService: Error during AudioService.init(): $e',
        );
        // Check if it's a platform exception
        if (e is PlatformException) {
          debugPrint(
            'AudioNotificationService: PlatformException code: ${e.code}, message: ${e.message}',
          );
        }
        rethrow;
      }
    } catch (e, stackTrace) {
      debugPrint('AudioNotificationService: Error initializing: $e');
      debugPrint('AudioNotificationService: Stack trace: $stackTrace');
      // If it's a platform exception, print more details
      if (e is PlatformException) {
        debugPrint(
          'AudioNotificationService: PlatformException code: ${e.code}, message: ${e.message}, details: ${e.details}',
        );
      }
      return null;
    }
  }

  static Future<void> dispose() async {
    await _audioHandler?.disposePlayer();
    await AudioService.stop();
    _audioHandler = null;
  }
}
