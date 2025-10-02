import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';

class SongSearchService {
  List<Song> filterSongs(List<Song> songs, String query) {
    if (query.isEmpty) {
      return List.from(songs);
    }
    
    final queryLower = query.toLowerCase();
    return songs.where((song) {
      final artistMatch = song.artists.any((artist) => artist.toLowerCase().contains(queryLower));
      return song.title.toLowerCase().contains(queryLower) ||
          artistMatch ||
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
          final artistA = a.artists.isNotEmpty ? a.artists.first : '';
          final artistB = b.artists.isNotEmpty ? b.artists.first : '';
          compare = artistA.compareTo(artistB);
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
      for (final artist in song.artists) {
        if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') {
          artistSet.add(artist);
        }
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }

  List<Song> getSongsByArtist(List<Song> songs, String artistName) {
    return songs.where((song) => song.artists.any((artist) => artist == artistName)).toList();
  }
}
