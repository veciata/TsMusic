/// One timestamped line of synced lyrics.
class LyricLine {
  const LyricLine({required this.time, required this.text});

  /// When the line should be highlighted, relative to the start of the track.
  final Duration time;

  final String text;
}

/// Lyrics for a single track.
///
/// [synced] is empty for plain (unsynced) lyrics; [plain] is always the
/// readable text, whether or not timestamps were available.
class Lyrics {
  const Lyrics({
    required this.plain,
    this.synced = const <LyricLine>[],
    required this.source,
  });

  final String plain;
  final List<LyricLine> synced;

  /// Human-readable name of the provider that supplied these lyrics.
  final String source;

  bool get hasSynced => synced.isNotEmpty;

  bool get isEmpty => plain.trim().isEmpty && synced.isEmpty;
}
