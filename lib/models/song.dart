class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArtUrl;
  final String url;
  final Duration duration;
  final bool isFavorite;
  final bool isDownloaded;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.albumArtUrl,
    required this.url,
    required this.duration,
    this.isFavorite = false,
    this.isDownloaded = false,
  });

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtUrl,
    String? url,
    Duration? duration,
    bool? isFavorite,
    bool? isDownloaded,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      url: url ?? this.url,
      duration: duration ?? this.duration,
      isFavorite: isFavorite ?? this.isFavorite,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      albumArtUrl: json['albumArtUrl'] as String?,
      url: json['url'] as String,
      duration: Duration(milliseconds: json['duration'] as int),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtUrl': albumArtUrl,
      'url': url,
      'duration': duration.inMilliseconds,
      'isFavorite': isFavorite,
      'isDownloaded': isDownloaded,
    };
  }
}
