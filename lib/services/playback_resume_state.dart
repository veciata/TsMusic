import 'package:shared_preferences/shared_preferences.dart';

class PlaybackResumeState {
  static const String indexKey = 'resume_current_index';
  static const String positionKey = 'resume_position_ms';
  static const String shuffleKey = 'resume_shuffle';
  static const String loopModeKey = 'resume_loop_mode';
  static const String usingTempPlaylistKey = 'resume_using_temp_playlist';
  static const String tempPlaylistIdsKey = 'resume_temp_playlist_ids';
  static const String playlistIdsKey = 'resume_playlist_ids';
  static const String widgetIndexKey = 'widget_resume_index';
  static const String widgetPositionKey = 'widget_resume_position_ms';
  final int index;
  final int positionMs;
  final bool shuffleEnabled;
  final String loopModeName;
  final bool isUsingTempPlaylist;
  final String? playlistIds;
  final String? tempPlaylistIds;
  const PlaybackResumeState({
    required this.index,
    required this.positionMs,
    required this.shuffleEnabled,
    required this.loopModeName,
    required this.isUsingTempPlaylist,
    this.playlistIds,
    this.tempPlaylistIds,
  });
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(indexKey, index);
    await prefs.setInt(positionKey, positionMs);
    await prefs.setBool(shuffleKey, shuffleEnabled);
    await prefs.setString(loopModeKey, loopModeName);
    await prefs.setBool(usingTempPlaylistKey, isUsingTempPlaylist);
    await _setOptional(prefs, playlistIdsKey, playlistIds);
    await _setOptional(prefs, tempPlaylistIdsKey, tempPlaylistIds);
  }

  static Future<PlaybackResumeState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(indexKey);
    if (index == null) return null;
    return PlaybackResumeState(
      index: index,
      positionMs: prefs.getInt(positionKey) ?? 0,
      shuffleEnabled: prefs.getBool(shuffleKey) ?? false,
      loopModeName: prefs.getString(loopModeKey) ?? '',
      isUsingTempPlaylist: prefs.getBool(usingTempPlaylistKey) ?? false,
      playlistIds: prefs.getString(playlistIdsKey),
      tempPlaylistIds: prefs.getString(tempPlaylistIdsKey),
    );
  }

  static Future<bool> exists() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(indexKey) != null;
  }

  static Future<void> _setOptional(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value != null && value.isNotEmpty) {
      await prefs.setString(key, value);
    } else {
      await prefs.remove(key);
    }
  }
}
