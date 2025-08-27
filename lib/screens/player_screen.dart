import 'package:flutter/material.dart';

class PlayerScreen extends StatefulWidget {
  final String songTitle;
  final String artist;
  final String albumArt;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;

  const PlayerScreen({
    super.key,
    required this.songTitle,
    required this.artist,
    required this.albumArt,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.songTitle)),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Image.network(
            widget.albumArt,
            height: 200,
            width: 200,
            fit: BoxFit.cover,
          ),
          const SizedBox(height: 20),
          Text(
            widget.songTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(widget.artist, style: const TextStyle(fontSize: 16)),
          Slider(
            value: widget.position.inSeconds.toDouble(),
            max: widget.duration.inSeconds.toDouble(),
            onChanged: (value) =>
                widget.onSeek(Duration(seconds: value.toInt())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_formatDuration(widget.position)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_formatDuration(widget.duration)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 40),
                onPressed: widget.onPrevious,
              ),
              IconButton(
                icon: Icon(
                  widget.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  size: 60,
                ),
                onPressed: widget.onPlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 40),
                onPressed: widget.onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
