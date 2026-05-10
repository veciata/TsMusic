/// Represents a single GitHub release.
class GitHubRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime publishedAt;
  final bool isPrerelease;

  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isPrerelease,
  });

  /// Parse a version from a tag name like "v1.1.3" or "1.1.3".
  /// Returns the version string without the leading 'v'.
  String get version {
    var v = tagName;
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    return v;
  }

  /// Create from GitHub API JSON.
  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      isPrerelease: json['prerelease'] as bool? ?? false,
    );
  }
}
