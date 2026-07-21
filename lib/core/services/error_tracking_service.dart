import 'dart:async';
import 'package:flutter/foundation.dart';

class ErrorTrackingService {
  static final ErrorTrackingService _instance = ErrorTrackingService._();
  factory ErrorTrackingService() => _instance;
  ErrorTrackingService._();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  void recordError(
    Object error,
    StackTrace stack, {
    String? context,
    Map<String, dynamic>? extras,
  }) {
    if (kDebugMode) {
      debugPrint('╔══════════════════════════════════════════╗');
      debugPrint('║  ERROR TRACKING                         ║');
      if (context != null) debugPrint('║  Context: $context');
      debugPrint('║  Error: $error');
      debugPrint('╚══════════════════════════════════════════╝');
      debugPrint('Stack trace:\n$stack');
    }
  }

  void recordFlutterError(FlutterErrorDetails details) {
    recordError(
      details.exception,
      details.stack ?? StackTrace.current,
      context: details.context?.toString(),
    );
  }

  void dispose() {
    _initialized = false;
  }
}
