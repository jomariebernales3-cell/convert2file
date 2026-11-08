import 'dart:io';

import 'package:file_picker/file_picker.dart';

class FileDownload {
  /// Opens the platform save dialog and writes the file bytes there.
  /// Returns an empty string if the user cancels.
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

    final resolvedFileName = (fileName != null && fileName.trim().isNotEmpty)
        ? _sanitizeFileName(fileName)
        : sourceFile.uri.pathSegments.isNotEmpty
            ? sourceFile.uri.pathSegments.last
            : 'downloaded-file';

    try {
      return await FilePicker.saveFile(
            fileName: resolvedFileName,
            bytes: await sourceFile.readAsBytes(),
          ) ??
          '';
    } catch (_) {
      throw FileSystemException(
        'Could not save the file. Please try again.',
        sourcePath,
      );
    }
  }

  static String _sanitizeFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.isEmpty ? 'downloaded-file' : sanitized;
  }
}
