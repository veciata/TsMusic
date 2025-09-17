import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';

class SongSearchService {
  List<Song> filterSongs(List<Song> songs, String query) {
    if (query.isEmpty) {
      return List.from(songs);
    }
    
    final queryLower = query.toLowerCase();
    return songs.where((song) {
      return song.title.toLowerCase().contains(queryLower) ||
          song.artist.toLowerCase().contains(queryLower) ||
          (song.album?.toLowerCase().contains(queryLower) ?? false);
    }).toList();
  }

  List<Song> sortSongs(List<Song> songs, {required SongSortOption sortBy, bool ascending = true}) {
    final sorted = List<Song>.from(songs);
    
    sorted.sort((a, b) {
      int compare;
      switch (sortBy) {
        case SongSortOption.title:
          compare = a.title.compareTo(b.title);
          break;
        case SongSortOption.artist:
          compare = a.artist.compareTo(b.artist);
          break;
        case SongSortOption.album:
          compare = (a.album ?? '').compareTo(b.album ?? '');
          break;
        case SongSortOption.duration:
          compare = a.duration.compareTo(b.duration);
          break;
        case SongSortOption.dateAdded:
          compare = a.dateAdded.compareTo(b.dateAdded);
          break;
      }
      return ascending ? compare : -compare;
    });
    
    return sorted;
  }

  List<String> getUniqueArtists(List<Song> songs) {
    final artistSet = <String>{};
    for (final song in songs) {
      if (song.artist.isNotEmpty && song.artist.toLowerCase() != 'unknown artist') {
        artistSet.add(song.artist);
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }

  List<Song> getSongsByArtist(List<Song> songs, String artistName) {
    return songs.where((song) => song.artist == artistName).toList();
  }
}
