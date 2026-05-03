import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class DownloadNotificationService {
  static final DownloadNotificationService _instance = DownloadNotificationService._internal();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Set to true when downloads screen is visible
  bool isDownloadsScreenVisible = false;

  static const int _downloadProgressNotificationId = 1;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(initSettings);
    _isInitialized = true;
    debugPrint('Download notification service initialized');
  }

  Future<void> showDownloadProgress({
    required String title,
    required double progress,
    required int totalDownloads,
  }) async {
    if (isDownloadsScreenVisible || !_isInitialized) return;

    final percent = (progress * 100).toStringAsFixed(0);
    final androidDetails = AndroidNotificationDetails(
      'download_progress',
      'Download Progress',
      channelDescription: 'Shows download progress for music files',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: int.parse(percent),
      ongoing: true,
      autoCancel: false,
    );

    const darwinDetails = DarwinNotificationDetails();

    await _notifications.show(
      _downloadProgressNotificationId,
      'Downloading: $title',
      '$percent% complete',
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
    );
  }

  Future<void> showDownloadComplete({
    required String title,
  }) async {
    if (isDownloadsScreenVisible || !_isInitialized) return;

    const androidDetails = AndroidNotificationDetails(
      'download_complete',
      'Download Complete',
      channelDescription: 'Notifies when a download is complete',
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    await _notifications.show(
      2,
      'Download Complete',
      '$title has been downloaded',
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
    );
  }

  Future<void> cancelDownloadNotification() async {
    await _notifications.cancel(_downloadProgressNotificationId);
  }
}
