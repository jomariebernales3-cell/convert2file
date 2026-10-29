import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppShareService {
  static const _channel = MethodChannel('convert2file/app_share');

  static Future<void> shareApp() async {
    final apkPath = await _channel.invokeMethod<String>('getInstalledApkPath');
    if (apkPath == null || apkPath.isEmpty) {
      throw StateError('Installed APK path is unavailable.');
    }

    final sourceApk = File(apkPath);
    if (!await sourceApk.exists()) {
      throw FileSystemException('Installed APK file not found.', apkPath);
    }

    final tempDir = await getTemporaryDirectory();
    final sharePath = '${tempDir.path}/Convert2File-installable.apk';
    final shareApk = await sourceApk.copy(sharePath);

    await _channel.invokeMethod<bool>(
      'shareApk',
      {'apkPath': shareApk.path},
    );
  }
}
