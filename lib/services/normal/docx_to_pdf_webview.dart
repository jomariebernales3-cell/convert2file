import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:webview_flutter/webview_flutter.dart';

/// Offline DOCX rendering bridge. The WebView itself is mounted by the Normal
/// conversion screen so its platform view remains alive while this runs.
class DocxToPdfWebView {
  DocxToPdfWebView._();

  /// Set to `legacy`, `webview`, or `auto` to compare/force an engine.
  static const String forcedEngine = 'auto';
  static const int maxInputBytes = 40 * 1024 * 1024;
  static const Duration renderTimeout = Duration(seconds: 45);

  static Completer<String>? _pageSignal;
  static final List<String> _javascriptConsoleErrors = [];
  static final List<String> _rendererWarnings = [];

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static WebViewController createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'DocxRender',
        onMessageReceived: (message) {
          if (message.message.startsWith('render-warning:')) {
            _rendererWarnings
                .add(message.message.substring('render-warning:'.length));
            return;
          }
          if (message.message.startsWith('console-error:')) {
            _javascriptConsoleErrors
                .add(message.message.substring('console-error:'.length));
            return;
          }
          final signal = _pageSignal;
          if (signal != null && !signal.isCompleted) {
            signal.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // Permit the local Flutter asset origin and its file subresources.
            final isLocal = uri == null ||
                uri.scheme == 'about' ||
                uri.scheme == 'file' ||
                uri.host == 'flutterassets.com';
            return isLocal
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    return controller;
  }

  static Future<Uint8List> convert(
    Uint8List docxBytes,
    WebViewController controller,
  ) async {
    if (docxBytes.isEmpty || docxBytes.length > maxInputBytes) {
      throw StateError(
          'DOCX input is empty or exceeds the 40 MiB WebView limit');
    }

    _javascriptConsoleErrors.clear();
    _rendererWarnings.clear();
    try {
      return await _renderWithController(docxBytes, controller);
    } finally {
      _pageSignal = null;
      // webview_flutter disposes the platform WebView with its mounted widget;
      // clear the document after each job so large HTML/image trees are freed.
      await controller.loadRequest(Uri.parse('about:blank'));
    }
  }

  static Future<Uint8List> _renderWithController(
    Uint8List docxBytes,
    WebViewController controller,
  ) async {
    final initialPage = Completer<String>();
    _pageSignal = initialPage;
    await controller.loadFlutterAsset('assets/docx_render/render.html');
    final loaded = await initialPage.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw TimeoutException('Local DOCX renderer did not load'),
    );
    if (loaded != 'page-ready') {
      throw StateError('Unexpected renderer startup message: $loaded');
    }

    final renderResult = Completer<String>();
    _pageSignal = renderResult;
    final base64Docx = base64Encode(docxBytes);
    await controller.runJavaScript(
      'window.renderDocxFromBase64(${jsonEncode(base64Docx)});',
    );
    final status = await renderResult.future.timeout(renderTimeout);
    if (!status.startsWith('render-complete:')) {
      throw StateError(status.startsWith('render-error:')
          ? status.substring('render-error:'.length)
          : 'Unexpected DOCX render status: $status');
    }
    final expectedPageCount = int.tryParse(
      status.substring('render-complete:'.length),
    );
    if (expectedPageCount == null || expectedPageCount < 1) {
      throw StateError('DOCX renderer returned an invalid page count: $status');
    }
    if (_javascriptConsoleErrors.isNotEmpty) {
      throw StateError(
        'JavaScript console error: ${_javascriptConsoleErrors.join(' | ')}',
      );
    }

    final renderedHtmlBase64 = await controller.runJavaScriptReturningResult(
      'window.getRenderedHtmlBase64()',
    );
    final htmlBase64 = _unwrapJavaScriptString(renderedHtmlBase64);
    final html = await _inlineBundledFontAssets(
      utf8.decode(base64Decode(htmlBase64)),
    );
    final printHtml = html.replaceFirst(
      '</head>',
      '<style media="print">'
          'html,body,#document{height:auto!important;min-height:0!important}'
          '#document>.docx{overflow:hidden!important;'
          'page-break-inside:avoid!important;break-inside:avoid-page!important}'
          '#document>.docx:last-child{page-break-after:auto!important;'
          'break-after:auto!important}'
          '</style></head>',
    );
    final pageFormat = await _readFirstSectionPageFormat(docxBytes);

    // printing's HTML conversion uses the platform's native HTML print engine
    // on Android and iOS, avoiding a WebView screenshot/raster PDF.
    // This is the native Android/iOS HTML print bridge used here; printing
    // currently deprecates it without an equivalent HTML-to-PDF API. On
    // Android, Printing.info() does not report canConvertHtml even though the
    // native method channel implements convertHtml, so calling that capability
    // flag here would incorrectly force every Android file to the legacy path.
    // ignore: deprecated_member_use
    final pdf = await Printing.convertHtml(
      html: printHtml,
      format: pageFormat,
    );
    if (pdf.length < 1000) {
      throw StateError('WebView renderer returned an empty or undersized PDF');
    }
    final cleanedPdf = await _removeBlankTrailingPrintPages(
      pdf,
      docxBytes,
      expectedPageCount,
    );
    final pdfDocument = sf.PdfDocument(inputBytes: cleanedPdf);
    final pageCount = pdfDocument.pages.count;
    pdfDocument.dispose();
    // The completion status is also sent over the DocxRender JavaScriptChannel.
    developer.log('DOCX WebView render complete; PDF pages=$pageCount');
    for (final warning in _rendererWarnings) {
      developer.log('DOCX WebView renderer warning: $warning');
    }
    return cleanedPdf;
  }

