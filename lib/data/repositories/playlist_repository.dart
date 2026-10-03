import 'package:tsmusic/database/database_helper.dart';
import 'package:tsmusic/models/playlist.dart';

class PlaylistRepository {
  PlaylistRepository({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper();
  final DatabaseHelper _database;
  static const int nowPlayingPlaylistId = 1;
  Future<List<Playlist>> getAllPlaylists() async {
    final rows = await _database.getAllPlaylists();
    return rows.map(Playlist.fromRow).toList();
  }

  Future<Playlist?> getPlaylist(int playlistId) async {
    final row = await _database.getPlaylist(playlistId);
    return row == null ? null : Playlist.fromRow(row);
  }

  Future<int> createPlaylist(
    String name, {
    String? description,
    String? coverArtUrl,
  }) => _database.createPlaylist(
    name,
    description: description,
    coverArtUrl: coverArtUrl,
  );
  Future<int> updatePlaylist(
    int playlistId, {
    String? name,
    String? description,
    String? coverArtUrl,
  }) => _database.updatePlaylist(
    playlistId,
    name: name,
    description: description,
    coverArtUrl: coverArtUrl,
  );
  Future<int> deletePlaylist(int playlistId) =>
      _database.deletePlaylist(playlistId);
  Future<int> addSongsToPlaylist(int playlistId, List<int> songIds) =>
      _database.addSongsToPlaylist(playlistId, songIds);
  Future<int> removeSongsFromPlaylist(int playlistId, List<int> songIds) =>
      _database.removeSongsFromPlaylist(playlistId, songIds);
  Future<void> reorderNowPlayingPlaylist(List<int> songIds) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseHelper.tablePlaylistSongs,
        where: 'playlist_id = ?',
        whereArgs: [nowPlayingPlaylistId],
      );
      for (int i = 0; i < songIds.length; i++) {
        await txn.insert(DatabaseHelper.tablePlaylistSongs, {
          'playlist_id': nowPlayingPlaylistId,
          'song_id': songIds[i],
          'position': i,
        });
      }
    });
  }

  Future<void> updateNowPlayingPlaylist(List<int> songIds) =>
      _database.updateNowPlayingPlaylist(songIds);
}
