import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _authService = AuthService();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  PlatformFile? _screenshot;
  final String _complaintMode = 'direct';
  final Map<String, PlatformFile> _attachments = {};
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.size > 5 * 1024 * 1024) {
      _showError('Screenshot must be 5 MB or smaller');
      return;
    }

    setState(() => _screenshot = file);
  }

  Future<void> _pickAttachment(String slot) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx', 'pdf', 'txt', 'ppt', 'pptx', 'html'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.size > 25 * 1024 * 1024) {
      _showError('Attached file must be 25 MB or smaller');
      return;
    }

    setState(() => _attachments[slot] = file);
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    final user = await _authService.requireLocalUser();
    if (subject.length < 4 || subject.length > 180) {
      _showError('Subject must be 4 to 180 characters');
      return;
    }
    if (message.length < 12) {
      _showError('Details must be at least 12 characters');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? screenshotPath;
      String? screenshotName;
      final bugDir = await _bugReportDirectory();
      if (_screenshot != null) {
        final ext = path.extension(_screenshot!.name);
        screenshotName = 'bug_${DateTime.now().millisecondsSinceEpoch}$ext';
        screenshotPath = '${bugDir.path}/$screenshotName';
        if (_screenshot!.bytes != null) {
          await File(screenshotPath).writeAsBytes(_screenshot!.bytes!);
        } else if (_screenshot!.path != null) {
          await File(_screenshot!.path!).copy(screenshotPath);
        }
      }

      final savedAttachments = <Map<String, dynamic>>[];
      for (final slot in _requiredAttachmentSlots) {
        final attachment = _attachments[slot];
        if (attachment == null) continue;

        final ext = path.extension(attachment.name);
        final safeSlot = slot.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
        final storedName =
            '${safeSlot}_${DateTime.now().microsecondsSinceEpoch}$ext';
        final storedPath = '${bugDir.path}/$storedName';
        if (attachment.bytes != null) {
          await File(storedPath).writeAsBytes(attachment.bytes!);
        } else if (attachment.path != null) {
          await File(attachment.path!).copy(storedPath);
        }
        savedAttachments.add({
          'slot': slot,
          'label': _attachmentLabel(slot),
          'original_name': attachment.name,
          'stored_name': storedName,
          'path': storedPath,
          'size_bytes': attachment.size,
        });
      }

      await DatabaseHelper.instance.insertBugReport({
        'user_id': user.id,
        'reporter_name': user.name,
        'reporter_email': user.email,
        'subject': subject,
        'message': message,
        'screenshot_path': screenshotPath,
        'screenshot_name': screenshotName,
        'complaint_mode': _complaintMode,
        'attachments_json': jsonEncode(savedAttachments),
        'status': 'new',
        'created_at': DateTime.now().toIso8601String(),
      });
      await DatabaseHelper.instance.insertLog({
        'user_id': user.id,
        'level': 'info',
        'event_type': 'bug_report.created',
        'message': 'Bug report submitted',
        'context_json': null,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bug report submitted')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      await DatabaseHelper.instance.insertLog({
        'user_id': user.id,
        'level': 'error',
        'event_type': 'bug_report.create_failed',
        'message': e.toString(),
        'context_json': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      _showError('Submit failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(message)),
    );
  }

  Future<Directory> _bugReportDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final bugDir = Directory('${dir.path}/smart_template/bug_reports');
    if (!await bugDir.exists()) await bugDir.create(recursive: true);
    return bugDir;
  }

  List<String> get _requiredAttachmentSlots {
    return ['data_source', 'output'];
  }

  String _attachmentLabel(String slot) {
    return switch (slot) {
      'data_source' => 'Data source file',
      'output' => 'Output file',
      _ => 'Attachment',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bug Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _subjectController,
            maxLength: 180,
            decoration: const InputDecoration(
              labelText: 'Subject',
              prefixIcon: Icon(Icons.subject),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Details',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 16),
          ..._requiredAttachmentSlots.map(_buildAttachmentButton),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.image),
            label: Text(
                _screenshot == null ? 'Attach screenshot' : _screenshot!.name),
          ),
          const SizedBox(height: 12),
          Text(
            'Admin contact: admin@smarttemplate.app',
            style: TextStyle(color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('SUBMIT REPORT'),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentButton(String slot) {
    final file = _attachments[slot];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: () => _pickAttachment(slot),
        icon: Icon(file == null ? Icons.attach_file : Icons.check_circle),
        label: Text(file == null ? _attachmentLabel(slot) : file.name),
      ),
    );
  }
}
