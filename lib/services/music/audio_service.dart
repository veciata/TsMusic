import 'package:media_kit/media_kit.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/audio_notification_service.dart';

class AudioService {
  final Player _player = Player();
  PlaylistMode _loopMode = PlaylistMode.none;
  bool _shuffleEnabled = false;
  
  // Getters
  Stream<Duration> get positionStream => _player.stream.position;
  Stream<bool> get playingStream => _player.stream.playing;
  bool get isPlaying => _player.state.playing;
  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  PlaylistMode get loopMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;

  AudioService() {
    _initialize();
  }

  void _initialize() {
    _player.stream.playlistMode.listen((mode) {
      _loopMode = mode;
    });
  }

  Future<void> setAudioSource(Song song) async {
    final media = Media(song.url);
    await _player.open(media);
    await _updateNotification(song);
  }

  Future<void> _updateNotification(Song? song) async {
    // Update notification with current song info
    if (song != null) {
      // This would typically update the system notification
      // For now, basic notification handling
    }
  }

  Future<void> play() async => await _player.play();
  Future<void> pause() async => await _player.pause();
  Future<void> stop() async => await _player.stop();
  Future<void> seek(Duration position) async => await _player.seek(position);
  
  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    // Shuffle mode handling will be done at playlist level
  }

  Future<void> setLoopMode(PlaylistMode mode) async {
    _loopMode = mode;
    await _player.setPlaylistMode(mode);
  }

  void dispose() {
    _player.dispose();
  }
}
