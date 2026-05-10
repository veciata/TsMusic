import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/github_release.dart';
import 'package:tsmusic/services/github_release_service.dart';
import 'package:tsmusic/utils/package_info_utils.dart';

/// Holds the state for checking new releases and showing the update modal.
enum UpdateCheckState { idle, loading, loaded, error }

class UpdateNotificationProvider extends ChangeNotifier {
  final GitHubReleaseService _releaseService;

  static const String _lastSeenVersionKey = 'last_seen_version';

  UpdateCheckState _state = UpdateCheckState.idle;
  List<GitHubRelease> _newReleases = [];
  String? _errorMessage;
  String _lastSeenVersion = '';

  UpdateNotificationProvider({
    GitHubReleaseService? releaseService,
    String? lastSeenVersion,
  }) : _releaseService = releaseService ?? GitHubReleaseService() {
    _lastSeenVersion = lastSeenVersion ?? '';
  }

  UpdateCheckState get state => _state;
  List<GitHubRelease> get newReleases => _newReleases;
  String? get errorMessage => _errorMessage;
  String get lastSeenVersion => _lastSeenVersion;

  /// Check if there are new releases since the last seen version.
  /// Returns `true` if new releases were found (caller should show the modal).
  Future<bool> checkForUpdates() async {
    _state = UpdateCheckState.loading;
    notifyListeners();

    try {
      final allReleases = await _releaseService.fetchReleases();

      if (allReleases.isEmpty) {
        _state = UpdateCheckState.loaded;
        _newReleases = [];
        notifyListeners();
        return false;
      }

      // Discover releases newer than the last-seen version.
      _newReleases = _getReleasesSinceLastSeen(allReleases);

      if (_newReleases.isEmpty) {
        _state = UpdateCheckState.loaded;
        notifyListeners();
        return false;
      }

      _state = UpdateCheckState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('UpdateNotification: check failed — $e');
      _state = UpdateCheckState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Mark the current version as seen (persisted), so the modal won't
  /// re-appear for the same batch of releases.
  Future<void> acknowledgeUpdates() async {
    final currentVersion = PackageInfoUtils.version;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenVersionKey, currentVersion);
    _lastSeenVersion = currentVersion;
    _newReleases = [];
    _state = UpdateCheckState.idle;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Version helpers
  // ---------------------------------------------------------------------------

  /// Compare two semantic version strings.
  /// Returns -1 if [a] < [b], 0 if equal, 1 if [a] > [b].
  static int _compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av < bv) return -1;
      if (av > bv) return 1;
    }
    return 0;
  }

  /// Split "1.2.3+4" → [1, 2, 3] (strip build metadata).
  static List<int> _parseVersion(String v) {
    // Remove leading 'v' if present
    var clean = v.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1);
    }
    // Strip build metadata (+something) and pre-release (-something)
    final plusIdx = clean.indexOf('+');
    if (plusIdx >= 0) clean = clean.substring(0, plusIdx);
    final dashIdx = clean.indexOf('-');
    if (dashIdx >= 0) clean = clean.substring(0, dashIdx);
    return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  /// Filter releases whose version is strictly greater than the
  /// last-seen version and ≤ the current app version.
  List<GitHubRelease> _getReleasesSinceLastSeen(List<GitHubRelease> all) {
    final currentVersion = PackageInfoUtils.version;

    // If we've never recorded a last-seen version, only show releases
    // that are *older* than the current version (so first-time users aren't
    // spammed with every release ever).
    if (_lastSeenVersion.isEmpty) {
      // Show nothing on first install — the user just installed this version.
      return [];
    }

    final result = <GitHubRelease>[];
    for (final release in all) {
      final rv = release.version;
      final isAfterLastSeen = _compareVersions(rv, _lastSeenVersion) > 0;
      final isAtOrBeforeCurrent = _compareVersions(rv, currentVersion) <= 0;

      if (isAfterLastSeen && isAtOrBeforeCurrent) {
        result.add(release);
      }
    }
    return result;
  }

  @override
  void dispose() {
    _releaseService.dispose();
    super.dispose();
  }
}
