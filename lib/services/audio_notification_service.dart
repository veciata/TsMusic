import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/core/services/error_tracking_service.dart';
import 'package:tsmusic/services/notification_settings.dart';
import 'package:flutter/services.dart';
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final Player _player;
  final Function(Song?) onCurrentSongChanged;
  final Function(bool) onPlaybackStateChanged;
  final Function()? onSkipToNext;
  final Function()? onSkipToPrevious;
  final Function(Song, bool)? onOnlineMediaChanged;
  Song? _currentSong;
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
  void setOnlineMedia(Song song, {required bool isPlaying}) {
    _currentSong = song;
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
    _player.stream.playing.listen(_updatePlaybackState);
    _player.stream.position.listen(_updatePosition);
    _player.stream.duration.listen(_updateDuration);
    _player.stream.buffer.listen(_updateBuffer);
    _updatePlaybackState(_player.state.playing);
  }
  @override
  Future<void> play() async {
    await _player.play();
    onPlaybackStateChanged(true);
  }
  @override
  Future<void> pause() async {
    await _player.pause();
    onPlaybackStateChanged(false);
  }
  @override
  Future<void> stop() async {
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
    if (onSkipToNext != null) {
      onSkipToNext!();
    } else {
      onCurrentSongChanged(null);
    }
  }
  @override
  Future<void> skipToPrevious() async {
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
    final controls = [
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
        updatePosition: _player.state.position,
        bufferedPosition: _player.state.buffer,
        speed: _player.state.rate,
        queueIndex: 0,
      ),
    );
  }
  void _updatePosition(Duration position) {
    final state = playbackState.value;
    playbackState.add(state.copyWith(updatePosition: position));
  }
  void _updateDuration(Duration? duration) {
    if (duration != null && _currentSong != null) {
      mediaItem.add(_createMediaItem(_currentSong!, duration));
    }
  }
  void _updateBuffer(Duration buffer) {
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
class AudioNotificationService {
  static AudioPlayerHandler? _audioHandler;
  static AudioPlayerHandler? get audioHandler => _audioHandler;
  static Future<AudioPlayerHandler?> init({
    required Player player,
    required Function(Song?) onCurrentSongChanged,
    required Function(bool) onPlaybackStateChanged,
    Function()? onSkipToNext,
    Function()? onSkipToPrevious,
    Color? notificationColor,
    Function(Song, bool)? onOnlineMediaChanged,
  }) async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
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
          config: getNotificationSettings(notificationColor: notificationColor),
        );
        if (_audioHandler == null) {
          throw Exception('AudioService.init() returned null');
        }
        return _audioHandler;
      } catch (e) {
        if (e is PlatformException) {
        }
        rethrow;
      }
    } catch (e, stackTrace) {
      ErrorTrackingService().recordError(
        e,
        stackTrace,
        context: 'AudioPlayerHandler.load',
      );
      return null;
    }
  }
  static Future<void> dispose() async {
    await _audioHandler?.disposePlayer();
    await _audioHandler?.stop();
    _audioHandler = null;
  }
}
