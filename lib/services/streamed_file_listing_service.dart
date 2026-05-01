import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Result from file scanning
class FileScanResult {
  final List<File> files;
  final int totalScanned;
  final String currentDirectory;
  final Duration elapsedTime;

  FileScanResult({
    required this.files,
    required this.totalScanned,
    required this.currentDirectory,
    required this.elapsedTime,
  });
}

/// Service for streaming file listings instead of accumulating them
/// Allows processing large directories without memory issues
class StreamedFileListingService {
  static const List<String> audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.opus',
    '.m4b'
  ];
  static const int minFileSize = 512; // bytes

  /// Stream files from directory recursively
  /// Emits results incrementally as files are discovered
  static Stream<FileScanResult> streamDirectoryFiles(
    String dirPath, {
    bool recursive = true,
    Set<String>? processedPaths,
  }) async* {
    final startTime = DateTime.now();
    int totalScanned = 0;
    final List<File> batchFiles = [];
    const batchSize = 50; // Emit every 50 files

    try {
      yield* _streamFilesRecursive(
        dirPath,
        recursive,
        processedPaths,
        startTime,
        totalScanned,
        batchFiles,
        batchSize,
      );
    } catch (e) {
      debugPrint('Error streaming files from $dirPath: $e');
    }
  }

  /// Internal recursive file streaming
  static Stream<FileScanResult> _streamFilesRecursive(
    String dirPath,
    bool recursive,
    Set<String>? processedPaths,
    DateTime startTime,
    int totalScanned,
    List<File> batchFiles,
    int batchSize,
  ) async* {
    try {
      final dir = Directory(dirPath);

      // Check if directory exists
      if (!await dir.exists()) {
        debugPrint('Directory does not exist: $dirPath');
        return;
      }

      // Track processed paths to avoid symlink loops
      processedPaths ??= {};
      final canonicalPath = await dir.resolveSymbolicLinks();
      if (processedPaths.contains(canonicalPath)) {
        return;
      }
      processedPaths.add(canonicalPath);

      // List files in directory
      final entities = await dir.list().toList();

      for (final entity in entities) {
        try {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            final ext = path.extension(fileName).toLowerCase();

            // Check if audio file
            if (audioExtensions.contains(ext)) {
              final stat = await entity.stat();
              
              // Check minimum file size
              if (stat.size >= minFileSize) {
                batchFiles.add(entity);
                totalScanned++;

                // Emit batch when size reached
                if (batchFiles.length >= batchSize) {
                  yield FileScanResult(
                    files: List.from(batchFiles),
                    totalScanned: totalScanned,
                    currentDirectory: dirPath,
                    elapsedTime: DateTime.now().difference(startTime),
                  );
                  batchFiles.clear();
                }
              }
            }
          } else if (entity is Directory && recursive) {
            // Recursively scan subdirectories
            yield* _streamFilesRecursive(
              entity.path,
              recursive,
              processedPaths,
              startTime,
              totalScanned,
              batchFiles,
              batchSize,
            );
          }
        } catch (e) {
          debugPrint('Error processing entity ${entity.path}: $e');
        }
      }

      // Emit remaining files
      if (batchFiles.isNotEmpty) {
        yield FileScanResult(
          files: List.from(batchFiles),
          totalScanned: totalScanned,
          currentDirectory: dirPath,
          elapsedTime: DateTime.now().difference(startTime),
        );
      }
    } catch (e) {
      debugPrint('Error in _streamFilesRecursive for $dirPath: $e');
    }
  }

  /// Stream files from multiple directories in parallel
  static Stream<FileScanResult> streamMultipleDirectories(
    List<String> directories, {
    bool recursive = true,
  }) async* {
    final processedPaths = <String>{};

    for (final dir in directories) {
      yield* streamDirectoryFiles(
        dir,
        recursive: recursive,
        processedPaths: processedPaths,
      );
    }
  }

  /// Stream files with filtering function
  static Stream<File> streamFilteredFiles(
    String dirPath, {
    bool Function(File)? filter,
    bool recursive = true,
  }) async* {
    final processedPaths = <String>{};

    await for (final result in streamDirectoryFiles(
      dirPath,
      recursive: recursive,
      processedPaths: processedPaths,
    )) {
      for (final file in result.files) {
        if (filter == null || filter(file)) {
          yield file;
        }
      }
    }
  }
}
