import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileShareService {
  static Future<void> shareFileWithName({
    required String sourcePath,
    required String fileName,
    String? subject,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('File not found.', sourcePath);
    }

    final tempDir = await getTemporaryDirectory();
    final safeName = _sanitizeFileName(fileName);
    final sharePath = path.join(tempDir.path,
        'convert2file_share_${DateTime.now().millisecondsSinceEpoch}_$safeName');
    final shareFile = await source.copy(sharePath);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(shareFile.path, name: safeName)],
        subject: subject ?? safeName,
      ),
    );
  }

  static String _sanitizeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'converted-file';
    return cleaned.length > 120 ? cleaned.substring(0, 120).trim() : cleaned;
  }
}
