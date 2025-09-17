import 'dart:developer' as developer;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  static bool _isRequestingPermission = false;

  static Future<int> _getSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }

  static Future<bool> hasStoragePermission() async {
    try {
      final sdkInt = await _getSdkInt();

      if (sdkInt >= 33) {
        return await Permission.audio.isGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    } catch (e) {
      developer.log('Error checking storage permission', error: e);
      return false;
    }
  }

  static Future<bool> requestStoragePermission() async {
    if (_isRequestingPermission) return false;
    _isRequestingPermission = true;

    try {
      if (await hasStoragePermission()) {
        _isRequestingPermission = false;
        return true;
      }

      final sdkInt = await _getSdkInt();
      final PermissionStatus status;

      if (sdkInt >= 33) {
        status = await Permission.audio.request();
      } else {
        status = await Permission.storage.request();
      }

      _isRequestingPermission = false;

      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return await hasStoragePermission();
      }

      return false;
    } catch (e) {
      _isRequestingPermission = false;
      developer.log('Error requesting storage permission', error: e);
      return false;
    }
  }

  static Future<bool> checkAndRequestStoragePermission() async {
    if (await hasStoragePermission()) return true;
    return await requestStoragePermission();
  }
}
