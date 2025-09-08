import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import '../models/song.dart';
import '../services/audio_notification_service.dart';
import '../services/metadata_enrichment_service.dart';
import '../database/database_helper.dart';

extension StringExtension on String {
  String trimAll() => trim().replaceAll(RegExp(r'\s+'), ' ');
}

enum SongSortOption {
  title,
  artist,
  duration,
  dateAdded,
}

class NewMusicProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final MetadataEnrichmentService _enrichment = MetadataEnrichmentService();
  List<Song> _playlist = [];
  List<Song> _displayedSongs = [];
  List<Song> _filteredSongs = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;
  SongSortOption _currentSortOption = SongSortOption.title;
  bool _sortAscending = true;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isEnriching = false;
  int _enrichedCount = 0;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  List<Song> get songs => _displayedSongs;
  List<Song> get filteredSongs => _filteredSongs;
  bool get isEnriching => _isEnriching;
  int get enrichedCount => _enrichedCount;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<bool> get playingStream => _audioPlayer.playingStream;
  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration get duration => _audioPlayer.duration ?? Duration.zero;
  Song? get currentSong =>
      _playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length
          ? _playlist[_currentIndex]
          : null;
  int? get currentIndex =>
      (_playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _currentIndex
          : null;
  List<Song> get queue => List.unmodifiable(_playlist);
  List<Song> get allSongs => _playlist;
  List<Song> get youtubeSongs =>
      _playlist.where((song) => song.hasTag('tsmusic')).toList();
      
  // Get unique artists from the playlist, excluding 'Unknown Artist'
  List<String> get artists {
    final artistSet = <String>{};
    for (final song in _playlist) {
      if (song.artist.isNotEmpty && song.artist.toLowerCase() != 'unknown artist') {
        artistSet.add(song.artist);
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }
  
  // Get artist image URL (placeholder implementation - replace with actual implementation)
  String? getArtistImageUrl(String artistName) {
    // In a real app, you would fetch this from a music metadata API
    // For now, return null to use a default icon
    return null;
  }
  
  // Get songs by artist
  List<Song> getSongsByArtist(String artistName) {
    return _playlist.where((song) => song.artist == artistName).toList();
  }
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Playback control methods
  Future<void> play() async {
    await _audioPlayer.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _audioPlayer.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  void cycleRepeatMode() {
    _loopMode = LoopMode.values[(_loopMode.index + 1) % LoopMode.values.length];
    _audioPlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  // Queue management methods
  Future<void> addSong(Song song) async {
    final existingIndex = _playlist.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _playlist[existingIndex] = song;
    } else {
      _playlist.add(song);
    }
    _displayedSongs = List.from(_playlist);
    await _saveSongsToStorage();
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      notifyListeners();
    }
  }

  Future<void> clearQueue() async {
    _playlist.clear();
    _currentIndex = 0;
    notifyListeners();
  }

  void moveInQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length || newIndex < 0 || newIndex >= _playlist.length) {
      return;
    }
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  void playAt(int index) {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      _audioPlayer.seek(Duration.zero);
      _audioPlayer.play();
      notifyListeners();
    }
  }

  // Favorite methods
  bool isFavorite(String songId) {
    // Implement your favorite logic here
    return false;
  }

  void toggleFavorite(String songId) {
    // Implement your favorite toggling logic here
    notifyListeners();
  }

  // Local music loading
  Future<void> loadLocalMusic() async {
    // Implement your local music loading logic here
    notifyListeners();
  }

  static const String _songsKey = 'cached_songs';

  NewMusicProvider() {
    _positionSubscription = _audioPlayer.positionStream.listen((_) {
      notifyListeners();
    });

    AudioNotificationService.init(
      player: _audioPlayer,
      onCurrentSongChanged: (_) => notifyListeners(),
      onPlaybackStateChanged: (_) => notifyListeners(),
    );

    _audioPlayer.loopModeStream.listen((mode) {
      _loopMode = mode;
      notifyListeners();
    });

    _audioPlayer.shuffleModeEnabledStream.listen((enabled) {
      _shuffleEnabled = enabled;
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.play();
        } else if (_loopMode == LoopMode.all) {
          if (_currentIndex == _playlist.length - 1) {
            _currentIndex = 0;
          } else {
            _currentIndex++;
          }
          await _setAudioSource(_playlist[_currentIndex]);
          await _audioPlayer.play();
          await _updateNotification();
          notifyListeners();
        } else {
          if (_playlist.length > 1 && _currentIndex < _playlist.length - 1) {
            await next();
          }
        }
      }
    });

    _initialize();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    AudioNotificationService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await loadSongsFromStorage();
  }

  // addSong method is now implemented above with async/await support

  Future<void> updateSong(Song updatedSong) async {
    final index = _playlist.indexWhere((song) => song.id == updatedSong.id);
    if (index != -1) {
      _playlist[index] = updatedSong;
      _displayedSongs = List.from(_playlist);
      await _saveSongsToStorage();
      notifyListeners();
    }
  }

  Future<void> _saveSongsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final songsJson = _playlist.map((song) => song.toJson()).toList();
    await prefs.setString(_songsKey, jsonEncode(songsJson));
  }

  Future<void> loadSongsFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final songsJson = prefs.getString(_songsKey);
    if (songsJson != null) {
      final List<dynamic> jsonList = jsonDecode(songsJson);
      _playlist = jsonList.map((json) => Song.fromJson(json)).toList();
      _displayedSongs = List.from(_playlist);
      notifyListeners();
    }
  }

  Future<void> setCurrentSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      notifyListeners();
    }
  }

  Future<void> _setAudioSource(Song song) async {
    if (song.url.startsWith('http')) {
      await _audioPlayer.setUrl(song.url);
    } else {
      await _audioPlayer.setFilePath(song.url);
    }
    await _updateNotification();
  }

  Future<void> _updateNotification() async {
    final audioHandler = AudioNotificationService.audioHandler;
    if (audioHandler != null && currentSong != null) {
      await audioHandler.setAudioSource(
        AudioSource.uri(Uri.parse(currentSong!.url)),
        song: currentSong,
      );
      if (_audioPlayer.playing) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    if (_shuffleEnabled) {
      int nextIndex = _currentIndex;
      final random = Random();
      while (nextIndex == _currentIndex && _playlist.length > 1) {
        nextIndex = random.nextInt(_playlist.length);
      }
      _currentIndex = nextIndex;
    } else {
      _currentIndex = (_currentIndex + 1) % _playlist.length;
    }
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _playlist.length;
    if (_currentIndex < 0) _currentIndex = _playlist.length - 1;
    await _setAudioSource(_playlist[_currentIndex]);
    await _audioPlayer.play();
    await _updateNotification();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    await _updateNotification();
    notifyListeners();
  }

  Future<void> playSong(Song song) async {
    final index = _playlist.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _currentIndex = index;
      await _setAudioSource(song);
      await _audioPlayer.play();
      await _updateNotification();
      notifyListeners();
    }
  }

  void sortSongs({required SongSortOption sortBy, bool ascending = true}) {
    _currentSortOption = sortBy;
    _sortAscending = ascending;
    _playlist.sort((a, b) {
      int compare;
      switch (sortBy) {
        case SongSortOption.title:
          compare = a.title.compareTo(b.title);
          break;
        case SongSortOption.artist:
          compare = a.artist.compareTo(b.artist);
          break;
        case SongSortOption.duration:
          compare = a.duration.compareTo(b.duration);
          break;
        case SongSortOption.dateAdded:
          compare = 0;
          break;
      }
      return ascending ? compare : -compare;
    });
    _displayedSongs = List.from(_playlist);
    notifyListeners();
  }

  void filterSongs(String query) {
    if (query.isEmpty) {
      _displayedSongs = List.from(_playlist);
    } else {
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _playlist.where((song) {
        return song.title.toLowerCase().contains(lowerQuery) ||
            song.artist.toLowerCase().contains(lowerQuery) ||
            (song.album?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    }
    notifyListeners();
  }
}
