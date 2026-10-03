import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
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
class StreamedFileListingService {
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
  static const int minFileSize = 512;
  static Stream<FileScanResult> streamDirectoryFiles(
    String dirPath, {
    bool recursive = true,
    Set<String>? processedPaths,
  }) async* {
    final startTime = DateTime.now();
    final int totalScanned = 0;
    final List<File> batchFiles = [];
    const batchSize = 50;
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
    }
  }
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
      if (!await dir.exists()) {
        return;
      }
      processedPaths ??= {};
      final canonicalPath = await dir.resolveSymbolicLinks();
      if (processedPaths.contains(canonicalPath)) {
        return;
      }
      processedPaths.add(canonicalPath);
      final entities = await dir.list().toList();
      for (final entity in entities) {
        try {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            final ext = path.extension(fileName).toLowerCase();
            if (audioExtensions.contains(ext)) {
              final stat = await entity.stat();
              if (stat.size >= minFileSize) {
                batchFiles.add(entity);
                totalScanned++;
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
        }
      }
      if (batchFiles.isNotEmpty) {
        yield FileScanResult(
          files: List.from(batchFiles),
          totalScanned: totalScanned,
          currentDirectory: dirPath,
          elapsedTime: DateTime.now().difference(startTime),
        );
      }
    } catch (e) {
    }
  }
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
