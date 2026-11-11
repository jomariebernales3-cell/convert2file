import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AppShareService {
  static const _channel = MethodChannel('convert2file/app_share');
  static const websiteUrl = 'https://jomariebernales3-cell.github.io/convert2file/';

  static Future<void> shareWebsiteLink() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Download Convert2File for Android: $websiteUrl',
        subject: 'Convert2File Android app',
      ),
    );
  }

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
