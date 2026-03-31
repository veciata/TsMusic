import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> hasStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    PermissionStatus status;

    if (deviceInfo.version.sdkInt >= 33) { // Android 13+
      status = await Permission.audio.status;
    } else { // Android 12 and below
      status = await Permission.storage.status;
    }

    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt;

    if (sdkInt >= 33) { // Android 13+
      // Request audio permission for reading music
      var audioStatus = await Permission.audio.request();
      
      // Request notification permission for media controls
      if (audioStatus.isGranted) {
        var notificationStatus = await Permission.notification.status;
        if (notificationStatus.isDenied) {
          await Permission.notification.request();
        }
      }
      
      return audioStatus.isGranted;
    } else if (sdkInt >= 30) { // Android 11-12
      // Request storage permission
      var status = await Permission.storage.request();
      
      // Request manage external storage for full file access
      if (status.isGranted) {
        var manageStatus = await Permission.manageExternalStorage.status;
        if (manageStatus.isDenied) {
          await Permission.manageExternalStorage.request();
        }
      }
      
      return status.isGranted;
    } else { // Android 10 and below
      var status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Check if all required permissions are granted
  Future<bool> hasAllPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt;

    if (sdkInt >= 33) { // Android 13+
      final audioStatus = await Permission.audio.status;
      return audioStatus.isGranted;
    } else if (sdkInt >= 30) { // Android 11-12
      final storageStatus = await Permission.storage.status;
      return storageStatus.isGranted;
    } else { // Android 10 and below
      final storageStatus = await Permission.storage.status;
      return storageStatus.isGranted;
    }
  }
}