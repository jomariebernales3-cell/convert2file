import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../core/database_helper.dart';
import 'auth_service.dart';

class FileStorage {
  static Future<String> get _basePath async {
    final dir = await getApplicationDocumentsDirectory();
    final base = Directory('${dir.path}/smart_template');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base.path;
  }

  static Future<String> get templatesPath async {
    final base = await _basePath;
    final dir = Directory('$base/templates');
    if (!await dir.exists()) await dir.create();
    return dir.path;
  }

  static Future<String> get dataPath async {
    final base = await _basePath;
    final dir = Directory('$base/data');
    if (!await dir.exists()) await dir.create();
    return dir.path;
  }

  static Future<String> get outputsPath async {
    final base = await _basePath;
    final dir = Directory('$base/outputs');
    if (!await dir.exists()) await dir.create();
    return dir.path;
  }

  static Future<String> get cachePath async {
    final base = await _basePath;
    final dir = Directory('$base/cache');
    if (!await dir.exists()) await dir.create();
    return dir.path;
  }

  static Future<String> saveUploadedFile(
    PlatformFile file,
    String kind, {
    int? userId,
    Map<String, dynamic>? metadata,
  }) async {
    final baseDir = kind == 'template_upload' || kind == 'template'
        ? await templatesPath
        : await dataPath;
    final recordKind = kind == 'template'
        ? 'template_upload'
        : kind == 'data'
            ? 'data_upload'
            : kind;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = path.extension(file.name).replaceFirst('.', '');
    final storedName = '${kind}_$timestamp.$ext';
    final filePath = '$baseDir/$storedName';

    if (file.bytes != null) {
      await File(filePath).writeAsBytes(file.bytes!);
    } else if (file.path != null) {
      await File(file.path!).copy(filePath);
    }

    final size = await File(filePath).length();
    final mimeType = _getMimeType(ext);
    final ownerId = userId ??
        AuthService().currentUser?.id ??
        await DatabaseHelper.instance.getOrCreateGuestUserId();

    await DatabaseHelper.instance.insertFile({
      'user_id': ownerId,
      'kind': recordKind,
      'original_name': file.name,
      'stored_name': storedName,
      'mime_type': mimeType,
      'extension': ext,
      'path': filePath,
      'size_bytes': size,
      'metadata_json': metadata == null ? null : jsonEncode(metadata),
      'created_at': DateTime.now().toIso8601String(),
    });

    return filePath;
  }

  static Future<String> saveOutputFile(
    String sourcePath,
    String kind,
    String originalName, {
    int? userId,
    int? sourceFileId,
    Map<String, dynamic>? metadata,
  }) async {
    final baseDir = await outputsPath;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = path.extension(originalName).replaceFirst('.', '');
    final storedName = '${kind}_$timestamp.$ext';
    final filePath = '$baseDir/$storedName';

    await File(sourcePath).copy(filePath);

    final size = await File(filePath).length();
    final mimeType = _getMimeType(ext);
    final ownerId = userId ??
        AuthService().currentUser?.id ??
        await DatabaseHelper.instance.getOrCreateGuestUserId();

    await DatabaseHelper.instance.insertFile({
      'user_id': ownerId,
      'source_file_id': sourceFileId,
      'kind': kind,
      'original_name': originalName,
      'stored_name': storedName,
      'mime_type': mimeType,
      'extension': ext,
      'path': filePath,
      'size_bytes': size,
      'metadata_json': metadata == null ? null : jsonEncode(metadata),
      'created_at': DateTime.now().toIso8601String(),
    });

    return filePath;
  }

  static Future<void> deleteFile(int fileId) async {
    final files = await DatabaseHelper.instance.queryAllFiles();
    final file = files.firstWhere((f) => f['id'] == fileId, orElse: () => {});
    if (file.isEmpty) return;

    final path = file['path'] as String?;
    if (path != null && await File(path).exists()) {
      await File(path).delete();
    }

    await DatabaseHelper.instance.deleteFile(fileId);
  }

  static Future<void> deleteFiles(List<int> fileIds) async {
    for (final fileId in fileIds) {
      await deleteFile(fileId);
    }
  }

  static String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'html':
        return 'text/html';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
