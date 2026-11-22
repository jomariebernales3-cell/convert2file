import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../document_parser.dart';
import 'styled_document.dart';

class DocxStyleReader {
  static Future<StyledDocument> read(String sourcePath) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await File(sourcePath).readAsBytes());
    } on Object catch (error) {
      return StyledDocument(
        notes: ['DOCX package could not be opened ($error).'],
      );
    }
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) file.name.replaceAll('\\', '/'): file,
    };
    final notes = <String>{};
    final media = <String, Uint8List>{};
    final relationships = _readRelationships(files, notes);
    final documentEntry = files['word/document.xml'];
    if (documentEntry == null) {
      return const StyledDocument(notes: ['DOCX content was unavailable.']);
    }

    XmlDocument xml;
    try {
      xml = XmlDocument.parse(_decode(documentEntry));
    } on Object {
      return const StyledDocument(notes: ['DOCX content could not be read.']);
    }
    final themePart = _relatedPart(files, 'theme') ?? 'word/theme/theme1.xml';
    final stylesPart = _relatedPart(files, 'styles') ?? 'word/styles.xml';
    final numberingPart =
        _relatedPart(files, 'numbering') ?? 'word/numbering.xml';
    final footnotesPart =
        _relatedPart(files, 'footnotes') ?? 'word/footnotes.xml';
    final settingsPart = _relatedPart(files, 'settings') ?? 'word/settings.xml';
    final theme = _readTheme(files[themePart], notes);
    final styles = _readStyles(files[stylesPart], notes, theme);
    final numbering = _readNumbering(files[numberingPart], notes);
    final footnotes = _readFootnotes(
      files[footnotesPart],
      styles,
      numbering,
      notes,
      theme: theme,
    );
    if (_hasSkippedContent(xml.rootElement, files)) {
      notes.add('Some items were simplified.');
    }
    for (final entry in files.entries) {
      if (!const {
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.bmp',
        '.tif',
        '.tiff',
        '.emf',
        '.wmf',
        '.svg',
      }.contains(path.posix.extension(entry.key).toLowerCase())) {
        continue;
      }
      media[entry.key] =
          Uint8List.fromList(List<int>.from(entry.value.content as List));
    }

    final body = _child(xml.rootElement, 'body');
    if (body == null) {
      return StyledDocument(notes: ['DOCX body was unavailable.']);
    }
    var pageWidth = 595.28;
    var pageHeight = 841.89;
    var marginTop = 72.0;
    var marginRight = 72.0;
    var marginBottom = 72.0;
    var marginLeft = 72.0;
    final blocks = <StyledBlock>[];
    for (final child in body.children.whereType<XmlElement>()) {
      try {
        if (child.name.local == 'p') {
          blocks.addAll(_readParagraphBlocks(
            child,
            styles,
            numbering,
            relationships,
            media,
            notes,
            theme: theme,
          ));
          final paragraphSection = _child(_child(child, 'pPr'), 'sectPr');
          if (paragraphSection != null) {
            blocks.add(_readSectionBreak(paragraphSection, relationships));
          }
        } else if (child.name.local == 'tbl') {
          blocks.add(_readTable(
            child,
            styles,
            numbering,
            relationships,
            media,
            notes,
            theme: theme,
          ));
        } else if (child.name.local == 'sectPr') {
          final setup = _readPageSetup(child);
          pageWidth = setup['width'] ?? pageWidth;
          pageHeight = setup['height'] ?? pageHeight;
          marginTop = setup['top'] ?? marginTop;
          marginRight = setup['right'] ?? marginRight;
          marginBottom = setup['bottom'] ?? marginBottom;
          marginLeft = setup['left'] ?? marginLeft;
          blocks.add(_readSectionBreak(
            child,
            relationships,
            finalSection: true,
          ));
        } else {
          final text = _fallbackText(child);
          if (text.isNotEmpty) {
            blocks.add(StyledParagraph(runs: [StyledRun(text: text)]));
          }
          notes.add(
            'Unsupported DOCX element <${child.name.local}>; kept its text where available.',
          );
        }
      } on Object catch (error) {
        final text = _fallbackText(child);
        if (text.isNotEmpty) {
          blocks.add(StyledParagraph(runs: [StyledRun(text: text)]));
        }
        notes.add(
          'DOCX element <${child.name.local}> was simplified ($error); kept its text where available.',
        );
      }
    }

    final headerStories = _readRelatedParts(
      files,
      media,
      'header',
      styles,
      numbering,
      notes,
      theme: theme,
    );
    final footerStories = _readRelatedParts(
      files,
      media,
      'footer',
      styles,
      numbering,
      notes,
      theme: theme,
    );
    final header = _firstStory(headerStories);
    final footer = _firstStory(footerStories);
    final evenAndOddHeaders = _readEvenAndOddHeaders(files[settingsPart]);
    _checkTextPreservation(body, blocks, notes);
    return StyledDocument(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      marginTop: marginTop,
      marginRight: marginRight,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      blocks: blocks,
      notes: notes.toList(),
      visibleText: _fallbackText(body),
      header: header,
      footer: footer,
      headerStories: headerStories,
      footerStories: footerStories,
      evenAndOddHeaders: evenAndOddHeaders,
      footnotes: footnotes,
    );
  }

  static String _decode(ArchiveFile file) =>
      utf8.decode(List<int>.from(file.content as List), allowMalformed: true);

  static String _fallbackText(XmlElement element) {
    final buffer = StringBuffer();
    void visit(XmlNode node) {
      if (node is XmlText) {
        buffer.write(node.value);
      } else if (node is XmlElement) {
        if (node.name.local == 'instrText' || node.name.local == 'fldChar') {
          return;
        }
        if (node.name.local == 'fldSimple') return;
        if (node.name.local == 't' || node.name.local == 'delText') {
          buffer.write(node.innerText);
          return;
        }
        if (node.name.local == 'sym') {
          buffer.write(DocumentParser.docxSymbolText(node));
          return;
        }
        if (node.name.local == 'tab') {
          buffer.write('\t');
        } else if (node.name.local == 'br' || node.name.local == 'cr') {
          buffer.write('\n');
        } else if (node.name.local == 'footnoteReference') {
          buffer.write(_attribute(node, 'id') ?? '');
        } else {
          for (final child in node.children) {
            visit(child);
          }
        }
      }
    }

    visit(element);
    return buffer.toString();
  }

  static void _checkTextPreservation(
    XmlElement sourceBody,
    List<StyledBlock> blocks,
    Set<String> notes,
  ) {
    final source = _fallbackText(sourceBody).replaceAll(RegExp(r'\s+'), '');
    final output = StringBuffer();
    void visit(List<StyledBlock> current) {
      for (final block in current) {
        if (block is StyledParagraph) {
          for (final run in block.runs) {
            if (run.imageBytes == null) output.write(run.text);
            if (run.shape != null) output.write(run.shape!.text);
          }
        } else if (block is StyledShape) {
          output.write(block.text);
        } else if (block is StyledTable) {
          for (final row in block.rows) {
            for (final cell in row.cells) {
              visit(cell.blocks);
            }
          }
        }
      }
    }

    visit(blocks);
    final parsed = output
        .toString()
        .replaceAll(RegExp(r'\{(?:PAGE|NUMPAGES|SECTIONPAGES|DATE)\}'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (source != parsed) {
      notes.add(
        'DOCX text check found a content/order difference '
        '(source ${source.length} characters, parsed ${parsed.length}).',
      );
    }
  }

  static Map<String, String> _readRelationships(
    Map<String, ArchiveFile> files,
    Set<String> notes,
  ) {
    final entry = files['word/_rels/document.xml.rels'];
    if (entry == null) return const {};
    try {
      final xml = XmlDocument.parse(_decode(entry));
      return {
        for (final element in xml.descendants.whereType<XmlElement>())
          if (element.name.local == 'Relationship' &&
              _attribute(element, 'Id') != null &&
              _attribute(element, 'Target') != null)
            _attribute(element, 'Id')!: _attribute(element, 'Target')!,
      };
    } on Object {
      notes.add('Some DOCX links and images were simplified.');
      return const {};
    }
  }

  // Resolves a relationship type from document.xml.rels, with conventional
  // part names as a fallback at the call site when a relationship is absent.
  static String? _relatedPart(
    Map<String, ArchiveFile> files,
    String relationshipKind,
  ) {
    final entry = files['word/_rels/document.xml.rels'];
    if (entry == null) return null;
    try {
      final xml = XmlDocument.parse(_decode(entry));
      for (final relationship in xml.descendants.whereType<XmlElement>()) {
        if (relationship.name.local != 'Relationship') continue;
        final type = _attribute(relationship, 'Type') ?? '';
        final target = _attribute(relationship, 'Target');
        if (!type.endsWith('/$relationshipKind') || target == null) continue;
        if ((_attribute(relationship, 'TargetMode') ?? '') == 'External') {
          continue;
        }
        return _normalizePartTarget('word/document.xml', target);
      }
    } on Object {
      return null;
    }
    return null;
  }

  static Map<String, _StyleDefinition> _readStyles(
    ArchiveFile? entry,
    Set<String> notes,
    _Theme theme,
  ) {
    if (entry == null) return const {};
    try {
      final xml = XmlDocument.parse(_decode(entry));
      final result = <String, _StyleDefinition>{};
      final defaults = _child(xml.rootElement, 'docDefaults');
      final runDefaults = _child(_child(defaults, 'rPrDefault'), 'rPr');
      final paraDefaults = _child(_child(defaults, 'pPrDefault'), 'pPr');
      result['__defaults__'] = _StyleDefinition(
        id: '__defaults__',
        run: _readRunProperties(runDefaults, theme),
        paragraph: _readParagraphProperties(paraDefaults, theme),
      );
      for (final style in xml.descendants.whereType<XmlElement>()) {
        if (style.name.local != 'style') continue;
        final id = _attribute(style, 'styleId');
        if (id == null) continue;
        result[id] = _StyleDefinition(
          id: id,
          basedOn: _attribute(_child(style, 'basedOn'), 'val'),
          name: _attribute(_child(style, 'name'), 'val'),
          run: _readRunProperties(_child(style, 'rPr'), theme),
          paragraph: _readParagraphProperties(_child(style, 'pPr'), theme),
          tableBorders: _readBorders(
            _child(_child(style, 'tblPr'), 'tblBorders'),
            theme,
          ),
          tableShading:
              _readShading(_child(_child(style, 'tblPr'), 'shd'), theme),
          cellBorders: _readBorders(
            _child(_child(style, 'tcPr'), 'tcBorders'),
            theme,
          ),
          cellShading:
              _readShading(_child(_child(style, 'tcPr'), 'shd'), theme),
          hasConditionalTableFormatting: style.descendants
              .whereType<XmlElement>()
              .any((item) => item.name.local == 'tblStylePr'),
        );
      }
      return result;
    } on Object {
      notes.add('Some DOCX styles were simplified.');
      return const {};
    }
  }

  static Map<String, _NumberDefinition> _readNumbering(
    ArchiveFile? entry,
    Set<String> notes,
  ) {
    if (entry == null) return const {};
    try {
      final xml = XmlDocument.parse(_decode(entry));
      final abstracts = <String, Map<int, _NumberLevel>>{};
      for (final abstract in xml.descendants.whereType<XmlElement>()) {
        if (abstract.name.local != 'abstractNum') continue;
        final abstractId = _attribute(abstract, 'abstractNumId');
        if (abstractId == null) continue;
        final levels = <int, _NumberLevel>{};
        for (final level in abstract.children.whereType<XmlElement>()) {
          if (level.name.local != 'lvl') continue;
          final index = int.tryParse(_attribute(level, 'ilvl') ?? '0') ?? 0;
          final format = _attribute(_child(level, 'numFmt'), 'val') ?? 'bullet';
          final marker = _attribute(_child(level, 'lvlText'), 'val') ?? '•';
          final markerFonts = _child(_child(level, 'rPr'), 'rFonts');
          final markerFontFamily = _attribute(markerFonts, 'ascii') ??
              _attribute(markerFonts, 'hAnsi');
          final start =
              int.tryParse(_attribute(_child(level, 'start'), 'val') ?? '') ??
                  1;
          final ind = _child(_child(level, 'pPr'), 'ind');
          levels[index] = _NumberLevel(
            format,
            marker,
            markerFontFamily: markerFontFamily,
            start: start,
            leftIndent:
                _twips(_attribute(ind, 'left') ?? _attribute(ind, 'start')),
            hangingIndent: _twips(_attribute(ind, 'hanging')),
          );
        }
        abstracts[abstractId] = levels;
      }
      final result = <String, _NumberDefinition>{};
      for (final number in xml.descendants.whereType<XmlElement>()) {
        if (number.name.local != 'num') continue;
        final id = _attribute(number, 'numId');
        final abstractId = _attribute(_child(number, 'abstractNumId'), 'val');
        if (id != null && abstractId != null) {
          result[id] = _NumberDefinition(abstracts[abstractId] ?? const {});
        }
      }
      return result;
    } on Object {
      notes.add('Some DOCX lists were simplified.');
      return const {};
    }
  }

  static Map<String, dynamic> _readRunProperties(
    XmlElement? properties, [
    _Theme? theme,
  ]) {
    if (properties == null) return {};
    final fonts = _child(properties, 'rFonts');
    final colorElement = _child(properties, 'color');
    final color = _attribute(colorElement, 'val') ??
        theme?.colors[_attribute(colorElement, 'themeColor')];
    final highlight =
        _highlightColor(_attribute(_child(properties, 'highlight'), 'val'));
    final runShading = _readShading(_child(properties, 'shd'), theme);
    final size =
        double.tryParse(_attribute(_child(properties, 'sz'), 'val') ?? '');
    final vertical = _attribute(_child(properties, 'vertAlign'), 'val');
    return {
      if (_child(properties, 'b') != null) 'bold': _on(_child(properties, 'b')),
      if (_child(properties, 'i') != null)
        'italic': _on(_child(properties, 'i')),
      if (_child(properties, 'u') != null)
        'underline':
            (_attribute(_child(properties, 'u'), 'val') ?? 'single') != 'none',
      if (_child(properties, 'strike') != null)
        'strike': _on(_child(properties, 'strike')),
      if (_child(properties, 'dstrike') != null)
        'strike': _on(_child(properties, 'dstrike')),
      if (color != null && color.toLowerCase() != 'auto') 'color': color,
      if (highlight != null || runShading != null)
        'background': highlight ?? runShading,
      if (fonts != null)
        'fontFamily': _attribute(fonts, 'ascii') ??
            _attribute(fonts, 'hAnsi') ??
            _attribute(fonts, 'eastAsia') ??
            theme?.fonts[_attribute(fonts, 'asciiTheme')] ??
            theme?.fonts[_attribute(fonts, 'hAnsiTheme')] ??
            theme?.fonts[_attribute(fonts, 'eastAsiaTheme')],
      // Word run font sizes are stored as half-points.
      if (size != null) 'fontSize': size / 2,
      if (vertical != null) 'vertical': vertical,
    };
  }

  static String? _highlightColor(String? value) => switch (value) {
        'black' => '#000000',
        'blue' => '#0000FF',
        'cyan' => '#00FFFF',
        'darkBlue' => '#000080',
        'darkCyan' => '#008080',
        'darkGray' => '#808080',
        'darkGreen' => '#008000',
        'darkMagenta' => '#800080',
        'darkRed' => '#800000',
        'darkYellow' => '#808000',
        'green' => '#00FF00',
        'lightGray' => '#C0C0C0',
        'magenta' => '#FF00FF',
        'red' => '#FF0000',
        'white' => '#FFFFFF',
        'yellow' => '#FFFF00',
        _ => null,
      };

  static Map<String, dynamic> _readParagraphProperties(
    XmlElement? properties, [
    _Theme? theme,
  ]) {
    if (properties == null) return {};
    final spacing = _child(properties, 'spacing');
    final ind = _child(properties, 'ind');
    final outline =
        int.tryParse(_attribute(_child(properties, 'outlineLvl'), 'val') ?? '');
    final number = _child(properties, 'numPr');
    final paragraphBorders = _readBorders(_child(properties, 'pBdr'), theme);
    final shading = _readShading(_child(properties, 'shd'), theme);
    final numId = _attribute(_child(number, 'numId'), 'val');
    final level =
        int.tryParse(_attribute(_child(number, 'ilvl'), 'val') ?? '0') ?? 0;
    final alignment = _attribute(_child(properties, 'jc'), 'val');
    final before = _twips(_attribute(spacing, 'before'));
    final after = _twips(_attribute(spacing, 'after'));
    final line = double.tryParse(_attribute(spacing, 'line') ?? '');
    final lineRule = _attribute(spacing, 'lineRule') ?? 'auto';
    final left = _twips(_attribute(ind, 'left') ?? _attribute(ind, 'start'));
    final right = _twips(_attribute(ind, 'right') ?? _attribute(ind, 'end'));
    final firstLine = _twips(_attribute(ind, 'firstLine')) -
        _twips(_attribute(ind, 'hanging'));
    return {
      if (alignment != null) 'alignment': alignment,
      if (before != 0) 'spacingBefore': before,
      if (after != 0) 'spacingAfter': after,
      // Auto line spacing uses 240 units per line; exact/atLeast use twips.
      if (line != null && line > 0)
        'lineSpacing': lineRule == 'auto' ? line / 240 : line / 20,
      if (line != null && line > 0) 'lineSpacingRule': lineRule,
      if (left != 0) 'indentLeft': left,
      if (right != 0) 'indentRight': right,
      if (firstLine != 0) 'firstLineIndent': firstLine,
      if (outline != null && outline < 9) 'headingLevel': outline + 1,
      if (numId != null) 'numId': numId,
      if (numId != null) 'listLevel': level,
      if (paragraphBorders.isNotEmpty) 'borders': paragraphBorders,
      if (shading != null && shading.toLowerCase() != 'auto')
        'shading': '#$shading',
    };
  }

  static List<StyledBlock> _readParagraphBlocks(
      XmlElement paragraph,
      Map<String, _StyleDefinition> styles,
      Map<String, _NumberDefinition> numbering,
      Map<String, String> relationships,
      Map<String, Uint8List> media,
      Set<String> notes,
      {_Theme? theme,
      String partPath = 'word/document.xml'}) {
    final pPr = _child(paragraph, 'pPr');
    final styleId = _attribute(_child(pPr, 'pStyle'), 'val');
    final style = _resolveStyle(styleId, styles);
    final paragraphProperties = <String, dynamic>{
      ..._resolveStyleProperties(styleId, styles, run: false),
      ..._readParagraphProperties(pPr, theme),
    };
    final runDefaults = <String, dynamic>{
      ...(_resolveStyleProperties(styleId, styles, run: true)),
      ..._resolveStyleProperties(
        _attribute(_child(_child(pPr, 'rPr'), 'rStyle'), 'val'),
        styles,
        run: true,
      ),
      ..._readRunProperties(_child(pPr, 'rPr'), theme),
    };
    var headingLevel = paragraphProperties['headingLevel'] as int?;
    final styleName = (style?.name ?? styleId ?? '').toLowerCase();
    final headingMatch = RegExp(r'heading\s*(\d+)').firstMatch(styleName);
    headingLevel ??=
        headingMatch == null ? null : int.tryParse(headingMatch.group(1)!);

    final listId = paragraphProperties['numId'] as String?;
    final listLevel = paragraphProperties['listLevel'] as int? ?? 0;
    StyledListInfo? listInfo;
    if (listId != null) {
      final list = numbering[listId]?.levels[listLevel];
      listInfo = StyledListInfo(
        id: listId,
        level: listLevel,
        format: list?.format ?? 'bullet',
        marker: list?.marker ?? '•',
        markerFontFamily: list?.markerFontFamily,
        leftIndent: list?.leftIndent ?? 0,
        hangingIndent: list?.hangingIndent ?? 0,
        start: list?.start ?? 1,
      );
    }

    final runs = _readParagraphRuns(
      paragraph,
      runDefaults,
      relationships,
      media,
      styles,
      theme,
      partPath,
    );
    final alignment = switch (paragraphProperties['alignment']) {
      'center' => 'center',
      'right' || 'end' => 'right',
      'both' || 'distribute' => 'justify',
      _ => 'left',
    };
    final paragraphBlock = StyledParagraph(
      runs: runs,
      alignment: alignment,
      spacingBefore: (paragraphProperties['spacingBefore'] as double?) ?? 0,
      spacingAfter: (paragraphProperties['spacingAfter'] as double?) ?? 0,
      lineSpacing: paragraphProperties['lineSpacing'] as double?,
      lineSpacingRule:
          paragraphProperties['lineSpacingRule'] as String? ?? 'auto',
      indentLeft: (paragraphProperties['indentLeft'] as double?) ?? 0,
      indentRight: (paragraphProperties['indentRight'] as double?) ?? 0,
      firstLineIndent: (paragraphProperties['firstLineIndent'] as double?) ?? 0,
      headingLevel: headingLevel,
      listInfo: listInfo,
      borders:
          (paragraphProperties['borders'] as Map<String, String>?) ?? const {},
      shading: paragraphProperties['shading'] as String?,
      borderPadding: _borderSpace(_child(pPr, 'pBdr')),
    );

    final result = <StyledBlock>[];
    if (_child(pPr, 'pageBreakBefore') != null) result.add(const PageBreak());
    final hasAnchoredObject = paragraph.descendants.whereType<XmlElement>().any(
        (element) =>
            (element.name.local == 'drawing' &&
                _firstDescendant(element, 'anchor') != null) ||
            element.name.local == 'pict');
    if (runs.isNotEmpty || !hasAnchoredObject) result.add(paragraphBlock);
    for (final drawing in paragraph.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'drawing',
        )) {
      if (_firstDescendant(drawing, 'inline') != null) continue;
      final groupedShapes = drawing.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'wsp')
          .toList();
      if (groupedShapes.isNotEmpty) {
        for (final shapeElement in groupedShapes) {
          final shape = _readShape(
            drawing,
            shapeElement: shapeElement,
            theme: theme,
          );
          if (shape != null) result.add(shape);
        }
        continue;
      }
      final blip = _firstDescendant(drawing, 'blip');
      if (blip == null) {
        final text = _fallbackText(drawing);
        if (text.isNotEmpty) {
          result.add(StyledParagraph(runs: [StyledRun(text: text)]));
        }
        notes.add(
          'Unsupported DOCX drawing <${drawing.name.local}>; kept its text where available.',
        );
        continue;
      }
      final relationshipId = _attribute(blip, 'embed');
      final target =
          relationshipId == null ? null : relationships[relationshipId];
      if (target == null) {
        notes.add('Some DOCX images were simplified.');
        continue;
      }
      final mediaPath = target.startsWith('/')
          ? target.substring(1)
          : _normalizePartTarget(partPath, target);
      final bytes = media[mediaPath];
      if (bytes == null) {
        notes.add('Some DOCX images were simplified.');
        continue;
      }
      final mime = _imageMime(mediaPath);
      final extent = _firstDescendant(drawing, 'extent');
      final docProperties = _firstDescendant(drawing, 'docPr');
      final width = double.tryParse(_attribute(extent, 'cx') ?? '');
      final height = double.tryParse(_attribute(extent, 'cy') ?? '');
      final anchor = _firstDescendant(drawing, 'anchor');
      result.add(StyledImage(
        bytes: bytes,
        mime: mime,
        // Drawing extents use EMUs; convert them to PDF points.
        width: width == null ? null : width / 12700,
        height: height == null ? null : height / 12700,
        position: anchor == null ? 'inline' : 'floating',
        alt: _attribute(docProperties, 'descr') ??
            _attribute(docProperties, 'name') ??
            'Image',
        crop: _imageCrop(drawing),
        rotation: _imageRotation(drawing),
        wrapMode: _wrapMode(anchor),
      ));
    }
    for (final pict in paragraph.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'pict',
        )) {
      final imageData = _firstDescendant(pict, 'imagedata');
      if (imageData != null) {
        final relationshipId = _attribute(imageData, 'id');
        final target =
            relationshipId == null ? null : relationships[relationshipId];
        final mediaPath = target == null
            ? null
            : target.startsWith('/')
                ? target.substring(1)
                : _normalizePartTarget(partPath, target);
        final bytes = mediaPath == null ? null : media[mediaPath];
        if (bytes != null && mediaPath != null) {
          final style =
              _attribute(_firstDescendant(pict, 'shape'), 'style') ?? '';
          result.add(StyledImage(
            bytes: bytes,
            mime: _imageMime(mediaPath),
            width: _cssLengthPt(style, 'width'),
            height: _cssLengthPt(style, 'height'),
            alt: _attribute(imageData, 'title') ?? 'VML image',
          ));
          final text = _fallbackText(pict);
          if (text.isNotEmpty) {
            result.add(StyledParagraph(runs: [StyledRun(text: text)]));
          }
          continue;
        }
      }
      final vmlShapes = pict.descendants
          .whereType<XmlElement>()
          .where((element) => const {
                'shape',
                'rect',
                'roundrect',
                'oval',
                'line',
              }.contains(element.name.local))
          .toList();
      var drewVmlShape = false;
      for (final vmlElement in vmlShapes) {
        final vmlShape = _readVmlShape(vmlElement);
        if (vmlShape != null) {
          result.add(vmlShape);
          drewVmlShape = true;
        }
      }
      if (!drewVmlShape) {
        final text = _fallbackText(pict);
        if (text.isNotEmpty) {
          result.add(StyledParagraph(runs: [StyledRun(text: text)]));
        }
        notes.add(
            'Unsupported legacy VML element <pict>; kept its text where available.');
      }
    }
    if (paragraph.descendants.whereType<XmlElement>().any(
          (element) =>
              element.name.local == 'br' &&
              _attribute(element, 'type') == 'page',
        )) {
      result.add(const PageBreak());
    }
    return result;
  }

  // Reads paragraph runs and replaces cached results for dynamic page/date
  // fields while retaining cached text for unsupported fields such as TOC.
  static List<StyledRun> _readParagraphRuns(
    XmlElement paragraph,
    Map<String, dynamic> runDefaults,
    Map<String, String> relationships,
    Map<String, Uint8List> media,
    Map<String, _StyleDefinition> styles,
    _Theme? theme,
    String partPath,
  ) {
    final runs = <StyledRun>[];
    var inField = false;
    var inFieldResult = false;
    var replaceFieldResult = false;
    var instruction = '';
    for (final child in paragraph.children.whereType<XmlElement>()) {
      if (child.name.local == 'pPr') continue;
      final fieldChar =
          child.name.local == 'r' ? _firstDescendant(child, 'fldChar') : null;
      final fieldType =
          _attribute(fieldChar, 'fldCharType') ?? _attribute(fieldChar, 'type');
      if (fieldType == 'begin') {
        inField = true;
        inFieldResult = false;
        replaceFieldResult = false;
        instruction = '';
        continue;
      }
      if (fieldType == 'separate') {
        inFieldResult = true;
        final marker = _fieldMarker(instruction);
        replaceFieldResult = marker != null;
        if (marker != null) runs.add(StyledRun(text: marker));
        continue;
      }
      if (fieldType == 'end') {
        inField = false;
        inFieldResult = false;
        replaceFieldResult = false;
        instruction = '';
        continue;
      }
      if (inField && !inFieldResult) {
        for (final text in child.descendants.whereType<XmlElement>().where(
              (element) => element.name.local == 'instrText',
            )) {
          instruction += text.innerText;
        }
        continue;
      }
      if (inField && inFieldResult && replaceFieldResult) continue;
      runs.addAll(_readRuns(
        child,
        runDefaults,
        relationships,
        media: media,
        styles: styles,
        theme: theme,
        sourcePartPath: partPath,
      ));
    }
    return runs;
  }

  static String? _fieldMarker(String instruction) {
    final value = instruction.toUpperCase();
    if (value.contains('SECTIONPAGES')) return '{SECTIONPAGES}';
    if (value.contains('NUMPAGES')) return '{NUMPAGES}';
    if (value.contains('PAGE')) return '{PAGE}';
    if (value.contains('DATE')) return '{DATE}';
    return null;
  }

  static List<StyledRun> _readRuns(
    XmlElement element,
    Map<String, dynamic> inherited,
    Map<String, String> relationships, {
    String? link,
    Map<String, Uint8List> media = const {},
    Map<String, _StyleDefinition> styles = const {},
    _Theme? theme,
    String sourcePartPath = 'word/document.xml',
  }) {
    if (element.name.local == 'fldSimple') {
      final marker = _fieldMarker(_attribute(element, 'instr') ?? '');
      if (marker != null) return [StyledRun(text: marker, link: link)];
      return element.children
          .whereType<XmlElement>()
          .expand((child) => _readRuns(
                child,
                inherited,
                relationships,
                link: link,
                media: media,
                styles: styles,
                theme: theme,
                sourcePartPath: sourcePartPath,
              ))
          .toList();
    }
    if (element.name.local == 'hyperlink') {
      final target = relationships[_attribute(element, 'id')] ??
          (_attribute(element, 'anchor') == null
              ? null
              : '#${_attribute(element, 'anchor')}');
      return element.children
          .whereType<XmlElement>()
          .expand((child) => _readRuns(child, inherited, relationships,
              link: target,
              media: media,
              styles: styles,
              theme: theme,
              sourcePartPath: sourcePartPath))
          .toList();
    }
    if (element.name.local == 'r') {
      final properties = <String, dynamic>{
        ...inherited,
        ..._resolveStyleProperties(
          _attribute(_child(_child(element, 'rPr'), 'rStyle'), 'val'),
          styles,
          run: true,
        ),
        ..._readRunProperties(_child(element, 'rPr'), theme),
      };
      final text = _text(element, skipDrawings: true);
      final footnoteReference = _firstDescendant(element, 'footnoteReference');
      final drawing = _firstDescendant(element, 'drawing');
      final inlineImage = drawing == null
          ? null
          : _inlineImage(drawing, relationships, media, sourcePartPath);
      final inlineShapes = <StyledRun>[];
      if (drawing != null && _firstDescendant(drawing, 'inline') != null) {
        for (final shapeElement in drawing.descendants
            .whereType<XmlElement>()
            .where((item) => item.name.local == 'wsp')) {
          final shape = _readShape(
            drawing,
            shapeElement: shapeElement,
            theme: theme,
          );
          if (shape != null)
            inlineShapes.add(StyledRun(text: '', shape: shape));
        }
      }
      if (text.isEmpty &&
          footnoteReference == null &&
          inlineImage == null &&
          inlineShapes.isEmpty) return const [];
      final vertical = properties['vertical'];
      final runs = <StyledRun>[
        if (text.isNotEmpty || footnoteReference != null)
          StyledRun(
            text: footnoteReference == null
                ? text
                : (_attribute(footnoteReference, 'id') ?? text),
            bold: properties['bold'] as bool? ?? false,
            italic: properties['italic'] as bool? ?? false,
            underline: properties['underline'] as bool? ?? false,
            strike: properties['strike'] as bool? ?? false,
            color: properties['color'] as String?,
            background: properties['background'] as String?,
            fontFamily: properties['fontFamily'] as String?,
            fontSize: properties['fontSize'] as double?,
            superscript: vertical == 'superscript' || footnoteReference != null,
            subscript: vertical == 'subscript',
            link: link,
            footnoteId: footnoteReference == null
                ? null
                : _attribute(footnoteReference, 'id'),
          ),
      ];
      if (inlineImage != null) runs.add(inlineImage);
      runs.addAll(inlineShapes);
      return runs;
    }
    if (element.name.local == 'oMath' || element.name.local == 'oMathPara') {
      return [
        StyledRun(text: DocumentParser.formulaToText(element), link: link)
      ];
    }
    if (element.name.local == 't')
      return [StyledRun(text: element.innerText, link: link)];
    if (element.name.local == 'tab' || element.name.local == 'ptab') {
      return [StyledRun(text: '\t', link: link)];
    }
    if (element.name.local == 'br' || element.name.local == 'cr') {
      return [StyledRun(text: '\n', link: link)];
    }
    return element.children
        .whereType<XmlElement>()
        .where(
            (child) => child.name.local != 'rPr' && child.name.local != 'pPr')
        .expand((child) => _readRuns(child, inherited, relationships,
            link: link,
            media: media,
            styles: styles,
            theme: theme,
            sourcePartPath: sourcePartPath))
        .toList();
  }

  static StyledRun? _inlineImage(
    XmlElement drawing,
    Map<String, String> relationships,
    Map<String, Uint8List> media,
    String sourcePartPath,
  ) {
    if (_firstDescendant(drawing, 'inline') == null) return null;
    final blip = _firstDescendant(drawing, 'blip');
    final id = _attribute(blip, 'embed');
    final target = id == null ? null : relationships[id];
    if (target == null) return null;
    final mediaPath = target.startsWith('/')
        ? target.substring(1)
        : _normalizePartTarget(sourcePartPath, target);
    final bytes = media[mediaPath];
    if (bytes == null) return null;
    final extent = _firstDescendant(drawing, 'extent');
    final docProperties = _firstDescendant(drawing, 'docPr');
    final width = double.tryParse(_attribute(extent, 'cx') ?? '');
    final height = double.tryParse(_attribute(extent, 'cy') ?? '');
    return StyledRun(
      text: '',
      imageBytes: bytes,
      imageMime: _imageMime(mediaPath),
      // Inline DrawingML extents use EMUs; 12,700 EMUs equal one PDF point.
      imageWidth: width == null ? null : width / 12700,
      imageHeight: height == null ? null : height / 12700,
      imageAlt: _attribute(docProperties, 'descr') ??
          _attribute(docProperties, 'name') ??
          'Image',
      imageCrop: _imageCrop(drawing),
      imageRotation: _imageRotation(drawing),
      wrapMode: _wrapMode(null),
    );
  }

  static String _text(XmlElement run, {bool skipDrawings = false}) {
    final buffer = StringBuffer();
    void visit(XmlNode node) {
      if (node is! XmlElement) return;
      if (skipDrawings && const {'drawing', 'pict'}.contains(node.name.local)) {
        return;
      }
      switch (node.name.local) {
        case 'rPr':
        case 'pPr':
          return;
        case 't':
        case 'delText':
          buffer.write(node.innerText);
          return;
        case 'sym':
          buffer.write(DocumentParser.docxSymbolText(node));
          return;
        case 'instrText':
          final instruction = node.innerText.toUpperCase();
          if (instruction.contains('NUMPAGES')) {
            buffer.write('{NUMPAGES}');
          } else if (instruction.contains('PAGE')) {
            buffer.write('{PAGE}');
          }
          return;
        case 'fldSimple':
          final instruction = (_attribute(node, 'instr') ?? '').toUpperCase();
          if (instruction.contains('NUMPAGES')) {
            buffer.write('{NUMPAGES}');
          } else if (instruction.contains('PAGE')) {
            buffer.write('{PAGE}');
          } else {
            for (final child in node.children) {
              visit(child);
            }
          }
          return;
        case 'tab':
          buffer.write('\t');
          return;
        case 'br':
        case 'cr':
          buffer.write('\n');
          return;
        case 'noBreakHyphen':
          buffer.write('‑');
          return;
        case 'softHyphen':
          buffer.write('­');
          return;
        case 'oMath':
        case 'oMathPara':
          buffer.write(DocumentParser.formulaToText(node));
          return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final child in run.children) {
      visit(child);
    }
    return buffer.toString();
  }

  static StyledTable _readTable(
      XmlElement table,
      Map<String, _StyleDefinition> styles,
      Map<String, _NumberDefinition> numbering,
      Map<String, String> relationships,
      Map<String, Uint8List> media,
      Set<String> notes,
      {_Theme? theme,
      String partPath = 'word/document.xml'}) {
    final grid = _child(table, 'tblGrid');
    final widths = grid?.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'gridCol')
            .map((element) => _twips(_attribute(element, 'w')))
            .toList() ??
        <double>[];
    final properties = _child(table, 'tblPr');
    final styleId = _attribute(_child(properties, 'tblStyle'), 'val');
    final tableStyle = _resolveTableStyle(styleId, styles);
    if (tableStyle.hasConditionalTableFormatting) {
      notes.add(
        'Conditional table style <tblStylePr> formatting was partially applied.',
      );
    }
    final borders = {
      ...tableStyle.tableBorders,
      ..._readBorders(_child(properties, 'tblBorders'), theme),
    };
    final shading = _readShading(_child(properties, 'shd'), theme) ??
        tableStyle.tableShading;
    final tableMargins = _readCellMargins(_child(properties, 'tblCellMar'));
    final tableWidth = _child(properties, 'tblW');
    final tableWidthType = _attribute(tableWidth, 'type') ?? 'auto';
    final rawTableWidth = double.tryParse(_attribute(tableWidth, 'w') ?? '');
    final resolvedTableWidth = switch (tableWidthType) {
      'dxa' => rawTableWidth == null ? null : rawTableWidth / 20,
      'pct' => rawTableWidth == null ? null : rawTableWidth / 50,
      _ => null,
    };
    final tableLayout =
        _attribute(_child(properties, 'tblLayout'), 'type') ?? 'autofit';
    final rows = <StyledTableRow>[];
    for (final row in table.children.whereType<XmlElement>().where(
          (element) => element.name.local == 'tr',
        )) {
      final cells = <StyledTableCell>[];
      for (final cell in row.children.whereType<XmlElement>().where(
            (element) => element.name.local == 'tc',
          )) {
        final tcPr = _child(cell, 'tcPr');
        final span =
            int.tryParse(_attribute(_child(tcPr, 'gridSpan'), 'val') ?? '1') ??
                1;
        final mergeElement = _child(tcPr, 'vMerge');
        final merge = mergeElement == null
            ? null
            : (_attribute(mergeElement, 'val') ?? 'continue');
        final cellBlocks = <StyledBlock>[];
        for (final content in cell.children.whereType<XmlElement>()) {
          if (content.name.local == 'p') {
            cellBlocks.addAll(_readParagraphBlocks(
              content,
              styles,
              numbering,
              relationships,
              media,
              notes,
              theme: theme,
              partPath: partPath,
            ));
          } else if (content.name.local == 'tbl') {
            cellBlocks.add(_readTable(
              content,
              styles,
              numbering,
              relationships,
              media,
              notes,
              theme: theme,
              partPath: partPath,
            ));
          }
        }
        cells.add(StyledTableCell(
          blocks: cellBlocks,
          gridSpan: span < 1 ? 1 : span,
          vMerge: merge,
          borders: {
            ...tableStyle.cellBorders,
            ..._readBorders(_child(tcPr, 'tcBorders'), theme),
          },
          shading: _readShading(_child(tcPr, 'shd'), theme) ??
              tableStyle.cellShading,
          marginTop: _cellMargin(tcPr, tableMargins, 'top'),
          marginRight: _cellMargin(tcPr, tableMargins, 'right'),
          marginBottom: _cellMargin(tcPr, tableMargins, 'bottom'),
          marginLeft: _cellMargin(tcPr, tableMargins, 'left'),
          verticalAlignment: _attribute(_child(tcPr, 'vAlign'), 'val') ?? 'top',
        ));
      }
      final rowProperties = _child(row, 'trPr');
      final heightElement = _child(rowProperties, 'trHeight');
      final rawHeight = double.tryParse(_attribute(heightElement, 'val') ?? '');
      rows.add(
        StyledTableRow(
          cells,
          isHeader: _child(rowProperties, 'tblHeader') != null &&
              _on(_child(rowProperties, 'tblHeader')),
          // Row height is in twips; convert to PDF points.
          height: rawHeight == null ? null : rawHeight / 20,
          exactHeight: _attribute(heightElement, 'hRule') == 'exact',
          cantSplit: _child(rowProperties, 'cantSplit') != null &&
              _on(_child(rowProperties, 'cantSplit')),
        ),
      );
    }
    return StyledTable(
      rows: rows,
      columnWidths: widths,
      borders: borders,
      shading: shading,
      width: resolvedTableWidth,
      widthType: tableWidthType,
      layout: tableLayout,
    );
  }

  static Map<String, double> _readCellMargins(XmlElement? margins) {
    if (margins == null) return const {};
    final result = <String, double>{};
    for (final side in ['top', 'right', 'bottom', 'left', 'start', 'end']) {
      final value = _attribute(_child(margins, side), 'w');
      if (value != null) {
        // Table cell margins use twips unless their type is pct.
        final marginType = _attribute(_child(margins, side), 'type');
        result[side] = marginType == 'pct'
            ? (double.tryParse(value) ?? 0) / 50
            : _twips(value);
      }
    }
    return result;
  }

  static double? _cellMargin(
    XmlElement? cellProperties,
    Map<String, double> tableMargins,
    String side,
  ) {
    final margins = _child(cellProperties, 'tcMar');
    final aliases = side == 'left'
        ? ['left', 'start']
        : side == 'right'
            ? ['right', 'end']
            : [side];
    for (final alias in aliases) {
      final value = _attribute(_child(margins, alias), 'w');
      if (value != null) {
        final marginType = _attribute(_child(margins, alias), 'type');
        return marginType == 'pct'
            ? (double.tryParse(value) ?? 0) / 50
            : _twips(value);
      }
    }
    for (final alias in aliases) {
      if (tableMargins.containsKey(alias)) return tableMargins[alias];
    }
    return null;
  }

  static Map<String, String> _readBorders(
    XmlElement? element, [
    _Theme? theme,
  ]) {
    if (element == null) return const {};
    final result = <String, String>{};
    for (final border in element.children.whereType<XmlElement>()) {
      final side = border.name.local;
      final value = _attribute(border, 'val');
      if (value == null) continue;
      if (value == 'nil' || value == 'none') {
        result[side] = 'none';
        continue;
      }
      // OOXML border size is measured in eighths of a point.
      final size = (double.tryParse(_attribute(border, 'sz') ?? '') ?? 4) / 8;
      final color = _attribute(border, 'color') ??
          theme?.colors[_attribute(border, 'themeColor')];
      // OOXML border spacing is already expressed in points.
      final space = double.tryParse(_attribute(border, 'space') ?? '') ?? 0;
      result[side] =
          '${size.clamp(0.25, 6)}pt $value ${_safeColor(color)} ${space}pt';
    }
    return result;
  }

  static String? _readShading(XmlElement? element, _Theme? theme) {
    final fill = _attribute(element, 'fill');
    if (fill != null && fill.toLowerCase() != 'auto') return '#$fill';
    final themeFill = _attribute(element, 'themeFill');
    final themed = theme?.colors[themeFill];
    return themed == null ? null : '#$themed';
  }

  // Reads a:clrScheme and a:fontScheme from the package theme part.
  static _Theme _readTheme(ArchiveFile? entry, Set<String> notes) {
    if (entry == null) return const _Theme();
    try {
      final xml = XmlDocument.parse(_decode(entry));
      final themeElements = _child(xml.rootElement, 'themeElements');
      final colorScheme = _child(themeElements, 'clrScheme');
      final fontScheme = _child(themeElements, 'fontScheme');
      final colors = <String, String>{};
      for (final slot in colorScheme?.children.whereType<XmlElement>() ??
          const <XmlElement>[]) {
        XmlElement? color;
        for (final child in slot.children.whereType<XmlElement>()) {
          color = child;
          break;
        }
        final value = _attribute(color, 'val') ?? _attribute(color, 'lastClr');
        if (value != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
          colors[slot.name.local] = value;
          final alias = switch (slot.name.local) {
            'dk1' => 'dark1',
            'lt1' => 'light1',
            'dk2' => 'dark2',
            'lt2' => 'light2',
            _ => slot.name.local,
          };
          colors[alias] = value;
        }
      }
      final fonts = <String, String>{};
      for (final (partName, prefix) in [
        ('majorFont', 'major'),
        ('minorFont', 'minor'),
      ]) {
        final latin = _child(_child(fontScheme, partName), 'latin');
        final typeface = _attribute(latin, 'typeface');
        if (typeface == null || typeface.isEmpty) continue;
        for (final suffix in ['Ascii', 'HAnsi', 'EastAsia', 'Bidi']) {
          fonts['$prefix$suffix'] = typeface;
        }
      }
      return _Theme(colors: colors, fonts: fonts);
    } on Object catch (error) {
      notes.add('DOCX theme was unavailable ($error); using bundled defaults.');
      return const _Theme();
    }
  }

  static StyledShape? _readShape(
    XmlElement drawing, {
    XmlElement? shapeElement,
    _Theme? theme,
  }) {
    final wsp = shapeElement ?? _firstDescendant(drawing, 'wsp');
    if (wsp == null) return null;
    final geometry =
        _attribute(_firstDescendant(wsp, 'prstGeom'), 'prst') ?? 'rect';
    final extent =
        _firstDescendant(wsp, 'ext') ?? _firstDescendant(drawing, 'extent');
    final cx = double.tryParse(_attribute(extent, 'cx') ?? '') ?? 0;
    final cy = double.tryParse(_attribute(extent, 'cy') ?? '') ?? 0;
    String? colorFor(String name) {
      final element = _firstDescendant(wsp, name);
      final color = _firstDescendant(element ?? wsp, 'srgbClr');
      if (color != null) return _safeColor(_attribute(color, 'val'));
      final themedColor = _firstDescendant(element ?? wsp, 'schemeClr');
      return theme?.colors[_attribute(themedColor, 'val')];
    }

    final line = _firstDescendant(wsp, 'ln');
    final lineWidth = double.tryParse(_attribute(line, 'w') ?? '') ?? 12700;
    final text = wsp.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 't')
        .map((element) => element.innerText)
        .join();
    return StyledShape(
      geometry: geometry,
      // DrawingML uses EMUs; 12,700 EMUs equal one PDF point.
      width: cx > 0 ? cx / 12700 : 100,
      height: cy > 0 ? cy / 12700 : 40,
      fill: colorFor('solidFill'),
      outline: colorFor('ln'),
      // DrawingML line width is stored in EMUs.
      outlineWidth: (lineWidth / 12700).clamp(0.25, 12),
      text: text,
    );
  }

  static Map<String, double> _imageCrop(XmlElement drawing) {
    final crop = _firstDescendant(drawing, 'srcRect');
    if (crop == null) return const {};
    return {
      for (final side in ['l', 't', 'r', 'b'])
        if (_attribute(crop, side) != null)
          side: (double.tryParse(_attribute(crop, side)!) ?? 0) / 100000,
    };
  }

  static double _imageRotation(XmlElement drawing) {
    final transform = _firstDescendant(drawing, 'xfrm');
    final rotation = double.tryParse(_attribute(transform, 'rot') ?? '0') ?? 0;
    // DrawingML rotation units are 60,000ths of a degree.
    return rotation / 60000;
  }

  static String _wrapMode(XmlElement? anchor) {
    if (anchor == null) return 'inline';
    for (final child in anchor.children.whereType<XmlElement>()) {
      if (child.name.local.startsWith('wrap')) return child.name.local;
    }
    return _attribute(anchor, 'behindDoc') == '1' ? 'behindDoc' : 'wrapNone';
  }

  static StyledShape? _readVmlShape(XmlElement shape) {
    final style = _attribute(shape, 'style') ?? '';
    final localName = shape.name.local;
    final geometry = switch (localName) {
      'roundrect' => 'roundRect',
      'oval' => 'ellipse',
      'line' => 'line',
      _ => 'rect',
    };
    final text = _fallbackText(shape);
    return StyledShape(
      geometry: geometry,
      width: _cssLengthPt(style, 'width') ?? 100,
      height: _cssLengthPt(style, 'height') ?? 40,
      fill: _vmlColor(_attribute(shape, 'fillcolor')),
      outline: _vmlColor(_attribute(shape, 'strokecolor')),
      text: text,
    );
  }

  static double? _cssLengthPt(String style, String property) {
    final match = RegExp('(?:^|;)\\s*$property\\s*:\\s*([\\d.]+)(pt|px|in|cm)?',
            caseSensitive: false)
        .firstMatch(style);
    if (match == null) return null;
    final amount = double.tryParse(match.group(1) ?? '');
    if (amount == null) return null;
    // Convert VML CSS lengths to PDF points; CSS px are 96 per inch.
    return switch ((match.group(2) ?? 'pt').toLowerCase()) {
      'in' => amount * 72,
      'cm' => amount * 72 / 2.54,
      'px' => amount * 72 / 96,
      _ => amount,
    };
  }

  static String? _vmlColor(String? value) {
    if (value == null || value.toLowerCase() == 'auto') return null;
    final normalized = value.replaceAll('#', '');
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)
        ? '#$normalized'
        : null;
  }

  static Map<String, double> _readPageSetup(XmlElement section) {
    final size = _child(section, 'pgSz');
    final margins = _child(section, 'pgMar');
    var width = _twips(_attribute(size, 'w'));
    var height = _twips(_attribute(size, 'h'));
    if (_attribute(size, 'orient') == 'landscape' && height > width) {
      final oldWidth = width;
      width = height;
      height = oldWidth;
    }
    return {
      if (width > 0) 'width': width,
      if (height > 0) 'height': height,
      if (_attribute(margins, 'top') != null)
        'top': _twips(_attribute(margins, 'top')),
      if (_attribute(margins, 'right') != null)
        'right': _twips(_attribute(margins, 'right')),
      if (_attribute(margins, 'bottom') != null)
        'bottom': _twips(_attribute(margins, 'bottom')),
      if (_attribute(margins, 'left') != null)
        'left': _twips(_attribute(margins, 'left')),
      if (_attribute(margins, 'header') != null)
        'header': _twips(_attribute(margins, 'header')),
      if (_attribute(margins, 'footer') != null)
        'footer': _twips(_attribute(margins, 'footer')),
    };
  }

  static Map<String, dynamic> _resolveStyleProperties(
    String? styleId,
    Map<String, _StyleDefinition> styles, {
    required bool run,
  }) {
    final chain = <_StyleDefinition>[];
    final seen = <String>{};
    var current = styleId;
    while (current != null && seen.add(current)) {
      final style = styles[current];
      if (style == null) break;
      chain.insert(0, style);
      current = style.basedOn;
    }
    final result = <String, dynamic>{
      if (run) ...?styles['__defaults__']?.run,
      if (!run) ...?styles['__defaults__']?.paragraph,
    };
    for (final style in chain) {
      result.addAll(run ? style.run : style.paragraph);
    }
    return result;
  }

  static _StyleDefinition _resolveTableStyle(
    String? styleId,
    Map<String, _StyleDefinition> styles,
  ) {
    final chain = <_StyleDefinition>[];
    final seen = <String>{};
    var current = styleId;
    while (current != null && seen.add(current)) {
      final style = styles[current];
      if (style == null) break;
      chain.insert(0, style);
      current = style.basedOn;
    }
    final tableBorders = <String, String>{};
    final cellBorders = <String, String>{};
    String? tableShading;
    String? cellShading;
    var hasConditionalTableFormatting = false;
    for (final style in chain) {
      tableBorders.addAll(style.tableBorders);
      cellBorders.addAll(style.cellBorders);
      tableShading = style.tableShading ?? tableShading;
      cellShading = style.cellShading ?? cellShading;
      hasConditionalTableFormatting =
          hasConditionalTableFormatting || style.hasConditionalTableFormatting;
    }
    return _StyleDefinition(
      id: styleId ?? '',
      tableBorders: tableBorders,
      cellBorders: cellBorders,
      tableShading: tableShading,
      cellShading: cellShading,
      hasConditionalTableFormatting: hasConditionalTableFormatting,
    );
  }

  static _StyleDefinition? _resolveStyle(
    String? id,
    Map<String, _StyleDefinition> styles,
  ) =>
      id == null ? null : styles[id];

  static XmlElement? _child(XmlElement? parent, String localName) {
    if (parent == null) return null;
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static XmlElement? _firstDescendant(XmlElement parent, String localName) {
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static bool _hasSkippedContent(
    XmlElement document,
    Map<String, ArchiveFile> files,
  ) {
    const unsupportedElements = {
      'pict',
      'ins',
      'del',
      'moveFrom',
      'moveTo',
      'relIds',
    };
    if (document.descendants
        .whereType<XmlElement>()
        .any((element) => unsupportedElements.contains(element.name.local))) {
      return true;
    }
    return files.keys.any((name) => name.startsWith('word/diagrams/'));
  }

  static String? _attribute(XmlElement? element, String localName) {
    if (element == null) return null;
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static bool _on(XmlElement? element) {
    final value = _attribute(element, 'val')?.toLowerCase();
    return value != '0' && value != 'false' && value != 'off' && value != 'no';
  }

  // Word dimensions such as margins and table widths are twentieths of a point.
  static double _twips(String? value) =>
      (double.tryParse(value ?? '') ?? 0) / 20;

  static double _borderSpace(XmlElement? borders) {
    final spaces = borders?.children.whereType<XmlElement>().map(
              (border) =>
                  double.tryParse(_attribute(border, 'space') ?? '') ?? 0,
            ) ??
        const <double>[];
    return spaces.fold<double>(0, (max, value) => value > max ? value : max);
  }

  static Map<String, List<StyledBlock>> _readRelatedParts(
      Map<String, ArchiveFile> files,
      Map<String, Uint8List> media,
      String kind,
      Map<String, _StyleDefinition> styles,
      Map<String, _NumberDefinition> numbering,
      Set<String> notes,
      {_Theme? theme}) {
    final stories = <String, List<StyledBlock>>{};
    for (final partPath in _relatedPartPaths(files, kind)) {
      final candidate = files[partPath];
      if (candidate == null) {
        notes.add(
            'DOCX relationship <$kind> points to missing part <$partPath>.');
        continue;
      }
      try {
        final xml = XmlDocument.parse(_decode(candidate));
        final partDirectory = path.posix.dirname(partPath);
        final partName = path.posix.basename(partPath);
        final relPath = path.posix.join(
          partDirectory,
          '_rels',
          '$partName.rels',
        );
        final relationships = _readRelationshipPart(files[relPath], notes);
        final blocks = <StyledBlock>[];
        for (final element
            in xml.rootElement.children.whereType<XmlElement>()) {
          if (element.name.local == 'p') {
            blocks.addAll(_readParagraphBlocks(
              element,
              styles,
              numbering,
              relationships,
              media,
              notes,
              theme: theme,
              partPath: partPath,
            ));
          } else if (element.name.local == 'tbl') {
            blocks.add(_readTable(
              element,
              styles,
              numbering,
              relationships,
              media,
              notes,
              theme: theme,
              partPath: partPath,
            ));
          } else if (element.name.local != 'sectPr') {
            final text = _fallbackText(element);
            if (text.isNotEmpty) {
              blocks.add(StyledParagraph(runs: [StyledRun(text: text)]));
            }
            notes.add(
              'Unsupported ${kind} element <${element.name.local}>; kept its text where available.',
            );
          }
        }
        stories[partPath] = blocks;
      } on Object catch (error) {
        notes.add('DOCX ${kind} part <$partPath> was skipped ($error).');
      }
    }
    return stories;
  }

  static Set<String> _relatedPartPaths(
    Map<String, ArchiveFile> files,
    String relationshipKind,
  ) {
    final parts = <String>{
      for (final name in files.keys)
        if (RegExp('^word/${relationshipKind}[^/]*\\.xml\$').hasMatch(name))
          name,
    };
    final relationships = files['word/_rels/document.xml.rels'];
    if (relationships == null) return parts;
    try {
      final xml = XmlDocument.parse(_decode(relationships));
      for (final relationship in xml.descendants.whereType<XmlElement>()) {
        if (relationship.name.local != 'Relationship') continue;
        if (!(_attribute(relationship, 'Type') ?? '')
            .endsWith('/$relationshipKind')) {
          continue;
        }
        if ((_attribute(relationship, 'TargetMode') ?? '') == 'External') {
          continue;
        }
        final target = _attribute(relationship, 'Target');
        if (target != null) {
          parts.add(_normalizePartTarget('word/document.xml', target));
        }
      }
    } on Object {
      // Conventional part names remain usable if relationships are malformed.
    }
    return parts;
  }

  static List<StyledBlock> _firstStory(
    Map<String, List<StyledBlock>> stories,
  ) {
    for (final entry in stories.entries) {
      if (path.posix.basename(entry.key).contains('1')) return entry.value;
    }
    return stories.values.isEmpty ? const [] : stories.values.first;
  }

  static List<StyledFootnote> _readFootnotes(
      ArchiveFile? entry,
      Map<String, _StyleDefinition> styles,
      Map<String, _NumberDefinition> numbering,
      Set<String> notes,
      {_Theme? theme}) {
    if (entry == null) return const [];
    try {
      final xml = XmlDocument.parse(_decode(entry));
      final result = <StyledFootnote>[];
      for (final footnote in xml.rootElement.children.whereType<XmlElement>()) {
        if (footnote.name.local != 'footnote' ||
            (_attribute(footnote, 'type') ?? '') == 'separator') {
          continue;
        }
        final id = _attribute(footnote, 'id') ?? '';
        final blocks = <StyledBlock>[];
        var firstParagraph = true;
        for (final paragraph in footnote.children.whereType<XmlElement>()) {
          if (paragraph.name.local != 'p') continue;
          final runs = paragraph.children
              .whereType<XmlElement>()
              .expand((run) => _readRuns(
                    run,
                    const {},
                    const {},
                    styles: styles,
                    theme: theme,
                  ))
              .toList();
          if (firstParagraph && id.isNotEmpty) {
            runs.insert(0, StyledRun(text: id, superscript: true));
          }
          firstParagraph = false;
          blocks.add(StyledParagraph(runs: runs, alignment: 'left'));
        }
        result.add(StyledFootnote(id: id, blocks: blocks));
      }
      return result;
    } on Object {
      notes.add('Some DOCX footnotes were simplified.');
      return const [];
    }
  }

  static Map<String, String> _readRelationshipPart(
    ArchiveFile? entry,
    Set<String> notes,
  ) {
    if (entry == null) return const {};
    try {
      final xml = XmlDocument.parse(_decode(entry));
      return {
        for (final element in xml.descendants.whereType<XmlElement>())
          if (element.name.local == 'Relationship' &&
              _attribute(element, 'Id') != null &&
              _attribute(element, 'Target') != null)
            _attribute(element, 'Id')!: _attribute(element, 'Target')!,
      };
    } on Object {
      notes.add('Some DOCX relationships were simplified.');
      return const {};
    }
  }

  static SectionBreak _readSectionBreak(
    XmlElement section,
    Map<String, String> relationships, {
    bool finalSection = false,
  }) {
    final setup = _readPageSetup(section);
    final cols = _child(section, 'cols');
    final declaredColumns = int.tryParse(_attribute(cols, 'num') ?? '');
    final explicitColumns = cols?.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'col')
            .length ??
        0;
    final headerReferences = <String, String>{};
    final footerReferences = <String, String>{};
    for (final reference in section.children.whereType<XmlElement>()) {
      final isHeader = reference.name.local == 'headerReference';
      if (!isHeader && reference.name.local != 'footerReference') continue;
      final relationshipId = _attribute(reference, 'id');
      final target =
          relationshipId == null ? null : relationships[relationshipId];
      if (target == null) continue;
      final kind = _attribute(reference, 'type') ?? 'default';
      (isHeader ? headerReferences : footerReferences)[kind] =
          _normalizePartTarget('word/document.xml', target);
    }
    return SectionBreak(
      pageWidth: setup['width'],
      pageHeight: setup['height'],
      marginTop: setup['top'],
      marginRight: setup['right'],
      marginBottom: setup['bottom'],
      marginLeft: setup['left'],
      headerDistance: setup['header'],
      footerDistance: setup['footer'],
      columns: declaredColumns ?? (explicitColumns > 0 ? explicitColumns : 1),
      type: _attribute(_child(section, 'type'), 'val') ?? 'nextPage',
      finalSection: finalSection,
      headerReferences: headerReferences,
      footerReferences: footerReferences,
      titlePage: _child(section, 'titlePg') != null,
    );
  }

  static String _normalizePartTarget(String basePart, String target) {
    if (target.startsWith('/'))
      return path.posix.normalize(target.substring(1));
    return path.posix
        .normalize(path.posix.join(path.posix.dirname(basePart), target));
  }

  static bool _readEvenAndOddHeaders(ArchiveFile? entry) {
    if (entry == null) return false;
    try {
      final xml = XmlDocument.parse(_decode(entry));
      final setting = xml.descendants.whereType<XmlElement>().where(
            (element) => element.name.local == 'evenAndOddHeaders',
          );
      for (final element in setting) {
        return _on(element);
      }
    } on Object {
      return false;
    }
    return false;
  }

  static String _safeColor(String? color) {
    if (color == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(color)) {
      return '#000000';
    }
    return '#$color';
  }

  static String _imageMime(String mediaPath) =>
      switch (path.posix.extension(mediaPath).toLowerCase()) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.bmp' => 'image/bmp',
        '.tif' || '.tiff' => 'image/tiff',
        '.emf' => 'image/emf',
        '.wmf' => 'image/wmf',
        '.svg' => 'image/svg+xml',
        _ => 'application/octet-stream',
      };
}

