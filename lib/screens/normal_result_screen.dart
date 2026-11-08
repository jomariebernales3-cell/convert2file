import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/file_storage.dart';
import '../theme/app_colors.dart';

class NormalResultScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String fileType;
  final int fileSizeBytes;
  final List<String> notes;

  const NormalResultScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.fileType,
    required this.fileSizeBytes,
    this.notes = const [],
  });

  @override
  State<NormalResultScreen> createState() => _NormalResultScreenState();
}

class _NormalResultScreenState extends State<NormalResultScreen> {
  bool _isBusy = false;

  Future<void> _open() async {
    await _runAction(() async {
      final result = await OpenFilex.open(widget.filePath);
      if (result.type != ResultType.done) {
        throw Exception(result.message.isEmpty
            ? 'No app is available to open this file type.'
            : result.message);
      }
    });
  }

  Future<void> _download() async {
    await _runAction(() async {
      final savedPath = await FileDownload.copyToDownloadsFolder(
        widget.filePath,
        fileName: widget.fileName,
      );
      if (savedPath.isEmpty) return;
      _showMessage('Downloaded to: $savedPath');
    });
  }

  Future<void> _share() async {
    await _runAction(() async {
      await FileShareService.shareFileWithName(
        sourcePath: widget.filePath,
        fileName: widget.fileName,
      );
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
    } catch (error) {
      _showMessage('Action failed: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final colors = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.surface2,
        content: Text(message, style: TextStyle(color: colors.text)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fileExists = File(widget.filePath).existsSync();
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Conversion complete'),
        backgroundColor: colors.background,
        foregroundColor: colors.text,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline,
                      color: colors.accent, size: 34),
                  const SizedBox(height: 16),
                  Text(
                    widget.fileName,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.fileType.toUpperCase()} · ${FileStorage.formatFileSize(widget.fileSizeBytes)}',
                    style: TextStyle(color: colors.muted),
                  ),
                  if (!fileExists) ...[
                    const SizedBox(height: 12),
                    Text(
                      'The saved file could not be found.',
                      style: TextStyle(color: colors.danger),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conversion notes',
                        style: TextStyle(
                            color: colors.text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final note in widget.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(note,
                            style: TextStyle(color: colors.muted)),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isBusy || !fileExists ? null : _open,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isBusy || !fileExists ? null : _download,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isBusy || !fileExists ? null : _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }
}
