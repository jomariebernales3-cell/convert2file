import 'dart:io';

import 'package:path_provider/path_provider.dart';

class FileDownload {
  /// Copies [sourcePath] into the app's downloads folder (platform-appropriate).
  /// Returns the destination path.
  static Future<String> copyToDownloadsFolder(
    String sourcePath, {
    String? fileName,
  }) async {
    if (sourcePath.isEmpty) {
      throw ArgumentError('sourcePath is empty');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('File not found', sourcePath);
    }

    // Use a stable explicit downloads path on Android so that tools like ZArchiver
    // can see the file under /storage/emulated/0/download.
    //
    // Note: For non-Android platforms, we fall back to the platform downloads directory.
    final resolvedFileName = (fileName != null && fileName.trim().isNotEmpty)
        ? _sanitizeFileName(fileName)
        : sourceFile.uri.pathSegments.isNotEmpty
            ? sourceFile.uri.pathSegments.last
            : 'downloaded-file';

    String? destDirPath;
    if (Platform.isAndroid) {
      destDirPath = '/storage/emulated/0/download';
    } else {
      final downloadsDir = await getDownloadsDirectory();
      destDirPath = downloadsDir?.path;
    }

    if (destDirPath == null || destDirPath.isEmpty) {
      throw FileSystemException('Downloads directory unavailable');
    }

    final destPath = '$destDirPath/$resolvedFileName';

    final destFile = File(destPath);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    await sourceFile.copy(destPath);
    return destPath;
  }

  static String _sanitizeFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.isEmpty ? 'downloaded-file' : sanitized;
  }
}
