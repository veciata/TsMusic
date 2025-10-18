import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/database/database_helper.dart';

class SongRepository {
  static const String _songsKey = 'cached_songs';
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<List<Song>> getSongs() async {
    try {
      final dbSongsData = await _databaseHelper.getSongs();
      final dbSongs = dbSongsData.map((data) => Song.fromJson(data)).toList();
      if (dbSongs.isNotEmpty) {
        await _cacheSongs(dbSongs);
        return dbSongs;
      }

      final prefs = await SharedPreferences.getInstance();
      final songsJson = prefs.getString(_songsKey);
      if (songsJson != null) {
        final List<dynamic> jsonList = jsonDecode(songsJson);
        final songs = jsonList.map((json) => Song.fromJson(json)).toList();
        if (songs.isNotEmpty) {
          await saveSongs(songs);
        }
        return songs;
      }

      return [];
    } catch (e) {
      print('Error getting songs: $e');
      return [];
    }
  }

  Future<void> saveSongs(List<Song> songs) async {
    try {
      await _databaseHelper.insertSongsBulk(songs.map((s) => s.toMap()).toList());
      await _cacheSongs(songs);
    } catch (e) {
      print('Error saving songs: $e');
      rethrow;
    }
  }

  Future<void> updateSong(Song song) async {
    try {
      await _databaseHelper.updateSong(int.parse(song.id), song.toMap());
      final songsData = await _databaseHelper.getSongs();
      final songs = songsData.map((data) => Song.fromJson(data)).toList();
      await _cacheSongs(songs);
    } catch (e) {
      print('Error updating song: $e');
      rethrow;
    }
  }

  Future<void> deleteSong(String songId) async {
    try {
      await _databaseHelper.deleteSong(int.parse(songId));
      final songsData = await _databaseHelper.getSongs();
      final songs = songsData.map((data) => Song.fromJson(data)).toList();
      await _cacheSongs(songs);
    } catch (e) {
      print('Error deleting song: $e');
      rethrow;
    }
  }

  Future<void> _cacheSongs(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final songsJson = jsonEncode(songs.map((song) => song.toJson()).toList());
    await prefs.setString(_songsKey, songsJson);
  }
}
