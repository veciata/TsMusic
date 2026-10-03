import 'package:tsmusic/models/song.dart';
class MetadataEnrichmentService {
  Future<EnrichmentResult?> enrichSong(Song song) async => null;
}
class EnrichmentResult {
  final Song updatedSong;
  final String? genreName;
  EnrichmentResult({required this.updatedSong, this.genreName});
}
