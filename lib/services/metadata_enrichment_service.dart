import '../models/song.dart';

/// A placeholder metadata enrichment service.
///
/// In production, this could call out to services like MusicBrainz/Last.fm
/// to enrich unknown artist/album/genre fields and return an updated `Song`.
class MetadataEnrichmentService {
  /// Attempt to enrich metadata for the given [song].
  ///
  /// Returns an [EnrichmentResult] with an updated song and optional genre
  /// when enrichment is successful, or `null` when no enrichment can be made.
  Future<EnrichmentResult?> enrichSong(Song song) async {
    // TODO: Implement actual enrichment logic.
    // For now, return null to indicate no enrichment available.
    return null;
  }
}

class EnrichmentResult {
  final Song updatedSong;
  final String? genreName;

  EnrichmentResult({required this.updatedSong, this.genreName});
}
