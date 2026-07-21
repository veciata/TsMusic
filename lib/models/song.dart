import 'storage_type.dart';

class Song {
  final int id;
  final String? youtubeId; // YouTube video ID for matching with search results
  final String title;
  final List<String> artists;
  final String? album;
  final String? albumArtUrl;
  final String url;
  final int duration; // Duration in milliseconds
  final StorageType storageType; // Whether the track is local or remote
  final List<String> tags;
  final int? trackNumber; // Track number in album
  final DateTime dateAdded; // When the song was added to the library
  final String? localThumbnailPath; // Local path to downloaded thumbnail

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

  bool hasTag(String tag) =>
      tags.any((t) => t.toLowerCase() == tag.toLowerCase());

  Song({
    required this.id,
    this.youtubeId,
    required this.title,
    required this.artists,
    this.album,
    this.albumArtUrl,
    required this.url,
    required this.duration,
    this.storageType = StorageType.local,
    this.isFavorite = false,
    this.isDownloaded = false,
    List<String>? tags,
    this.trackNumber,
    DateTime? dateAdded,
    this.localThumbnailPath,
  }) : tags = tags ?? [],
       dateAdded = dateAdded ?? DateTime.now();

  Song copyWith({
    int? id,
    String? youtubeId,
    String? title,
    List<String>? artists,
    String? album,
    String? albumArtUrl,
    String? url,
    int? duration,
    StorageType? storageType,
    bool? isFavorite,
    bool? isDownloaded,
    List<String>? tags,
    int? trackNumber,
    DateTime? dateAdded,
    String? localThumbnailPath,
  }) => Song(
    id: id ?? this.id,
    youtubeId: youtubeId ?? this.youtubeId,
    title: title ?? this.title,
    artists: artists ?? this.artists,
    album: album ?? this.album,
    albumArtUrl: albumArtUrl ?? this.albumArtUrl,
    url: url ?? this.url,
    duration: duration ?? this.duration,
    storageType: storageType ?? this.storageType,
    isFavorite: isFavorite ?? this.isFavorite,
    isDownloaded: isDownloaded ?? this.isDownloaded,
    tags: tags ?? this.tags,
    trackNumber: trackNumber ?? this.trackNumber,
    dateAdded: dateAdded ?? this.dateAdded,
    localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
  );

  factory Song.fromJson(Map<String, dynamic> json) {
    // Handle both int and String IDs for robustness
    int songId;
    if (json['id'] is String) {
      songId = int.tryParse(json['id'] as String) ?? 0;
    } else if (json['id'] is int) {
      songId = json['id'] as int;
    } else {
      songId = 0; // Default or error case
    }

    final storageStr = json['storageType'] as String?;
    final storageType = storageStr != null
        ? StorageType.values.firstWhere(
            (e) => e.name == storageStr,
            orElse: () => StorageType.local,
          )
        : StorageType.local;

    return Song(
      id: songId,
      youtubeId: json['youtubeId'] as String?,
      title: json['title'] as String,
      artists: json['artists'] is List
          ? List<String>.from(json['artists'])
          : [json['artist'] as String? ?? 'Unknown Artist'],
      album: json['album'] as String?,
      albumArtUrl: json['albumArtUrl'] as String?,
      url: json['url'] as String,
      duration: json['duration'] as int,
      storageType: storageType,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      trackNumber: json['trackNumber'] as int?,
      dateAdded: json['dateAdded'] != null
          ? DateTime.parse(json['dateAdded'] as String)
          : null,
      localThumbnailPath: json['localThumbnailPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'youtubeId': youtubeId,
    'title': title,
    'artists': artists,
    'album': album,
    'albumArtUrl': albumArtUrl,
    'url': url,
    'duration': duration,
    'storageType': storageType.name,
    'isFavorite': isFavorite,
    'isDownloaded': isDownloaded,
    'tags': tags,
    'trackNumber': trackNumber,
    'dateAdded': dateAdded.toIso8601String(),
    'localThumbnailPath': localThumbnailPath,
  };

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'youtube_id': youtubeId,
    'title': title,
    'file_path': url,
    'duration': duration,
    'track_number': trackNumber,
    'thumbnail_path': localThumbnailPath,
    'created_at': dateAdded.toIso8601String(),
  };

  Map<String, dynamic> toJson() => toMap();
}
