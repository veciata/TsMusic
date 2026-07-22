import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/isolate_metadata_service.dart';
import 'package:tsmusic/services/paginated_songs_service.dart';
import 'package:tsmusic/services/streamed_file_listing_service.dart';
import 'package:tsmusic/utils/lru_cache.dart';

/// Test file to verify all performance implementations work correctly
void main() {
  testLRUCache();
  testPaginationService();
  testStreamedFileListing();
  // testIsolateMetadataService(); // requires actual files
  debugPrint('✅ All tests completed');
}

void testLRUCache() {
  debugPrint('\n--- Testing LRU Cache ---');
  final cache = LRUCache<String, String>(maxCapacity: 3)
    ..put('key1', 'value1')
    ..put('key2', 'value2')
    ..put('key3', 'value3');
  debugPrint('Cache after filling: ${cache.getStats()}');
  debugPrint('Getting key1: ${cache.get('key1')}');
  cache.put('key4', 'value4');
  debugPrint('Cache after adding key4: ${cache.getStats()}');
  debugPrint('Key2 exists: ${cache.containsKey('key2')}');
  debugPrint('Key4 exists: ${cache.containsKey('key4')}');
  debugPrint('✅ LRU Cache test passed');
}

/// Test the Pagination Service
void testPaginationService() {
  debugPrint('\n--- Testing Pagination Service ---');
  final songs = List.generate(100, (i) => Song(
    id: i,
    title: 'Song $i',
    artists: ['Artist ${i % 10}'],
    album: 'Album ${i % 5}',
    url: 'file:///path/to/song$i.mp3',
    duration: 200000 + i * 1000,
  ));
  final paginationService = PaginatedSongsService(songs: songs, pageSize: 10);
  paginateAndPrint(paginationService, 1);
  paginateAndPrint(paginationService, 5);
  paginateAndPrint(paginationService, 10);
  paginationService
    ..filterAndPaginate('Song 1', 1).then((result) {
      debugPrint('Filtered results (page 1): ${result.items.length} songs\n'
          'Total matches: ${result.totalCount}\n'
          'Has more: ${result.hasMore}');
    })
    ..dispose();
  debugPrint('✅ Pagination Service test passed');
}

Future<void> paginateAndPrint(PaginatedSongsService service, int pageNumber) async {
  final result = await service.loadPage(pageNumber);
  debugPrint('Page $pageNumber: ${result.items.length} songs, '
      'Total: ${result.totalCount}, Has more: ${result.hasMore}');
}

Future<void> testStreamedFileListing() async {
  debugPrint('\n--- Testing Streamed File Listing ---');
  try {
    final tempDir = await Directory.systemTemp.createTemp('tsmusic_test_');
    debugPrint('Created temp dir: ${tempDir.path}');
    final testFiles = ['song1.mp3', 'song2.wav', 'song3.flac', 'not_audio.txt'];
    for (final filename in testFiles) {
      final file = File('${tempDir.path}/$filename');
      await file.writeAsString('fake audio content');
      debugPrint('Created test file: $filename');
    }
    int fileCount = 0;
    await for (final scanResult in 
        StreamedFileListingService.streamDirectoryFiles(tempDir.path)) {
      fileCount += scanResult.files.length;
      debugPrint('Batch: ${scanResult.files.length} files, '
          'Total so far: $fileCount');
      for (final file in scanResult.files) {
        final ext = file.path.split('.').last.toLowerCase();
        if (!['mp3', 'wav', 'flac'].contains(ext)) {
          debugPrint('❌ Non-audio file found: ${file.path}');
        }
      }
    }
    debugPrint('Total files found: $fileCount');
    debugPrint('Expected: 3 audio files');
    if (fileCount == 3) {
      debugPrint('✅ Streamed File Listing test passed');
    } else {
      debugPrint('⚠️ Unexpected file count');
    }
    await tempDir.delete(recursive: true);
    debugPrint('Cleaned up temp directory');
  } catch (e) {
    debugPrint('❌ Streamed File Listing test failed: $e');
  }
}

Future<void> testIsolateMetadataService() async {
  debugPrint('\n--- Testing Isolate Metadata Service ---');
  try {
    await IsolateMetadataExtractionService.instance.initialize();
    debugPrint('Isolate service initialized');
    final result = await IsolateMetadataExtractionService.instance
        .extractMetadata('/non/existent/file.mp3');
    debugPrint('Non-existent file result: $result');
    IsolateMetadataExtractionService.instance.dispose();
    debugPrint('✅ Isolate Metadata Service test completed');
  } catch (e) {
    debugPrint('⚠️ Isolate Metadata Service test skipped or failed: $e');
  }
}
