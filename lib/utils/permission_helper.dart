import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionHelper {
  /// Request necessary storage permissions based on Android version
  static Future<bool> requestStoragePermission() async {
    try {
      if (!await _shouldRequestPermission()) {
        return true; // No need to request, already granted
      }

      // Request the appropriate permission based on Android version
      final permission = await _getStoragePermission();
      
      // First check if we should show a rationale
      if (await permission.shouldShowRequestRationale) {
        // Show a dialog explaining why we need the permission
        final shouldRequest = await showDialog<bool>(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'To play your music, we need access to your audio files. '
              'Please grant the storage permission to continue.'
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
        ) ?? false;

        if (!shouldRequest) {
          return false;
        }
      }

      // Request the permission
      final status = await permission.request();
      
      if (status.isPermanentlyDenied) {
        // The user opted to never see the permission request dialog again
        if (navigatorKey.currentContext != null) {
          final openSettings = await showDialog<bool>(
            context: navigatorKey.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'Storage permission is required to access your music files. '
                'Please enable it in the app settings.'
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
      
      // On Android 13+, we also need notification permission for media controls
      if (await _isAndroid13OrHigher() && status.isGranted) {
        final notificationStatus = await Permission.notification.status;
        if (notificationStatus.isDenied) {
          await Permission.notification.request();
        }
      }
      
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
      return false;
    }
  }
  
  // Global key for navigation
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Initialize the navigator key with a navigator
  static void initializeNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }
  
  // Check if device is Android 13 or higher
  static Future<bool> isAndroid13OrHigher() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 33; // Android 13 is API 33
    } catch (e) {
      debugPrint('Error checking Android version: $e');
      return false;
    }
  }

  /// Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    try {
      if (!await _shouldRequestPermission()) {
        return true; // No need to check, consider it granted
      }
      
      final permission = await _getStoragePermission();
      final status = await permission.status;
      
      // If permission is denied but we can request it, return false
      if (status.isDenied) {
        return false;
      }
      
      // If permission is restricted, check if we can request it
      if (status.isRestricted) {
        return false;
      }
      
      return status.isGranted;
    } catch (e) {
      debugPrint('Error checking storage permission: $e');
      return false;
    }
  }

  /// Open app settings so user can grant permission
  static Future<bool> openAppSettings() async {
    try {
      final opened = await openAppSettings();
      return opened;
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }

  /// Show a dialog explaining why the permission is needed
  static Future<bool> showPermissionRationale(BuildContext context, {String? message}) async => await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message ?? 'Storage permission is required to access your music files.'),
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
    ) ?? false;

  /// Get the appropriate storage permission based on Android version
  static Future<Permission> _getStoragePermission() async {
    if (await _isAndroid13OrHigher()) {
      return Permission.audio;
    }
    return Permission.storage;
  }

  /// Request file management permission for Android 11+ (API 30+)
  static Future<bool> requestFileManagementPermission() async {
    try {
      if (!await _isAndroid()) return true;
      
      final sdkInt = await _getSdkInt();
      
      // On Android 11+ (API 30+), request manage external storage
      if (sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (status.isDenied) {
          status = await Permission.manageExternalStorage.request();
        }
        return status.isGranted;
      }
      
      // On older versions, storage permission covers file operations
      return true;
    } catch (e) {
      debugPrint('Error requesting file management permission: $e');
      return false;
    }
  }

  /// Check if file management permission is granted
  static Future<bool> hasFileManagementPermission() async {
    try {
      if (!await _isAndroid()) return true;
      
      final sdkInt = await _getSdkInt();
      
      // On Android 11+ (API 30+), check manage external storage
      if (sdkInt >= 30) {
        final status = await Permission.manageExternalStorage.status;
        return status.isGranted;
      }
      
      // On older versions, storage permission covers file operations
      return true;
    } catch (e) {
      debugPrint('Error checking file management permission: $e');
      return false;
    }
  }

  static Future<int> _getSdkInt() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      debugPrint('Error getting SDK version: $e');
      return 0;
    }
  }

  /// Check if we need to request storage permission
  static Future<bool> _shouldRequestPermission() async {
    if (!await _isAndroid()) {
      return false; // Not Android, no need to request
    }
    
    if (await _isAndroid13OrHigher()) {
      // On Android 13+, we need to request audio permission
      final audioStatus = await Permission.audio.status;
      return !audioStatus.isGranted;
    } else {
      // On older versions, request storage permission
      final storageStatus = await Permission.storage.status;
      return !storageStatus.isGranted;
    }
  }

  static Future<bool> _isAndroid() async {
    return true; // In a real app, you'd check the platform here
  }

  static Future<bool> _isAndroid13OrHigher() async {
    if (!(await _isAndroid())) {
      return false;
    }
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 33; // Android 13 is API 33
    } catch (e) {
      debugPrint('Error checking Android version: $e');
      return false;
    }
  }
}
