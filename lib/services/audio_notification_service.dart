import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/song.dart';

/// Audio handler that integrates MediaKit with audio_service for system notifications
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final Player _player;
  final Function(Song?) onCurrentSongChanged;
  final Function(bool) onPlaybackStateChanged;
  Song? _currentSong;
  
  AudioPlayerHandler(this._player, this.onCurrentSongChanged, this.onPlaybackStateChanged) {
    _init();
  }

  void _init() {
    // Listen to player state changes and update notification
    _player.stream.playing.listen(_updatePlaybackState);
    _player.stream.position.listen(_updatePosition);
    _player.stream.duration.listen(_updateDuration);
    _player.stream.buffer.listen(_updateBuffer);
    
    // Set initial playback state
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
    // Handled by playlist manager
    onCurrentSongChanged(null);
  }

  @override
  Future<void> skipToPrevious() async {
    // Handled by playlist manager
    onCurrentSongChanged(null);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  void _updatePlaybackState(bool isPlaying) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(),
      playing: isPlaying,
      updatePosition: _player.state.position,
      bufferedPosition: _player.state.buffer,
      speed: _player.state.rate,
      queueIndex: 0,
    ));
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
    if (_player.state.playing) {
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
      artist: song.artists.isNotEmpty ? song.artists.join(', ') : 'Unknown Artist',
      album: song.album,
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
  static Future<AudioPlayerHandler> init({
    required Player player,
    required Function(Song?) onCurrentSongChanged,
    required Function(bool) onPlaybackStateChanged,
  }) async {
    // Configure audio session for music playback
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    
    // Initialize audio service
    _audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(
        player,
        onCurrentSongChanged,
        onPlaybackStateChanged,
      ),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.veciata.tsmusic.channel.audio',
        androidNotificationChannelName: 'TsMusic Playback',
        androidNotificationChannelDescription: 'TsMusic playback notification',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidShowNotificationBadge: true,
        notificationColor: Colors.blue,
      ),
    );
    
    return _audioHandler!;
  }

  static Future<void> dispose() async {
    await _audioHandler?.disposePlayer();
    await AudioService.stop();
    _audioHandler = null;
  }
}
