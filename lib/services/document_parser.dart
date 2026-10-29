import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentParser {
  static String normalize(String text) {
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = _repairControlPunctuation(text);
    text = text.replaceAll(RegExp(r'[ ]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static String _repairControlPunctuation(String text) {
    return text
        .replaceAll('\u0013', '-')
        .replaceAll('\u0014', '-')
        .replaceAll('\u0018', "'")
        .replaceAll('\u0019', "'")
        .replaceAll('\u001c', '"')
        .replaceAll('\u001d', '"')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  }

  static Future<String> extractText(String path, String extension) async {
    switch (extension.toLowerCase()) {
      case 'txt':
        return _fromTxt(path);
      case 'docx':
        return _fromDocx(path);
      case 'pdf':
        return _fromPdf(path);
      case 'pptx':
        return _fromPptx(path);
      case 'ppt':
        return _fromLegacyPpt(path);
      default:
        throw Exception('Unsupported file type: $extension');
    }
  }

  static Future<List<Map<String, dynamic>>> extractEmbeddedImages(
    String path,
    String extension,
  ) async {
    switch (extension.toLowerCase()) {
      case 'docx':
        return _extractZipImages(path, 'word/media/');
      case 'pptx':
        return _extractZipImages(path, 'ppt/media/');
      default:
        return [];
    }
  }

  /// Reads a DOCX body in its original order instead of flattening it into
  /// plain text first. A Word document is a sequence of paragraph and table
  /// nodes; treating images and tables as separate collections loses where
  /// they belong in that sequence.
  ///
  /// The returned image paths are local temporary copies of the original
  /// package media. They are used by PDF/HTML/reflow exports, while a
  /// preserve-layout DOCX export keeps the source package itself intact.
  static Future<List<Map<String, dynamic>>> extractDocxStructuredBlocks(
    String path,
  ) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final filesByName = <String, ArchiveFile>{
      for (final file in archive.where((file) => file.isFile)) file.name: file,
    };
    final documentFile = filesByName['word/document.xml'];
    if (documentFile == null) {
      throw Exception('Unable to open DOCX file: document.xml not found');
    }

    final relationships = _docxImageRelationships(
      filesByName['word/_rels/document.xml.rels'],
    );
    final document = XmlDocument.parse(
      _repairControlPunctuation(String.fromCharCodes(documentFile.content)),
    );
    XmlElement? body;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    if (body == null) return [];

    final docsDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(
      '${docsDir.path}/smart_template/extracted_images/docx_${DateTime.now().millisecondsSinceEpoch}',
    );
    final blocks = <Map<String, dynamic>>[];
    final extractedMedia = <String, String>{};
    var sourceOrder = 0;
    var imageIndex = 1;

    for (final node in body.children.whereType<XmlElement>()) {
      if (node.name.local == 'p') {
        final text = _docxNodeText(node).trim();
        final type = _docxParagraphType(node);
        if (text.isNotEmpty) {
          blocks.add({
            'type': type,
            'text': text,
            'source_order': sourceOrder,
            'source_paragraph_xml': node.toXmlString(),
            if (type == 'formula')
              'source_math_xml': _firstDocxMathXml(node),
          });
        }

        // A paragraph can contain text, a caption, and one or more inline or
        // floating images. Keep each image immediately next to that paragraph
        // in the block stream instead of appending every image at the end.
        for (final relationshipId in _docxImageRelationshipIds(node)) {
          final mediaTarget = relationships[relationshipId];
          if (mediaTarget == null) continue;
          final mediaPath = _normalizeDocxTarget(mediaTarget);
          final mediaFile = filesByName[mediaPath];
          if (mediaFile == null) continue;

          var extractedPath = extractedMedia[mediaPath];
          if (extractedPath == null) {
            if (!await imageDir.exists()) await imageDir.create(recursive: true);
            final extension = p.extension(mediaPath).toLowerCase();
            if (!['.png', '.jpg', '.jpeg', '.gif'].contains(extension)) {
              continue;
            }
            extractedPath = p.join(imageDir.path, 'image_$imageIndex$extension');
            await File(extractedPath)
                .writeAsBytes(List<int>.from(mediaFile.content as List));
            extractedMedia[mediaPath] = extractedPath;
            imageIndex++;
          }

          blocks.add({
            'type': 'image',
            'path': extractedPath,
            'caption': text,
            'context_text': text,
            'source_order': sourceOrder,
            'source_relationship_id': relationshipId,
            'source_media_target': mediaPath,
          });
        }
      } else if (node.name.local == 'tbl') {
        final rows = _docxTableRows(node);
        if (rows.isNotEmpty) {
          blocks.add({
            'type': 'table',
            'rows': rows,
            // This is intentionally retained for reflow DOCX exports. The
            // exact preserve mode copies the original DOCX package instead.
            'source_table_xml': node.toXmlString(),
            'source_order': sourceOrder,
          });
        }
      }
      sourceOrder++;
    }

    return blocks;
  }

  static Map<String, String> _docxImageRelationships(ArchiveFile? relsFile) {
    if (relsFile == null) return const {};
    final relationships = <String, String>{};
    try {
      final rels = XmlDocument.parse(String.fromCharCodes(relsFile.content));
      for (final relationship in rels.descendants.whereType<XmlElement>()) {
        if (relationship.name.local != 'Relationship') continue;
        final id = _attributeValue(relationship, 'Id');
        final target = _attributeValue(relationship, 'Target');
        final type = _attributeValue(relationship, 'Type') ?? '';
        if (id != null && target != null && type.endsWith('/image')) {
          relationships[id] = target;
        }
      }
    } catch (_) {
      // The normal text conversion can still proceed if a malformed
      // relationship part prevents locating an image.
    }
    return relationships;
  }

  static String _normalizeDocxTarget(String target) {
    final normalized = target.replaceAll('\\', '/');
    return normalized.startsWith('word/') ? normalized : 'word/$normalized';
  }

  static List<String> _docxImageRelationshipIds(XmlElement paragraph) {
    final ids = <String>[];
    for (final element in paragraph.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'blip' && element.name.local != 'imagedata') {
        continue;
      }
      final id = _attributeValue(element, 'embed') ??
          _attributeValue(element, 'id');
      if (id != null && id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static String? _attributeValue(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _docxParagraphType(XmlElement paragraph) {
    final hasMath = paragraph.descendants
        .whereType<XmlElement>()
        .any((element) => element.name.local == 'oMath' || element.name.local == 'oMathPara');
    if (hasMath) return 'formula';

    final style = paragraph.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'pStyle',
          orElse: () => XmlElement(XmlName('missing')),
        );
    final styleValue = _attributeValue(style, 'val')?.toLowerCase() ?? '';
    final hasOutlineLevel = paragraph.descendants
        .whereType<XmlElement>()
        .any((element) => element.name.local == 'outlineLvl');
    if (styleValue.contains('heading') || styleValue == 'title' || hasOutlineLevel) {
      return 'heading';
    }
    return 'paragraph';
  }

  static String? _firstDocxMathXml(XmlElement paragraph) {
    for (final element in paragraph.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'oMath' || element.name.local == 'oMathPara') {
        return element.toXmlString();
      }
    }
    return null;
  }

  static Future<Map<int, String>> extractPdfPageTexts(String path) async {
    final bytes = await File(path).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final Map<int, String> pages = {};
    
    for (int i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
      if (text.trim().isNotEmpty) {
        pages[i + 1] = normalize(text);
      }
    }
    
    document.dispose();
    return pages;
  }

  static Future<Map<String, dynamic>> extractPdfLayoutInfo(String path) async {
    final bytes = await File(path).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final rawPages = <String>[];

    for (int i = 0; i < document.pages.count; i++) {
      rawPages.add(PdfTextExtractor(document)
          .extractText(startPageIndex: i, endPageIndex: i));
    }

    document.dispose();
    final analysis = _analyzePdfPageMargins(rawPages);
    final pageCharacterCounts = rawPages
        .map((page) => _contentLines(page).join(' ').replaceAll(RegExp(r'\s+'), '').length)
        .toList();
    final sparsePages = pageCharacterCounts
        .where((characterCount) => characterCount < 40)
        .length;
    // A PDF page with almost no extractable text is commonly a scanned page or
    // a page whose text is baked into an image. We do not pretend OCR happened:
    // this signal is surfaced to the user for an accurate review decision.
    final likelyScanned = rawPages.isNotEmpty &&
        sparsePages >= (rawPages.length * 0.6).ceil();
    return {
      'page_count': rawPages.length,
      'text_characters': pageCharacterCounts.fold<int>(0, (sum, value) => sum + value),
      'sparse_text_pages': sparsePages,
      'likely_scanned': likelyScanned,
      'repeated_header_footer_lines': analysis.removedLines,
      'has_repeated_header_footer': analysis.removedLines.isNotEmpty,
      'layout_warning':
          'PDF source detected. If the file has heavy design, columns, diagrams, decorative headers, or footers, extracted content may need manual review.',
    };
  }

  static Future<String> _fromTxt(String path) async {
    final text = await File(path).readAsString();
    return normalize(text);
  }

  static Future<String> _fromDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    String? documentXml;
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        documentXml = String.fromCharCodes(file.content);
        break;
      }
    }
    
    if (documentXml == null) {
      throw Exception('Unable to open DOCX file: document.xml not found');
    }

    return normalize(_parseDocxBodyText(documentXml));
  }

  static String _parseDocxBodyText(String documentXml) {
    final repairedXml = _repairControlPunctuation(documentXml);
    final document = XmlDocument.parse(repairedXml);
    XmlElement? body;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    if (body == null) {
      return _stripXmlTags(repairedXml);
    }

    final lines = <String>[];
    for (final node in body.children.whereType<XmlElement>()) {
      if (node.name.local == 'p') {
        final text = _docxNodeText(node).trim();
        if (text.isNotEmpty) lines.add(text);
      } else if (node.name.local == 'tbl') {
        final rows = _docxTableRows(node);
        for (final row in rows) {
          if (row.any((cell) => cell.trim().isNotEmpty)) {
            lines.add(row.join('\t'));
          }
        }
      }
    }

    return lines.join('\n');
  }

  static List<List<String>> _docxTableRows(XmlElement table) {
    final rows = <List<String>>[];
    for (final row in table.children.whereType<XmlElement>().where(
          (element) => element.name.local == 'tr',
        )) {
      final cells = <String>[];
      for (final cell in row.children.whereType<XmlElement>().where(
            (element) => element.name.local == 'tc',
          )) {
        final cellParagraphs = cell.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'p')
            .map((paragraph) => _docxNodeText(paragraph).trim())
            .where((text) => text.isNotEmpty)
            .toList();
        cells.add(cellParagraphs.join(' '));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static String _docxNodeText(XmlNode node) {
    if (node is XmlText) return node.value;
    if (node is! XmlElement) return '';

    if (node.name.local == 'oMath' || node.name.local == 'oMathPara') {
      return _ommlToLinearText(node);
    }
    if (node.name.local == 'r') {
      final font = _docxRunFont(node);
      final text = node.children
          .where((child) => child is! XmlElement || child.name.local != 'rPr')
          .map(_docxNodeText)
          .join();
      return _decodeLegacySymbolFont(text, font);
    }
    if (node.name.local == 'tab') return '\t';
    if (node.name.local == 'br' || node.name.local == 'cr') return '\n';
    if (node.name.local == 'noBreakHyphen') return '‑';
    if (node.name.local == 'softHyphen') return '­';
    if (node.name.local == 'sym') return _docxSymbolText(node);

    final buffer = StringBuffer();
    for (final child in node.children) {
      buffer.write(_docxNodeText(child));
    }
    return buffer.toString();
  }

  static String _docxRunFont(XmlElement run) {
    for (final element in run.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'rFonts') continue;
      return _attributeValue(element, 'ascii') ??
          _attributeValue(element, 'hAnsi') ??
          _attributeValue(element, 'cs') ??
          '';
    }
    return '';
  }

  /// Older Word documents sometimes encode Greek/math characters as ordinary
  /// Latin letters rendered with the Symbol font. The raw character alone is
  /// misleading after conversion, so translate the well-defined Symbol
  /// alphabet before exporting to PDF/HTML/TXT. Preserve Layout still keeps
  /// the original font and character bytes untouched.
  static String _decodeLegacySymbolFont(String text, String font) {
    final normalizedFont = font.toLowerCase();
    if (!normalizedFont.contains('symbol')) return text;

    const symbolAlphabet = <String, String>{
      'A': 'Α', 'B': 'Β', 'C': 'Χ', 'D': 'Δ', 'E': 'Ε', 'F': 'Φ',
      'G': 'Γ', 'H': 'Η', 'I': 'Ι', 'J': 'ϑ', 'K': 'Κ', 'L': 'Λ',
      'M': 'Μ', 'N': 'Ν', 'O': 'Ο', 'P': 'Π', 'Q': 'Θ', 'R': 'Ρ',
      'S': 'Σ', 'T': 'Τ', 'U': 'Υ', 'V': 'ς', 'W': 'Ω', 'X': 'Ξ',
      'Y': 'Ψ', 'Z': 'Ζ',
      'a': 'α', 'b': 'β', 'c': 'χ', 'd': 'δ', 'e': 'ε', 'f': 'φ',
      'g': 'γ', 'h': 'η', 'i': 'ι', 'j': 'ϕ', 'k': 'κ', 'l': 'λ',
      'm': 'μ', 'n': 'ν', 'o': 'ο', 'p': 'π', 'q': 'θ', 'r': 'ρ',
      's': 'σ', 't': 'τ', 'u': 'υ', 'v': 'ϖ', 'w': 'ω', 'x': 'ξ',
      'y': 'ψ', 'z': 'ζ',
    };
    return text.split('').map((character) => symbolAlphabet[character] ?? character).join();
  }

  /// Converts Office Math Markup Language (OMML) to a readable linear form
  /// for PDF, HTML, TXT, and the in-app preview. The untouched OMML is kept
  /// alongside it for DOCX output. Without this, a fraction such as an ANOVA
  /// F-ratio is read as a single flat string or a broken font glyph.
  static String _ommlToLinearText(XmlElement node) {
    final name = node.name.local;
    final children = node.children.whereType<XmlElement>().toList();
    String child(String localName) {
      for (final element in children) {
        if (element.name.local == localName) return _ommlToLinearText(element);
      }
      return '';
    }

    switch (name) {
      case 'oMath':
      case 'oMathPara':
      case 'e':
      case 'num':
      case 'den':
      case 'base':
      case 'sub':
      case 'sup':
      case 'deg':
      case 'lim':
      case 'fName':
        return children.map(_ommlToLinearText).join();
      case 'r':
        return children
            .where((element) => element.name.local != 'rPr')
            .map(_ommlToLinearText)
            .join();
      case 't':
        return node.innerText;
      case 'f':
        final numerator = child('num');
        final denominator = child('den');
        return numerator.isEmpty && denominator.isEmpty
            ? ''
            : '($numerator)/($denominator)';
      case 'sSub':
        return '${child('e')}_{${child('sub')}}';
      case 'sSup':
        return '${child('e')}^{${child('sup')}}';
      case 'sSubSup':
        return '${child('e')}_{${child('sub')}}^{${child('sup')}}';
      case 'rad':
        final degree = child('deg');
        final expression = child('e');
        return degree.isEmpty ? '√($expression)' : '√[$degree]($expression)';
      case 'nary':
        final operator = _ommlNaryOperator(node);
        final lower = child('sub');
        final upper = child('sup');
        final expression = child('e');
        return '$operator${lower.isEmpty ? '' : '_{$lower}'}${upper.isEmpty ? '' : '^{$upper}'}$expression';
      case 'func':
        return '${child('fName')}(${child('e')})';
      case 'd':
        final expression = child('e');
        final delimiters = _ommlDelimiters(node);
        return '${delimiters.$1}$expression${delimiters.$2}';
      case 'bar':
      case 'acc':
      case 'groupChr':
        return child('e');
      case 'mPr':
      case 'rPr':
      case 'fPr':
      case 'sSubPr':
      case 'sSupPr':
      case 'sSubSupPr':
      case 'radPr':
      case 'naryPr':
      case 'dPr':
      case 'funcPr':
      case 'ctrlPr':
        return '';
      default:
        return children.map(_ommlToLinearText).join();
    }
  }

  static String _ommlNaryOperator(XmlElement node) {
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'chr') continue;
      final value = _attributeValue(element, 'val');
      if (value != null && value.isNotEmpty) return value;
    }
    return '∑';
  }

  static (String, String) _ommlDelimiters(XmlElement node) {
    var start = '(';
    var end = ')';
    for (final element in node.descendants.whereType<XmlElement>()) {
      final value = _attributeValue(element, 'val');
      if (value == null || value.isEmpty) continue;
      if (element.name.local == 'begChr') start = value;
      if (element.name.local == 'endChr') end = value;
    }
    return (start, end);
  }

  /// Word can store a character as `<w:sym>` rather than normal text. Keep a
  /// readable Unicode equivalent for reflow formats; the preserve-layout DOCX
  /// path retains the original symbol/font bytes without this conversion.
  static String _docxSymbolText(XmlElement symbol) {
    final rawCharacter = _attributeValue(symbol, 'char');
    if (rawCharacter == null) return '□';
    final code = int.tryParse(rawCharacter, radix: 16);
    if (code == null) return '□';

    final font = (_attributeValue(symbol, 'font') ?? '').toLowerCase();
    if (font.contains('symbol')) {
      const symbolFontMap = <int, String>{
        0x22: '∀',
        0x24: '∃',
        0x2A: '∗',
        0x2D: '−',
        0x40: '≅',
        0xB1: '±',
        0xB4: '×',
        0xB8: '÷',
        0xA3: '≤',
        0xB3: '≥',
        0xB9: '≠',
        0xD5: 'Π',
        0xE5: 'Σ',
        0xF2: '∫',
        0xA5: '∞',
      };
      if (symbolFontMap.containsKey(code)) return symbolFontMap[code]!;
    }

    // Values in the Unicode range are already safe to emit. Private-use
    // glyphs (common in Wingdings) have no dependable Unicode equivalent, so
    // show a stable placeholder rather than corrupting surrounding text.
    if (code >= 0x20 && code <= 0x10FFFF &&
        !(code >= 0xE000 && code <= 0xF8FF)) {
      return String.fromCharCode(code);
    }
    return '□';
  }

  static Future<String> _fromPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final pages = <String>[];
    for (int i = 0; i < document.pages.count; i++) {
      pages.add(PdfTextExtractor(document)
          .extractText(startPageIndex: i, endPageIndex: i));
    }
    document.dispose();
    return normalize(_stripRepeatedPdfHeadersAndFooters(pages));
  }

  static String _stripRepeatedPdfHeadersAndFooters(List<String> pages) {
    final analysis = _analyzePdfPageMargins(pages);
    if (analysis.removedLines.isEmpty) {
      return pages.join('\n\n');
    }

    final cleanedPages = <String>[];
    for (final page in pages) {
      final cleanedLines = _contentLines(page)
          .where((line) => !analysis.removedLines.contains(_marginKey(line)))
          .toList();
      cleanedPages.add(cleanedLines.join('\n'));
    }
    return cleanedPages.join('\n\n');
  }

  static _PdfMarginAnalysis _analyzePdfPageMargins(List<String> pages) {
    if (pages.length < 2) return const _PdfMarginAnalysis({});

    final counts = <String, int>{};
    for (final page in pages) {
      final lines = _contentLines(page);
      final marginLines = <String>{};
      marginLines.addAll(lines.take(3).map(_marginKey));
      marginLines.addAll(lines.reversed.take(3).map(_marginKey));
      for (final line in marginLines.where((line) => line.isNotEmpty)) {
        counts[line] = (counts[line] ?? 0) + 1;
      }
    }

    final threshold = pages.length == 2 ? 2 : (pages.length * 0.6).ceil();
    final repeated = counts.entries
        .where((entry) => entry.value >= threshold)
        .map((entry) => entry.key)
        .toSet();
    return _PdfMarginAnalysis(repeated);
  }

  static List<String> _contentLines(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => _repairControlPunctuation(line).trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String _marginKey(String line) {
    return line.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static Future<String> _fromPptx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final Map<String, String> slideXml = {};
    for (final file in archive) {
      if (RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name)) {
        slideXml[file.name] = String.fromCharCodes(file.content);
      }
    }
    
    final sortedKeys = slideXml.keys.toList()..sort();
    final slides = <String>[];
    
    for (final key in sortedKeys) {
      final xml = slideXml[key]!;
      final lines = _parsePptxSlideText(xml);
      if (lines.isNotEmpty) {
        slides.add(lines.join('\n'));
      }
    }
    
    return normalize(slides.join('\n\n'));
  }

  static Future<List<Map<String, dynamic>>> _extractZipImages(
    String sourcePath,
    String mediaPrefix,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final docsDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(
      '${docsDir.path}/smart_template/extracted_images/${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!await imageDir.exists()) await imageDir.create(recursive: true);

    final images = <Map<String, dynamic>>[];
    var index = 1;
    final seenHashes = <int, int>{};
    for (final file in archive) {
      if (!file.isFile || !file.name.startsWith(mediaPrefix)) continue;
      final extension = p.extension(file.name).toLowerCase();
      if (!['.png', '.jpg', '.jpeg', '.gif'].contains(extension)) continue;

      final imageBytes = List<int>.from(file.content as List);
      if (_shouldSkipDecorativeImage(
        imageBytes,
        file.name,
        seenHashes,
      )) {
        continue;
      }

      final targetName = 'image_$index$extension';
      final targetPath = p.join(imageDir.path, targetName);
      await File(targetPath).writeAsBytes(imageBytes);
      images.add({
        'path': targetPath,
        'caption': 'Figure $index',
        'section_hint': '',
        'width_percent': 80,
        'rotation': 0,
      });
      index++;
    }

    return images;
  }

  static bool _shouldSkipDecorativeImage(
    List<int> bytes,
    String name,
    Map<int, int> seenHashes,
  ) {
    final size = _readImageSize(bytes);
    final hash = Object.hashAll(bytes.take(4096));
    seenHashes[hash] = (seenHashes[hash] ?? 0) + 1;
    final duplicate = seenHashes[hash]! > 1;

    if (size == null) return bytes.length < 10 * 1024 || duplicate;

    final width = size.width;
    final height = size.height;
    final area = width * height;
    final squareIcon = (width - height).abs() <= 12 && width <= 320;
    final tinyAsset = area < 120000 || bytes.length < 10 * 1024;
    final logoName = RegExp(
      r'(logo|icon|favicon|brand|seal|badge)',
      caseSensitive: false,
    ).hasMatch(name);

    return logoName || squareIcon || (tinyAsset && duplicate);
  }

  static _ImageSize? _readImageSize(List<int> bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      return _ImageSize(data.getUint32(16), data.getUint32(20));
    }

    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 9 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        final length = (bytes[offset + 2] << 8) + bytes[offset + 3];
        if (length < 2 || offset + length >= bytes.length) break;

        final isStartOfFrame =
            (marker >= 0xC0 && marker <= 0xC3) ||
                (marker >= 0xC5 && marker <= 0xC7) ||
                (marker >= 0xC9 && marker <= 0xCB) ||
                (marker >= 0xCD && marker <= 0xCF);
        if (isStartOfFrame) {
          final height = (bytes[offset + 5] << 8) + bytes[offset + 6];
          final width = (bytes[offset + 7] << 8) + bytes[offset + 8];
          return _ImageSize(width, height);
        }
        offset += 2 + length;
      }
    }

    return null;
  }

  static Future<String> _fromLegacyPpt(String path) async {
    final bytes = await File(path).readAsBytes();
    final text = String.fromCharCodes(bytes);
    final matches =
        RegExp(r"[A-Za-z0-9][A-Za-z0-9,.\-()/:;'\s]{4,}").allMatches(text);
    final chunks = matches.map((m) => m.group(0)!).where((s) => s.trim().length >= 4).toList();
    return normalize(chunks.join('\n'));
  }

  static List<String> _parsePptxSlideText(String xml) {
    final document = XmlDocument.parse(xml);
    final texts = <String>[];
    
    for (final element in document.findAllElements('a:t')) {
      final text = element.innerText.trim();
      if (text.isNotEmpty) {
        texts.add(text);
      }
    }
    
    return texts;
  }

  static String _stripXmlTags(String xml) {
    return xml.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Future<List<Map<String, dynamic>>> extractDocxTables(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    String? documentXml;
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        documentXml = String.fromCharCodes(file.content);
        break;
      }
    }
    
    if (documentXml == null) return [];

    final document = XmlDocument.parse(_repairControlPunctuation(documentXml));
    // The raw OpenXML is kept for DOCX export only. This retains cell widths,
    // borders, shading, merges and alignment when the source table is reused.
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tbl')
        .map((table) => {
              'rows': _docxTableRows(table),
              'raw_xml': table.toXmlString(),
              'source_format': 'docx_openxml',
            })
        .where((table) => (table['rows'] as List).isNotEmpty)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> extractPptxTables(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final tables = <List<List<String>>>[];
    
    for (final file in archive) {
      if (!RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name)) continue;
      
      final xml = String.fromCharCodes(file.content);
      final tableMatches = RegExp(r'<a:tbl\b.*?>(.*?)<\/a:tbl>', dotAll: true).allMatches(xml);
      
      for (final tableMatch in tableMatches) {
        final tableXml = tableMatch.group(1)!;
        final rows = <List<String>>[];
        
        final rowMatches = RegExp(r'<a:tr\b.*?>(.*?)<\/a:tr>', dotAll: true).allMatches(tableXml);
        for (final rowMatch in rowMatches) {
          final rowXml = rowMatch.group(1)!;
          final cells = <String>[];
          
          final cellMatches = RegExp(r'<a:tc\b.*?>(.*?)<\/a:tc>', dotAll: true).allMatches(rowXml);
          for (final cellMatch in cellMatches) {
            final cellXml = cellMatch.group(1)!;
            final textMatches = RegExp(r'<a:t>(.*?)<\/a:t>', dotAll: true).allMatches(cellXml);
            final cellText = textMatches.map((m) => m.group(1)!).join('').trim();
            cells.add(cellText);
          }
          
          if (cells.isNotEmpty) rows.add(cells);
        }
        
        if (rows.isNotEmpty) tables.add(rows);
      }
    }
    
    return tables.map((rows) => {'rows': rows}).toList();
  }
}

class _ImageSize {
  final int width;
  final int height;

  const _ImageSize(this.width, this.height);
}

class _PdfMarginAnalysis {
  final Set<String> removedLines;

  const _PdfMarginAnalysis(this.removedLines);
}
