import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tsmusic/models/github_release.dart';

/// Fetches releases from the GitHub API for the given repository.
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

  /// Fetch all published (non-prerelease) releases for the repository.
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
        debugPrint(
          'GitHub releases API returned ${response.statusCode}: ${response.body}',
        );
        return [];
      }

      final List<dynamic> jsonList =
          json.decode(response.body) as List<dynamic>;
      final releases = jsonList
          .map((j) => GitHubRelease.fromJson(j as Map<String, dynamic>))
          .where((r) => !r.isPrerelease)
          .toList();

      // Sort by published date ascending (oldest first).
      releases.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
      return releases;
    } catch (e) {
      debugPrint('Failed to fetch GitHub releases: $e');
      return [];
    }
  }

  void dispose() {
    _client.close();
  }
}
