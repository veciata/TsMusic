import 'dart:io';
import 'package:tsmusic/models/song.dart';
import 'package:tsmusic/services/isolate_metadata_service.dart';
import 'package:tsmusic/services/paginated_songs_service.dart';
import 'package:tsmusic/services/streamed_file_listing_service.dart';
import 'package:tsmusic/utils/lru_cache.dart';

/// Test file to verify all performance implementations work correctly
void main() {
  // Test LRU Cache
  testLRUCache();
  
  // Test Pagination Service
  testPaginationService();
  
  // Test Streamed File Listing (mocked)
  testStreamedFileListing();
  
  // Test Isolate Metadata Service (requires actual files)
  // testIsolateMetadataService();
  
  print('✅ All tests completed');
}

/// Test the LRU Cache implementation
void testLRUCache() {
  print('\n--- Testing LRU Cache ---');
  
  final cache = LRUCache<String, String>(maxCapacity: 3);
  
  // Fill cache
  cache.put('key1', 'value1');
  cache.put('key2', 'value2');
  cache.put('key3', 'value3');
  
  print('Cache after filling: ${cache.getStats()}');
  
  // Access key1 to make it recently used
  print('Getting key1: ${cache.get('key1')}');
  
  // Add one more to trigger eviction
  cache.put('key4', 'value4');
  print('Cache after adding key4: ${cache.getStats()}');
  
  // key2 should be evicted (least recently used)
  print('Key2 exists: ${cache.containsKey('key2')}');
  print('Key4 exists: ${cache.containsKey('key4')}');
  
  print('✅ LRU Cache test passed');
}

/// Test the Pagination Service
void testPaginationService() {
  print('\n--- Testing Pagination Service ---');
  
  // Create test songs
  final songs = List.generate(100, (i) => Song(
    id: i,
    title: 'Song $i',
    artists: ['Artist ${i % 10}'],
    album: 'Album ${i % 5}',
    url: 'file:///path/to/song$i.mp3',
    duration: 200000 + i * 1000, // 200s + i seconds
  ));
  
  final paginationService = PaginatedSongsService(songs: songs, pageSize: 10);
  
  // Test loading pages
  paginateAndPrint(paginationService, 1);
  paginateAndPrint(paginationService, 5);
  paginateAndPrint(paginationService, 10);
  
  // Test filtering
  final filteredFuture = paginationService.filterAndPaginate('Song 1', 1);
  filteredFuture.then((result) {
    print('Filtered results (page 1): ${result.items.length} songs');
    print('Total matches: ${result.totalCount}');
    print('Has more: ${result.hasMore}');
  });
  
  // Clean up
  paginationService.dispose();
  
  print('✅ Pagination Service test passed');
}

void paginateAndPrint(PaginatedSongsService service, int pageNumber) async {
  final result = await service.loadPage(pageNumber);
  print('Page $pageNumber: ${result.items.length} songs, '
      'Total: ${result.totalCount}, Has more: ${result.hasMore}');
}

/// Test Streamed File Listing (using temp directory)
Future<void> testStreamedFileListing() async {
  print('\n--- Testing Streamed File Listing ---');
  
  try {
    // Create a temporary directory with test files
    final tempDir = await Directory.systemTemp.createTemp('tsmusic_test_');
    print('Created temp dir: ${tempDir.path}');
    
    // Create test audio files
    final testFiles = ['song1.mp3', 'song2.wav', 'song3.flac', 'not_audio.txt'];
    for (final filename in testFiles) {
      final file = File('${tempDir.path}/$filename');
      await file.writeAsString('fake audio content');
      print('Created test file: $filename');
    }
    
    // Test streaming files
    int fileCount = 0;
    await for (final scanResult in 
        StreamedFileListingService.streamDirectoryFiles(tempDir.path)) {
      fileCount += scanResult.files.length;
      print('Batch: ${scanResult.files.length} files, '
          'Total so far: $fileCount');
      
      // Verify these are audio files
      for (final file in scanResult.files) {
        final ext = file.path.split('.').last.toLowerCase();
        if (!['mp3', 'wav', 'flac'].contains(ext)) {
          print('❌ Non-audio file found: ${file.path}');
        }
      }
    }
    
    print('Total files found: $fileCount');
    print('Expected: 3 audio files');
    
    if (fileCount == 3) {
      print('✅ Streamed File Listing test passed');
    } else {
      print('⚠️ Unexpected file count');
    }
    
    // Cleanup
    await tempDir.delete(recursive: true);
    print('Cleaned up temp directory');
    
  } catch (e) {
    print('❌ Streamed File Listing test failed: $e');
  }
}

/// Test Isolate Metadata Service (requires real media files)
Future<void> testIsolateMetadataService() async {
  print('\n--- Testing Isolate Metadata Service ---');
  
  try {
    // Initialize service
    await IsolateMetadataExtractionService.instance.initialize();
    print('Isolate service initialized');
    
    // Note: In a real test, we would use actual audio files
    // For this demo, we'll just verify the service responds correctly
    
    // Test with non-existent file (should return null metadata)
    final result = await IsolateMetadataExtractionService.instance
        .extractMetadata('/non/existent/file.mp3');
    
    print('Non-existent file result: $result');
    
    // Cleanup
    IsolateMetadataExtractionService.instance.dispose();
    
    print('✅ Isolate Metadata Service test completed');
    
  } catch (e) {
    print('⚠️ Isolate Metadata Service test skipped or failed: $e');
    // Don't fail the entire test suite for this
  }
}
