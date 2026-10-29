import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/generation_options.dart';
import 'docx_builder.dart';
import 'file_storage.dart';
import 'html_generator.dart';
import 'txt_generator.dart';

class OutputGenerator {
  static Future<pw.Font>? _mathFontFuture;

  static Future<pw.Font> _mathFont() {
    return _mathFontFuture ??= _loadMathFont();
  }

  static Future<pw.Font> _loadMathFont() async {
    final bytes = await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf');
    return pw.Font.ttf(bytes);
  }

  static Future<Map<String, String>> generate(
    Map<String, dynamic> templateModel,
    Map<String, dynamic> mapping,
    GenerationOptions options,
  ) async {
    final results = <String, String>{};
    final baseName = _resolveDownloadBaseName(
      options.outputName,
      mapping['{{TITLE}}'] as String? ?? 'document',
    );
    final preservedDocxPath = mapping['{{SOURCE_DOCX_PATH}}'] as String? ?? '';
    final preservedPdfPath = mapping['{{SOURCE_PDF_PATH}}'] as String? ?? '';
    final hasUnappliedLayoutEdits = mapping['{{LAYOUT_EDITED}}'] == true;
    final canPreserveOriginalDocx = options.preserveSourceLayout &&
        !hasUnappliedLayoutEdits &&
        preservedDocxPath.isNotEmpty &&
        await File(preservedDocxPath).exists();
    final canPreserveOriginalPdf = options.preserveSourceLayout &&
        !hasUnappliedLayoutEdits &&
        preservedPdfPath.isNotEmpty &&
        await File(preservedPdfPath).exists();

    for (final format in options.selectedFormats) {
      switch (format) {
        case 'docx':
          // Rebuilding a DOCX from extracted text cannot retain every Office
          // XML feature. When Preserve Layout is active, retain the verified
          // original package so symbols, merged tables, relationships, and
          // floating/inline image anchors remain exactly where Word stored
          // them. Applying an editor change intentionally falls back to the
          // editable reflow builder below.
          final path = canPreserveOriginalDocx
              ? preservedDocxPath
              : await DocxBuilder.generate(
                  templateModel,
                  mapping,
                  options,
                  baseName,
                );
          results['docx'] = await FileStorage.saveOutputFile(
            path,
            'output_docx',
            '$baseName.docx',
            metadata: {
              'workspace_mode': options.workspaceMode,
              'preserved_source_layout': canPreserveOriginalDocx,
            },
          );
          break;
        case 'pdf':
          final path = canPreserveOriginalPdf
              ? preservedPdfPath
              : await _generatePdf(mapping, options, baseName);
          results['pdf'] = await FileStorage.saveOutputFile(
            path,
            'output_pdf',
            '$baseName.pdf',
            metadata: {
              'workspace_mode': options.workspaceMode,
              'preserved_source_layout': canPreserveOriginalPdf,
            },
          );
          break;
        case 'html':
          final path = await HtmlGenerator.generate(mapping, options, baseName);
          results['html'] = await FileStorage.saveOutputFile(
            path,
            'output_html',
            '$baseName.html',
            metadata: {'workspace_mode': options.workspaceMode},
          );
          break;
        case 'txt':
          final path = await TxtGenerator.generate(mapping, options, baseName);
          results['txt'] = await FileStorage.saveOutputFile(
            path,
            'output_txt',
            '$baseName.txt',
            metadata: {'workspace_mode': options.workspaceMode},
          );
          break;
      }
    }

    return results;
  }

