import '../widgets/report_problem_entry.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../services/file_storage.dart';
import '../services/app_remote_config_service.dart';
import '../services/supabase_config.dart';
import '../services/document_parser.dart';
import '../services/data_extractor.dart';
import '../services/template_engine.dart';
import '../services/output_generator.dart';
import '../services/content_safety.dart';
import '../services/normal/normal_converter.dart';
import '../services/normal/pdf_to_docx.dart';
import '../models/data_model.dart';
import '../models/generation_options.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_app_chrome.dart';
import 'normal_result_screen.dart';
import 'preview_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool conversionOnly;

  const DashboardScreen({super.key, this.conversionOnly = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final _outputNameController = TextEditingController();

  File? _dataFile;
  String? _dataFileName;
  int? _selectedCreateActionIndex;
  AppRemoteConfig _remoteConfig = const AppRemoteConfig();
  RealtimeChannel? _appControlChannel;

  bool _isLoading = false;
  String _statusMessage = '';
  double _conversionProgress = 0;
  bool _cancelRequested = false;
  bool _progressPulse = false;
  int _elapsedSeconds = 0;
  DateTime _lastProgressUpdate = DateTime.now();
  DateTime _conversionStartedAt = DateTime.now();
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadRemoteConfig());
    _subscribeToAppControlChanges();
  }

  Future<void> _loadRemoteConfig() async {
    try {
      final config = await const AppRemoteConfigService().load();
      if (mounted) setState(() => _remoteConfig = config);
    } catch (_) {
      // Keep local tools available when remote settings cannot be reached.
    }
  }

  void _subscribeToAppControlChanges() {
    if (!SupabaseConfig.isConfigured) return;
    _appControlChannel = Supabase.instance.client
        .channel('dashboard-app-control-settings-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_control_settings',
          callback: (_) => unawaited(_loadRemoteConfig()),
        )
        .subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadRemoteConfig());
  }

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
  bool _preserveSourceLayout = false;
  int? _sourceFileId;
  bool _legacyPptWarningShown = false;
  String _conversionMode = 'normal';
  final List<String> _selectedFormats = ['docx'];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _appControlChannel;
    if (channel != null) unawaited(Supabase.instance.client.removeChannel(channel));
    _progressTimer?.cancel();
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
        if (kind == 'data' &&
            file.extension?.toLowerCase() == 'ppt' &&
            !_legacyPptWarningShown) {
          _legacyPptWarningShown = true;
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                content: const Text(
                  'Old .ppt files are read with limited accuracy. For best results, save the file as .pptx first.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
        final path = await FileStorage.saveUploadedFile(
          file,
          kind,
          metadata: {
            'workspace_mode': 'direct',
          },
        );
        _sourceFileId = FileStorage.lastUploadedFileId;

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
      _cancelRequested = false;
      _conversionProgress = 0;
      _statusMessage = 'Preparing conversion';
      _elapsedSeconds = 0;
      _lastProgressUpdate = DateTime.now();
      _conversionStartedAt = DateTime.now();
    });
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _progressPulse = !_progressPulse;
        _elapsedSeconds = DateTime.now().difference(_conversionStartedAt).inSeconds;
      });
    });

    try {
      final dataExtension = _extensionOf(_dataFileName ?? _dataFile!.path);
      if (_conversionMode == 'normal') {
        final targetExtension =
            _selectedFormats.isEmpty ? 'docx' : _selectedFormats.first;
        final hasDetailedPdfProgress =
            dataExtension == 'pdf' && targetExtension == 'docx';
        if (!hasDetailedPdfProgress) {
          _updateProgress(0.08, 'Converting file...');
        }
        final sourceName = _dataFileName ?? path.basename(_dataFile!.path);
        final sourceBaseName = path.basenameWithoutExtension(sourceName);
        final requestedName = _outputNameController.text.trim();
        final requestedBaseName = requestedName.isEmpty
            ? sourceBaseName
            : requestedName;
        final cleanedBaseName = path
            .basenameWithoutExtension(requestedBaseName)
            .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
            .trim();
        final outputBaseName =
            cleanedBaseName.isEmpty ? 'converted-file' : cleanedBaseName;
        final result = await NormalConverter.convert(
          _dataFile!.path,
          dataExtension,
          targetExtension,
          outputBaseName,
          onProgress: _updateProgress,
          isCancelled: () => _cancelRequested,
        );
        if (!hasDetailedPdfProgress) {
          _updateProgress(0.88, 'Saving converted file...');
        }
        final outputName = '$outputBaseName.$targetExtension';
        final savedPath = await FileStorage.saveOutputFile(
          result.path,
          'output_$targetExtension',
          outputName,
          sourceFileId: _sourceFileId,
          metadata: {'conversion_mode': 'normal'},
        );
        final outputSize = await File(savedPath).length();
        _updateProgress(1, 'Conversion complete');
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NormalResultScreen(
                filePath: savedPath,
                fileName: outputName,
                fileType: targetExtension,
                fileSizeBytes: outputSize,
                notes: result.notes,
                sourceFilePath: _dataFile?.path,
                reportContext: {
                  'mode': 'normal',
                  'source_ext': _extensionOf(_dataFileName ?? _dataFile?.path ?? ''),
                  'target_ext': targetExtension,
                  'style_profile': _styleProfile,
                  'selected_options': {
                    'paper_size': _paperSize,
                    'orientation': 'auto',
                    'margins': _marginPreset,
                    'line_spacing': _lineSpacing,
                    'font': _fontFamily,
                    'clean_grammar': _warningAction,
                    'summarize': _summarize,
                    'preserve_layout': _preserveSourceLayout,
                  },
                  'file_sizes_bytes': {'source': _dataFile?.lengthSync(), 'output': outputSize},
                },
              ),
            ),
          );
        }
        return;
      }
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
          if (block['type'] != 'table' ||
              sourceTableIndex >= extractedTables.length) {
            continue;
          }
          final sourceTable = extractedTables[sourceTableIndex++];
          block['rows'] = sourceTable['rows'];
          if (_preserveSourceTableFormat && sourceTable['raw_xml'] != null) {
            block['source_table_xml'] = sourceTable['raw_xml'];
          }
        }
      }
      if (_includeTables &&
          extractedTables.isNotEmpty &&
          !hasParsedTableBlocks) {
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
        final warnings =
            List<String>.from(diagnostics['warnings'] as List? ?? []);
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

      _updateProgress(0.86,
          'Generating ${_selectedFormats.join(', ').toUpperCase()} output...');
      final options = GenerationOptions(
        conversionMode: _conversionMode,
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
        sourceFileId: _sourceFileId,
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
              sourceFilePath: _dataFile?.path,
              reportContext: {
                'mode': 'advanced',
                'source_ext': _extensionOf(_dataFileName ?? _dataFile?.path ?? ''),
                'style_profile': _styleProfile,
                'selected_options': {
                  'paper_size': _paperSize,
                  'orientation': 'auto',
                  'margins': _marginPreset,
                  'line_spacing': _lineSpacing,
                  'font': _fontFamily,
                  'clean_grammar': _warningAction,
                  'summarize': _summarize,
                  'preserve_layout': _preserveSourceLayout,
                },
              },
            ),
          ),
        );
      }
    } on PdfToDocxCancelled {
      // Cancel returns to the current screen without showing an error.
    } on NormalUnsupported catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Unsupported in Normal mode'),
            content: Text(
              'Normal mode doesn\'t support ${e.sourceExt.toUpperCase()} to ${e.targetExt.toUpperCase()} yet. Use Advanced mode?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  setState(() => _conversionMode = 'advanced');
                },
                child: const Text('Switch to Advanced'),
              ),
            ],
          ),
        );
      }
    } catch (e, stackTrace) {
      _showError('Generation failed during $_statusMessage: $e');
      debugPrint(stackTrace.toString());
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
          _conversionProgress = 0;
        });
      }
    }
  }

  void _updateProgress(double progress, String message) {
    if (mounted) {
      setState(() {
        _conversionProgress = progress.clamp(0, 1);
        _statusMessage = message;
        _lastProgressUpdate = DateTime.now();
      });
    }
  }

  void _cancelNormalConversion() {
    if (!_isLoading) return;
    setState(() {
      _cancelRequested = true;
      _statusMessage = 'Canceling conversion...';
    });
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
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          content: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Report this problem',
            onPressed: () => openReportProblem(
              context,
              area: 'conversion',
              sourceFilePath: _dataFile?.path,
              contextInfo: {
                'error': message.length > 500 ? message.substring(0, 500) : message,
                'mode': _conversionMode,
                'source_ext': _extensionOf(_dataFileName ?? _dataFile?.path ?? ''),
                'target_ext': _selectedFormats.isEmpty ? null : _selectedFormats.first,
                'style_profile': _styleProfile,
                'selected_options': {'paper_size': _paperSize, 'orientation': 'auto', 'margins': _marginPreset, 'line_spacing': _lineSpacing, 'font': _fontFamily, 'clean_grammar': _warningAction, 'summarize': _summarize, 'preserve_layout': _preserveSourceLayout},
              },
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: widget.conversionOnly ? 'Convert file' : 'Create',
      subtitle: widget.conversionOnly ? '' : 'Choose what you want to create',
      selectedIndex: 1,
      showBack: true,
      showProfile: !widget.conversionOnly,
      bottomAction: widget.conversionOnly
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: FigmaAppColors.bg(context),
                border: Border(
                  top: BorderSide(color: FigmaAppColors.border(context)),
                ),
              ),
              child: FigmaPrimaryButton(
                label: 'Convert file',
                icon: Icons.transform_rounded,
                onPressed: (_isLoading || _dataFile == null)
                    ? null
                    : _generateDocument,
              ),
            )
          : null,
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
                  _buildUploadCard(
                    title: 'Tap to upload a file',
                    subtitle: 'PDF, DOCX, PPTX, PPT or TXT',
                    fileName: _dataFileName,
                    icon: Icons.upload_file,
                    onTap: () => _pickFile('data'),
                  ),
                  const SizedBox(height: 24),
                  _buildOptionsSection(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (_isLoading) _buildConversionLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildConversionLoadingOverlay() {
    final percentage = (_conversionProgress * 100).round();
    final sourceExt = _extensionOf(_dataFileName ?? _dataFile?.path ?? '');
    final targetExt = _selectedFormats.isEmpty ? '' : _selectedFormats.first;
    final canCancel = _conversionMode == 'normal' &&
        sourceExt == 'pdf' && targetExt == 'docx';
    final isStalled = DateTime.now().difference(_lastProgressUpdate).inSeconds >= 5;
    final elapsed = '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(_elapsedSeconds % 60).toString().padLeft(2, '0')}';
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
                      color: FigmaAppColors.primary(context)
                          .withValues(alpha: 0.14),
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
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 450),
                            opacity: isStalled && _progressPulse ? 0.55 : 1,
                            child: LinearProgressIndicator(
                              value: _conversionProgress,
                              minHeight: 9,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$percentage%',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Elapsed $elapsed',
                      style: TextStyle(fontSize: 12, color: FigmaAppColors.subtext(context))),
                  if (canCancel) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _cancelRequested ? null : _cancelNormalConversion,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(_cancelRequested ? 'Canceling...' : 'Cancel'),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Keep the app open while we prepare your file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: FigmaAppColors.subtext(context)),
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
        featureFlag: 'document_conversion',
      ),
      _CreateAction(
        'Create Study Guide',
        Icons.menu_book_outlined,
        () => Navigator.of(context).pushNamed('/study-builder'),
        featureFlag: 'study_guides',
      ),
      _CreateAction(
        'Generate Quiz',
        Icons.quiz_outlined,
        () => Navigator.of(context).pushNamed('/generate-quiz'),
        featureFlag: 'quiz_generator',
      ),
      _CreateAction(
        'QR Code',
        Icons.qr_code_scanner_outlined,
        () => Navigator.of(context).pushNamed('/qr-code'),
        featureFlag: 'qr_code',
      ),
      _CreateAction(
        'Text to File',
        Icons.text_snippet_outlined,
        () => Navigator.of(context).pushNamed('/text-to-file'),
        featureFlag: 'text_to_file',
      ),
      _CreateAction(
        'My Materials',
        Icons.folder_copy_outlined,
        () => Navigator.of(context).pushNamed('/saved-files'),
        featureFlag: 'my_materials',
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
            final isSelected = _selectedCreateActionIndex == index;
            final isEnabled = action.featureFlag == null ||
                _remoteConfig.featureEnabled(action.featureFlag!);
            final colors = Theme.of(context).colorScheme;
            return InkWell(
              onTap: () {
                if (!isEnabled) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This feature is temporarily disabled by the administrator.',
                      ),
                    ),
                  );
                  return;
                }
                setState(() => _selectedCreateActionIndex = index);
                action.onTap();
              },
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.12)
                      : FigmaAppColors.card(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? colors.primary
                        : FigmaAppColors.border(context),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withValues(alpha: 0.025),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      action.icon,
                      color: isEnabled
                          ? colors.primary
                          : FigmaAppColors.subtext(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: !isEnabled
                                  ? FigmaAppColors.subtext(context)
                                  : isSelected
                                      ? colors.primary
                                      : FigmaAppColors.text(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          if (!isEnabled)
                            Text(
                              'Disabled by admin',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: FigmaAppColors.subtext(context),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: FigmaCard(
        padding: EdgeInsets.zero,
        child: Container(
          height: 178,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: FigmaAppColors.fill(context),
            border: Border.all(color: FigmaAppColors.border(context)),
          ),
          child: Center(
            child: fileName == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          color: FigmaAppColors.primary(context), size: 34),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: TextStyle(
                          color: FigmaAppColors.text(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
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
                      Icon(Icons.check_circle, color: Theme.of(context).colorScheme.tertiary, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName,
                          style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMoreOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FigmaAppColors.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.86,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildConversionModeControl(
                        sheetSetState,
                        sheetContext,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _conversionMode == 'normal'
                            ? 'Same look, new file type.'
                            : 'Rebuilds your content with a new design.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.of(sheetContext).muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'More options',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: _conversionMode == 'normal'
                        ? _buildNormalOptionsFields(sheetSetState)
                        : _buildAdvancedOptionsFields(sheetSetState),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setSheetOption(StateSetter sheetSetState, VoidCallback change) {
    setState(change);
    sheetSetState(() {});
  }

  Widget _buildConversionModeControl(
    StateSetter sheetSetState,
    BuildContext sheetContext,
  ) {
    final colors = AppColors.of(sheetContext);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line, width: 1),
      ),
      child: Row(
        children: [
          _buildModeChoice('normal', 'Normal', sheetSetState, colors),
          _buildModeChoice('advanced', 'Advanced', sheetSetState, colors),
        ],
      ),
    );
  }

  Widget _buildModeChoice(
    String mode,
    String label,
    StateSetter sheetSetState,
    AppColors colors,
  ) {
    final selected = _conversionMode == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _setSheetOption(
          sheetSetState,
          () => _conversionMode = mode,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.accent : colors.surface2,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.accentInk : colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalOptionsFields(StateSetter sheetSetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFormatChips(
          sheetSetState: sheetSetState,
          label: 'Output format',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _outputNameController,
          decoration: const InputDecoration(
            labelText: 'Output name (optional)',
            prefixIcon: Icon(Icons.drive_file_rename_outline),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedOptionsFields(StateSetter sheetSetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _warningAction = val!),
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
            DropdownMenuItem(value: 'courier_new', child: Text('Courier New')),
          ],
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _fontFamily = val!),
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
                onChanged: (val) =>
                    _setSheetOption(sheetSetState, () => _paperSize = val!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown(
                label: 'Orientation',
                value: _pageOrientation,
                items: const [
                  DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
                  DropdownMenuItem(
                      value: 'landscape', child: Text('Landscape')),
                ],
                onChanged: (val) => _setSheetOption(
                    sheetSetState, () => _pageOrientation = val!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildToggle(
          label: 'Include detected images',
          value: _includeImages,
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _includeImages = val),
        ),
        const SizedBox(height: 8),
        _buildToggle(
          label: 'Include detected tables',
          value: _includeTables,
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _includeTables = val),
        ),
        if (_includeTables) ...[
          const SizedBox(height: 8),
          _buildToggle(
            label: 'Keep original DOCX table formatting',
            value: _preserveSourceTableFormat,
            onChanged: (val) => _setSheetOption(
                sheetSetState, () => _preserveSourceTableFormat = val),
          ),
        ],
        const SizedBox(height: 8),
        _buildToggle(
          label: 'Preserve original layout (DOCX/PDF)',
          value: _preserveSourceLayout,
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _preserveSourceLayout = val),
        ),
        const SizedBox(height: 4),
        Text(
          'Preserves the original formula, table, image, and page layout when exporting to the same source format. Turn it off for a fully regenerated file.',
          style:
              TextStyle(color: FigmaAppColors.subtext(context), fontSize: 11),
        ),
        const SizedBox(height: 12),
        _buildToggle(
          label: 'Clean Grammar',
          value: _cleanGrammar,
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _cleanGrammar = val),
        ),
        const SizedBox(height: 8),
        _buildToggle(
          label: 'Summarize',
          value: _summarize,
          onChanged: (val) =>
              _setSheetOption(sheetSetState, () => _summarize = val),
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
                onChanged: (val) =>
                    _setSheetOption(sheetSetState, () => _marginPreset = val!),
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
                onChanged: (val) => _setSheetOption(
                    sheetSetState, () => _lineSpacing = double.parse(val!)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_conversionMode == 'advanced') FigmaCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Output',
                style: TextStyle(
                  color: FigmaAppColors.text(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _buildFormatChips(),
              const SizedBox(height: 14),
              _buildDropdown(
                label: 'Style profile',
                value: _styleProfile,
                items: const [
                  DropdownMenuItem(value: 'academic', child: Text('Academic')),
                  DropdownMenuItem(
                      value: 'module', child: Text('Learning Module')),
                  DropdownMenuItem(
                      value: 'clean', child: Text('Clean Handout')),
                ],
                onChanged: (val) => setState(() => _styleProfile = val!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: _openMoreOptions,
          borderRadius: BorderRadius.circular(18),
          child: FigmaCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    color: FigmaAppColors.primary(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('More options',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        _conversionMode == 'normal'
                            ? 'Same look, new file type.'
                            : '${_paperSize.toUpperCase()} · ${_pageOrientation == 'portrait'
                                ? 'Portrait'
                                : 'Landscape'} · $_lineSpacing spacing · images${_includeTables ? ', tables' : ''}${_cleanGrammar ? ', grammar' : ''}',
                        style: TextStyle(
                          color: FigmaAppColors.subtext(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: FigmaAppColors.subtext(context)),
              ],
            ),
          ),
        ),
      ],
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

  Widget _buildFormatChips({
    StateSetter? sheetSetState,
    String label = 'Format',
  }) {
    final formats = [
      {'label': 'DOCX', 'value': 'docx', 'icon': Icons.description_outlined},
      {'label': 'PDF', 'value': 'pdf', 'icon': Icons.picture_as_pdf_outlined},
      {'label': 'HTML', 'value': 'html', 'icon': Icons.code_outlined},
      {'label': 'TXT', 'value': 'txt', 'icon': Icons.notes_outlined},
    ];
    final colors = Theme.of(context).colorScheme;

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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: formats.map((format) {
            final value = format['value']! as String;
            final label = format['label']! as String;
            final isSelected = _selectedFormats.contains(value);
            return ChoiceChip(
              avatar: Icon(
                format['icon']! as IconData,
                size: 18,
                color: isSelected ? colors.onPrimary : colors.primary,
              ),
              label: Text(label),
              selected: isSelected,
              selectedColor: colors.primary,
              backgroundColor: FigmaAppColors.fill(context),
              labelStyle: TextStyle(
                color: isSelected
                    ? colors.onPrimary
                    : FigmaAppColors.text(context),
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: isSelected
                    ? colors.primary
                    : FigmaAppColors.border(context),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (selected) {
                if (!selected) return;
                void updateSelection() {
                  _selectedFormats
                    ..clear()
                    ..add(value);
                }
                if (sheetSetState == null) {
                  setState(updateSelection);
                } else {
                  _setSheetOption(sheetSetState, updateSelection);
                }
              },
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
  final String? featureFlag;

  const _CreateAction(
    this.label,
    this.icon,
    this.onTap, {
    this.featureFlag,
  });
}
