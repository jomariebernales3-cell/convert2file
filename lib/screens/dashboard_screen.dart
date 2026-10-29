import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_storage.dart';
import '../services/document_parser.dart';
import '../services/data_extractor.dart';
import '../services/template_engine.dart';
import '../services/output_generator.dart';
import '../services/content_safety.dart';
import '../models/data_model.dart';
import '../models/generation_options.dart';
import '../widgets/figma_app_chrome.dart';
import 'preview_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool conversionOnly;

  const DashboardScreen({super.key, this.conversionOnly = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _outputNameController = TextEditingController();

  File? _dataFile;
  String? _dataFileName;

  bool _isLoading = false;
  String _statusMessage = '';
  double _conversionProgress = 0;

  String _styleProfile = 'academic';
  String _warningAction = 'sanitize';
  String _fontFamily = 'default';
  String _paperSize = 'a4';
  String _pageOrientation = 'portrait';
  String _marginPreset = 'normal';
  double _lineSpacing = 1.5;
  bool _cleanGrammar = true;
  bool _summarize = false;
  bool _includeImages = true;
  bool _includeTables = true;
  bool _preserveSourceTableFormat = true;
  bool _preserveSourceLayout = true;
  bool _isMappingExpanded = false;
  final List<String> _selectedFormats = ['docx'];

  @override
  void dispose() {
    _outputNameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(String kind) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx', 'pdf', 'txt', 'ppt', 'pptx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final path = await FileStorage.saveUploadedFile(
          file,
          kind,
          metadata: {
            'workspace_mode': 'direct',
          },
        );

        setState(() {
          _dataFile = File(path);
          _dataFileName = file.name;
        });
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _generateDocument() async {
    if (_dataFile == null) {
      _showError('Please upload a source file');
      return;
    }

    setState(() {
      _isLoading = true;
      _conversionProgress = 0.06;
      _statusMessage = 'Parsing document...';
    });

    try {
      final dataExtension = _extensionOf(_dataFileName ?? _dataFile!.path);
      // Preserve layout is only compatible with a complete DOCX source. If a
      // user removes source images/tables, we deliberately use reflow mode so
      // the requested omissions are respected.
      final useStructuredDocx = dataExtension == 'docx' &&
          _preserveSourceLayout &&
          _includeImages &&
          _includeTables;
      final usePreservedPdf = dataExtension == 'pdf' &&
          _preserveSourceLayout &&
          _includeImages &&
          _includeTables;

      // Parse data file. DOCX preservation uses body-level blocks in their
      // source order instead of converting everything to lines first.
      final dataText = await DocumentParser.extractText(
        _dataFile!.path,
        dataExtension,
      );
      _updateProgress(
        0.18,
        useStructuredDocx ? 'Preserving DOCX layout...' : 'Extracting data...',
      );

      var dataModel = useStructuredDocx
          ? DataExtractor.fromStructuredBlocks(
              await DocumentParser.extractDocxStructuredBlocks(_dataFile!.path),
            )
          : DataExtractor.extract(dataText);
      final extractedImages = useStructuredDocx
          ? <Map<String, dynamic>>[]
          : await DocumentParser.extractEmbeddedImages(
              _dataFile!.path,
              dataExtension,
            );
      if (_includeImages && extractedImages.isNotEmpty) {
        dataModel.meta['images'] = extractedImages;
      }
      _updateProgress(0.36, 'Organizing text, images, and sections...');

      if (dataExtension == 'pdf') {
        final pdfLayoutInfo =
            await DocumentParser.extractPdfLayoutInfo(_dataFile!.path);
        final sourceWarnings = <String>[
          pdfLayoutInfo['layout_warning'] as String,
        ];
        if (pdfLayoutInfo['has_repeated_header_footer'] == true) {
          sourceWarnings.add(
            'Repeated PDF header/footer text was detected and removed from extraction.',
          );
        }
        if (pdfLayoutInfo['likely_scanned'] == true) {
          sourceWarnings.add(
            'This PDF appears to be scanned or image-based. Text may be incomplete because OCR is not available yet.',
          );
        }
        dataModel.meta['source_warnings'] = sourceWarnings;
        dataModel.meta['pdf_layout_info'] = pdfLayoutInfo;
      }

      final qualityWarnings = <String>[
        ...List<String>.from(dataModel.meta['source_warnings'] as List? ?? []),
      ];
      if (dataText.trim().length < 80) {
        qualityWarnings.add(
          'Very little text was extracted. Review the generated document before exporting.',
        );
      }
      if (dataModel.blocks.isEmpty) {
        qualityWarnings.add(
          'No readable document structure was detected. The output may need manual editing.',
        );
      }
      dataModel.meta['source_warnings'] = qualityWarnings.toSet().toList();

      final extractedTables = useStructuredDocx
          ? <Map<String, dynamic>>[]
          : dataExtension == 'docx'
          ? await DocumentParser.extractDocxTables(_dataFile!.path)
          : dataExtension == 'pptx'
              ? await DocumentParser.extractPptxTables(_dataFile!.path)
              : <Map<String, dynamic>>[];
      final hasParsedTableBlocks =
          dataModel.blocks.any((block) => block['type'] == 'table');
      if (_includeTables && extractedTables.isNotEmpty) {
        var sourceTableIndex = 0;
        for (final block in dataModel.blocks) {
          if (block['type'] != 'table' || sourceTableIndex >= extractedTables.length) {
            continue;
          }
          final sourceTable = extractedTables[sourceTableIndex++];
          block['rows'] = sourceTable['rows'];
          if (_preserveSourceTableFormat && sourceTable['raw_xml'] != null) {
            block['source_table_xml'] = sourceTable['raw_xml'];
          }
        }
      }
      if (_includeTables && extractedTables.isNotEmpty && !hasParsedTableBlocks) {
        final tableRows = extractedTables
            .map((table) => table['rows'])
            .whereType<List>()
            .toList();
        dataModel.tables.addAll(
          tableRows
              .map((rows) =>
                  rows.map((row) => List<String>.from(row as List)).toList())
              .toList(),
        );
        for (final rows in tableRows) {
          final table = extractedTables[tableRows.indexOf(rows)];
          dataModel.blocks.add({
            'type': 'table',
            'rows': rows,
            if (_preserveSourceTableFormat && table['raw_xml'] != null)
              'source_table_xml': table['raw_xml'],
          });
        }
      }
      if (!_includeTables) {
        dataModel.tables.clear();
        dataModel.blocks.removeWhere((block) => block['type'] == 'table');
      }

      // Safety check
      _updateProgress(0.54, 'Checking document quality...');
      final safetyCheck = ContentSafety.scanText(dataText);
      if (safetyCheck['has_issues'] == true) {
        _updateProgress(
          0.63,
          'Cleaning ${safetyCheck['issue_count']} content issue(s)...',
        );
        // Sanitizing raw OOXML may alter its protected source structure. Keep
        // it intact in Preserve Layout mode and surface the warning instead.
        if (_warningAction == 'sanitize' && !useStructuredDocx) {
          dataModel = DataModel.fromJson(
            ContentSafety.sanitizeDataModel(dataModel.toJson()),
          );
        }
      }

      _updateProgress(0.72, 'Building your document...');
      final directPayload = TemplateEngine.buildDirectDocumentPayload(
        dataModel,
        cleanGrammar: _cleanGrammar,
        summarize: _summarize,
      );
      final mappingResults = directPayload['mapping'] as Map<String, dynamic>;
      if (useStructuredDocx) {
        mappingResults['{{SOURCE_DOCX_PATH}}'] = _dataFile!.path;
        mappingResults['{{PRESERVE_DOCX_LAYOUT}}'] = true;
        mappingResults['{{LAYOUT_EDITED}}'] = false;
        final diagnostics = Map<String, dynamic>.from(
          mappingResults['{{CONVERSION_DIAGNOSTICS}}'] as Map? ?? const {},
        );
        final warnings = List<String>.from(diagnostics['warnings'] as List? ?? []);
        warnings.add(
          'DOCX Preserve Layout is active. The initial DOCX export keeps original symbols, tables, image locations, and formatting.',
        );
        diagnostics['warnings'] = warnings.toSet().toList();
        mappingResults['{{CONVERSION_DIAGNOSTICS}}'] = diagnostics;
      } else if (usePreservedPdf) {
        mappingResults['{{SOURCE_PDF_PATH}}'] = _dataFile!.path;
        mappingResults['{{PRESERVE_PDF_LAYOUT}}'] = true;
        mappingResults['{{LAYOUT_EDITED}}'] = false;
        final diagnostics = Map<String, dynamic>.from(
          mappingResults['{{CONVERSION_DIAGNOSTICS}}'] as Map? ?? const {},
        );
        final warnings = List<String>.from(
          diagnostics['warnings'] as List? ?? [],
        );
        warnings.add(
          'PDF Preserve Layout is active. The initial PDF export keeps the original formula rendering and page layout.',
        );
        diagnostics['warnings'] = warnings.toSet().toList();
        mappingResults['{{CONVERSION_DIAGNOSTICS}}'] = diagnostics;
      }

      _updateProgress(0.86, 'Generating ${_selectedFormats.join(', ').toUpperCase()} output...');
      final options = GenerationOptions(
        selectedFormats: _selectedFormats,
        styleProfile: _styleProfile,
        outputName: _outputNameController.text.trim(),
        fontFamily: _fontFamily,
        paperSize: _paperSize,
        pageOrientation: _pageOrientation,
        marginPreset: _marginPreset,
        lineSpacing: _lineSpacing,
        warningAction: _warningAction,
        cleanGrammar: _cleanGrammar,
        summarize: _summarize,
        includeImages: _includeImages,
        includeTables: _includeTables,
        preserveSourceTableFormat: _preserveSourceTableFormat,
        preserveSourceLayout: useStructuredDocx || usePreservedPdf,
        workspaceMode: 'direct',
      );

      final templateModel =
          directPayload['template_model'] as Map<String, dynamic>;

      final outputPaths = await OutputGenerator.generate(
        templateModel,
        mappingResults,
        options,
      );
      _updateProgress(0.98, 'Opening the editable preview...');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewScreen(
              outputPaths: outputPaths,
              mapping: mappingResults,
              options: options,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      _showError('Generation failed: $e');
      debugPrint(stackTrace.toString());
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
        _conversionProgress = 0;
      });
    }
  }

  void _updateProgress(double progress, String message) {
    if (mounted) {
      setState(() {
        _conversionProgress = progress.clamp(0, 1);
        _statusMessage = message;
      });
    }
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: widget.conversionOnly ? 'Convert File' : 'Create',
      subtitle: widget.conversionOnly
          ? ''
          : 'Choose what you want to create',
      selectedIndex: 1,
      showBack: widget.conversionOnly,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.conversionOnly) ...[
                  _buildCreateActions(),
                  const SizedBox(height: 24),
                  _buildModeSummary(),
                ] else ...[
                  _buildModeSummary(),
                  const SizedBox(height: 24),
                  _buildUploadCard(
                    title: 'Source File',
                    subtitle:
                        'Upload a document to convert into study material',
                    fileName: _dataFileName,
                    icon: Icons.upload_file,
                    onTap: () => _pickFile('data'),
                  ),
                  const SizedBox(height: 24),
                  _buildOptionsSection(),
                  FigmaPrimaryButton(
                    label: 'Convert File',
                    icon: Icons.transform_rounded,
                    onPressed: (_isLoading || _dataFile == null)
                        ? null
                        : _generateDocument,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (_isLoading)
            _buildConversionLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildConversionLoadingOverlay() {
    final percentage = (_conversionProgress * 100).round();
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.68),
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
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: FigmaAppColors.primary(context),
                      size: 29,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Converting your document',
                    style: TextStyle(
                      color: FigmaAppColors.text(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FigmaAppColors.subtext(context)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _conversionProgress,
                            minHeight: 9,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$percentage%', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Keep the app open while we prepare your file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: FigmaAppColors.subtext(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSummary() {
    return FigmaCard(
      padding: const EdgeInsets.all(14),
      color: FigmaAppColors.fill(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome,
            color: FigmaAppColors.primary(context),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Upload one source file. Convert2File will extract readable content, clean it, and generate structured study-ready output.',
              style: TextStyle(
                color: FigmaAppColors.subtext(context),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateActions() {
    final actions = [
      _CreateAction(
        'Convert File',
        Icons.transform_outlined,
        () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DashboardScreen(conversionOnly: true),
          ),
        ),
      ),
      _CreateAction(
        'Create Study Guide',
        Icons.menu_book_outlined,
        () => Navigator.of(context).pushNamed('/study-builder'),
      ),
      _CreateAction(
        'Generate Quiz',
        Icons.quiz_outlined,
        () => Navigator.of(context).pushNamed('/generate-quiz'),
      ),
      _CreateAction(
        'QR Code',
        Icons.qr_code_scanner_outlined,
        () => Navigator.of(context).pushNamed('/qr-code'),
      ),
      _CreateAction(
        'Text to File',
        Icons.text_snippet_outlined,
        () => Navigator.of(context).pushNamed('/text-to-file'),
      ),
      _CreateAction(
        'My Materials',
        Icons.folder_copy_outlined,
        () => Navigator.of(context).pushNamed('/saved-files'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Main Actions',
          style: TextStyle(
            color: FigmaAppColors.text(context),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.78,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return InkWell(
              onTap: action.onTap,
              borderRadius: BorderRadius.circular(8),
              child: FigmaCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(action.icon, color: FigmaAppColors.primary(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        action.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FigmaAppColors.text(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required String? fileName,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return FigmaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FigmaAppColors.text(context),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(color: _mutedTextColor(context), fontSize: 13),
          ),
          const SizedBox(height: 15),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: FigmaAppColors.fill(context),
                border: Border.all(color: FigmaAppColors.border(context)),
              ),
              child: Center(
                child: fileName == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: FigmaAppColors.subtext(context),
                            size: 18,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to upload',
                            style: TextStyle(
                              color: FigmaAppColors.subtext(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fileName,
                              style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isMappingExpanded = !_isMappingExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Active Mapping Rules',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  Icon(_isMappingExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Using smart parser engine. Review generated outputs before sharing.',
            style: TextStyle(
              color: FigmaAppColors.subtext(context),
              fontSize: 13,
            ),
          ),
          if (_isMappingExpanded) ...[
            const SizedBox(height: 12),
          _buildDropdown(
            label: 'Style Profile',
            value: _styleProfile,
            items: const [
              DropdownMenuItem(value: 'academic', child: Text('Academic')),
              DropdownMenuItem(value: 'module', child: Text('Learning Module')),
              DropdownMenuItem(value: 'clean', child: Text('Clean Handout')),
            ],
            onChanged: (val) => setState(() => _styleProfile = val!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _outputNameController,
            decoration: const InputDecoration(
              labelText: 'Custom output name (optional)',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Content Warning Handling',
            value: _warningAction,
            items: const [
              DropdownMenuItem(
                  value: 'sanitize', child: Text('Sanitize flagged content')),
              DropdownMenuItem(
                  value: 'continue', child: Text('Continue with warnings')),
            ],
            onChanged: (val) => setState(() => _warningAction = val!),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Font Family',
            value: _fontFamily,
            items: const [
              DropdownMenuItem(value: 'default', child: Text('Default')),
              DropdownMenuItem(value: 'aptos', child: Text('Aptos')),
              DropdownMenuItem(value: 'times', child: Text('Times New Roman')),
              DropdownMenuItem(value: 'arial', child: Text('Arial')),
              DropdownMenuItem(
                  value: 'arial_narrow', child: Text('Arial Narrow')),
              DropdownMenuItem(value: 'calibri', child: Text('Calibri')),
              DropdownMenuItem(value: 'cambria', child: Text('Cambria')),
              DropdownMenuItem(value: 'garamond', child: Text('Garamond')),
              DropdownMenuItem(value: 'georgia', child: Text('Georgia')),
              DropdownMenuItem(
                  value: 'book_antiqua', child: Text('Book Antiqua')),
              DropdownMenuItem(
                  value: 'palatino', child: Text('Palatino Linotype')),
              DropdownMenuItem(value: 'tahoma', child: Text('Tahoma')),
              DropdownMenuItem(value: 'verdana', child: Text('Verdana')),
              DropdownMenuItem(value: 'trebuchet', child: Text('Trebuchet MS')),
              DropdownMenuItem(
                  value: 'century_gothic', child: Text('Century Gothic')),
              DropdownMenuItem(
                  value: 'courier_new', child: Text('Courier New')),
            ],
            onChanged: (val) => setState(() => _fontFamily = val!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Paper Size',
                  value: _paperSize,
                  items: const [
                    DropdownMenuItem(value: 'a4', child: Text('A4')),
                    DropdownMenuItem(value: 'letter', child: Text('Letter')),
                    DropdownMenuItem(value: 'legal', child: Text('Legal')),
                  ],
                  onChanged: (val) => setState(() => _paperSize = val!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Orientation',
                  value: _pageOrientation,
                  items: const [
                    DropdownMenuItem(
                        value: 'portrait', child: Text('Portrait')),
                    DropdownMenuItem(
                        value: 'landscape', child: Text('Landscape')),
                  ],
                  onChanged: (val) => setState(() => _pageOrientation = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildToggle(
            label: 'Include detected images',
            value: _includeImages,
            onChanged: (val) => setState(() => _includeImages = val),
          ),
          const SizedBox(height: 8),
          _buildToggle(
            label: 'Include detected tables',
            value: _includeTables,
            onChanged: (val) => setState(() => _includeTables = val),
          ),
          if (_includeTables) ...[
            const SizedBox(height: 8),
            _buildToggle(
              label: 'Keep original DOCX table formatting',
              value: _preserveSourceTableFormat,
              onChanged: (val) =>
                  setState(() => _preserveSourceTableFormat = val),
            ),
          ],
          const SizedBox(height: 8),
          _buildToggle(
            label: 'Preserve original layout (DOCX/PDF)',
            value: _preserveSourceLayout,
            onChanged: (val) => setState(() => _preserveSourceLayout = val),
          ),
          const SizedBox(height: 4),
          Text(
            'Preserves the original formula, table, image, and page layout when exporting to the same source format. Turn it off for a fully regenerated file.',
            style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 11),
          ),
          const SizedBox(height: 12),
          _buildToggle(
            label: 'Clean Grammar',
            value: _cleanGrammar,
            onChanged: (val) => setState(() => _cleanGrammar = val),
          ),
          const SizedBox(height: 8),
          _buildToggle(
            label: 'Summarize',
            value: _summarize,
            onChanged: (val) => setState(() => _summarize = val),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Margins',
                  value: _marginPreset,
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'narrow', child: Text('Narrow')),
                    DropdownMenuItem(value: 'wide', child: Text('Wide')),
                  ],
                  onChanged: (val) => setState(() => _marginPreset = val!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Line Spacing',
                  value: _lineSpacing.toString(),
                  items: const [
                    DropdownMenuItem(value: '1.15', child: Text('1.15')),
                    DropdownMenuItem(value: '1.5', child: Text('1.5')),
                    DropdownMenuItem(value: '2.0', child: Text('2.0')),
                  ],
                  onChanged: (val) =>
                      setState(() => _lineSpacing = double.parse(val!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFormatChips(),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
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
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FigmaAppColors.fill(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FigmaAppColors.border(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormatChips() {
    final formats = [
      {'label': 'DOCX', 'value': 'docx', 'icon': Icons.description_outlined},
      {'label': 'PDF', 'value': 'pdf', 'icon': Icons.picture_as_pdf_outlined},
      {'label': 'HTML', 'value': 'html', 'icon': Icons.code_outlined},
      {'label': 'TXT', 'value': 'txt', 'icon': Icons.notes_outlined},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Output Formats',
              style: TextStyle(
                color: FigmaAppColors.subtext(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _selectedFormats.first.toUpperCase(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: formats.map((format) {
            final value = format['value']! as String;
            final isSelected = _selectedFormats.contains(value);
            return Tooltip(
              message: format['label']! as String,
              child: IconButton.filledTonal(
                icon: Icon(format['icon']! as IconData),
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                style: IconButton.styleFrom(
                  backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                onPressed: () {
                  if (isSelected) return;
                  setState(() {
                    _selectedFormats
                      ..clear()
                      ..add(value);
                  });
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FigmaAppColors.fill(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Color _mutedTextColor(BuildContext context) {
    return FigmaAppColors.subtext(context);
  }
}

class _CreateAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _CreateAction(this.label, this.icon, this.onTap);
}
