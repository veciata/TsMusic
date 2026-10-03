import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tsmusic/models/github_release.dart';

class GitHubReleaseService {
  final String owner;
  final String repo;
  final http.Client _client;
  GitHubReleaseService({
    this.owner = 'veciata',
    this.repo = 'TsMusic',
    http.Client? client,
  }) : _client = client ?? http.Client();
  static const String _baseUrl = 'https://api.github.com';
  Future<List<GitHubRelease>> fetchReleases() async {
    try {
      final uri = Uri.parse('$_baseUrl/repos/$owner/$repo/releases');
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'TsMusic/$owner',
        },
      );
      if (response.statusCode != 200) {
        return [];
      }
      final List<dynamic> jsonList =
          json.decode(response.body) as List<dynamic>;
      final releases =
          jsonList
              .map((j) => GitHubRelease.fromJson(j as Map<String, dynamic>))
              .where((r) => !r.isPrerelease)
              .toList()
            ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
      return releases;
    } catch (e) {
      return [];
    }
  }

  void dispose() {
    _client.close();
  }
}
