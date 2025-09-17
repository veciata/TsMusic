import 'package:just_audio/just_audio.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/audio_notification_service.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  
  // Getters
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<bool> get playingStream => _audioPlayer.playingStream;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration get duration => _audioPlayer.duration ?? Duration.zero;
  LoopMode get loopMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;

  AudioService() {
    _initialize();
  }

  void _initialize() {
    AudioNotificationService.init(
      player: _audioPlayer,
      onCurrentSongChanged: (_) {},
      onPlaybackStateChanged: (_) {},
    );

    _audioPlayer.loopModeStream.listen((mode) {
      _loopMode = mode;
    });

    _audioPlayer.shuffleModeEnabledStream.listen((enabled) {
      _shuffleEnabled = enabled;
    });
  }

  Future<void> setAudioSource(Song song) async {
    if (song.isLocalFile) {
      await _audioPlayer.setFilePath(song.filePath);
    } else {
      await _audioPlayer.setUrl(song.url);
    }
    await _updateNotification(song);
  }

  Future<void> _updateNotification(Song? song) async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && song != null) {
      await audioHandler.setAudioSource(
        AudioSource.uri(Uri.parse(song.url)),
        song: song,
      );
      if (_audioPlayer.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  Future<void> play() async => await _audioPlayer.play();
  Future<void> pause() async => await _audioPlayer.pause();
  Future<void> stop() async => await _audioPlayer.stop();
  Future<void> seek(Duration position) async => await _audioPlayer.seek(position);
  
  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    await _audioPlayer.setShuffleModeEnabled(enabled);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _audioPlayer.setLoopMode(mode);
  }

  void dispose() {
    AudioNotificationService.dispose();
    _audioPlayer.dispose();
  }
}