  static Future<String> _generatePdf(
    Map<String, dynamic> mapping,
    GenerationOptions options,
    String baseName,
  ) async {
    final pdf = pw.Document();
    final profile = _resolvedProfile(options.styleProfile);
    final mathFont = await _mathFont();

    final titleFont = pw.TextStyle(
      font: profile['font'] as pw.Font,
      fontSize: profile['title_size'] as double,
      fontWeight: pw.FontWeight.bold,
      color: profile['title_color'] as PdfColor,
    );

    final headingFont = pw.TextStyle(
      font: profile['font'] as pw.Font,
      fontSize: profile['heading_size'] as double,
      fontWeight: pw.FontWeight.bold,
      color: profile['heading_color'] as PdfColor,
    );

    final bodyFont = pw.TextStyle(
      font: profile['font'] as pw.Font,
      fontSize: profile['body_size'] as double,
      color: profile['body_color'] as PdfColor,
    );

    final formulaFont = pw.TextStyle(
      font: mathFont,
      fontSize: (profile['body_size'] as double) + 1,
      color: profile['body_color'] as PdfColor,
    );

    final sections = _extractSections(mapping);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _getPageFormat(options),
        margin: pw.EdgeInsets.all(_marginPoints(options.marginPreset)),
        build: (context) {
          return [
            pw.Text(
              mapping['{{TITLE}}'] as String? ?? 'Generated Document',
              style: titleFont,
            ),
            pw.SizedBox(height: 20),
            ...sections.expand((section) {
              final heading = section['heading'] as String? ?? '';
              final widgets = <pw.Widget>[
                if (heading.trim().isNotEmpty || options.workspaceMode != 'text') ...[
                  pw.Text(heading, style: headingFont),
                  pw.SizedBox(height: 10),
                ],
              ];

              for (final item in section['content'] as List? ?? []) {
                final type = item['type'] as String? ?? '';

                if (type == 'paragraph') {
                  final align = item['align'] as String? ?? 'left';
                  final alignment = switch (align) {
                    'center' => pw.Alignment.center,
                    'right' => pw.Alignment.centerRight,
                    _ => pw.Alignment.centerLeft,
                  };
                  final paragraph = pw.Text(
                    item['text'] as String? ?? '',
                    style: bodyFont.copyWith(
                      lineSpacing: options.lineSpacing,
                      fontWeight: item['bold'] == true ? pw.FontWeight.bold : null,
                      fontStyle: item['italic'] == true ? pw.FontStyle.italic : null,
                      color: PdfColor.fromHex(item['textColor'] as String? ?? '374151'),
                    ),
                    textAlign: align == 'center' ? pw.TextAlign.center : align == 'right' ? pw.TextAlign.right : align == 'justify' ? pw.TextAlign.justify : pw.TextAlign.left,
                  );
                  widgets.add(pw.Container(
                    width: double.infinity,
                    alignment: alignment,
                    color: item['highlight'] == true ? PdfColor.fromHex(item['highlightColor'] as String? ?? 'FFF2A6') : null,
                    padding: item['highlight'] == true ? const pw.EdgeInsets.all(3) : null,
                    child: paragraph,
                  ));
                  widgets.add(pw.SizedBox(height: 8));
                } else if (type == 'list') {
                  for (final listItem in item['items'] as List? ?? []) {
                    widgets.add(pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• ', style: bodyFont),
                        pw.Expanded(
                            child:
                                pw.Text(listItem.toString(), style: bodyFont)),
                      ],
                    ));
                  }
                  widgets.add(pw.SizedBox(height: 8));
                } else if (type == 'formula') {
                  final formula = item['text'] as String? ?? '';
                  if (formula.trim().isNotEmpty) {
                    widgets.add(
                      pw.Container(
                        width: double.infinity,
                        margin: const pw.EdgeInsets.only(bottom: 8),
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('F0F7FF'),
                          border: pw.Border(
                            left: pw.BorderSide(
                              color: PdfColor.fromHex('2563EB'),
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: pw.Text(formula, style: formulaFont),
                      ),
                    );
                  }
                } else if (type == 'table') {
                  final rows = item['rows'] as List? ?? [];
                  if (rows.isNotEmpty) {
                    widgets.add(
                      pw.TableHelper.fromTextArray(
                        data: rows
                            .map((r) =>
                                (r as List).map((c) => c.toString()).toList())
                            .toList(),
                        headerStyle: pw.TextStyle(
                            font: mathFont,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white),
                        cellStyle: pw.TextStyle(font: mathFont),
                        headerDecoration: pw.BoxDecoration(
                            color: profile['accent_color'] as PdfColor? ??
                                PdfColors.orange),
                        cellHeight: 30,
                        cellAlignments: {
                          for (int i = 0; i < (rows.first as List).length; i++)
                            i: pw.Alignment.centerLeft,
                        },
                      ),
                    );
                    widgets.add(pw.SizedBox(height: 8));
                  }
                } else if (type == 'image') {
                  final imagePath = item['path'] as String? ?? '';
                  final imageFile = File(imagePath);
                  if (imagePath.isNotEmpty && imageFile.existsSync()) {
                    try {
                      widgets.add(
                        pw.Center(
                          child: pw.Image(
                            pw.MemoryImage(imageFile.readAsBytesSync()),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      );
                      widgets.add(pw.SizedBox(height: 8));
                    } catch (_) {
                      // Keep producing the remaining document if an embedded
                      // source image uses an unsupported format.
                    }
                  }
                }
              }

              widgets.add(pw.SizedBox(height: 16));
              return widgets;
            }),
          ];
        },
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$baseName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  static Map<String, dynamic> _resolvedProfile(String styleProfile) {
    switch (styleProfile) {
      case 'modern':
        return {
          'font': pw.Font.helvetica(),
          'title_size': 22.0,
          'heading_size': 16.0,
          'body_size': 11.0,
          'title_color': PdfColor.fromHex('111827'),
          'heading_color': PdfColor.fromHex('1F2937'),
          'body_color': PdfColor.fromHex('374151'),
          'accent_color': PdfColor.fromHex('2563EB'),
          'margin': 72.0,
          'line_height': 1.15,
        };
      case 'module':
        return {
          'font': pw.Font.helvetica(),
          'title_size': 20.0,
          'heading_size': 14.0,
          'body_size': 11.0,
          'title_color': PdfColor.fromHex('153A5B'),
          'heading_color': PdfColor.fromHex('153A5B'),
          'body_color': PdfColor.fromHex('222222'),
          'accent_color': PdfColor.fromHex('2563EB'),
          'margin': 72.0,
          'line_height': 1.2,
        };
      case 'clean':
        return {
          'font': pw.Font.helvetica(),
          'title_size': 18.0,
          'heading_size': 13.0,
          'body_size': 11.0,
          'title_color': PdfColor.fromHex('111111'),
          'heading_color': PdfColor.fromHex('111111'),
          'body_color': PdfColor.fromHex('111111'),
          'accent_color': PdfColor.fromHex('888888'),
          'margin': 57.0,
          'line_height': 1.15,
        };
      default:
        return {
          'font': pw.Font.times(),
          'title_size': 20.0,
          'heading_size': 14.0,
          'body_size': 12.0,
          'title_color': PdfColor.fromHex('111111'),
          'heading_color': PdfColor.fromHex('111111'),
          'body_color': PdfColor.fromHex('111111'),
          'accent_color': PdfColor.fromHex('D96E31'),
          'margin': 80.0,
          'line_height': 1.3,
        };
    }
  }

  static PdfPageFormat _getPageFormat(GenerationOptions options) {
    PdfPageFormat format;
    switch (options.paperSize) {
      case 'letter':
        format = PdfPageFormat.letter;
        break;
      case 'legal':
        format = PdfPageFormat.legal;
        break;
      default:
        format = PdfPageFormat.a4;
    }

    if (options.pageOrientation == 'landscape') {
      format = format.landscape;
    }

    return format;
  }

  static double _marginPoints(String preset) {
    switch (preset) {
      case 'narrow':
        return 36;
      case 'wide':
        return 90;
      default:
        return 72;
    }
  }

  static List<Map<String, dynamic>> _extractSections(
      Map<String, dynamic> mapping) {
    final sections = <Map<String, dynamic>>[];
    final usedPlaceholders = <String>{};

    for (final key in mapping.keys) {
      if (key.startsWith('{{SECTION_') && !key.contains('_CONTENT')) {
        final heading = mapping[key] as String? ?? '';
        final contentKey = key.replaceFirst('{{SECTION_', '{{CONTENT_');
        final content = mapping[contentKey] as List? ?? [];

        if (!usedPlaceholders.contains(key)) {
          usedPlaceholders.add(key);
          sections.add({
            'heading': heading,
            'content': content,
          });
        }
      }
    }

    return sections;
  }

  static String _resolveDownloadBaseName(String requestedName, String title) {
    final candidates = [requestedName, title, 'converted-file'];
    for (final candidate in candidates) {
      final sanitized = _sanitizeFileBaseName(candidate);
      if (sanitized.isNotEmpty) return sanitized;
    }
    return 'converted-file';
  }

  static String _sanitizeFileBaseName(String value) {
    value = value.trim();
    value = value.replaceAll(RegExp(r'[^\p{L}\p{N}\-_ ]', unicode: true), '');
    value = value.replaceAll(RegExp(r'\s+'), '-');
    value = value.replaceAll(RegExp(r'-+'), '-');
    value = value.replaceAll(RegExp(r'^[-_. ]+|[-_. ]+$'), '');
    return value.length > 80 ? value.substring(0, 80) : value;
  }
}
