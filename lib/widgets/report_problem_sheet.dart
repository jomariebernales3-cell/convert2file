import 'bootstrap_icon.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/file_storage.dart';
import '../services/report_service.dart';

Future<void> showReportProblemSheet(BuildContext context,
        {required String area,
        Map<String, dynamic> contextInfo = const {},
        String? sourceFilePath,
        String? outputFilePath}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ReportProblemSheet(
              area: area,
              contextInfo: contextInfo,
              sourceFilePath: sourceFilePath,
              outputFilePath: outputFilePath),
        ),
      ),
    );

class ReportProblemSheet extends StatefulWidget {
  final String area;
  final Map<String, dynamic> contextInfo;
  final String? sourceFilePath;
  final String? outputFilePath;
  const ReportProblemSheet(
      {super.key,
      required this.area,
      required this.contextInfo,
      this.sourceFilePath,
      this.outputFilePath});
  @override
  State<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<ReportProblemSheet> {
  static const areas = <String, String>{
    'conversion': 'Conversion',
    'study_guide': 'Study guide',
    'quiz': 'Quiz',
    'qr_code': 'QR code',
    'text_to_file': 'Text to file',
    'my_materials': 'My materials',
    'offline_ai': 'Offline AI',
    'login': 'Sign in',
    'settings': 'Settings',
    'other': 'Other'
  };
  final _controller = TextEditingController();
  final _service = ReportService();
  late String _area;
  late bool _includeEmail;
  bool _source = false,
      _output = false,
      _technical = true,
      _sending = false,
      _sent = false,
      _offline = false;
  String? _error, _id, _screenshotPath, _screenshotName;
  @override
  void initState() {
    super.initState();
    _area = areas.containsKey(widget.area) ? widget.area : 'other';
    _includeEmail = AuthService().isLoggedIn;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fileSummary(String path) {
    final file = File(path);
    final name = file.uri.pathSegments.last;
    try {
      final size = file.lengthSync();
      return '$name · ${size < 1048576 ? '${(size / 1024).ceil()} KB' : '${(size / 1048576).toStringAsFixed(1)} MB'}';
    } catch (_) {
      return name;
    }
  }

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final image = result.files.first;
    if (image.size > 10 * 1024 * 1024) {
      setState(() => _error = 'Screenshots must be 10 MB or smaller.');
      return;
    }
    try {
      final directory = await FileStorage.cachePath;
      final extension = image.name.contains('.')
          ? '.${image.name.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}'
          : '.png';
      final destination =
          '$directory/report_screenshot_${DateTime.now().microsecondsSinceEpoch}$extension';
      if (image.bytes != null) {
        await File(destination).writeAsBytes(image.bytes!);
      } else if (image.path != null) {
        await File(image.path!).copy(destination);
      } else {
        setState(() => _error =
            'Could not read that screenshot. Please choose another image.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _screenshotPath = destination;
        _screenshotName = image.name;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not save that screenshot. Please try again.');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.length < 10 || text.length > 2000) {
      setState(
          () => _error = 'Enter 10 to 2,000 characters about the problem.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await _service.submit(ReportDraft(
          area: _area,
          description: text,
          contextInfo: widget.contextInfo,
          sourceFilePath: widget.sourceFilePath,
          outputFilePath: widget.outputFilePath,
          attachSource: _source,
          attachOutput: _output,
          screenshotFilePath: _screenshotPath,
          includeTechnicalDetails: _technical,
          includeEmail: _includeEmail));
      if (mounted)
        setState(() {
          _id = result.id;
          _offline = result.savedOffline;
          _sent = true;
        });
    } on ReportServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not save the report. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _toggle(String title, String? subtitle, bool value,
          ValueChanged<bool> changed) =>
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: _sending ? null : changed);
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
        top: false,
        child: Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _sent ? _success(colors) : _form(colors)));
  }

  Widget _success(ColorScheme colors) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BootstrapIcon.material(
                _offline
                    ? Icons.cloud_off_outlined
                    : Icons.check_circle_outline,
                size: 56,
                color: colors.primary),
            const SizedBox(height: 14),
            Text(
                _offline
                    ? "Saved. We'll send it when you're back online."
                    : 'Thanks, we got your report',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (!_offline && _id != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Reference: ${_id!.substring(0, 8)}',
                      style: TextStyle(color: colors.onSurfaceVariant))),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'))),
          ])));
  Widget _form(ColorScheme colors) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
            child: Row(children: [
              Expanded(
                  child: Text('Report a problem',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800))),
              SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                      tooltip: 'Close',
                      onPressed: _sending ? null : () => Navigator.pop(context),
                      icon: const BootstrapIcon.material(Icons.close)))
            ])),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
              if (widget.area == 'other') ...[
                DropdownButtonFormField<String>(
                    value: _area,
                    decoration: const InputDecoration(labelText: 'Area'),
                    items: areas.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: _sending
                        ? null
                        : (v) {
                            if (v != null) setState(() => _area = v);
                          }),
                const SizedBox(height: 14)
              ],
              TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 2000,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                      labelText: 'What went wrong?',
                      hintText:
                          'Tell us what you did, what you expected, and what happened.',
                      alignLabelWithHint: true,
                      errorText: _error)),
              const SizedBox(height: 6),
              if (widget.sourceFilePath != null)
                _toggle(
                    'Attach the original file',
                    _fileSummary(widget.sourceFilePath!),
                    _source,
                    (v) => setState(() => _source = v)),
              if (widget.outputFilePath != null)
                _toggle(
                    'Attach the converted file',
                    _fileSummary(widget.outputFilePath!),
                    _output,
                    (v) => setState(() => _output = v)),
              OutlinedButton.icon(
                onPressed: _sending ? null : _pickScreenshot,
                icon: const BootstrapIcon.material(Icons.screenshot_outlined),
                label: Text(_screenshotName == null
                    ? 'Attach screenshot (optional)'
                    : 'Screenshot: $_screenshotName'),
              ),
              const SizedBox(height: 8),
              _toggle('Include technical details', 'Platform and options used',
                  _technical, (v) => setState(() => _technical = v)),
              if (AuthService().isLoggedIn)
                _toggle(
                    'Include my email so you can reply',
                    AuthService().currentUser?.email,
                    _includeEmail,
                    (v) => setState(() => _includeEmail = v)),
              Text(
                  'Files are sent to the Convert2File team only to fix this problem. Do not attach files with private information.',
                  style:
                      TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 16),
              SizedBox(
                  height: 56,
                  child: FilledButton(
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Send'))),
            ])),
      ]);
}
