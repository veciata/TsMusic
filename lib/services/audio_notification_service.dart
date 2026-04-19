import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/song.dart';

class AudioPlayerTask extends BaseAudioHandler {
  final Player _player;
  final Function(Song?) onCurrentSongChanged;
  final Function(bool) onPlaybackStateChanged;
  
  AudioPlayerTask(this._player, this.onCurrentSongChanged, this.onPlaybackStateChanged) {
    _player.stream.playing.listen(_onPlaybackStateChanged);
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
  }

  @override
  Future<void> skipToNext() async {
    // Skip to next logic handled by playlist
  }

  @override
  Future<void> skipToPrevious() async {
    // Skip to previous logic handled by playlist
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  void _onPlaybackStateChanged(dynamic event) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.state.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _getProcessingState(),
      playing: _player.state.playing,
      updatePosition: _player.state.position ?? Duration.zero,
      bufferedPosition: (_player.state.buffer?.inMilliseconds ?? 0) > 0 
          ? _player.state.buffer! 
          : Duration.zero,
      speed: _player.state.rate ?? 1.0,
      queueIndex: 0,
    ),);
  }

  AudioProcessingState _getProcessingState() {
    // Simplified processing state detection for media_kit
    return AudioProcessingState.ready;
  }

  Future<void> setMedia(Media media, {Song? song}) async {
    await _player.open(media);
    if (song != null) {
      try {
        final title = song.title.isNotEmpty ? song.title : 'Unknown Title';
        final artist = song.artists.isNotEmpty ? song.artists.first : 'Unknown Artist';
        
        final artUri = song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty 
            ? Uri.parse(song.albumArtUrl!) 
            : null;
            
        mediaItem.add(MediaItem(
          id: song.id.toString(),
          title: title,
          artist: artist,
          artUri: artUri,
          duration: song.duration > 0 ? Duration(milliseconds: song.duration) : null,
        ));
        onCurrentSongChanged(song);
      } catch (e) {
        debugPrint('Error setting media item: $e');
      }
    }
  }

  Future<void> disposePlayer() async {
    await _player.dispose();
  }
}

class AudioNotificationService {
  static AudioPlayerTask? _audioHandler;
  static AudioPlayerTask? get audioHandler => _audioHandler;

  static Future<AudioPlayerTask> init({
    required Player player,
    required Function(Song?) onCurrentSongChanged,
    required Function(bool) onPlaybackStateChanged,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    
    _audioHandler = AudioPlayerTask(
      player,
      onCurrentSongChanged,
      onPlaybackStateChanged,
    );
    
    return _audioHandler!;
  }

  static Future<void> dispose() async {
    await _audioHandler?.disposePlayer();
    _audioHandler = null;
  }
}
