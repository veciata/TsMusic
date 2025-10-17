import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../models/youtube_audio.dart';

class YoutubePlayerService extends ChangeNotifier {
  YoutubePlayerController? _controller;
  bool _isPlaying = false;
  YouTubeAudio? currentAudio;

  bool get isPlaying => _isPlaying;

  Duration get position => _controller?.value.position ?? Duration.zero;

  Duration get duration => _controller?.metadata.duration ?? Duration.zero;

  YoutubePlayerController? get controller => _controller;

  Future<void> playAudio(YouTubeAudio audio) async {
    debugPrint('youtube music video is trying to play: ${audio.id}');
    currentAudio = audio;
    await _disposeController();

    if (audio.id == null || audio.id!.isEmpty) return;

    _controller = YoutubePlayerController(
      initialVideoId: audio.id!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true, // Play muted for audio
      ),
    );

    _controller!.addListener(() {
      final wasPlaying = _isPlaying;
      _isPlaying = _controller!.value.isPlaying;
      if (wasPlaying != _isPlaying) {
        notifyListeners();
      }
    });

    _isPlaying = true;
    notifyListeners();
  }



  Future<void> play() async {
    _controller?.play();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    _controller?.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _controller?.pause();
    _controller?.seekTo(Duration.zero);
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    _controller?.seekTo(position);
  }

  Future<void> _disposeController() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    super.dispose();
  }
}
