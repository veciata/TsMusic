class Song {
  final String id;
  final String title;
  final List<String> artists;
  final String? album;
  final String? albumArtUrl;
  final String url;
  final int duration; // Duration in milliseconds
  final List<String> tags;
  final int? trackNumber; // Track number in album
  final DateTime dateAdded; // When the song was added to the library
  
  // For backward compatibility
  String get artist => artists.isNotEmpty ? artists.first : 'Unknown Artist';
  
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
    required String title,
    required List<String> artists,
    this.album,
    this.albumArtUrl,
    required this.url,
    required this.duration,
    this.isFavorite = false,
    this.isDownloaded = false,
    List<String>? tags,
    this.trackNumber,
    DateTime? dateAdded,
  })  : title = title,
        artists = artists,
        tags = tags ?? [],
        dateAdded = dateAdded ?? DateTime.now();

  Song copyWith({
    String? id,
    String? title,
    List<String>? artists,
    String? album,
    String? albumArtUrl,
    String? url,
    int? duration,
    bool? isFavorite,
    bool? isDownloaded,
    List<String>? tags,
    int? trackNumber,
    DateTime? dateAdded,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      url: url ?? this.url,
      duration: duration ?? this.duration,
      isFavorite: isFavorite ?? this.isFavorite,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      tags: tags ?? this.tags,
      trackNumber: trackNumber ?? this.trackNumber,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artists: json['artists'] is List 
          ? List<String>.from(json['artists'])
          : [json['artist'] as String? ?? 'Unknown Artist'],
      album: json['album'] as String?,
      albumArtUrl: json['albumArtUrl'] as String?,
      url: json['url'] as String,
      duration: json['duration'] as int,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      trackNumber: json['trackNumber'] as int?,
      dateAdded: json['dateAdded'] != null 
          ? DateTime.parse(json['dateAdded'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artists': artists,
      'album': album,
      'albumArtUrl': albumArtUrl,
      'url': url,
      'duration': duration,
      'isFavorite': isFavorite,
      'isDownloaded': isDownloaded,
      'tags': tags,
      'trackNumber': trackNumber,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toMap();
}
