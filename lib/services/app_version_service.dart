import 'package:package_info_plus/package_info_plus.dart';

class AppVersionService {
  AppVersionService._();

  static String? _cachedVersion;
  static String? get cachedVersion => _cachedVersion;

  static Future<String?> loadInstalledVersion() async {
    try {
      final package = await PackageInfo.fromPlatform();
      final version = package.version.trim();
      final build = package.buildNumber.trim();
      if (version.isEmpty) return null;
      _cachedVersion =
          build.isEmpty || build == '0' ? version : '$version.$build';
      return _cachedVersion;
    } catch (_) {
      return _cachedVersion;
    }
  }

  static bool isBelowMinimum(String installed, String minimum) {
    return compare(installed, minimum) < 0;
  }

  static bool isAtLeast(String installed, String minimum) {
    return compare(installed, minimum) >= 0;
  }

  static int compare(String left, String right) {
    final currentParts = _numericParts(left);
    final minimumParts = _numericParts(right);
    final length = currentParts.length > minimumParts.length
        ? currentParts.length
        : minimumParts.length;
    for (var index = 0; index < length; index++) {
      final current = index < currentParts.length ? currentParts[index] : 0;
      final required = index < minimumParts.length ? minimumParts[index] : 0;
      if (current != required) return current.compareTo(required);
    }
    return 0;
  }

  static List<int> _numericParts(String version) => RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.tryParse(match.group(0)!) ?? 0)
      .toList(growable: false);
}
