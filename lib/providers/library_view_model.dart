import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:tsmusic/data/repositories/song_repository.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/models/song_sort_option.dart';
import 'package:tsmusic/services/thumbnail_service.dart';

class LibraryViewModel extends ChangeNotifier {
  final SongRepository _songRepository;
  static const List<String> audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.opus',
    '.m4b',
  ];
  static const String _songsKey = 'cached_songs';
  static const int _maxRetries = 3;
  static const int _baseRetryDelay = 3;
  bool _isLoading = false;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(false);
  String? _error;
  String? _lastError;
  int _retryCount = 0;
  final Map<String, Song> _songsMap = {};
  List<Song> _displayedSongs = [];
  final List<Song> _filteredSongs = [];
  SongSortOption _currentSortOption = SongSortOption.title;
  bool _sortAscending = true;
  bool _isDatabaseInitialized = false;
  ThumbnailService? _thumbnailService;
  final Set<String> _thumbnailLoadingIds = {};
  bool _thumbnailBgStarted = false;
  void Function(Song updated)? onSongUpdated;
  VoidCallback? onLibraryCacheCleared;
  Future<void> Function()? onNowPlayingReloadRequested;
  Future<void> Function()? onQueuePersistenceRequested;
  LibraryViewModel({SongRepository? songRepository})
    : _songRepository = songRepository ?? SongRepository();
  List<Song> get songs => _displayedSongs;
  List<Song> get filteredSongs => _filteredSongs;
  List<Song> get librarySongs => _songsMap.values.toList();
  List<Song> get _cachedSongs => _songsMap.values.toList();
  SongSortOption get currentSortOption => _currentSortOption;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  ValueNotifier<bool> get loadingNotifier => _loadingNotifier;
  String? get error => _error;
  List<String> get artists {
    final artistSet = <String>{};
    for (final song in _songsMap.values) {
      for (final artist in song.artists) {
        if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') {
          artistSet.add(artist);
        }
      }
    }
    return artistSet.toList()..sort((a, b) => a.compareTo(b));
  }

  void addSongToLibrary(Song song) {
    if (!_songsMap.containsKey(song.url)) {
      _songsMap[song.url] = song;
      _displayedSongs.add(song);
      notifyListeners();
    }
  }

  void removeSongFromLibrary(Song song) {
    _displayedSongs.removeWhere((s) => s.id == song.id);
    _songsMap.remove(song.url);
    notifyListeners();
  }

  void updateSongInPlace(Song updated) {
    for (int i = 0; i < _displayedSongs.length; i++) {
      if (_displayedSongs[i].id == updated.id) {
        _displayedSongs[i] = updated;
      }
    }
    if (_songsMap.containsKey(updated.url)) {
      _songsMap[updated.url] = updated;
    }
    onSongUpdated?.call(updated);
    notifyListeners();
  }

  void setDisplayedSongs(List<Song> songs) {
    _displayedSongs = List.of(songs);
    notifyListeners();
  }

  void clearDisplayedSongs() {
    _displayedSongs.clear();
    notifyListeners();
  }

  Future<void> clearLibraryCache() async {
    try {
      _songsMap.clear();
      _displayedSongs.clear();
      onLibraryCacheCleared?.call();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_songsKey);
    } catch (e) {}
  }

  Future<void> saveSongsToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _songsKey,
      jsonEncode(_cachedSongs.map((s) => s.toJson()).toList()),
    );
  }

  void initThumbnailService() {
    _initThumbnailService();
  }

  void _initThumbnailService() {
    _thumbnailService = ThumbnailService();
    _thumbnailService!.onThumbnailReady = (song, localPath) {
      final updated = song.copyWith(localThumbnailPath: localPath);
      updateSongInPlace(updated);
      final ytId = song.youtubeId;
      if (ytId != null && ytId.isNotEmpty) {
        _thumbnailLoadingIds.remove(ytId);
      } else if (song.artists.isNotEmpty) {
        _thumbnailLoadingIds.remove('artist:${song.artists.first}');
      }
      _songRepository.updateThumbnailPath(song.id, localPath);
    };
    _thumbnailService!.onThumbnailFailed = (song) {
      final ytId = song.youtubeId;
      if (ytId != null && ytId.isNotEmpty) {
        _thumbnailLoadingIds.remove(ytId);
      } else if (song.artists.isNotEmpty) {
        _thumbnailLoadingIds.remove('artist:${song.artists.first}');
      }
    };
  }

  bool isThumbnailLoading(Song song) {
    if (song.localThumbnailPath != null) return false;
    final ytId = song.youtubeId;
    if (ytId != null && ytId.isNotEmpty) {
      return _thumbnailLoadingIds.contains(ytId);
    }
    if (song.artists.isNotEmpty) {
      return _thumbnailLoadingIds.contains('artist:${song.artists.first}');
    }
    return false;
  }

  void requestThumbnail(Song song, {int priority = 2}) {
    if (song.localThumbnailPath != null) return;
    final ytId = song.youtubeId;
    if (ytId != null && ytId.isNotEmpty) {
      if (_thumbnailLoadingIds.contains(ytId)) return;
      _thumbnailLoadingIds.add(ytId);
    } else if (song.artists.isNotEmpty) {
      final artistKey = 'artist:${song.artists.first}';
      if (_thumbnailLoadingIds.contains(artistKey)) return;
      _thumbnailLoadingIds.add(artistKey);
    } else {
      return;
    }
    _thumbnailService?.requestThumbnail(song, priority: priority);
  }

  void _startBackgroundThumbnails() {
    if (_thumbnailBgStarted) return;
    _thumbnailBgStarted = true;
    Future.delayed(const Duration(seconds: 3), () {
      final songs = _songsMap.values
          .where(
            (s) =>
                s.youtubeId != null &&
                s.youtubeId!.isNotEmpty &&
                s.localThumbnailPath == null,
          )
          .toList();
      for (final song in songs) {
        final ytId = song.youtubeId;
        if (ytId != null && !_thumbnailLoadingIds.contains(ytId)) {
          _thumbnailLoadingIds.add(ytId);
        }
      }
      _thumbnailService?.requestThumbnailForAll(songs);
      final artistSongs = _songsMap.values
          .where(
            (s) =>
                (s.youtubeId == null || s.youtubeId!.isEmpty) &&
                s.localThumbnailPath == null &&
                s.artists.isNotEmpty,
          )
          .toList();
      if (artistSongs.isNotEmpty) {
        for (final song in artistSongs) {
          final artistKey = 'artist:${song.artists.first}';
          if (!_thumbnailLoadingIds.contains(artistKey)) {
            _thumbnailLoadingIds.add(artistKey);
          }
        }
        _thumbnailService?.requestThumbnailForAll(artistSongs);
      }
    });
  }

  void setSortOption(SongSortOption option) {
    _currentSortOption = option;
    _applySorting();
    notifyListeners();
  }

  void toggleSortDirection() {
    _sortAscending = !_sortAscending;
    _applySorting();
    notifyListeners();
  }

  List<Song> sortLibrary({
    required SongSortOption sortBy,
    bool ascending = true,
  }) {
    _currentSortOption = sortBy;
    _sortAscending = ascending;
    final sortedSongs = _songsMap.values.toList()
      ..sort((a, b) {
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
    _displayedSongs = List.of(sortedSongs);
    return sortedSongs;
  }

  void _applySorting() {
    switch (_currentSortOption) {
      case SongSortOption.title:
        _displayedSongs.sort(
          (a, b) => _sortAscending
              ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
              : b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SongSortOption.artist:
        _displayedSongs.sort((a, b) {
          final artistA = a.artists.isNotEmpty
              ? a.artists.first.toLowerCase()
              : '';
          final artistB = b.artists.isNotEmpty
              ? b.artists.first.toLowerCase()
              : '';
          return _sortAscending
              ? artistA.compareTo(artistB)
              : artistB.compareTo(artistA);
        });
        break;
      case SongSortOption.dateAdded:
        if (!_sortAscending) {
          _displayedSongs = _displayedSongs.reversed.toList();
        }
        break;
      case SongSortOption.album:
        _displayedSongs.sort((a, b) {
          final albumA = a.album?.toLowerCase() ?? '';
          final albumB = b.album?.toLowerCase() ?? '';
          return _sortAscending
              ? albumA.compareTo(albumB)
              : albumB.compareTo(albumA);
        });
        break;
      case SongSortOption.duration:
        _displayedSongs.sort(
          (a, b) => _sortAscending
              ? a.duration.compareTo(b.duration)
              : b.duration.compareTo(a.duration),
        );
        break;
    }
  }

  Future<void> filterSongs(String query) async {
    if (query.isEmpty) {
      _displayedSongs = _cachedSongs;
      _applySorting();
      notifyListeners();
      return;
    }
    try {
      final searchedSongs = await _songRepository.search(query);
      if (searchedSongs.isNotEmpty) {
        _displayedSongs = searchedSongs;
      } else {
        final lowerQuery = query.toLowerCase();
        _displayedSongs = _cachedSongs
            .where(
              (song) =>
                  song.title.toLowerCase().contains(lowerQuery) ||
                  song.artists.any(
                    (artist) => artist.toLowerCase().contains(lowerQuery),
                  ) ||
                  (song.album?.toLowerCase().contains(lowerQuery) ?? false),
            )
            .toList();
      }
    } catch (e) {
      final lowerQuery = query.toLowerCase();
      _displayedSongs = _cachedSongs
          .where(
            (song) =>
                song.title.toLowerCase().contains(lowerQuery) ||
                song.artists.any(
                  (artist) => artist.toLowerCase().contains(lowerQuery),
                ) ||
                (song.album?.toLowerCase().contains(lowerQuery) ?? false),
          )
          .toList();
    }
    notifyListeners();
  }

  String? getArtistImageUrl(String artistName) {
    final artistSongs = getSongsByArtist(artistName);
    if (artistSongs.isNotEmpty) {
      return artistSongs.first.albumArtUrl;
    }
    return null;
  }

  String? getAlbumArtUrl(String albumName, {String? artistName}) {
    for (final song in _songsMap.values) {
      if (song.album == albumName &&
          (artistName == null ||
              song.artists.any((artist) => artist == artistName))) {
        return song.albumArtUrl;
      }
    }
    return null;
  }

  List<Song> getSongsByArtist(String artistName) => _songsMap.values
      .where((song) => song.artists.any((artist) => artist == artistName))
      .toList();
  List<Song> getSongsByAlbum(String albumName, {String? artistName}) =>
      _songsMap.values
          .where(
            (song) =>
                song.album == albumName &&
                (artistName == null ||
                    song.artists.any((artist) => artist == artistName)),
          )
          .toList();
  List<String> getAlbumsByArtist(String artistName) {
    final albumSet = <String>{};
    for (final song in _songsMap.values) {
      if (song.artists.any((artist) => artist == artistName) &&
          song.album != null &&
          song.album!.isNotEmpty) {
        albumSet.add(song.album!);
      }
    }
    return albumSet.toList()..sort();
  }

  Future<void> recordPlay(Song song) => _songRepository.recordPlay(song.id);
  Future<List<Song>> getRecentlyPlayed({int limit = 20}) =>
      _songRepository.getRecentlyPlayed(limit: limit);
  Future<List<Song>> getMostPlayed({int limit = 20}) =>
      _songRepository.getMostPlayed(limit: limit);
  Future<void> _loadSongsFromDatabase() async {
    if (_songsMap.isNotEmpty) {
      _displayedSongs = _cachedSongs;
      return;
    }
    try {
      final songsFromDb = await _songRepository.getAllSongs();
      _songsMap.clear();
      for (final song in songsFromDb) {
        if (!_songsMap.containsKey(song.url)) {
          _songsMap[song.url] = song;
        }
      }
      _displayedSongs = _cachedSongs;
      _startBackgroundThumbnails();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> loadFromDatabaseOnly() async {
    if (_isLoading) return;
    try {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Loading music from database...';
      notifyListeners();
      _songsMap.clear();
      _displayedSongs.clear();
      await _loadSongsFromDatabase();
      await onNowPlayingReloadRequested?.call();
      _isLoading = false;
      _loadingNotifier.value = false;
      if (_songsMap.isEmpty) {
        await _scanLocalStorageForMusic();
      } else {
        await _scanLocalStorageForMusic(background: true);
        _error = null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Error loading music from database: $e';
      _isLoading = false;
      _loadingNotifier.value = false;
      if (_songsMap.isEmpty) {
        notifyListeners();
      } else {
        _error = null;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> loadLocalMusic({bool forceRescan = false}) async {
    if (_isLoading) return;
    try {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Loading music...';
      notifyListeners();
      _displayedSongs.clear();
      if (_songsMap.isNotEmpty && !forceRescan) {
        _displayedSongs = _cachedSongs;
        await onQueuePersistenceRequested?.call();
        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null;
        notifyListeners();
        return;
      }
      if (forceRescan) {
        await clearLibraryCache();
      }
      await _loadSongsFromDatabase();
      if (_songsMap.isNotEmpty) {
        _displayedSongs = _cachedSongs;
        _isLoading = false;
        _loadingNotifier.value = false;
        _error = null;
        notifyListeners();
        unawaited(_checkForNewMusicInBackground());
      } else {
        await _scanLocalStorageForMusic();
        await onQueuePersistenceRequested?.call();
      }
    } catch (e) {
      _error = 'Error loading music: $e';
      _isLoading = false;
      _loadingNotifier.value = false;
      if (_songsMap.isEmpty) {
        await _scanLocalStorageForMusic();
      }
    } finally {
      _isLoading = false;
      _loadingNotifier.value = false;
      if (_songsMap.isNotEmpty) {
        _error = null;
      }
      notifyListeners();
    }
  }

  Future<void> refreshSongs() async {
    try {
      _thumbnailBgStarted = false;
      _thumbnailLoadingIds.clear();
      _thumbnailService?.dispose();
      _thumbnailService = null;
      _songsMap.clear();
      _displayedSongs.clear();
      _initThumbnailService();
      await _loadSongsFromDatabase();
      await _scanLocalStorageForMusic();
      _songsMap.clear();
      await _loadSongsFromDatabase();
      _applySorting();
      await onNowPlayingReloadRequested?.call();
    } catch (e) {}
  }

  Future<void> loadLocalMusicWithRetry({bool forceRescan = false}) async {
    try {
      await loadLocalMusic(forceRescan: forceRescan);
      _retryCount = 0;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delaySeconds = _baseRetryDelay * _retryCount;
        _error =
            'Error: $_lastError\n\nRetrying in ${delaySeconds}s... (attempt $_retryCount/$_maxRetries)';
        notifyListeners();
        await Future.delayed(Duration(seconds: delaySeconds));
        await loadLocalMusicWithRetry(forceRescan: forceRescan);
      } else {
        _error = 'Error loading music:\n$_lastError\n\nPlease try again.';
        _retryCount = 0;
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryLoading() async {
    _retryCount = 0;
    _error = null;
    notifyListeners();
    await loadLocalMusicWithRetry(forceRescan: true);
  }

  Future<void> scanForNewMusic() async {
    await loadLocalMusic(forceRescan: true);
  }

  Future<void> _scanLocalStorageForMusic({bool background = false}) async {
    if (!background) {
      _isLoading = true;
      _loadingNotifier.value = true;
      _error = 'Scanning for music...';
      notifyListeners();
    }
    try {
      await _cleanupDeletedSongs();
      await _cleanupOldDuplicateFiles();
      final bool hasPermission = await _checkStoragePermission();
      if (!hasPermission) {
        _error = 'Storage permission is required to scan for music.';
        if (!background) {
          _isLoading = false;
          _loadingNotifier.value = false;
        }
        notifyListeners();
        return;
      }
      final musicDirectories = await _getAllMusicDirectories();
      _error = 'Scanning all directories simultaneously...';
      if (!background) notifyListeners();
      final scanResults = await _scanAllDirectoriesParallel(musicDirectories);
      final totalFilesFound = scanResults['totalFiles'] as int;
      final musicFiles = scanResults['files'] as List<File>;
      if (totalFilesFound == 0) {
        final alternativeFiles = await _scanAlternativeLocations();
        if (alternativeFiles.isNotEmpty) {
          musicFiles.addAll(alternativeFiles);
        }
      }
      if (musicFiles.isEmpty) {
        final count = await _songRepository.countSongs();
        if (count == 0) {
          _error = 'No music files found on device.';
        }
        if (!background) {
          _isLoading = false;
          _loadingNotifier.value = false;
        }
        notifyListeners();
        return;
      }
      await _processAndAddAllSongs(musicFiles, background);
      if (!background) {
        _isLoading = false;
        _loadingNotifier.value = false;
        final count = await _songRepository.countSongs();
        if (_songsMap.isEmpty && count == 0) {
          _error =
              'No music found. Add music to your device or download from YouTube.';
        } else {
          _error = null;
        }
      }
      notifyListeners();
    } catch (e) {
      if (!background) {
        final count = await _songRepository.countSongs();
        if (count == 0) {
          _error =
              'Could not scan for music. Please check storage permissions.';
        }
        _isLoading = false;
        _loadingNotifier.value = false;
        notifyListeners();
      }
    }
  }

  Future<void> _cleanupDeletedSongs() async {
    try {
      final allSongs = await _songRepository.getAllSongs();
      final List<int> songsToRemove = [];
      for (final song in allSongs) {
        if (song.url.isEmpty || song.url.startsWith('yt:')) continue;
        final file = File(song.url);
        if (!await file.exists()) {
          songsToRemove.add(song.id);
        }
      }
      if (songsToRemove.isNotEmpty) {
        await _songRepository.deleteSongsByIds(songsToRemove);
      }
    } catch (e) {}
  }

  Future<void> _cleanupOldDuplicateFiles() async {
    try {
      final musicDirectories = await _getAllMusicDirectories();
      for (final dirPath in musicDirectories) {
        try {
          final dir = Directory(dirPath);
          if (!await dir.exists()) continue;
          final Map<String, List<File>> videoIdFiles = {};
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (audioExtensions.contains(ext)) {
                final fileName = path.basenameWithoutExtension(entity.path);
                final parts = fileName.split('_');
                if (parts.isNotEmpty) {
                  final lastPart = parts.last;
                  if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(lastPart)) {
                    videoIdFiles.putIfAbsent(lastPart, () => []).add(entity);
                  }
                }
              }
            }
          }
          for (final entry in videoIdFiles.entries) {
            if (entry.value.length > 1) {
              File? bestFile;
              List<File> toDelete = [];
              for (final file in entry.value) {
                final fileName = path.basenameWithoutExtension(file.path);
                if (RegExp(r'_[0-9]+$').hasMatch(fileName)) {
                  toDelete.add(file);
                } else {
                  bestFile = file;
                }
              }
              if (bestFile == null && entry.value.isNotEmpty) {
                bestFile = entry.value.first;
                toDelete = entry.value.skip(1).toList();
              }
              for (final file in toDelete) {
                try {
                  await file.delete();
                } catch (e) {}
              }
            }
          }
        } catch (e) {}
      }
    } catch (e) {}
  }

  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 33) {
        var status = await Permission.audio.status;
        if (!status.isGranted) status = await Permission.audio.request();
        return status.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        final hasStorage = status.isGranted;
        if (hasStorage && sdkInt >= 30) {
          await Permission.manageExternalStorage.request();
        }
        return hasStorage;
      }
    } else {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<List<String>> _getAllMusicDirectories() async {
    final musicDirectories = <String>{};
    final standardPaths = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Android/data/com.veciata.tsmusic/files/Music',
      '/storage/emulated/0/Android/data/com.veciata.tsmusic/files/Download',
    ];
    musicDirectories.addAll(standardPaths);
    final uniquePaths = musicDirectories
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList();
    return uniquePaths;
  }

  Future<Map<String, dynamic>> _scanAllDirectoriesParallel(
    List<String> directories,
  ) async {
    final List<File> allMusicFiles = [];
    final Set<String> processedPaths = {};
    int totalFilesFound = 0;
    const batchSize = 5;
    for (int i = 0; i < directories.length; i += batchSize) {
      final endIndex = (i + batchSize < directories.length)
          ? i + batchSize
          : directories.length;
      final batch = directories.sublist(i, endIndex);
      final futures = batch
          .map((dirPath) => _scanSingleDirectory(dirPath, processedPaths))
          .toList();
      try {
        final results = await Future.wait(futures);
        for (final result in results) {
          if (result != null) {
            allMusicFiles.addAll(result['files'] as List<File>);
            totalFilesFound += result['count'] as int;
          }
        }
      } catch (e) {}
    }
    return {'files': allMusicFiles, 'totalFiles': totalFilesFound};
  }

  Future<Map<String, dynamic>?> _scanSingleDirectory(
    String dirPath,
    Set<String> processedPaths,
  ) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return null;
      final List<File> musicFiles = [];
      int fileCount = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && !processedPaths.contains(entity.path)) {
          final ext = path.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
            try {
              final stat = await entity.stat();
              if (stat.size > 512) {
                musicFiles.add(entity);
                processedPaths.add(entity.path);
                fileCount++;
              }
            } catch (_) {}
          }
        }
      }
      if (fileCount > 0) {}
      return {'files': musicFiles, 'count': fileCount};
    } catch (e) {
      return null;
    }
  }

  Future<List<File>> _scanAlternativeLocations() async {
    final List<File> alternativeFiles = [];
    final alternativePaths = ['/storage', '/mnt', '/data', '/system'];
    for (final basePath in alternativePaths) {
      try {
        final dir = Directory(basePath);
        if (await dir.exists()) {
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (audioExtensions.contains(ext)) {
                try {
                  final stat = await entity.stat();
                  if (stat.size > 512) {
                    alternativeFiles.add(entity);
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {}
    }
    return alternativeFiles;
  }

  Future<void> _processAndAddAllSongs(
    List<File> musicFiles,
    bool background,
  ) async {
    _songsMap.clear();
    final List<Song> validSongs = [];
    for (int i = 0; i < musicFiles.length; i++) {
      final file = musicFiles[i];
      if (i % 20 == 0) {
        _error = 'Processing ${i + 1} of ${musicFiles.length} files...';
        if (!background) notifyListeners();
      }
      try {
        final song = await _processMusicFile(file);
        if (song != null) {
          validSongs.add(song);
        }
      } catch (e) {}
    }
    if (validSongs.isEmpty) {
      return;
    }
    await _songRepository.saveSongs(validSongs);
    for (final song in validSongs) {
      if (!_songsMap.containsKey(song.url)) {
        _songsMap[song.url] = song;
      }
    }
    _displayedSongs = _cachedSongs;
    await onQueuePersistenceRequested?.call();
  }

  Future<Song?> _processMusicFile(File file) async {
    try {
      final fileName = path.basenameWithoutExtension(file.path);
      String cleanFileName(String fileName) => fileName
          .replaceAll(
            RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(
              r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(
            RegExp(
              r'\b(official|music|video|lyrics|hd|clear|audio)\b',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      final cleanedName = cleanFileName(fileName);
      String title = cleanedName;
      List<String> artistsList = ['Unknown Artist'];
      final mainPattern = RegExp(r'^\s*(.*?)\s*[-–]\s*(.*?)\s*$');
      final match = mainPattern.firstMatch(fileName);
      if (match != null) {
        final String mainArtist = match.group(1)?.trim() ?? 'Unknown Artist';
        String rawTitle = match.group(2)?.trim() ?? fileName;
        artistsList = mainArtist
            .split(RegExp(r'\s*(?:,|&|and|\+)\s*', caseSensitive: false))
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
        String? featuredArtists;
        final featPattern = RegExp(
          r'^(.*?)\s*(?:ft\.?|feat\.?|featuring)\s+(.+)$',
          caseSensitive: false,
        );
        final featMatch = featPattern.firstMatch(rawTitle);
        if (featMatch != null) {
          rawTitle = featMatch.group(1)?.trim() ?? rawTitle;
          featuredArtists = featMatch.group(2)?.trim();
        }
        List<String> featuredList = [];
        if (featuredArtists != null && featuredArtists.isNotEmpty) {
          featuredList = featuredArtists
              .split(RegExp(r'\s*(?:,|&|and|\+)\s*', caseSensitive: false))
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty)
              .toList();
        }
        artistsList.addAll(featuredList);
        title = rawTitle
            .replaceAll(
              RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}', caseSensitive: false),
              '',
            )
            .replaceAll(
              RegExp(
                r'(?:ft\.?|feat\.?|featuring)\s+.+$',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(
              RegExp(
                r'\d+kbps|\d+\s*kbps|\d+\s*bit|\d+\s*k\s*bps',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
      }
      final duration = await _getAudioDuration(file.path);
      if (duration == Duration.zero) {
        return null;
      }
      final isTSMusic =
          file.path.toLowerCase().contains('music/tsmusic') ||
          file.path.toLowerCase().contains('tsmusic');
      final song = Song(
        id: file.path.hashCode,
        title: title.isNotEmpty
            ? title
            : path.basenameWithoutExtension(file.path),
        artists: artistsList,
        album: 'Unknown Album',
        url: file.path,
        duration: duration.inMilliseconds,
        tags: isTSMusic ? ['tsmusic'] : [],
      );
      return song;
    } catch (e) {
      return null;
    }
  }

  Future<Duration> _getAudioDuration(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Duration.zero;
      }
      final fileSize = await file.length();
      if (fileSize < 1024) {
        return Duration.zero;
      }
      final extension = path.extension(filePath).toLowerCase();
      int estimatedBitrate;
      if (extension == '.mp3') {
        estimatedBitrate = 128000;
      } else if (extension == '.m4a' || extension == '.aac') {
        estimatedBitrate = 128000;
      } else if (extension == '.opus') {
        estimatedBitrate = 96000;
      } else if (extension == '.ogg' || extension == '.flac') {
        estimatedBitrate = 256000;
      } else if (extension == '.wav') {
        estimatedBitrate = 1411200;
      } else {
        estimatedBitrate = 128000;
      }
      final estimatedMs = (fileSize * 8 * 1000) / estimatedBitrate;
      if (estimatedMs < 10000 || estimatedMs > 1800000) {
        return const Duration(minutes: 3);
      }
      return Duration(milliseconds: estimatedMs.round());
    } catch (e) {
      return Duration.zero;
    }
  }

  Future<void> _checkForNewMusicInBackground() async {
    try {
      if (_isDatabaseInitialized) return;
      _isDatabaseInitialized = true;
      final prefs = await SharedPreferences.getInstance();
      final lastScanTime = prefs.getInt('last_music_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneDayInMs = 24 * 60 * 60 * 1000;
      if (now - lastScanTime > oneDayInMs || _cachedSongs.isEmpty) {
        await _scanLocalStorageForMusic(background: true);
        await prefs.setInt('last_music_scan', now);
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _loadingNotifier.dispose();
    super.dispose();
  }
}
