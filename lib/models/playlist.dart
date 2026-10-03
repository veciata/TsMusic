class Playlist {
  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverArtUrl,
    this.createdAt,
  });
  factory Playlist.fromRow(Map<String, dynamic> row) => Playlist(
    id: row['id'] as int,
    name: row['name'] as String,
    description: row['description'] as String?,
    coverArtUrl: row['cover_art_url'] as String?,
    createdAt: row['created_at'] != null
        ? DateTime.tryParse(row['created_at'] as String)
        : null,
  );
  final int id;
  final String name;
  final String? description;
  final String? coverArtUrl;
  final DateTime? createdAt;
  Playlist copyWith({
    int? id,
    String? name,
    String? description,
    String? coverArtUrl,
    DateTime? createdAt,
  }) => Playlist(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverArtUrl: coverArtUrl ?? this.coverArtUrl,
    createdAt: createdAt ?? this.createdAt,
  );
}
