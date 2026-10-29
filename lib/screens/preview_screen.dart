import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:open_filex/open_filex.dart';
import '../models/generation_options.dart';
import '../services/file_storage.dart';
import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/output_generator.dart';
import '../widgets/figma_app_chrome.dart';

class PreviewScreen extends StatefulWidget {
  final Map<String, String> outputPaths;
  final Map<String, dynamic> mapping;
  final GenerationOptions options;

  const PreviewScreen({
    super.key,
    required this.outputPaths,
    required this.mapping,
    required this.options,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _selectedFormat = 'docx';
  bool _isSharing = false;
  bool _isDownloading = false;
  bool _isApplyingEdits = false;
  bool _isOpeningFile = false;
  int? _selectedTextBlock;
  String? _selectedContentKey;
  bool _isTextToolbarExpanded = false;
  bool _isQualityNoticeDismissed = false;
  final Set<String> _selectedParagraphKeys = <String>{};
  late Map<String, String> _outputPaths;
  late Map<String, dynamic> _editableMapping;

  @override
  void initState() {
    super.initState();
    _outputPaths = Map<String, String>.from(widget.outputPaths);
    _editableMapping = _cloneMapping(widget.mapping);
    _selectedFormat = widget.options.selectedFormats.first;
  }

  Map<String, dynamic> _cloneMapping(Map<String, dynamic> source) {
    return source.map((key, value) => MapEntry(key, _cloneValue(value)));
  }

  dynamic _cloneValue(dynamic value) {
    if (value is Map) {
      return value
          .map((key, child) => MapEntry(key.toString(), _cloneValue(child)));
    }
    if (value is List) {
      return value.map(_cloneValue).toList();
    }
    return value;
  }

  Future<void> _shareFile() async {
    final path = _outputPaths[_selectedFormat];
    if (path == null || !await File(path).exists()) {
      _showError('File not found');
      return;
    }

    setState(() => _isSharing = true);
    try {
      await FileShareService.shareFileWithName(
        sourcePath: path,
        fileName: _preferredDownloadName(),
        subject: 'Convert2File - ${widget.mapping['{{TITLE}}'] ?? 'Document'}',
      );
    } catch (e) {
      _showError('Share failed: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  Future<void> _openGeneratedFile() async {
    final path = _outputPaths[_selectedFormat];
    if (path == null || !await File(path).exists()) {
      _showError('File not found');
      return;
    }

    setState(() => _isOpeningFile = true);
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        _showError(result.message.isEmpty
            ? 'No app is available to open this file type.'
            : result.message);
      }
    } catch (e) {
      _showError('Could not open file: $e');
    } finally {
      if (mounted) setState(() => _isOpeningFile = false);
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _plainOutputText()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Output text copied to clipboard')),
      );
    }
  }

  String _plainOutputText() {
    final buffer = StringBuffer();
    final title =
        (_editableMapping['{{TITLE}}'] as String? ?? 'Generated Document')
            .trim();
    if (title.isNotEmpty) {
      buffer.writeln(title);
      buffer.writeln();
    }

    for (final section in _extractPreviewSections()) {
      final heading = (section['heading'] as String? ?? '').trim();
      if (heading.isNotEmpty) {
        buffer.writeln(heading);
        buffer.writeln();
      }

      for (final item in section['content'] as List? ?? []) {
        if (item is! Map) continue;
        final type = item['type'] as String? ?? '';
        if (type == 'paragraph') {
          final text = (item['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
            buffer.writeln();
          }
        } else if (type == 'formula') {
          final text = (item['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            buffer.writeln('Formula: $text');
            final error = (item['error'] as String? ?? '').trim();
            if (error.isNotEmpty) {
              buffer.writeln('Formula detection note: $error');
            }
            buffer.writeln();
          }
        } else if (type == 'list') {
          for (final entry in item['items'] as List? ?? []) {
            buffer.writeln('- ${entry.toString()}');
          }
          buffer.writeln();
        } else if (type == 'table') {
          for (final row in item['rows'] as List? ?? []) {
            if (row is List) {
              buffer.writeln(row.map((cell) => cell.toString()).join('\t'));
            }
          }
          buffer.writeln();
        } else if (type == 'image') {
          final caption = (item['caption'] as String? ?? '').trim();
          if (caption.isNotEmpty) {
            buffer.writeln(caption);
            buffer.writeln();
          }
        }
      }
    }

    return buffer.toString().trim();
  }

  List<Map<String, dynamic>> _extractPreviewSections() {
    final sections = <Map<String, dynamic>>[];
    final usedPlaceholders = <String>{};

    for (final key in _editableMapping.keys) {
      if (key.startsWith('{{SECTION_') && !key.contains('_CONTENT')) {
        final contentKey = key.replaceFirst('{{SECTION_', '{{CONTENT_');
        if (usedPlaceholders.add(key)) {
          sections.add({
            'heading': _editableMapping[key] as String? ?? '',
            'content': _editableMapping[contentKey] as List? ?? [],
          });
        }
      }
    }

    return sections;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _editableMapping['{{TITLE}}'] as String? ?? 'Generated Document';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Preview & Export'),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Output file type',
              icon: Icon(_formatIcon(_selectedFormat), size: 21),
              onSelected: (format) => setState(() => _selectedFormat = format),
              itemBuilder: (context) => _outputPaths.keys
                  .map((format) => PopupMenuItem(
                        value: format,
                        child: Row(children: [
                          Icon(_formatIcon(format), size: 19),
                          const SizedBox(width: 10),
                          Text(format.toUpperCase()),
                        ]),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyToClipboard,
            tooltip: 'Copy output text',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTextEditorToolbar(),
          _buildConversionQualityNotice(),
          Expanded(
            child: _buildPreviewContent(title),
          ),
        ],
      ),
    );
  }

  IconData _formatIcon(String format) => switch (format) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'html' => Icons.code_outlined,
        'txt' => Icons.notes_outlined,
        _ => Icons.description_outlined,
      };

  Widget _buildConversionQualityNotice() {
    if (_isQualityNoticeDismissed) return const SizedBox.shrink();
    final diagnostics = _editableMapping['{{CONVERSION_DIAGNOSTICS}}'];
    if (diagnostics is! Map) return const SizedBox.shrink();
    final score = (diagnostics['score'] as num?)?.toInt() ?? 100;
    final warnings = (diagnostics['warnings'] as List? ?? [])
        .map((warning) => warning.toString().trim())
        .where((warning) => warning.isNotEmpty)
        .toList();
    final hasWarnings = warnings.isNotEmpty;
    final preservesOriginalLayout =
        (_editableMapping['{{PRESERVE_DOCX_LAYOUT}}'] == true ||
            _editableMapping['{{PRESERVE_PDF_LAYOUT}}'] == true) &&
        _editableMapping['{{LAYOUT_EDITED}}'] != true;
    final color = preservesOriginalLayout
        ? Colors.blue.shade700
        : hasWarnings
            ? Colors.amber.shade800
            : Colors.green.shade700;
    final label = preservesOriginalLayout
        ? 'Original layout preserved'
        : hasWarnings
            ? 'Review recommended'
            : 'Extraction looks good';
    final statusDetail = preservesOriginalLayout
        ? 'original source retained'
        : 'conversion confidence $score%';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasWarnings ? Icons.warning_amber_rounded : Icons.verified_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text('$label · $statusDetail', style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Close conversion notice',
                onPressed: () => setState(() => _isQualityNoticeDismissed = true),
                icon: const Icon(Icons.close_rounded, size: 19),
                color: color,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (hasWarnings) ...[
            const SizedBox(height: 6),
            ...warnings.map((warning) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('• $warning', style: const TextStyle(fontSize: 12)),
            )),
          ],
          if (preservesOriginalLayout) ...[
            const SizedBox(height: 6),
            const Text(
              'Formulas, tables, images, and original layout remain in the source export. Applying preview edits switches the edited format to reflow mode.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextEditorToolbar() {
    final selectedContentKey = _selectedContentKey ??
        (widget.options.workspaceMode == 'text' ? '{{CONTENT_TEXT}}' : '');
    final content = _editableMapping[selectedContentKey] as List? ?? [];
    final hasSelection = _selectedTextBlock != null &&
        _selectedTextBlock! >= 0 &&
        _selectedTextBlock! < content.length &&
        content[_selectedTextBlock!] is Map;
    final item = hasSelection
        ? Map<String, dynamic>.from(content[_selectedTextBlock!] as Map)
        : const <String, dynamic>{};
    final index = _selectedTextBlock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _isTextToolbarExpanded = !_isTextToolbarExpanded),
            child: SizedBox(
              height: 48,
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Edit', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface))),
                _editorTool(Icons.tune, 'Apply preview edits', _isApplyingEdits ? null : _applyPreviewEdits),
                _editorTool(Icons.open_in_new, 'Open actual ${_selectedFormat.toUpperCase()} file', _isOpeningFile ? null : _openGeneratedFile),
                _editorTool(Icons.download_outlined, 'Download', _isDownloading ? null : _downloadFile),
                _editorTool(Icons.share_outlined, 'Share', _isSharing ? null : _shareFile),
                Icon(_isTextToolbarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              ]),
            ),
          ),
          if (_isTextToolbarExpanded)
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
            _editorTool(Icons.select_all, 'Select all editable paragraphs', _selectAllEditableParagraphs, selected: _selectedParagraphKeys.isNotEmpty),
            _editorTool(Icons.format_bold, 'Bold', hasSelection ? () => _updateTextBlock(index!, {'bold': item['bold'] != true}) : null, selected: item['bold'] == true),
            _editorTool(Icons.format_italic, 'Italic', hasSelection ? () => _updateTextBlock(index!, {'italic': item['italic'] != true}) : null, selected: item['italic'] == true),
            _editorTool(Icons.highlight_alt_outlined, 'Highlight', hasSelection ? () => _updateTextBlock(index!, {'highlight': item['highlight'] != true}) : null, selected: item['highlight'] == true),
            _editorColorTool(Icons.format_color_text, 'Text color', item['textColor'] is String ? _colorFromHex(item['textColor'] as String) : FigmaAppColors.text(context), hasSelection ? (value) => _updateTextBlock(index!, {'textColor': value}) : null),
            _editorColorTool(Icons.format_color_fill, 'Highlight color', _colorFromHex(item['highlightColor'] as String? ?? 'FFF2A6'), hasSelection ? (value) => _updateTextBlock(index!, {'highlight': true, 'highlightColor': value}) : null),
            _editorTool(Icons.format_align_left, 'Left', hasSelection ? () => _updateTextBlock(index!, {'align': 'left'}) : null, selected: item['align'] == 'left'),
            _editorTool(Icons.format_align_center, 'Center', hasSelection ? () => _updateTextBlock(index!, {'align': 'center'}) : null, selected: item['align'] == 'center'),
            _editorTool(Icons.format_align_right, 'Right', hasSelection ? () => _updateTextBlock(index!, {'align': 'right'}) : null, selected: item['align'] == 'right'),
            _editorTool(Icons.format_align_justify, 'Justify', hasSelection ? () => _updateTextBlock(index!, {'align': 'justify'}) : null, selected: item['align'] == 'justify'),
            _editorTool(Icons.delete_outline, 'Delete', hasSelection ? () => _deleteTextBlock(index!) : null, destructive: true),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _editorTool(IconData icon, String label, VoidCallback? onPressed, {bool selected = false, bool destructive = false}) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        color: destructive ? Colors.red : selected ? Theme.of(context).colorScheme.primary : null,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    ),
  );

  Widget _editorColorTool(IconData icon, String label, Color color, ValueChanged<String>? onSelected) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: PopupMenuButton<String>(
      tooltip: label,
      enabled: onSelected != null,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: '111827', child: _ColorMenuItem('Black', Color(0xFF111827))),
        PopupMenuItem(value: '2563EB', child: _ColorMenuItem('Blue', Color(0xFF2563EB))),
        PopupMenuItem(value: 'DC2626', child: _ColorMenuItem('Red', Color(0xFFDC2626))),
        PopupMenuItem(value: '15803D', child: _ColorMenuItem('Green', Color(0xFF15803D))),
        PopupMenuItem(value: '7C3AED', child: _ColorMenuItem('Purple', Color(0xFF7C3AED))),
        PopupMenuItem(value: 'FFF2A6', child: _ColorMenuItem('Yellow', Color(0xFFFFF2A6))),
        PopupMenuItem(value: 'BBF7D0', child: _ColorMenuItem('Light green', Color(0xFFBBF7D0))),
        PopupMenuItem(value: 'BFDBFE', child: _ColorMenuItem('Light blue', Color(0xFFBFDBFE))),
        PopupMenuItem(value: 'FBCFE8', child: _ColorMenuItem('Pink', Color(0xFFFBCFE8))),
      ],
      child: IconButton(
        onPressed: null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        visualDensity: VisualDensity.compact,
        icon: Stack(alignment: Alignment.bottomCenter, children: [Icon(icon, size: 19), Container(width: 15, height: 3, color: color)]),
      ),
    ),
  );

  Color _colorFromHex(String hex) => Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  String _paragraphSelectionKey(String contentKey, int index) =>
      '$contentKey::$index';

  Future<void> _selectAllEditableParagraphs() async {
    final selectedKeys = <String>{};
    final paragraphs = <String>[];

    for (final entry in _editableMapping.entries) {
      final content = entry.value;
      if (content is! List) continue;
      for (var index = 0; index < content.length; index++) {
        final item = content[index];
        if (item is! Map || item['type'] != 'paragraph') continue;
        selectedKeys.add(_paragraphSelectionKey(entry.key, index));
        final text = (item['text'] as String? ?? '').trim();
        if (text.isNotEmpty) paragraphs.add(text);
      }
    }

    if (selectedKeys.isEmpty) {
      _showError('There are no editable paragraphs to select.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: paragraphs.join('\n\n')));
    if (!mounted) return;
    setState(() {
      _selectedParagraphKeys
        ..clear()
        ..addAll(selectedKeys);
      _selectedTextBlock = null;
      _selectedContentKey = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedKeys.length} paragraph(s) selected and copied.'),
      ),
    );
  }

  Widget _buildPreviewContent(String title) {
    if (widget.options.workspaceMode == 'text') {
      return _buildTextWorkspace();
    }
    if (_selectedFormat == 'html') {
      return _buildHtmlPreview();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          ..._buildSectionWidgets(),
          const SizedBox(height: 40),
          _buildFileInfo(),
        ],
      ),
    );
  }

  Widget _buildTextWorkspace() {
    final content = _editableMapping['{{CONTENT_TEXT}}'] as List? ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (content.isEmpty)
            _buildEmptyTextState()
          else
            ...content.asMap().entries.where((entry) => entry.value is Map).map((entry) => _buildTextBlock(entry.key, Map<String, dynamic>.from(entry.value as Map))),
        ],
      ),
    );
  }

  Widget _buildEmptyTextState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
    child: const Text('No text content is available.'),
  );

  Widget _buildTextBlock(int index, Map<String, dynamic> item) {
    final selected = _selectedTextBlock == index;
    final selectedBySelectAll = _selectedParagraphKeys.contains(
      _paragraphSelectionKey('{{CONTENT_TEXT}}', index),
    );
    final isBold = item['bold'] == true;
    final isHighlighted = item['highlight'] == true;
    final highlightColor = _colorFromHex(item['highlightColor'] as String? ?? 'FFF2A6');
    final rawTextColor = item['textColor'] as String?;
    final textColor = rawTextColor == null
        ? FigmaAppColors.text(context)
        : _colorFromHex(rawTextColor);
    final align = item['align'] as String? ?? 'left';
    final textAlign = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHighlighted
            ? highlightColor.withValues(alpha: 0.42)
            : (selected || selectedBySelectAll)
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: selectedBySelectAll
            ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65))
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          TextFormField(
            key: ValueKey('text-block-$index'),
            initialValue: item['text'] as String? ?? '',
            minLines: 2,
            maxLines: null,
            textAlign: textAlign,
            style: TextStyle(fontSize: 15, height: 1.5, fontWeight: isBold ? FontWeight.w800 : FontWeight.w400, fontStyle: item['italic'] == true ? FontStyle.italic : FontStyle.normal, color: textColor),
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              isDense: true,
              hintText: 'Type your text...',
            ),
            onTap: () => setState(() {
              _selectedParagraphKeys.clear();
              _selectedTextBlock = index;
              _selectedContentKey = '{{CONTENT_TEXT}}';
            }),
            onChanged: (value) => _updateTextBlock(index, {'text': value}),
          ),
        ],
      ),
    );
  }

  void _updateTextBlock(int index, Map<String, dynamic> changes) {
    final contentKey = _selectedContentKey ?? '{{CONTENT_TEXT}}';
    final content = _editableMapping[contentKey] as List? ?? [];
    if (index >= content.length || content[index] is! Map) return;
    setState(() => content[index] = {...Map<String, dynamic>.from(content[index] as Map), ...changes});
  }

  void _deleteTextBlock(int index) {
    final contentKey = _selectedContentKey ?? '{{CONTENT_TEXT}}';
    final content = _editableMapping[contentKey] as List? ?? [];
    if (index >= content.length) return;
    setState(() {
      content.removeAt(index);
      _selectedTextBlock = null;
    });
  }

  Widget _buildHtmlPreview() {
    final path = _outputPaths['html'];
    if (path == null) {
      return const Center(child: Text('HTML preview not available'));
    }

    return FutureBuilder<String>(
      future: File(path).readAsString(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            snapshot.data ?? '',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }

  List<Widget> _buildSectionWidgets() {
    final widgets = <Widget>[];
    final usedPlaceholders = <String>{};

    for (final key in _editableMapping.keys) {
      if (key.startsWith('{{SECTION_') && !key.contains('_CONTENT')) {
        final heading = _editableMapping[key] as String? ?? '';
        final contentKey = key.replaceFirst('{{SECTION_', '{{CONTENT_');
        final content = _editableMapping[contentKey] as List? ?? [];

        if (!usedPlaceholders.contains(key)) {
          usedPlaceholders.add(key);
          widgets.add(_buildSection(heading, contentKey, content));
        }
      }
    }

    return widgets;
  }

  Widget _buildSection(
      String heading, String contentKey, List<dynamic> content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...content.asMap().entries.map((entry) {
          final itemIndex = entry.key;
          final item = entry.value as Map<String, dynamic>;
          final type = item['type'] as String? ?? '';

          if (type == 'paragraph') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildEditableParagraph(contentKey, itemIndex, item),
            );
          } else if (type == 'formula') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildFormulaWidget(item),
            );
          } else if (type == 'list') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: (item['items'] as List? ?? []).map((listItem) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 14)),
                        Expanded(
                          child: Text(
                            listItem.toString(),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          } else if (type == 'table') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildEditableTable(contentKey, itemIndex, item),
            );
          } else if (type == 'image') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildEditableImage(contentKey, itemIndex, item),
            );
          }

          return const SizedBox.shrink();
        }),
        const SizedBox(height: 20),
        const Divider(color: Colors.white10),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildEditableParagraph(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> item,
  ) {
    final selected = _selectedContentKey == contentKey &&
        _selectedTextBlock == itemIndex;
    final selectedBySelectAll = _selectedParagraphKeys.contains(
      _paragraphSelectionKey(contentKey, itemIndex),
    );
    final align = item['align'] as String? ?? 'left';
    final textAlign = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
    final textColor = item['textColor'] is String
        ? _colorFromHex(item['textColor'] as String)
        : FigmaAppColors.text(context);
    final highlightColor = _colorFromHex(
      item['highlightColor'] as String? ?? 'FFF2A6',
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item['highlight'] == true
            ? highlightColor.withValues(alpha: 0.42)
            : (selected || selectedBySelectAll)
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: selectedBySelectAll
            ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65))
            : null,
      ),
      child: TextFormField(
        key: ValueKey('paragraph-$contentKey-$itemIndex'),
        initialValue: item['text'] as String? ?? '',
        minLines: 2,
        maxLines: null,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: item['bold'] == true ? FontWeight.w800 : FontWeight.w400,
          fontStyle:
              item['italic'] == true ? FontStyle.italic : FontStyle.normal,
          color: textColor,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onTap: () => setState(() {
          _selectedParagraphKeys.clear();
          _selectedContentKey = contentKey;
          _selectedTextBlock = itemIndex;
        }),
        onChanged: (value) {
          final content = _editableMapping[contentKey] as List? ?? [];
          if (itemIndex >= content.length) return;
          setState(() {
            content[itemIndex] = {
              ...Map<String, dynamic>.from(content[itemIndex] as Map),
              'text': value,
            };
          });
        },
      ),
    );
  }

  Widget _buildEditableTable(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> item,
  ) {
    final widthPercent = (item['width_percent'] as num?)?.toDouble() ?? 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (widthPercent / 100).clamp(0.45, 1.0),
            child: _buildTableWidget(item['rows'] as List? ?? []),
          ),
        ),
        TextButton.icon(
          onPressed: () => _showTableEditor(contentKey, itemIndex, item),
          icon: const Icon(Icons.table_chart),
          label: const Text('Edit table'),
        ),
      ],
    );
  }

  Widget _buildFormulaWidget(Map<String, dynamic> item) {
    final error = (item['error'] as String? ?? '').trim();
    final latex = (item['latex'] as String? ?? '').trim();
    final hasLatex = latex.contains('\\');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hasLatex
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    latex,
                    mathStyle: MathStyle.display,
                    textStyle: const TextStyle(fontSize: 18),
                    onErrorFallback: (_) => SelectableText(
                      item['text'] as String? ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        fontFamily: 'NotoSansMath',
                      ),
                    ),
                  ),
                )
              : SelectableText(
                  item['text'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontFamily: 'NotoSansMath',
                  ),
                ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: Colors.amber.shade300, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableWidget(List<dynamic> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(Theme.of(context).colorScheme.primary),
          border: TableBorder.all(color: Colors.white24),
          columns: (rows.first as List).map((cell) {
            return DataColumn(
              label: Text(
                cell.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          }).toList(),
          rows: rows.skip(1).map((row) {
            final rowList = (row as List).toList();
            final columnCount = (rows.first as List).length;

            // Ensure every DataRow has exactly the same number of cells
            // as there are columns, to avoid Flutter assertion errors.
            final normalizedCells = List.generate(columnCount, (index) {
              if (index < rowList.length) {
                return DataCell(Text(rowList[index].toString()));
              }
              return const DataCell(Text(''));
            });

            return DataRow(cells: normalizedCells);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEditableImage(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> item,
  ) {
    final widthPercent = (item['width_percent'] as num?)?.toDouble() ?? 60;
    final rotation = (item['rotation'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (widthPercent / 100).clamp(0.30, 1.0),
            child: Transform.rotate(
              angle: rotation * math.pi / 180,
              child: _buildImageWidget(item),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => _showImageEditor(contentKey, itemIndex, item),
          icon: const Icon(Icons.image),
          label: const Text('Edit image'),
        ),
      ],
    );
  }

  Widget _buildImageWidget(Map<String, dynamic> item) {
    final path = item['path'] as String? ?? '';
    final caption = item['caption'] as String? ?? 'Image';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (path.isNotEmpty && File(path).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                height: 100,
                color: Colors.black26,
                child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),
          )
        else
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image, color: Colors.grey, size: 32),
                  const SizedBox(height: 4),
                  Text(caption,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              caption,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildFileInfo() {
    final path = _outputPaths[_selectedFormat];
    if (path == null) return const SizedBox.shrink();

    return FutureBuilder<FileStat>(
      future: File(path).stat(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'File Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text('Path: $path',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                'Size: ${FileStorage.formatFileSize(snapshot.data!.size)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Modified: ${snapshot.data!.modified}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadFile() async {
    final path = _outputPaths[_selectedFormat];
    if (path == null || path.isEmpty) {
      _showError('File not found');
      return;
    }
    if (!await File(path).exists()) {
      _showError('File not found');
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final destPath = await FileDownload.copyToDownloadsFolder(
        path,
        fileName: _preferredDownloadName(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to: $destPath')),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  String _preferredDownloadName() {
    final requestedName = widget.options.outputName.trim();
    final title =
        (_editableMapping['{{TITLE}}'] as String? ?? 'converted-file').trim();
    final baseName = requestedName.isNotEmpty ? requestedName : title;
    final cleanBase = baseName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safeBase = cleanBase.isEmpty ? 'converted-file' : cleanBase;
    return '$safeBase.$_selectedFormat';
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
            Tooltip(
              message: 'Apply preview edits',
              child: SizedBox(
                width: 52,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isApplyingEdits ? null : _applyPreviewEdits,
                  child: _isApplyingEdits
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Open actual ${_selectedFormat.toUpperCase()} file',
              child: SizedBox(
                width: 52,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isOpeningFile ? null : _openGeneratedFile,
                  child: _isOpeningFile
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.open_in_new),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Download',
              child: SizedBox(
                width: 52,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isDownloading ? null : _downloadFile,
                  child: _isDownloading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Share',
              child: SizedBox(
                width: 52,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isSharing ? null : _shareFile,
                  child: _isSharing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.share),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyPreviewEdits() async {
    setState(() => _isApplyingEdits = true);
    try {
      final wasPreservingLayout =
          (_editableMapping['{{PRESERVE_DOCX_LAYOUT}}'] == true ||
              _editableMapping['{{PRESERVE_PDF_LAYOUT}}'] == true) &&
          _editableMapping['{{LAYOUT_EDITED}}'] != true;
      if (wasPreservingLayout) {
        // A source package cannot remain byte-for-byte layout-preserved after
        // a user changes its extracted preview content. Switch only this
        // regenerated export to the editable/reflow path.
        _editableMapping['{{LAYOUT_EDITED}}'] = true;
      }
      final regenerated = await OutputGenerator.generate(
        const {},
        _editableMapping,
        widget.options,
      );
      setState(() {
        _outputPaths = regenerated;
        if (!_outputPaths.containsKey(_selectedFormat)) {
          _selectedFormat = _outputPaths.keys.first;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasPreservingLayout
                ? 'Preview edits applied. DOCX is now regenerated in editable layout mode.'
                : 'Preview edits applied'),
          ),
        );
      }
    } catch (e) {
      _showError('Apply edits failed: $e');
    } finally {
      if (mounted) setState(() => _isApplyingEdits = false);
    }
  }

  void _showTableEditor(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> item,
  ) {
    _showBlockEditor(
      title: 'Table options',
      contentKey: contentKey,
      itemIndex: itemIndex,
      widthOptions: const {
        'Compact': 45,
        'Balanced': 60,
        'Wide': 80,
        'Full': 100,
      },
    );
  }

  void _showImageEditor(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> item,
  ) {
    _showBlockEditor(
      title: 'Image options',
      contentKey: contentKey,
      itemIndex: itemIndex,
      widthOptions: const {
        'Small': 30,
        'Medium': 45,
        'Balanced': 60,
        'Large': 80,
        'Full': 100,
      },
      showRotation: true,
    );
  }

  void _showBlockEditor({
    required String title,
    required String contentKey,
    required int itemIndex,
    required Map<String, int> widthOptions,
    bool showRotation = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: widthOptions.entries.map((entry) {
                    return ActionChip(
                      label: Text(entry.key),
                      onPressed: () {
                        Navigator.pop(context);
                        _updateItem(contentKey, itemIndex, {
                          'width_percent': entry.value,
                        });
                      },
                    );
                  }).toList(),
                ),
                if (showRotation) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [0, 90, 180, 270].map((degrees) {
                      return ActionChip(
                        label: Text('$degrees°'),
                        onPressed: () {
                          Navigator.pop(context);
                          _updateItem(contentKey, itemIndex, {
                            'rotation': degrees,
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.drive_file_move),
                  title: const Text('Move to another section'),
                  onTap: () {
                    Navigator.pop(context);
                    _moveItem(contentKey, itemIndex);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete from output',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteItem(contentKey, itemIndex);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateItem(
    String contentKey,
    int itemIndex,
    Map<String, dynamic> changes,
  ) {
    final content = _editableMapping[contentKey] as List? ?? [];
    if (itemIndex >= content.length) return;
    setState(() {
      final item = Map<String, dynamic>.from(content[itemIndex] as Map);
      content[itemIndex] = {...item, ...changes};
    });
  }

  void _deleteItem(String contentKey, int itemIndex) {
    final content = _editableMapping[contentKey] as List? ?? [];
    if (itemIndex >= content.length) return;
    setState(() => content.removeAt(itemIndex));
  }

  Future<void> _moveItem(String sourceContentKey, int itemIndex) async {
    final sections = _sectionTargets();
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to section'),
        children: sections.map((section) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, section.key),
            child: Text(section.value),
          );
        }).toList(),
      ),
    );
    if (destination == null || destination == sourceContentKey) return;

    final source = _editableMapping[sourceContentKey] as List? ?? [];
    final target = _editableMapping[destination] as List? ?? [];
    if (itemIndex >= source.length) return;
    setState(() {
      final item = source.removeAt(itemIndex);
      target.add(item);
    });
  }

  List<MapEntry<String, String>> _sectionTargets() {
    final targets = <MapEntry<String, String>>[];
    for (final key in _editableMapping.keys) {
      if (key.startsWith('{{SECTION_') && !key.contains('_CONTENT')) {
        final contentKey = key.replaceFirst('{{SECTION_', '{{CONTENT_');
        targets.add(MapEntry(contentKey, _editableMapping[key].toString()));
      }
    }
    return targets;
  }
}

class _ColorMenuItem extends StatelessWidget {
  final String label;
  final Color color;

  const _ColorMenuItem(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 10),
        Text(label),
      ]);
}
