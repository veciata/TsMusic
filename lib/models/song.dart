class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArtUrl;
  final String url;
  final int duration; // Duration in milliseconds
  final List<String> tags;
  
  String get formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final duration = this.duration ~/ 1000; // Convert to seconds
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${twoDigits(seconds)}';
  }
  
  Duration get durationObject => Duration(milliseconds: duration);
  final bool isFavorite;
  final bool isDownloaded;
  
  bool hasTag(String tag) => tags.any((t) => t.toLowerCase() == tag.toLowerCase());

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
    List<String>? tags,
  }) : tags = tags ?? [];

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtUrl,
    String? url,
    int? duration,
    bool? isFavorite,
    bool? isDownloaded,
    List<String>? tags,
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
      tags: tags ?? this.tags,
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
      duration: json['duration'] as int,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
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
      'duration': duration, // duration is already in milliseconds
      'isFavorite': isFavorite,
      'isDownloaded': isDownloaded,
      'tags': tags,
    };
  }
}
