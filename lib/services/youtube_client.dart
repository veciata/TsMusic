import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Sends a modern desktop Chrome User-Agent on watch-page and CDN stream
/// requests. The youtube_explode_dart default is Chrome 96 (2021); YouTube's
/// unsigned bot-check treats it as a bot, which surfaces as "Sign in to
/// confirm you're not a bot" / "The page needs to be reloaded" and stalled
/// downloads that never deliver bytes, even across different networks.
class ModernUserAgentHttpClient extends YoutubeHttpClient {
  @override
  Map<String, String> get headers => {
    ...YoutubeHttpClient.defaultHeaders,
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'referer': 'https://www.youtube.com/',
    'origin': 'https://www.youtube.com',
  };

  ModernUserAgentHttpClient([super.httpClient]);
}
