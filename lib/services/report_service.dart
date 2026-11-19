import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/database_helper.dart';
import 'auth_service.dart';
import 'file_storage.dart';
import 'supabase_config.dart';

class ReportDraft {
  final String area;
  final String description;
  final Map<String, dynamic> contextInfo;
  final String? sourceFilePath;
  final String? outputFilePath;
  final String? screenshotFilePath;
  final bool attachSource;
  final bool attachOutput;
  final bool includeTechnicalDetails;
  final bool includeEmail;

  const ReportDraft({
    required this.area,
    required this.description,
    this.contextInfo = const {},
    this.sourceFilePath,
    this.outputFilePath,
    this.screenshotFilePath,
    this.attachSource = false,
    this.attachOutput = false,
    this.includeTechnicalDetails = true,
    this.includeEmail = true,
  });
}

class ReportSubmissionResult {
  final String id;
  final bool savedOffline;

  const ReportSubmissionResult({required this.id, required this.savedOffline});
}

class ReportServiceException implements Exception {
  final String message;
  const ReportServiceException(this.message);
  @override
  String toString() => message;
}

class ReportService {
  static const _rateLimitKey = 'problem_report_attempts_v1';
  static const _maximumFileBytes = 10 * 1024 * 1024;

  Future<ReportSubmissionResult> submit(ReportDraft draft) async {
    final description = draft.description.trim();
    if (description.length < 10 || description.length > 2000) {
      throw const ReportServiceException('Describe the problem in 10 to 2,000 characters.');
    }
    final source = draft.attachSource ? draft.sourceFilePath : null;
    final output = draft.attachOutput ? draft.outputFilePath : null;
    final screenshot = draft.screenshotFilePath;
    await _checkFileSize(source);
    await _checkFileSize(output);
    await _checkFileSize(screenshot);
    final reportId = _newUuid();
    await _recordAttempt();

    final copiedFiles = await _copyAttachments(reportId, source, output, screenshot);
    final authUser = SupabaseConfig.isConfigured
        ? Supabase.instance.client.auth.currentUser
        : null;
    final technical = draft.includeTechnicalDetails;
    final row = <String, dynamic>{
      'id': reportId,
      'user_id': authUser?.id,
      'reporter_email': draft.includeEmail ? authUser?.email : null,
      'area': draft.area,
      'description': description,
      'platform': technical ? Platform.operatingSystem : null,
      'context': technical ? _sanitizeContext(draft.contextInfo) : <String, dynamic>{},
      'status': 'new',
    };

    try {
      if (!SupabaseConfig.isConfigured) throw const SocketException('Supabase is unavailable');
      await _send(
        row,
        copiedFiles.sourcePath,
        copiedFiles.outputPath,
        copiedFiles.screenshotPath,
      );
      await _deleteLocalCopies(copiedFiles);
      await retryPending();
      return ReportSubmissionResult(id: reportId, savedOffline: false);
    } catch (_) {
      await DatabaseHelper.instance.insertPendingReport({
        'id': reportId,
        'payload_json': jsonEncode(row),
        'source_local_path': copiedFiles.sourcePath,
        'output_local_path': copiedFiles.outputPath,
        'screenshot_local_path': copiedFiles.screenshotPath,
        'created_at': DateTime.now().toIso8601String(),
      });
      return ReportSubmissionResult(id: reportId, savedOffline: true);
    }
  }

