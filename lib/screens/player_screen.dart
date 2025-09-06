import 'package:flutter/material.dart';

class PlayerScreen extends StatefulWidget {
  final String? songTitle;
  final String? artist;
  final String? albumArt;
  final Duration? duration;
  final Duration? position;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;

  const PlayerScreen({
    super.key,
    this.songTitle,
    this.artist,
    this.albumArt,
    this.duration,
    this.position,
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.songTitle ?? 'No Title'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          if (widget.albumArt != null)
            Image.network(
              widget.albumArt!,
              height: 200,
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 200,
                width: 200,
                color: theme.colorScheme.surfaceVariant,
                child: const Icon(Icons.music_note, size: 50),
              ),
            )
          else
            Container(
              height: 200,
              width: 200,
              color: theme.colorScheme.surfaceVariant,
              child: const Icon(Icons.music_note, size: 50),
            ),
          const SizedBox(height: 20),
          Text(
            widget.songTitle ?? 'Unknown Title',
            style: theme.textTheme.headlineSmall,
          ),
          if (widget.artist != null)
            Text(
              widget.artist!,
              style: theme.textTheme.bodyLarge,
            ),
          const SizedBox(height: 20),
          if (widget.position != null && widget.duration != null)
            Column(
              children: [
                Slider(
                  value: widget.position!.inSeconds.toDouble(),
                  max: widget.duration!.inSeconds.toDouble(),
                  onChanged: (value) {
                    widget.onSeek(Duration(seconds: value.toInt()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(widget.position!)),
                      Text(_formatDuration(widget.duration!)),
                    ],
                  ),
                ),
              ],
            )
          else
            const SizedBox(height: 40),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: widget.onPrevious,
                  iconSize: 36,
                ),
                IconButton(
                  icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: widget.onPlayPause,
                  iconSize: 48,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: widget.onNext,
                  iconSize: 36,
                ),
              ],
            ),
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
