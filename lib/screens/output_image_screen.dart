import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/file_share_service.dart';
import '../services/file_storage.dart';

class OutputImageScreen extends StatefulWidget {
  final Map<String, dynamic> file;

  const OutputImageScreen({super.key, required this.file});

  @override
  State<OutputImageScreen> createState() => _OutputImageScreenState();
}

class _OutputImageScreenState extends State<OutputImageScreen> {
  String get _path => widget.file['path'] as String? ?? '';
  String get _name => widget.file['original_name'] as String? ?? 'Image';
  bool _isSavingPhotos = false;
  int get _size => widget.file['size_bytes'] as int? ?? 0;
  String get _createdAt => widget.file['created_at'] as String? ?? '';

  void _message(String message, {String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      action: action == null || onAction == null
          ? null
          : SnackBarAction(label: action, onPressed: onAction),
    ));
  }

  Future<void> _share() async {
    try {
      await FileShareService.shareFileWithName(sourcePath: _path, fileName: _name);
    } catch (error) {
      debugPrint('[QR] Share image failed: $error');
      _message('Could not share this image.');
    }
  }

  Future<void> _saveToPhotos() async {
    if (_isSavingPhotos) return;
    setState(() => _isSavingPhotos = true);
    try {
      var allowed = await Gal.hasAccess(toAlbum: true);
      if (!allowed) allowed = await Gal.requestAccess(toAlbum: true);
      if (!allowed) {
        _message('Photos permission was denied.', action: 'Open settings', onAction: openAppSettings);
        return;
      }
      await Gal.putImage(_path, album: 'Convert2File');
      _message('Saved to Photos.');
    } on GalException catch (error) {
      debugPrint('[QR] Save image to Photos failed: $error');
      if (error.type == GalExceptionType.accessDenied) {
        _message('Photos permission was denied.', action: 'Open settings', onAction: openAppSettings);
      } else {
        _message(switch (error.type) {
          GalExceptionType.notEnoughSpace => 'Not enough space to save this image.',
          GalExceptionType.notSupportedFormat => 'This image format is not supported.',
          _ => 'Could not save this image to Photos.',
        });
      }
    } catch (error) {
      debugPrint('[QR] Save image to Photos failed: $error');
      _message('Could not save this image to Photos.');
    } finally {
      if (mounted) setState(() => _isSavingPhotos = false);
    }
  }
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete output?'),
        content: const Text('This removes the image from My materials.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await FileStorage.deleteFile(widget.file['id'] as int);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _dateLabel() {
    final parsed = DateTime.tryParse(_createdAt)?.toLocal();
    if (parsed == null) return _createdAt;
    final date = '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}';
    return parsed.year == DateTime.now().year ? date : '$date/${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Share image', onPressed: _share, icon: const Icon(Icons.share_outlined)),
          IconButton(tooltip: 'Save to Photos', onPressed: _isSavingPhotos ? null : _saveToPhotos, icon: _isSavingPhotos ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined)),
          IconButton(tooltip: 'Delete output', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<bool>(
          future: File(_path).exists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data != true) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('This file was moved or deleted'),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _delete, child: const Text('Remove entry')),
                  ]),
                ),
              );
            }
            return Column(children: [
              Expanded(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.file(File(_path), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Column(mainAxisSize: MainAxisSize.min, children: [const Text('This file was moved or deleted'), TextButton(onPressed: _delete, child: const Text('Remove entry'))])),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(children: [
                  Expanded(child: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
                  const SizedBox(width: 12),
                  Text('${FileStorage.formatFileSize(_size)} · ${_dateLabel()}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}