class _Theme {
  final Map<String, String> colors;
  final Map<String, String> fonts;

  const _Theme({this.colors = const {}, this.fonts = const {}});
}

class _StyleDefinition {
  final String id;
  final String? basedOn;
  final String? name;
  final Map<String, dynamic> run;
  final Map<String, dynamic> paragraph;
  final Map<String, String> tableBorders;
  final String? tableShading;
  final Map<String, String> cellBorders;
  final String? cellShading;
  final bool hasConditionalTableFormatting;

  const _StyleDefinition({
    required this.id,
    this.basedOn,
    this.name,
    this.run = const {},
    this.paragraph = const {},
    this.tableBorders = const {},
    this.tableShading,
    this.cellBorders = const {},
    this.cellShading,
    this.hasConditionalTableFormatting = false,
  });
}

class _NumberDefinition {
  final Map<int, _NumberLevel> levels;
  const _NumberDefinition(this.levels);
}

class _NumberLevel {
  final String format;
  final String marker;
  final String? markerFontFamily;
  final double leftIndent;
  final double hangingIndent;
  final int start;
  const _NumberLevel(
    this.format,
    this.marker, {
    this.markerFontFamily,
    this.leftIndent = 0,
    this.hangingIndent = 0,
    this.start = 1,
  });
}
