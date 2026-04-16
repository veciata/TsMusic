class ArtistParser {
  static List<String> parseArtists(String artistString) {
    if (artistString.isEmpty || artistString == 'Unknown Artist') {
      return ['Unknown Artist'];
    }

    List<String> artists = [artistString];

    final featPattern = RegExp(
      r'^(.*?)\s*(?:ft\.?|feat\.?|featuring)\s+(.+)$',
      caseSensitive: false,
    );
    final featMatch = featPattern.firstMatch(artistString);

    if (featMatch != null) {
      final mainArtist = featMatch.group(1)?.trim() ?? '';
      final featuredArtists = featMatch.group(2)?.trim() ?? '';

      artists = [mainArtist];

      if (featuredArtists.isNotEmpty) {
        final featuredList = featuredArtists
            .split(RegExp(r'\s*(?:,|&|and|\+)\s*', caseSensitive: false))
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
        artists.addAll(featuredList);
      }
    }

    return artists.where((a) => a.isNotEmpty).toList();
  }
}
