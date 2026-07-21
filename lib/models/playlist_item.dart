class PlaylistItem {
  final int? songId;
  final String? youtubeId;
  final String? title;
  final List<String>? artists;
  final int? duration;
  final String? thumbnailUrl;

  const PlaylistItem({
    this.songId,
    this.youtubeId,
    this.title,
    this.artists,
    this.duration,
    this.thumbnailUrl,
  });
}
