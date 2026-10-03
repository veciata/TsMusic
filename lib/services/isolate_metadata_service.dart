import 'dart:isolate';
import 'dart:io';
import 'package:media_kit/media_kit.dart';

class _MetadataExtractionRequest {
  final String filePath;
  final SendPort sendPort;
  _MetadataExtractionRequest({required this.filePath, required this.sendPort});
}

class _MetadataExtractionResult {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  _MetadataExtractionResult({
    this.title,
    this.artist,
    this.album,
    this.duration,
  });
}

class IsolateMetadataExtractionService {
  static IsolateMetadataExtractionService? _instance;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  IsolateMetadataExtractionService._();
  static IsolateMetadataExtractionService get instance =>
      _instance ??= IsolateMetadataExtractionService._();
  Future<void> initialize() async {
    if (_isolate != null) return;
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);
  }

  Future<Map<String, dynamic>?> extractMetadata(String filePath) async {
    if (_sendPort == null) await initialize();
    final responsePort = ReceivePort();
    _sendPort!.send(
      _MetadataExtractionRequest(
        filePath: filePath,
        sendPort: responsePort.sendPort,
      ),
    );
    try {
      final result = await responsePort.first.timeout(
        const Duration(seconds: 10),
      );
      if (result is _MetadataExtractionResult) {
        return {
          'title': result.title,
          'artist': result.artist,
          'album': result.album,
          'duration': result.duration,
        };
      }
    } catch (e) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> extractBatchMetadata(
    List<String> filePaths,
  ) async {
    final futures = filePaths.map(extractMetadata).toList();
    final results = await Future.wait(futures);
    return results.whereType<Map<String, dynamic>>().toList();
  }

  void dispose() {
    _isolate?.kill();
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    receivePort.listen((message) async {
      if (message is _MetadataExtractionRequest) {
        try {
          final file = File(message.filePath);
          if (!await file.exists()) {
            message.sendPort.send(_MetadataExtractionResult());
            return;
          }
          final player = Player();
          final media = Media(message.filePath);
          String? title;
          String? artist;
          String? album;
          Duration? duration;
          try {
            await player.open(media);
            await Future.delayed(const Duration(milliseconds: 500));
            duration = player.state.duration;
          } catch (e) {
          } finally {
            await player.dispose();
          }
          message.sendPort.send(
            _MetadataExtractionResult(
              title: title,
              artist: artist,
              album: album,
              duration: duration,
            ),
          );
        } catch (e) {
          message.sendPort.send(_MetadataExtractionResult());
        }
      }
    });
  }
}
