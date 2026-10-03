import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
class PermissionHelper {
  static Future<bool> requestStoragePermission() async {
    try {
      if (!await _shouldRequestPermission()) {
        return true;
      }
      final permission = await _getStoragePermission();
      if (await permission.shouldShowRequestRationale) {
        final shouldRequest =
            await showDialog<bool>(
              context: navigatorKey.currentContext!,
              builder: (context) => AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                  'To play your music, we need access to your audio files. '
                  'Please grant the storage permission to continue.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!shouldRequest) {
          return false;
        }
      }
      final status = await permission.request();
      if (status.isPermanentlyDenied) {
        if (navigatorKey.currentContext != null) {
          final openSettings = await showDialog<bool>(
            context: navigatorKey.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'Storage permission is required to access your music files. '
                'Please enable it in the app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await openAppSettings();
          }
        }
        return false;
      }
      if (await _isAndroid13OrHigher() && status.isGranted) {
        final notificationStatus = await Permission.notification.status;
        if (notificationStatus.isDenied) {
          await Permission.notification.request();
        }
      }
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static Future<bool> isAndroid13OrHigher() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 33;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> hasStoragePermission() async {
    try {
      if (!await _shouldRequestPermission()) {
        return true;
      }
      final permission = await _getStoragePermission();
      final status = await permission.status;
      if (status.isDenied) {
        return false;
      }
      if (status.isRestricted) {
        return false;
      }
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> openAppSettings() async {
    try {
      final opened = await openAppSettings();
      return opened;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> showPermissionRationale(
    BuildContext context, {
    String? message,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: Text(
            message ??
                'Storage permission is required to access your music files.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ) ??
      false;
  static Future<bool> _isAndroid11OrHigher() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 30;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> requestManageExternalStorage() async {
    try {
      if (!await _isAndroid11OrHigher()) {
        return true;
      }
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        if (navigatorKey.currentContext != null) {
          final openSettings = await showDialog<bool>(
            context: navigatorKey.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('All Files Access Required'),
              content: const Text(
                'To manage music files in Downloads and Music folders, '
                'this app needs "All Files Access" permission. '
                'Please enable it in app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await openAppSettings();
          }
        }
        return false;
      }
      final result = await Permission.manageExternalStorage.request();
      return result.isGranted;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> hasManageExternalStorage() async {
    if (!await _isAndroid11OrHigher()) {
      return true;
    }
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }
  static Future<bool> requestFileManagementPermission() async {
    try {
      if (!await _isAndroid()) return true;
      final sdkInt = await _getSdkInt();
      if (sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (status.isDenied) {
          status = await Permission.manageExternalStorage.request();
        }
        return status.isGranted;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  static Future<bool> hasFileManagementPermission() async {
    try {
      if (!await _isAndroid()) return true;
      final sdkInt = await _getSdkInt();
      if (sdkInt >= 30) {
        final status = await Permission.manageExternalStorage.status;
        return status.isGranted;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  static Future<int> _getSdkInt() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      return 0;
    }
  }
  static Future<bool> _shouldRequestPermission() async {
    if (!await _isAndroid()) {
      return false;
    }
    if (await _isAndroid13OrHigher()) {
      final audioStatus = await Permission.audio.status;
      return !audioStatus.isGranted;
    } else {
      final storageStatus = await Permission.storage.status;
      return !storageStatus.isGranted;
    }
  }
  static Future<bool> _isAndroid() async => true;
  static Future<bool> _isAndroid13OrHigher() async {
    if (!(await _isAndroid())) {
      return false;
    }
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 33;
    } catch (e) {
      return false;
    }
  }
  static Future<Permission> _getStoragePermission() async {
    if (await _isAndroid13OrHigher()) {
      return Permission.audio;
    }
    return Permission.storage;
  }
}
