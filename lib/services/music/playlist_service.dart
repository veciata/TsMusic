import 'package:tsmusic/models/song.dart';

class PlaylistService {
  List<Song> _playlist = [];
  int _currentIndex = -1;
  
  // Getters
  List<Song> get playlist => List.unmodifiable(_playlist);
  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _playlist.length 
      ? _playlist[_currentIndex] 
      : null;
  int? get currentIndex => _currentIndex >= 0 && _currentIndex < _playlist.length 
      ? _currentIndex 
      : null;
  bool get hasNext => _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _currentIndex > 0;
  
  // Playlist management
  void setPlaylist(List<Song> songs, {int? initialIndex}) {
    // Ensure all songs have a dateAdded field
    _playlist = songs.map((song) => song.copyWith(
      dateAdded: song.dateAdded ?? DateTime.now(),
    )).toList();
    _currentIndex = initialIndex ?? (_playlist.isNotEmpty ? 0 : -1);
  }
  
  void addToPlaylist(Song song) {
    // Ensure the song has a dateAdded field
    final songWithDate = song.copyWith(
      dateAdded: song.dateAdded ?? DateTime.now(),
    );
    _playlist.add(songWithDate);
    if (_currentIndex == -1) _currentIndex = 0;
  }
  
  // Alias for addToPlaylist for backward compatibility
  void addSong(Song song) {
    addToPlaylist(song);
  }
  
  void removeFromPlaylist(int index) {
    if (index < 0 || index >= _playlist.length) return;
    
    _playlist.removeAt(index);
    
    if (_playlist.isEmpty) {
      _currentIndex = -1;
    } else if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
    }
  }
  
  void moveInPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < 0 || 
        oldIndex >= _playlist.length || 
        newIndex < 0 || 
        newIndex >= _playlist.length) {
      return;
    }
    
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
  }
  
  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = -1;
  }
  
  // Navigation
  bool setCurrentIndex(int index) {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      return true;
    }
    return false;
  }
  
  bool next() {
    if (hasNext) {
      _currentIndex++;
      return true;
    }
    return false;
  }
  
  bool previous() {
    if (hasPrevious) {
      _currentIndex--;
      return true;
    }
    return false;
  }
  
  bool shuffle() {
    if (_playlist.isEmpty) return false;
    
    final currentSong = this.currentSong;
    _playlist.shuffle();
    
    if (currentSong != null) {
      final newIndex = _playlist.indexWhere((s) => s.id == currentSong.id);
      if (newIndex != -1) {
        _currentIndex = newIndex;
      }
    }
    
    return true;
  }
}
