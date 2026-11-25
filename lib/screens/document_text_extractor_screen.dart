import '../widgets/bootstrap_icon.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/document_parser.dart';
import '../widgets/figma_app_chrome.dart';

class DocumentTextExtractorScreen extends StatefulWidget {
  const DocumentTextExtractorScreen({super.key});

  @override
  State<DocumentTextExtractorScreen> createState() =>
      _DocumentTextExtractorScreenState();
}

class _DocumentTextExtractorScreenState
    extends State<DocumentTextExtractorScreen> {
  bool _includeTables = true;
  bool _includeEquations = true;
  bool _busy = false;
  String? _sourceName;
  String? _sourceExtension;
  String? _sourcePath;
  String? _temporarySourcePath;
  String _text = '';

  @override
  void dispose() {
    final temporaryPath = _temporarySourcePath;
    if (temporaryPath != null) {
      unawaited(
          File(temporaryPath).delete().then<void>((_) {}).catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _pickAndExtract() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'pptx', 'ppt', 'txt'],
      withData: true,
    );
    if (!mounted) return;
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final extension =
        p.extension(file.name).replaceFirst('.', '').toLowerCase();
    if (!const {'pdf', 'docx', 'pptx', 'ppt', 'txt'}.contains(extension)) {
      _showMessage('Choose a PDF, DOCX, PPTX, PPT, or TXT file.', error: true);
      return;
    }

    final priorTemporaryPath = _temporarySourcePath;
    if (priorTemporaryPath != null) {
      try {
        await File(priorTemporaryPath).delete();
      } on Object {
        // Continue with the newly selected source even if cleanup fails.
      }
    }
    _temporarySourcePath = null;
    try {
      var sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        final bytes = file.bytes;
        if (bytes == null)
          throw Exception('The selected file could not be read.');
        final temporaryDirectory = await getTemporaryDirectory();
        final temporaryFile = File(p.join(
          temporaryDirectory.path,
          'extract_${DateTime.now().microsecondsSinceEpoch}.$extension',
        ));
        await temporaryFile.writeAsBytes(bytes, flush: true);
        sourcePath = temporaryFile.path;
        _temporarySourcePath = sourcePath;
      }
      _sourcePath = sourcePath;
      _sourceName = file.name;
      _sourceExtension = extension;
      await _extractCurrent();
    } catch (error) {
      if (mounted) _showMessage('Could not extract text: $error', error: true);
    }
  }

  Future<void> _extractCurrent() async {
    final sourcePath = _sourcePath;
    final extension = _sourceExtension;
    if (!mounted || sourcePath == null || extension == null) return;
    setState(() {
      _busy = true;
      _text = '';
    });
    try {
      final result = await DocumentParser.extractTextForUser(
        sourcePath,
        extension,
        includeTables: _includeTables,
        includeEquations: _includeEquations,
      );
      if (!mounted) return;
      setState(() => _text = result.trim());
      if (_text.isEmpty) {
        _showMessage(
          extension == 'pdf'
              ? 'No selectable text was found. This may be a scanned PDF; OCR is not available offline in this extractor.'
              : 'No text was found in this file.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Could not extract text: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyText() async {
    if (_text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) _showMessage('Extracted text copied.');
  }

  Future<void> _saveText() async {
    if (_text.isEmpty) return;
    final baseName = p.basenameWithoutExtension(_sourceName ?? 'document');
    final safeName = baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    try {
      final savedPath = await FilePicker.saveFile(
        fileName: '${safeName.isEmpty ? 'extracted_text' : safeName}_text.txt',
        bytes: Uint8List.fromList(utf8.encode(_text)),
      );
      if (mounted && (savedPath?.isNotEmpty ?? false)) {
        _showMessage('Text file saved.');
      }
    } catch (error) {
      if (mounted)
        _showMessage('Could not save the text file: $error', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) => FigmaAppShell(
        title: 'Text extractor',
        subtitle: 'Get clean text from your documents',
        selectedIndex: 1,
        showBack: true,
        showProfile: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _introCard(context),
            const SizedBox(height: 16),
            FigmaPrimaryButton(
              label: _busy ? 'Extracting text…' : 'Choose a document',
              onPressed: _busy ? null : _pickAndExtract,
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (_sourceName != null) ...[
              const SizedBox(height: 16),
              _optionsCard(context),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _sourceName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FigmaAppColors.text(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_text.length} characters',
                    style: TextStyle(color: FigmaAppColors.subtext(context)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                constraints:
                    const BoxConstraints(minHeight: 220, maxHeight: 460),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: FigmaAppColors.card(context),
                  border: Border.all(color: FigmaAppColors.border(context)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _text.isEmpty
                    ? Center(
                        child: Text(
                          _busy
                              ? 'Reading document…'
                              : 'Extracted text will appear here.',
                          style:
                              TextStyle(color: FigmaAppColors.subtext(context)),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _text,
                          style: TextStyle(
                            height: 1.45,
                            color: FigmaAppColors.text(context),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _text.isEmpty ? null : _copyText,
                      icon: const BootstrapIcon.material(Icons.copy_outlined),
                      label: const Text('Copy text'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _text.isEmpty ? null : _saveText,
                      icon:
                          const BootstrapIcon.material(Icons.download_outlined),
                      label: const Text('Save as TXT'),
                    ),
                  ),
                ],
              ),
              if (_sourceExtension == 'pdf') ...[
                const SizedBox(height: 10),
                Text(
                  'PDF extraction reads selectable text. Scanned pages need OCR, and repeated page header/footer lines are removed when detected.',
                  style: TextStyle(
                      fontSize: 12, color: FigmaAppColors.subtext(context)),
                ),
              ],
              if (_sourceExtension == 'ppt') ...[
                const SizedBox(height: 10),
                Text(
                  'Legacy PPT files use a basic offline text reader; review the result for accuracy.',
                  style: TextStyle(
                      fontSize: 12, color: FigmaAppColors.subtext(context)),
                ),
              ],
            ],
          ],
        ),
      );

  Widget _introCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FigmaAppColors.card(context),
          border: Border.all(color: FigmaAppColors.border(context)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BootstrapIcon.material(Icons.text_fields_outlined,
                color: FigmaAppColors.primary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Extracts document text only. Pictures and decorative graphics are left out. Choose whether to keep tables and equations where the file format exposes them.',
                style:
                    TextStyle(color: FigmaAppColors.text(context), height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _optionsCard(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: FigmaAppColors.card(context),
          border: Border.all(color: FigmaAppColors.border(context)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              value: _includeTables,
              onChanged: _busy || !{'docx', 'pptx'}.contains(_sourceExtension)
                  ? null
                  : (value) {
                      setState(() => _includeTables = value);
                      if (_sourceName != null) _extractCurrent();
                    },
              title: const Text('Include tables'),
              subtitle: Text(
                {'docx', 'pptx'}.contains(_sourceExtension)
                    ? 'Keep table cell text in reading order'
                    : 'Table structure is unavailable for this format',
              ),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              value: _includeEquations,
              onChanged: _busy || _sourceExtension != 'docx'
                  ? null
                  : (value) {
                      setState(() => _includeEquations = value);
                      if (_sourceName != null) _extractCurrent();
                    },
              title: const Text('Include equations and symbols'),
              subtitle: Text(
                _sourceExtension == 'docx'
                    ? 'Keep readable formula text and special characters'
                    : 'Structured equation filtering is available for DOCX; other formats keep extracted symbols',
              ),
            ),
          ],
        ),
      );
}
