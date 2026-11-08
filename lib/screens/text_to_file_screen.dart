import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/generation_options.dart';
import '../services/math_formula_service.dart';
import '../services/output_generator.dart';
import '../widgets/figma_app_chrome.dart';
import 'preview_screen.dart';

class TextToFileScreen extends StatefulWidget {
  const TextToFileScreen({super.key});

  @override
  State<TextToFileScreen> createState() => _TextToFileScreenState();
}

class _TextToFileScreenState extends State<TextToFileScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  String _format = 'docx';
  String _style = 'modern';
  bool _isConverting = false;
  double _conversionProgress = 0;
  String _conversionStatus = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(_refreshTextCount);
  }

  void _refreshTextCount() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_refreshTextCount);
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pasteText() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (value?.text == null || value!.text!.trim().isEmpty) {
      _message('Your clipboard has no text.', error: true);
      return;
    }
    _text.text = value.text!;
  }

  Future<void> _convert() async {
    final raw = _text.text.trim();
    if (raw.isEmpty) { _message('Paste or type text first.', error: true); return; }
    setState(() {
      _isConverting = true;
      _conversionProgress = 0.08;
      _conversionStatus = 'Preparing your text...';
    });
    try {
      final title = _title.text.trim().isEmpty ? 'Text Document' : _title.text.trim();
      _updateConversionProgress(0.28, 'Separating paragraphs and detecting formulas...');
      final mapping = <String, dynamic>{
        '{{TITLE}}': title,
        '{{SECTION_TEXT}}': '',
        '{{CONTENT_TEXT}}': [
          for (final paragraph in raw.split(RegExp(r'\n\s*\n')).where((item) => item.trim().isNotEmpty))
            _contentBlockForText(paragraph.trim()),
        ],
      };
      final options = GenerationOptions(selectedFormats: [_format], styleProfile: _style, outputName: title, workspaceMode: 'text');
      _updateConversionProgress(0.62, 'Formatting your ${_format.toUpperCase()} document...');
      final files = await OutputGenerator.generate(const {}, mapping, options);
      _updateConversionProgress(0.95, 'Opening the editable preview...');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PreviewScreen(outputPaths: files, mapping: mapping, options: options)));
    } catch (e) { _message('Could not convert text: $e', error: true); }
    finally {
      if (mounted) {
        setState(() {
          _isConverting = false;
          _conversionProgress = 0;
          _conversionStatus = '';
        });
      }
    }
  }

  void _updateConversionProgress(double progress, String status) {
    if (!mounted) return;
    setState(() {
      _conversionProgress = progress.clamp(0, 1);
      _conversionStatus = status;
    });
  }

  Map<String, dynamic> _contentBlockForText(String value) {
    final formula = MathFormulaService.parse(value);
    if (formula == null) return {'type': 'paragraph', 'text': value};
    return {
      'type': 'formula',
      'text': formula.displayText,
      'latex': value,
      'formula_omml': formula.omml,
      if (formula.warning?.isNotEmpty == true) 'error': formula.warning,
    };
  }

  void _message(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
          content: Text(
            text,
            style: error
                ? TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)
                : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FigmaAppShell(
        title: 'Text to file',
        subtitle: 'Turn pasted text into a document',
        selectedIndex: 1,
        showBack: true,
        showProfile: false,
        referenceHeader: true,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      hintText: 'File title (optional)',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Document text',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FigmaAppColors.text(context),
                        ),
                      ),
                      const Spacer(),
                      TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _pasteText, child: const Text('Paste')),
                      TextButton(
                        onPressed: _text.text.isEmpty ? null : () => _text.clear(),
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).hintColor, minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 220,
                    child: TextField(
                      controller: _text,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Paste or type your text',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _text.text.length.toString() + ' characters',
                    style: TextStyle(
                      color: FigmaAppColors.subtext(context),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth < 360
                            ? Column(
                                children: [
                                  _formatPicker(),
                                  const SizedBox(height: 10),
                                  _stylePicker(),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: _formatPicker()),
                                  const SizedBox(width: 10),
                                  Expanded(child: _stylePicker()),
                                ],
                              ),
                  ),
                  const SizedBox(height: 18),
                  FigmaPrimaryButton(
                    label: _isConverting ? 'Converting...' : 'Convert text',
                    onPressed: _isConverting ? null : _convert,
                  ),
                ],
              ),
            ),
            if (_isConverting) _buildConversionLoadingOverlay(),
          ],
        ),
      );

  Widget _buildConversionLoadingOverlay() {
    final percentage = (_conversionProgress * 100).round();
    return ColoredBox(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.68),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: FigmaCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: FigmaAppColors.primary(context).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: FigmaAppColors.primary(context), size: 29),
                  ),
                  const SizedBox(height: 18),
                  Text('Creating your document', style: TextStyle(color: FigmaAppColors.text(context), fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(_conversionStatus, textAlign: TextAlign.center, style: TextStyle(color: FigmaAppColors.subtext(context))),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: _conversionProgress, minHeight: 9, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
                    )),
                    const SizedBox(width: 12),
                    Text('$percentage%', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 14),
                  Text('Keep the app open while we prepare your file.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: FigmaAppColors.subtext(context))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formatPicker() => _buildChoicePicker(
        label: 'Format',
        currentValue: _format,
        options: const {
          'DOCX': 'docx',
          'PDF': 'pdf',
          'HTML': 'html',
          'TXT': 'txt',
        },
        onSelected: (value) => setState(() => _format = value),
      );

  Widget _stylePicker() => _buildChoicePicker(
        label: 'Style',
        currentValue: _style,
        options: const {
          'Modern': 'modern',
          'Clean': 'clean',
          'Academic': 'academic',
          'Notes': 'module',
        },
        onSelected: (value) => setState(() => _style = value),
      );

  Widget _buildChoicePicker({
    required String label,
    required String currentValue,
    required Map<String, String> options,
    required ValueChanged<String> onSelected,
  }) {
    final currentLabel =
        options.entries.firstWhere((entry) => entry.value == currentValue).key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FigmaAppColors.subtext(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showChoiceSheet(
            label: label,
            currentValue: currentValue,
            options: options,
            onSelected: onSelected,
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: FigmaAppColors.fill(context),
              border: Border.all(color: FigmaAppColors.border(context)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentLabel,
                    style: TextStyle(
                      color: FigmaAppColors.text(context),
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  color: FigmaAppColors.subtext(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showChoiceSheet({
    required String label,
    required String currentValue,
    required Map<String, String> options,
    required ValueChanged<String> onSelected,
  }) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final option in options.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.key),
                  trailing: option.value == currentValue
                      ? Icon(
                          Icons.check_rounded,
                          color: FigmaAppColors.primary(sheetContext),
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null) onSelected(value);
  }
}