  Future<void> retryPending() async {
    if (!SupabaseConfig.isConfigured) return;
    List<Map<String, dynamic>> pending;
    try {
      pending = await DatabaseHelper.instance.queryPendingReports();
    } catch (_) {
      return;
    }
    for (final item in pending) {
      try {
        final row = Map<String, dynamic>.from(
          jsonDecode(item['payload_json'] as String) as Map,
        );
        final paths = _CopiedAttachments(
          sourcePath: item['source_local_path'] as String?,
          outputPath: item['output_local_path'] as String?,
          screenshotPath: item['screenshot_local_path'] as String?,
        );
        await _send(row, paths.sourcePath, paths.outputPath, paths.screenshotPath);
        await _deleteLocalCopies(paths);
        await DatabaseHelper.instance.deletePendingReport(item['id'] as String);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _send(
    Map<String, dynamic> row,
    String? sourcePath,
    String? outputPath,
    String? screenshotPath,
  ) async {
    final client = Supabase.instance.client;
    final reportId = row['id'] as String;
    if (sourcePath != null) {
      final key = await _upload(client, reportId, sourcePath, 'source_');
      row['source_file_path'] = key;
    }
    if (outputPath != null) {
      final key = await _upload(client, reportId, outputPath, 'output_');
      row['output_file_path'] = key;
    }
    if (screenshotPath != null) {
      final key = await _upload(client, reportId, screenshotPath, 'screenshot_');
      row['screenshot_file_path'] = key;
    }
    try {
      await client.from('problem_reports').insert(row);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
  }

  Future<String> _upload(
    SupabaseClient client,
    String reportId,
    String localPath,
    String prefix,
  ) async {
    final file = File(localPath);
    final name = _safeFileName(file.uri.pathSegments.last);
    final key = 'reports/$reportId/$prefix$name';
    final contentType = prefix == 'screenshot_'
        ? switch (name.split('.').last.toLowerCase()) {
            'jpg' || 'jpeg' => 'image/jpeg',
            'webp' => 'image/webp',
            _ => 'image/png',
          }
        : 'application/octet-stream';
    try {
      await client.storage.from('report-files').uploadBinary(
            key,
            await file.readAsBytes(),
            fileOptions: FileOptions(contentType: contentType),
          );
    } catch (error) {
      final text = error.toString().toLowerCase();
      if (!text.contains('409') && !text.contains('already exists') && !text.contains('duplicate')) {
        rethrow;
      }
    }
    return key;
  }

  Future<void> _checkFileSize(String? filePath) async {
    if (filePath == null) return;
    final file = File(filePath);
    if (!await file.exists()) {
      throw const ReportServiceException('An attached file could not be found.');
    }
    if (await file.length() > _maximumFileBytes) {
      throw const ReportServiceException('Each attached file must be 10 MB or smaller.');
    }
  }

  Future<_CopiedAttachments> _copyAttachments(
    String id,
    String? source,
    String? output,
    String? screenshot,
  ) async {
    if (source == null && output == null && screenshot == null) {
      return const _CopiedAttachments();
    }
    final base = await FileStorage.cachePath;
    final directory = Directory('$base/report_pending/$id');
    await directory.create(recursive: true);
    Future<String?> copy(String? path, String prefix) async {
      if (path == null) return null;
      final file = File(path);
      final name = _safeFileName(file.uri.pathSegments.last);
      final destination = '${directory.path}/$prefix$name';
      await file.copy(destination);
      return destination;
    }

    return _CopiedAttachments(
      sourcePath: await copy(source, 'source_'),
      outputPath: await copy(output, 'output_'),
      screenshotPath: await copy(screenshot, 'screenshot_'),
    );
  }

  Future<void> _deleteLocalCopies(_CopiedAttachments paths) async {
    for (final path in [paths.sourcePath, paths.outputPath, paths.screenshotPath]) {
      if (path == null) continue;
      try {
        final file = File(path);
        final parent = file.parent;
        await file.delete();
        if (await parent.exists()) await parent.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _recordAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final recent = (prefs.getStringList(_rateLimitKey) ?? const <String>[])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .where((value) => now.difference(value) < const Duration(hours: 1))
        .toList();
    if (recent.length >= 5) {
      throw const ReportServiceException('Please wait a bit before sending another report.');
    }
    recent.add(now);
    await prefs.setStringList(
      _rateLimitKey,
      recent.map((value) => value.toIso8601String()).toList(),
    );
  }

  Map<String, dynamic> _sanitizeContext(Map<String, dynamic> context) {
    final result = <String, dynamic>{};
    for (final entry in context.entries.take(40)) {
      final key = entry.key.trim();
      if (key.isEmpty ||
          RegExp(r'password|token|secret|credential|email|qr|wifi|content|path|auth', caseSensitive: false).hasMatch(key)) {
        continue;
      }
      final value = _sanitizeValue(entry.value);
      if (value != null) result[key.length > 100 ? key.substring(0, 100) : key] = value;
    }
    return result;
  }

  dynamic _sanitizeValue(dynamic value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return value.length > 500 ? value.substring(0, 500) : value;
    if (value is List) return value.take(20).map(_sanitizeValue).where((v) => v != null).toList();
    if (value is Map) {
      return _sanitizeContext(Map<String, dynamic>.from(value));
    }
    final text = value.toString();
    return text.length > 500 ? text.substring(0, 500) : text;
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned.substring(0, min(cleaned.length, 120));
  }

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class _CopiedAttachments {
  final String? sourcePath;
  final String? outputPath;
  final String? screenshotPath;
  const _CopiedAttachments({this.sourcePath, this.outputPath, this.screenshotPath});
}
