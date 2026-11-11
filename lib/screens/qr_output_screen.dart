import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/file_storage.dart';
import '../widgets/report_problem_entry.dart';

class QrOutputScreen extends StatefulWidget {
  final Map<String, dynamic> file;

  const QrOutputScreen({super.key, required this.file});

  @override
  State<QrOutputScreen> createState() => _QrOutputScreenState();
}

class _QrOutputScreenState extends State<QrOutputScreen> {
  Map<String, dynamic> get _metadata {
    try {
      return jsonDecode(widget.file['metadata_json'] as String? ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  bool get _isWifi =>
      (_metadata['qr_type'] as String? ?? '').toLowerCase().contains('wifi');

  String get _path => widget.file['path'] as String? ?? '';
  String get _name => widget.file['original_name'] as String? ?? 'QR code.png';
  bool _isSavingPhotos = false;

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        content: Text(text),
      ),
    );
  }

  Future<void> _share() async {
    try {
      await FileShareService.shareFileWithName(sourcePath: _path, fileName: _name);
    } catch (e) {
      if (mounted) _message('Could not share QR code: $e', error: true);
    }
  }

  Future<void> _download() async {
    try {
      final destination = await FileDownload.copyToDownloadsFolder(
        _path,
        fileName: _name,
      );
      if (mounted && destination.isNotEmpty) _message('QR code downloaded.');
    } catch (e) {
      if (mounted) _message('Could not download QR code: $e', error: true);
    }
  }

  Future<void> _saveToPhotos() async {
    if (_isSavingPhotos) return;
    setState(() => _isSavingPhotos = true);
    try {
      var allowed = await Gal.hasAccess(toAlbum: true);
      if (!allowed) allowed = await Gal.requestAccess(toAlbum: true);
      if (!allowed) {
        if (mounted) _message('Photos permission was denied.');
        return;
      }
      await Gal.putImage(_path, album: 'Convert2File');
      if (mounted) _message('QR code saved to Photos.');
    } on GalException catch (error) {
      debugPrint('[QR] Save to Photos failed: $error');
      if (mounted) {
        final message = switch (error.type) {
          GalExceptionType.accessDenied => 'Photos permission was denied.',
          GalExceptionType.notEnoughSpace => 'Not enough space to save the QR image.',
          GalExceptionType.notSupportedFormat => 'This image format is not supported.',
          GalExceptionType.unexpected => 'Could not save the QR image to Photos.',
        };
        _message(message, error: true);
      }
    } catch (error) {
      debugPrint('[QR] Save to Photos failed: $error');
      if (mounted) _message('Could not save the QR image to Photos.', error: true);
    } finally {
      if (mounted) setState(() => _isSavingPhotos = false);
    }
  }
  Future<void> _copyContent() async {
    final content = _metadata['content'] as String?;
    if (content == null || content.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) _message('QR content copied.');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete QR code?'),
        content: const Text('This will remove the saved QR image from My materials.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await FileStorage.deleteFile(widget.file['id'] as int);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = _metadata['content'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Share QR image', onPressed: _share, icon: const Icon(Icons.share_outlined)),
          IconButton(tooltip: 'Save to Photos', onPressed: _isSavingPhotos ? null : _saveToPhotos, icon: _isSavingPhotos ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined)),
          IconButton(tooltip: 'Delete QR output', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 420),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 6,
                    child: Image.file(
                      File(_path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant),
                        const Text('This file was moved or deleted'),
                        TextButton(onPressed: _delete, child: const Text('Remove entry')),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${FileStorage.formatFileSize(widget.file['size_bytes'] as int? ?? 0)} · ${widget.file['created_at'] as String? ?? ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (!_isWifi && content != null && content.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(content),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _isSavingPhotos ? null : _saveToPhotos,
                icon: _isSavingPhotos ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined),
                label: const Text('Save to Photos'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
              ),
              if (!_isWifi && content != null && content.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _copyContent,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy content'),
                ),
              ],
              const SizedBox(height: 10),
              ReportProblemEntry(
                area: 'qr_code',
                contextInfo: {'action': 'create', 'qr_type': _metadata['qr_type'] ?? 'unknown'},
                outputFilePath: _path,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: colors.error),
                label: Text('Delete', style: TextStyle(color: colors.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
