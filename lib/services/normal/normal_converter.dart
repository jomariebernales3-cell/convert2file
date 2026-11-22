import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'docx_style_reader.dart';
import 'normal_html_renderer.dart';
import 'normal_unsupported.dart';
import 'pdf_style_writer.dart';
import 'pdf_to_docx.dart';
import 'pdf_to_html.dart';
import 'pdf_to_txt.dart';
import 'docx_to_txt.dart';
import 'docx_to_pdf_webview.dart';
import 'styled_document.dart';
import 'package:webview_flutter/webview_flutter.dart';

export 'normal_unsupported.dart' show NormalUnsupported;

class NormalResult {
  final String path;
  final List<String> notes;

  const NormalResult({required this.path, this.notes = const []});
}

class NormalConverter {
  static Future<NormalResult> convert(
    String sourcePath,
    String sourceExt,
    String targetExt,
    String baseName, {
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
    WebViewController? docxWebViewController,
  }) async {
    final source = sourceExt.toLowerCase().replaceFirst('.', '');
    final target = targetExt.toLowerCase().replaceFirst('.', '');
    final safeBaseName = _safeBaseName(baseName);
    late final String outputPath;
    try {
      final directory = await getTemporaryDirectory();
      outputPath = path.join(
        directory.path,
        'normal_${DateTime.now().millisecondsSinceEpoch}_$safeBaseName.$target',
      );
    } catch (error) {
      if (source == 'docx' && target == 'pdf') {
        debugPrint(
          'DOCX->PDF engine=legacy reason=setup exception: $error fonts=Noto Sans Symbols 2,Noto Sans Symbols',
        );
      }
      rethrow;
    }

    if (source == target && (source == 'docx' || source == 'pdf')) {
      await File(sourcePath).copy(outputPath);
      return NormalResult(path: outputPath);
    }
    if (source == 'txt' && target == 'docx') {
      final text = await File(sourcePath).readAsString();
      await _writeTxtDocx(text, outputPath);
      return NormalResult(path: outputPath);
    }
    if (source == 'txt' && target == 'html') {
      final text = await File(sourcePath).readAsString();
      await File(outputPath).writeAsBytes(
        utf8.encode(NormalHtmlRenderer.renderText(text, safeBaseName)),
      );
      return NormalResult(path: outputPath);
    }
    if (source == 'txt' && target == 'pdf') {
      final text = await File(sourcePath).readAsString();
      final document = StyledDocument(
        pageWidth: 595.28,
        pageHeight: 841.89,
        marginTop: 72,
        marginRight: 72,
        marginBottom: 72,
        marginLeft: 72,
        blocks: text
            .split(RegExp(r'\r\n|\n|\r'))
            .map(
              (line) => StyledParagraph(
                runs: [
                  StyledRun(
                    text: line,
                    fontFamily: 'Liberation Sans',
                    fontSize: 11,
                  ),
                ],
                lineSpacing: 1,
              ),
            )
            .toList(),
      );
      final notes = await PdfStyleWriter.write(document, outputPath);
      return NormalResult(path: outputPath, notes: notes);
    }
    if (source == 'docx' && target == 'html') {
      final document = await DocxStyleReader.read(sourcePath);
      await File(outputPath).writeAsBytes(
        utf8.encode(NormalHtmlRenderer.renderDocx(document, safeBaseName)),
      );
      return NormalResult(path: outputPath, notes: document.notes);
    }
    if (source == 'pdf' && target == 'html') {
      final notes = await PdfToHtml.convert(sourcePath, outputPath);
      return NormalResult(path: outputPath, notes: notes);
    }
    if (source == 'pdf' && target == 'docx') {
      try {
        final notes = await PdfToDocx.convert(
          sourcePath,
          outputPath,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        return NormalResult(path: outputPath, notes: notes);
      } catch (_) {
        final output = File(outputPath);
        if (await output.exists()) await output.delete();
        rethrow;
      }
    }
    if (source == 'docx' && target == 'txt') {
      final notes = await DocxToTxt.convert(sourcePath, outputPath);
      return NormalResult(path: outputPath, notes: notes);
    }
    if (source == 'pdf' && target == 'txt') {
      final notes = await PdfToTxt.convert(sourcePath, outputPath);
      return NormalResult(path: outputPath, notes: notes);
    }
    if (source == 'docx' && target == 'pdf') {
      var engine = 'legacy';
      var reason = DocxToPdfWebView.forcedEngine == 'legacy'
          ? 'forcedEngine=legacy'
          : 'WebView host unavailable';
      try {
        if (DocxToPdfWebView.forcedEngine != 'legacy') {
          if (!DocxToPdfWebView.isSupportedPlatform) {
            reason = 'unsupported platform=${DocxToPdfWebView.platformName}';
          } else if (docxWebViewController == null) {
            reason = 'WebView host unavailable';
          } else {
            try {
              final webViewPdf = await DocxToPdfWebView.convert(
                await File(sourcePath).readAsBytes(),
                docxWebViewController,
              );
              await File(outputPath).writeAsBytes(webViewPdf, flush: true);
              engine = 'webview';
              reason = 'ok';
              return NormalResult(path: outputPath);
            } catch (error) {
              // Preserve the precise WebView failure as the fallback reason.
              reason = error.toString();
            }
          }
        }
        final document = await DocxStyleReader.read(sourcePath);
        final writerNotes = await PdfStyleWriter.write(document, outputPath);
        final pageCount = await _pdfPageCount(outputPath);
        developer.log('DOCX legacy PDF pages=${pageCount ?? 'unknown'}');
        return NormalResult(
          path: outputPath,
          notes: {...document.notes, ...writerNotes}.toList(),
        );
      } catch (error) {
        reason = 'legacy exception: $error';
        rethrow;
      } finally {
        debugPrint(
          'DOCX->PDF engine=$engine reason=$reason fonts=Noto Sans Symbols 2,Noto Sans Symbols',
        );
      }
    }
    throw NormalUnsupported(source, target);
  }

  static Future<void> _writeTxtDocx(String text, String outputPath) async {
    final paragraphs = text
        .split(RegExp(r'\r\n|\n|\r'))
        .map((line) => '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>'
            '<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" '
            'w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/>'
            '</w:rPr><w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>')
        .join();
    const documentStart =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>';
    const section = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
        'w:left="1440" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>';
    final documentXml =
        '$documentStart$paragraphs$section</w:body></w:document>';
    const contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const relationships =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';

    final archive = Archive();
    _addUtf8File(archive, '[Content_Types].xml', contentTypes);
    _addUtf8File(archive, '_rels/.rels', relationships);
    _addUtf8File(archive, 'word/document.xml', documentXml);
    final encoded = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(encoded);
  }

  static Future<int?> _pdfPageCount(String pdfPath) async {
    try {
      final pdf = sf.PdfDocument(inputBytes: await File(pdfPath).readAsBytes());
      final count = pdf.pages.count;
      pdf.dispose();
      return count;
    } catch (error) {
      developer.log('Unable to read DOCX PDF page count: $error');
      return null;
    }
  }

  static void _addUtf8File(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static String _safeBaseName(String value) {
    final withoutExtension = path.basenameWithoutExtension(value.trim());
    final cleaned = withoutExtension
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'converted-file' : cleaned;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
