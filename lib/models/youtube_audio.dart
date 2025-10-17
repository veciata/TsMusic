import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeAudio {
  final String id;
  final String title;
  final List<String> artists;
  final String? thumbnailUrl;
  final String? audioUrl;
  final Duration? duration;

  YouTubeAudio({
    required this.id,
    required this.title,
    this.artists = const [],
    this.thumbnailUrl,
    this.audioUrl,
    this.duration,
  });

  factory YouTubeAudio.fromVideo(Video video) {
    // Extract artist from channel name or title
    final channelName = video.author;

    return YouTubeAudio(
      id: video.id.value,
      title: video.title,
      artists: [channelName],
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration,
    );
  }

  YouTubeAudio copyWith({
    String? id,
    String? title,
    List<String>? artists,
    String? thumbnailUrl,
    String? audioUrl,
    Duration? duration,
  }) {
    return YouTubeAudio(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
    );
  }
}
