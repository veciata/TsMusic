import 'package:package_info_plus/package_info_plus.dart';

class PackageInfoUtils {
  static PackageInfo? _packageInfo;
  
  /// Initialize package info
  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }
  
  /// Get app version (e.g., 1.0.0)
  static String get version => _packageInfo?.version ?? '1.0.0';
  
  /// Get app name
  static String get appName => _packageInfo?.appName ?? 'TS Music';
  
  /// Get build number (e.g., 1)
  static String get buildNumber => _packageInfo?.buildNumber ?? '1';
  
  /// Get package name (e.g., com.example.tsmusic)
  static String get packageName => _packageInfo?.packageName ?? 'com.veciata.tsmusic';
}
