import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppShareService {
  static const _channel = MethodChannel('convert2file/app_share');

  static Future<void> shareApp() async {
    final installedApp = await _channel.invokeMapMethod<String, dynamic>(
      'getInstalledApkPath',
    );
    final apkPath = installedApp?['path'] as String?;
    if (apkPath == null || apkPath.isEmpty) {
      throw StateError('Installed APK path is unavailable.');
    }

    final sourceApk = File(apkPath);
    if (!await sourceApk.exists()) {
      throw FileSystemException('Installed APK file not found.', apkPath);
    }

    final tempDir = await getTemporaryDirectory();
    final versionName = (installedApp?['versionName'] as String?)?.trim();
    final safeVersion = versionName == null || versionName.isEmpty
        ? 'installed'
        : versionName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final sharePath = '${tempDir.path}/Convert2File-$safeVersion.apk';
    final shareApk = await sourceApk.copy(sharePath);

    await _channel.invokeMethod<bool>(
      'shareApk',
      {'apkPath': shareApk.path},
    );
  }
}
