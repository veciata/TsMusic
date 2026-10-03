import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
