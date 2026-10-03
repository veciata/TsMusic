import 'package:package_info_plus/package_info_plus.dart';

class PackageInfoUtils {
  static PackageInfo? _packageInfo;
  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static String get version => _packageInfo?.version ?? '1.1.0';
  static String get appName => _packageInfo?.appName ?? 'TS Music';
  static String get buildNumber => _packageInfo?.buildNumber ?? '1';
  static String get packageName =>
      _packageInfo?.packageName ?? 'com.veciata.tsmusic';
}
