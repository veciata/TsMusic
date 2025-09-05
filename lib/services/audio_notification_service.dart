import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../models/song.dart';

class AudioPlayerTask extends BaseAudioHandler {
  final AudioPlayer _player;
  final Function(Song?) onCurrentSongChanged;
  final Function(bool) onPlaybackStateChanged;
  
  AudioPlayerTask(this._player, this.onCurrentSongChanged, this.onPlaybackStateChanged) {
    _player.playbackEventStream.listen(_onPlaybackStateChanged);
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
    // Implement skip to next logic
  }

  @override
  Future<void> skipToPrevious() async {
    // Implement skip to previous logic
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  void _onPlaybackStateChanged(PlaybackEvent event) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
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
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    ));
  }

  AudioProcessingState _getProcessingState() {
    if (_player.playing) {
      return AudioProcessingState.ready;
    } else if (_player.processingState == ProcessingState.completed) {
      return AudioProcessingState.completed;
    } else if (_player.processingState == ProcessingState.loading) {
      return AudioProcessingState.loading;
    } else {
      return AudioProcessingState.idle;
    }
  }

  Future<void> setAudioSource(AudioSource audioSource, {Song? song}) async {
    await _player.setAudioSource(audioSource);
    if (song != null) {
      mediaItem.add(MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.albumArtUrl != null ? Uri.parse(song.albumArtUrl!) : null,
      ));
      onCurrentSongChanged(song);
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
    required AudioPlayer player,
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
