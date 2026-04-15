class YouTubeArtistParser {
  static String parseArtistName(String title, String channelName) {
    final fromTitle = _extractFromTitle(title);
    if (fromTitle != null && fromTitle.length > 2) {
      return fromTitle;
    }

    final cleaned = _cleanChannelName(channelName);
    if (cleaned.isNotEmpty) {
      return cleaned;
    }

    return channelName;
  }

  static String? _extractFromTitle(String title) {
    final patterns = [
      RegExp(r'^(.+?)\s*[-:]\s*.+'),
      RegExp(r'^(.+?)\s+ft\.\s+.+', caseSensitive: false),
      RegExp(r'^(.+?)\s+feat\.\s+.+', caseSensitive: false),
      RegExp(r'^(.+?)\s+with\s+.+', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null) {
        String artist = match.group(1)!.trim();
        artist = artist
            .split(RegExp(r'\s*(ft\.|feat\.|with)\s*', caseSensitive: false))[0]
            .trim();
        if (artist.isNotEmpty && artist.length > 1) {
          return _cleanChannelName(artist);
        }
      }
    }
    return null;
  }

  static String _cleanChannelName(String channel) {
    String cleaned = channel
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(VEVO|vevo|Vevo)\s*[-|]?',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Official)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Music)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Topic)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Lyrics?)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Audio)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(HD)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(4K?)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Explicit)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Remix)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Cover)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Live)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\s*[-|]?\s*(Original)\s*[-|]?', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s*\|\s*.*$'), '')
        .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
        .trim();

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned.isNotEmpty ? cleaned : channel;
  }
}
