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
    PermissionStatus status;

    if (deviceInfo.version.sdkInt >= 33) { // Android 13+
      status = await Permission.audio.request();
    } else { // Android 12 and below
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }
}