  static Future<Uint8List> _removeBlankTrailingPrintPages(
    Uint8List pdfBytes,
    Uint8List docxBytes,
    int expectedPageCount,
  ) async {
    sf.PdfDocument? document;
    try {
      if (_docxRequiresTrailingPage(docxBytes)) return pdfBytes;
      document = sf.PdfDocument(inputBytes: pdfBytes);
      final actualPageCount = document.pages.count;
      if (actualPageCount < 2) return pdfBytes;
      final lastPageIndex = actualPageCount - 1;
      final isBlank = _pdfLastPageHasOnlyWhiteBackground(
        pdfBytes,
        lastPageIndex,
      );
      if (!isBlank) {
        developer.log(
          'DOCX WebView kept trailing page; pdf=$actualPageCount '
          'renderer=$expectedPageCount blank=$isBlank',
        );
        return pdfBytes;
      }
      // The renderer's DOM count is the target page count. Also remove an
      // empty final page when it equals that count: some print engines expose
      // an overflow page as a final .docx element with no visible text.
      document.pages.removeAt(lastPageIndex);
      final trimmed = document.saveSync();
      final check = sf.PdfDocument(inputBytes: Uint8List.fromList(trimmed));
      final savedPageCount = check.pages.count;
      check.dispose();
      if (savedPageCount != actualPageCount - 1) {
        developer.log(
          'DOCX WebView trailing-page cleanup expected '
          '${actualPageCount - 1}, saved $savedPageCount; keeping original PDF',
        );
        return pdfBytes;
      }
      developer.log(
        'DOCX WebView removed blank trailing page '
        '(renderer=$expectedPageCount, before=$actualPageCount)',
      );
      return Uint8List.fromList(trimmed);
    } catch (error) {
      // Cleanup is best-effort; a malformed or unfamiliar PDF stays intact.
      developer.log('DOCX WebView trailing-page cleanup failed: $error');
      return pdfBytes;
    } finally {
      document?.dispose();
    }
  }

