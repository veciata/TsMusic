import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/song.dart';
class PaginationResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int totalCount;
  final bool hasMore;
  PaginationResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.hasMore,
  });
  int get totalPages => (totalCount / pageSize).ceil();
}
class PaginatedSongsService {
  final List<Song> _allSongs;
  final int pageSize;
  final StreamController<PaginationResult<Song>> _streamController =
      StreamController<PaginationResult<Song>>.broadcast();
  late Stream<PaginationResult<Song>> paginatedStream;
  PaginatedSongsService({required List<Song> songs, this.pageSize = 50})
    : _allSongs = List.from(songs) {
    paginatedStream = _streamController.stream;
  }
  Future<PaginationResult<Song>> loadPage(int pageNumber) async {
    if (pageNumber < 1) {
      throw ArgumentError('Page number must be >= 1');
    }
    return await compute(_loadPageInBackground, {
      'songs': _allSongs,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
  }
  Future<void> streamAllPages() async {
    final totalPages = (_allSongs.length / pageSize).ceil();
    for (int page = 1; page <= totalPages; page++) {
      try {
        final result = await loadPage(page);
        if (!_streamController.isClosed) {
          _streamController.add(result);
        }
        await Future.delayed(const Duration(milliseconds: 10));
      } catch (e) {
      }
    }
  }
  Future<PaginationResult<Song>> filterAndPaginate(
    String query,
    int pageNumber,
  ) async {
    final filteredSongs = _allSongs
        .where(
          (song) =>
              song.title.toLowerCase().contains(query.toLowerCase()) ||
              song.artist.toLowerCase().contains(query.toLowerCase()) ||
              (song.album != null &&
                  song.album!.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    return await compute(_loadPageInBackground, {
      'songs': filteredSongs,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
  }
  Future<PaginationResult<Song>> loadPageWithSort(
    int pageNumber,
    int Function(Song, Song) comparator,
  ) async {
    final sortedSongs = List.from(_allSongs)
      ..sort((a, b) => comparator(a as Song, b as Song));
    return await compute(_loadPageInBackground, {
      'songs': sortedSongs,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    });
  }
  void dispose() {
    _streamController.close();
  }
  static PaginationResult<Song> _loadPageInBackground(
    Map<String, dynamic> params,
  ) {
    final songs = params['songs'] as List<Song>;
    final pageNumber = params['pageNumber'] as int;
    final pageSize = params['pageSize'] as int;
    final startIndex = (pageNumber - 1) * pageSize;
    final endIndex = (startIndex + pageSize).clamp(0, songs.length);
    final pageItems = startIndex < songs.length
        ? songs.sublist(startIndex, endIndex)
        : <Song>[];
    return PaginationResult<Song>(
      items: pageItems,
      page: pageNumber,
      pageSize: pageSize,
      totalCount: songs.length,
      hasMore: endIndex < songs.length,
    );
  }
}