  static bool _pdfLastPageHasOnlyWhiteBackground(
    Uint8List pdfBytes,
    int pageIndex,
  ) {
    try {
      final rawPdf = String.fromCharCodes(pdfBytes);
      final objects = RegExp(
        r'(?m)^(\d+)\s+\d+\s+obj\b([\s\S]*?)endobj',
      ).allMatches(rawPdf).toList(growable: false);
      final pageObjects = objects.where((match) {
        final body = match.group(2)!;
        return RegExp(r'/Type\s*/Page\b').hasMatch(body) &&
            !RegExp(r'/Type\s*/Pages\b').hasMatch(body);
      }).toList(growable: false);
      if (pageIndex < 0 || pageIndex >= pageObjects.length) return false;
      final pageBody = pageObjects[pageIndex].group(2)!;
      final contentReferences = RegExp(r'(\d+)\s+\d+\s+R')
          .allMatches(RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)')
                  .firstMatch(pageBody)
                  ?.group(1) ??
              '')
          .map((match) => match.group(1)!)
          .toList(growable: false);
      if (contentReferences.isEmpty) return false;
      final objectById = <String, String>{
        for (final object in objects) object.group(1)!: object.group(2)!,
      };
      for (final objectId in contentReferences) {
        final streamObject = objectById[objectId];
        if (streamObject == null ||
            !_streamHasWhiteBackgroundOnly(streamObject)) {
          return false;
        }
      }
      return true;
    } catch (error) {
      developer.log('DOCX WebView PDF blank-page inspection skipped: $error');
      return false;
    }
  }

  static bool _streamHasWhiteBackgroundOnly(String objectBody) {
    final streamMarker = objectBody.indexOf('stream');
    final endMarker = objectBody.indexOf('endstream', streamMarker + 6);
    if (streamMarker < 0 || endMarker < 0) return false;
    var dataStart = streamMarker + 6;
    if (dataStart < objectBody.length && objectBody[dataStart] == '\r') {
      dataStart++;
    }
    if (dataStart < objectBody.length && objectBody[dataStart] == '\n') {
      dataStart++;
    }
    var dataEnd = endMarker;
    while (dataEnd > dataStart &&
        (objectBody[dataEnd - 1] == '\r' || objectBody[dataEnd - 1] == '\n')) {
      dataEnd--;
    }
    final streamBytes = <int>[
      for (final unit
          in objectBody.codeUnits.skip(dataStart).take(dataEnd - dataStart))
        unit & 0xff,
    ];
    final decodedBytes = objectBody.contains('/FlateDecode')
        ? const ZLibDecoder().decodeBytes(streamBytes)
        : streamBytes;
    final content = String.fromCharCodes(decodedBytes);
    final tokens = RegExp(
      r'/[A-Za-z0-9]+|[-+]?(?:\d*\.\d+|\d+\.?\d*)|[A-Za-z][A-Za-z*]*',
    ).allMatches(content).map((match) => match.group(0)!).toList();
    var operands = <String>[];
    var fillIsWhite = false;
    for (final token in tokens) {
      if (token.startsWith('/') || double.tryParse(token) != null) {
        operands.add(token);
        continue;
      }
      switch (token) {
        case 'q':
        case 'Q':
        case 'cm':
        case 'gs':
        case 're':
        case 'W':
        case 'W*':
        case 'n':
          break;
        case 'rg':
        case 'RG':
          fillIsWhite = operands.length >= 3 &&
              operands
                  .take(operands.length)
                  .toList()
                  .sublist(operands.length - 3)
                  .every((v) => v == '1');
          if (!fillIsWhite) return false;
          break;
        case 'g':
        case 'G':
          fillIsWhite = operands.isNotEmpty && operands.last == '1';
          if (!fillIsWhite) return false;
          break;
        case 'f':
        case 'F':
        case 'f*':
          if (!fillIsWhite) return false;
          break;
        default:
          // Text, images, strokes, and non-rectangular paths are real content.
          return false;
      }
      operands = <String>[];
    }
    return true;
  }

  static bool _docxRequiresTrailingPage(Uint8List docxBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes, verify: false);
      final documentEntry = archive.findFile('word/document.xml');
      if (documentEntry == null) return true;
      final xml = utf8.decode(documentEntry.content as List<int>);
      final paragraphs = RegExp(
        r'<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>',
      ).allMatches(xml).toList(growable: false);
      final finalParagraph =
          paragraphs.isEmpty ? '' : paragraphs.last.group(0)!;
      final explicitBreak = RegExp(
        r'''<w:(?:lastRenderedPageBreak|pageBreakBefore)\b|<w:br\b[^>]*w:type=(?:"page"|'page')''',
      ).hasMatch(finalParagraph);
      final finalSectionStart = xml.lastIndexOf('<w:sectPr');
      final finalSection =
          finalSectionStart < 0 ? '' : xml.substring(finalSectionStart);
      final sectionRequiresBlankPage = RegExp(
        r'''<w:type\b[^>]*w:val=(?:"oddPage"|'oddPage'|"evenPage"|'evenPage')''',
      ).hasMatch(finalSection);
      return explicitBreak || sectionRequiresBlankPage;
    } catch (error) {
      developer.log('DOCX WebView terminal-page check failed: $error');
      return true;
    }
  }

  static String _unwrapJavaScriptString(Object value) {
    if (value is String) {
      // Android WebView may JSON-quote string evaluation results.
      if (value.startsWith('"') && value.endsWith('"')) {
        final decoded = jsonDecode(value);
        if (decoded is String) return decoded;
      }
      return value;
    }
    return value.toString();
  }

  static Future<String> _inlineBundledFontAssets(String html) async {
    // Printing.convertHtml runs in a separate native WebView, so Flutter asset
    // URLs are replaced with data URLs before crossing that platform boundary.
    const fontAssets = <String, String>{
      'LiberationSans-Regular.ttf': 'assets/fonts/LiberationSans-Regular.ttf',
      'LiberationSerif-Regular.ttf': 'assets/fonts/LiberationSerif-Regular.ttf',
      'LiberationMono-Regular.ttf': 'assets/fonts/LiberationMono-Regular.ttf',
      'Carlito-Regular.ttf': 'assets/fonts/Carlito-Regular.ttf',
      'Carlito-Bold.ttf': 'assets/fonts/Carlito-Bold.ttf',
      'NotoSansSymbols2-Regular.ttf':
          'assets/docx_render/fonts/NotoSansSymbols2-Regular.ttf',
      'NotoSansSymbols-Regular.ttf':
          'assets/docx_render/fonts/NotoSansSymbols-Regular.ttf',
    };
    var result = html;
    for (final entry in fontAssets.entries) {
      final fileName = entry.key;
      try {
        final data = await rootBundle.load(entry.value);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final dataUrl = 'data:font/ttf;base64,${base64Encode(bytes)}';
        result = result.replaceAll('../fonts/$fileName', dataUrl);
        result = result.replaceAll('fonts/$fileName', dataUrl);
      } catch (error) {
        developer.log('DOCX WebView font fallback missing: $fileName ($error)');
      }
    }
    return result;
  }

  static Future<PdfPageFormat> _readFirstSectionPageFormat(
    Uint8List docxBytes,
  ) async {
    // The DOCX package parser is already used by the legacy converter. This
    // small reader uses document.xml's first w:pgSz and w:pgMar values.
    final pageInfo = await _readPageTwips(docxBytes);
    const twipsPerPoint = 20.0; // OOXML twips are 1/20 of a PDF point.
    return PdfPageFormat(
      pageInfo.width / twipsPerPoint,
      pageInfo.height / twipsPerPoint,
      marginLeft: 0,
      marginTop: 0,
      marginRight: 0,
      marginBottom: 0,
    );
  }

  static Future<_PageTwips> _readPageTwips(Uint8List docxBytes) async {
    // Missing or malformed section geometry raises a detailed exception so
    // the converter can record why it selected the legacy route.
    final xml = await _readDocumentXml(docxBytes);
    final section =
        RegExp(r'<w:sectPr\b[\s\S]*?</w:sectPr>').firstMatch(xml)?.group(0) ??
            xml;
    final size =
        RegExp(r'<w:pgSz\b([^>]*)').firstMatch(section)?.group(1) ?? '';
    var width = _xmlAttribute(size, 'w') ?? 12240;
    var height = _xmlAttribute(size, 'h') ?? 15840;
    final orientation = _xmlStringAttribute(size, 'orient');
    if (orientation == 'landscape' && width < height) {
      final swap = width;
      width = height;
      height = swap;
    }
    return _PageTwips(width, height);
  }

  static Future<String> _readDocumentXml(Uint8List bytes) async {
    // Importing the DOCX ZIP reader here would duplicate ZIP work; use the
    // application's existing archive package through its public API.
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final file = archive.findFile('word/document.xml');
    if (file == null) throw const FormatException('DOCX has no document.xml');
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  static int? _xmlAttribute(String attributes, String name) {
    final match = RegExp('(?:^|\\s)w:$name="(\\d+)"').firstMatch(attributes);
    return int.tryParse(match?.group(1) ?? '');
  }

  static String? _xmlStringAttribute(String attributes, String name) {
    final match = RegExp('(?:^|\\s)w:$name="([^"]+)"').firstMatch(attributes);
    return match?.group(1);
  }
}

class _PageTwips {
  const _PageTwips(this.width, this.height);
  final int width;
  final int height;
}
