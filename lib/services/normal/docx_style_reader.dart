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
    final archive = ZipDecoder().decodeBytes(await File(sourcePath).readAsBytes());
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
    final styles = _readStyles(files['word/styles.xml'], notes);
    final numbering = _readNumbering(files['word/numbering.xml'], notes);
    if (_hasSkippedContent(xml.rootElement, files)) {
      notes.add('Some items were simplified.');
    }
    for (final entry in files.entries) {
      if (!entry.key.startsWith('word/media/')) continue;
      media[entry.key] = Uint8List.fromList(List<int>.from(entry.value.content as List));
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
          ));
        } else if (child.name.local == 'tbl') {
          blocks.add(_readTable(
            child,
            styles,
            numbering,
            relationships,
            media,
            notes,
          ));
        } else if (child.name.local == 'sectPr') {
          final setup = _readPageSetup(child);
          pageWidth = setup['width'] ?? pageWidth;
          pageHeight = setup['height'] ?? pageHeight;
          marginTop = setup['top'] ?? marginTop;
          marginRight = setup['right'] ?? marginRight;
          marginBottom = setup['bottom'] ?? marginBottom;
          marginLeft = setup['left'] ?? marginLeft;
        } else {
          notes.add('Some advanced DOCX layout features were simplified.');
        }
      } on Object {
        notes.add('Some DOCX content was simplified.');
      }
    }

    return StyledDocument(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      marginTop: marginTop,
      marginRight: marginRight,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      blocks: blocks,
      notes: notes.toList(),
    );
  }

  static String _decode(ArchiveFile file) =>
      utf8.decode(List<int>.from(file.content as List), allowMalformed: true);

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

  static Map<String, _StyleDefinition> _readStyles(
    ArchiveFile? entry,
    Set<String> notes,
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
        run: _readRunProperties(runDefaults),
        paragraph: _readParagraphProperties(paraDefaults),
      );
      for (final style in xml.descendants.whereType<XmlElement>()) {
        if (style.name.local != 'style') continue;
        final id = _attribute(style, 'styleId');
        if (id == null) continue;
        result[id] = _StyleDefinition(
          id: id,
          basedOn: _attribute(_child(style, 'basedOn'), 'val'),
          name: _attribute(_child(style, 'name'), 'val'),
          run: _readRunProperties(_child(style, 'rPr')),
          paragraph: _readParagraphProperties(_child(style, 'pPr')),
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
          levels[index] = _NumberLevel(format, marker);
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

  static Map<String, dynamic> _readRunProperties(XmlElement? properties) {
    if (properties == null) return {};
    final fonts = _child(properties, 'rFonts');
    final color = _attribute(_child(properties, 'color'), 'val');
    final size = double.tryParse(_attribute(_child(properties, 'sz'), 'val') ?? '');
    final vertical = _attribute(_child(properties, 'vertAlign'), 'val');
    return {
      if (_child(properties, 'b') != null) 'bold': _on(_child(properties, 'b')),
      if (_child(properties, 'i') != null) 'italic': _on(_child(properties, 'i')),
      if (_child(properties, 'u') != null)
        'underline': (_attribute(_child(properties, 'u'), 'val') ?? 'single') != 'none',
      if (_child(properties, 'strike') != null)
        'strike': _on(_child(properties, 'strike')),
      if (color != null && color.toLowerCase() != 'auto') 'color': color,
      if (fonts != null)
        'fontFamily': _attribute(fonts, 'ascii') ??
            _attribute(fonts, 'hAnsi') ??
            _attribute(fonts, 'eastAsia'),
      if (size != null) 'fontSize': size / 2,
      if (vertical != null) 'vertical': vertical,
    };
  }

  static Map<String, dynamic> _readParagraphProperties(XmlElement? properties) {
    if (properties == null) return {};
    final spacing = _child(properties, 'spacing');
    final ind = _child(properties, 'ind');
    final outline = int.tryParse(_attribute(_child(properties, 'outlineLvl'), 'val') ?? '');
    final number = _child(properties, 'numPr');
    final numId = _attribute(_child(number, 'numId'), 'val');
    final level = int.tryParse(_attribute(_child(number, 'ilvl'), 'val') ?? '0') ?? 0;
    final alignment = _attribute(_child(properties, 'jc'), 'val');
    final before = _twips(_attribute(spacing, 'before'));
    final after = _twips(_attribute(spacing, 'after'));
    final line = double.tryParse(_attribute(spacing, 'line') ?? '');
    final left = _twips(_attribute(ind, 'left') ?? _attribute(ind, 'start'));
    final right = _twips(_attribute(ind, 'right') ?? _attribute(ind, 'end'));
    final firstLine = _twips(_attribute(ind, 'firstLine')) -
        _twips(_attribute(ind, 'hanging'));
    return {
      if (alignment != null) 'alignment': alignment,
      if (before != 0) 'spacingBefore': before,
      if (after != 0) 'spacingAfter': after,
      if (line != null && line > 0) 'lineSpacing': line / 240,
      if (left != 0) 'indentLeft': left,
      if (right != 0) 'indentRight': right,
      if (firstLine != 0) 'firstLineIndent': firstLine,
      if (outline != null && outline < 9) 'headingLevel': outline + 1,
      if (numId != null) 'numId': numId,
      if (numId != null) 'listLevel': level,
    };
  }

  static List<StyledBlock> _readParagraphBlocks(
    XmlElement paragraph,
    Map<String, _StyleDefinition> styles,
    Map<String, _NumberDefinition> numbering,
    Map<String, String> relationships,
    Map<String, Uint8List> media,
    Set<String> notes,
  ) {
    final pPr = _child(paragraph, 'pPr');
    final styleId = _attribute(_child(pPr, 'pStyle'), 'val');
    final style = _resolveStyle(styleId, styles);
    final paragraphProperties = <String, dynamic>{
      ..._resolveStyleProperties(styleId, styles, run: false),
      ..._readParagraphProperties(pPr),
    };
    final runDefaults = <String, dynamic>{
      ...(_resolveStyleProperties(styleId, styles, run: true)),
      ..._readRunProperties(_child(pPr, 'rPr')),
    };
    var headingLevel = paragraphProperties['headingLevel'] as int?;
    final styleName = (style?.name ?? styleId ?? '').toLowerCase();
    final headingMatch = RegExp(r'heading\s*(\d+)').firstMatch(styleName);
    headingLevel ??= headingMatch == null ? null : int.tryParse(headingMatch.group(1)!);

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
      );
    }

    final runs = <StyledRun>[];
    for (final child in paragraph.children.whereType<XmlElement>()) {
      if (child.name.local == 'pPr') continue;
      runs.addAll(_readRuns(child, runDefaults, relationships));
    }
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
      indentLeft: (paragraphProperties['indentLeft'] as double?) ?? 0,
      indentRight: (paragraphProperties['indentRight'] as double?) ?? 0,
      firstLineIndent: (paragraphProperties['firstLineIndent'] as double?) ?? 0,
      headingLevel: headingLevel,
      listInfo: listInfo,
    );

    final result = <StyledBlock>[];
    if (_child(pPr, 'pageBreakBefore') != null) result.add(const PageBreak());
    result.add(paragraphBlock);
    for (final drawing in paragraph.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'drawing',
        )) {
      final blip = _firstDescendant(drawing, 'blip');
      if (blip == null) continue;
      final relationshipId = _attribute(blip, 'embed');
      final target = relationshipId == null ? null : relationships[relationshipId];
      if (target == null) {
        notes.add('Some DOCX images were simplified.');
        continue;
      }
      final mediaPath = target.startsWith('/')
          ? target.substring(1)
          : path.normalize(path.join('word', target));
      final bytes = media[mediaPath];
      if (bytes == null) {
        notes.add('Some DOCX images were simplified.');
        continue;
      }
      final extension = path.extension(mediaPath).toLowerCase();
      final mime = switch (extension) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        _ => 'application/octet-stream',
      };
      final extent = _firstDescendant(drawing, 'extent');
      final width = double.tryParse(_attribute(extent, 'cx') ?? '');
      final height = double.tryParse(_attribute(extent, 'cy') ?? '');
      result.add(StyledImage(
        bytes: bytes,
        mime: mime,
        width: width == null ? null : width / 12700,
        height: height == null ? null : height / 12700,
      ));
    }
    if (paragraph.descendants.whereType<XmlElement>().any(
      (element) =>
          element.name.local == 'br' && _attribute(element, 'type') == 'page',
    )) {
      result.add(const PageBreak());
    }
    return result;
  }

  static List<StyledRun> _readRuns(
    XmlElement element,
    Map<String, dynamic> inherited,
    Map<String, String> relationships, {
    String? link,
  }
  ) {
    if (const {
      'txbxContent',
      'pict',
      'sp',
      'wsp',
      'ins',
      'del',
      'moveFrom',
      'moveTo',
    }.contains(element.name.local)) {
      return const [];
    }
    if (element.name.local == 'hyperlink') {
      final target = relationships[_attribute(element, 'id')] ??
          (_attribute(element, 'anchor') == null
              ? null
              : '#${_attribute(element, 'anchor')}');
      return element.children
          .whereType<XmlElement>()
          .expand((child) => _readRuns(child, inherited, relationships, link: target))
          .toList();
    }
    if (element.name.local == 'r') {
      final properties = <String, dynamic>{
        ...inherited,
        ..._readRunProperties(_child(element, 'rPr')),
      };
      final text = _text(element);
      if (text.isEmpty) return const [];
      final vertical = properties['vertical'];
      return [
        StyledRun(
          text: text,
          bold: properties['bold'] as bool? ?? false,
          italic: properties['italic'] as bool? ?? false,
          underline: properties['underline'] as bool? ?? false,
          strike: properties['strike'] as bool? ?? false,
          color: properties['color'] as String?,
          fontFamily: properties['fontFamily'] as String?,
          fontSize: properties['fontSize'] as double?,
          superscript: vertical == 'superscript',
          subscript: vertical == 'subscript',
          link: link,
        ),
      ];
    }
    if (element.name.local == 'oMath' || element.name.local == 'oMathPara') {
      return [StyledRun(text: DocumentParser.formulaToText(element), link: link)];
    }
    if (element.name.local == 't') return [StyledRun(text: element.innerText, link: link)];
    if (element.name.local == 'tab') return [StyledRun(text: '\t', link: link)];
    if (element.name.local == 'br' || element.name.local == 'cr') {
      return [StyledRun(text: '\n', link: link)];
    }
    return element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local != 'rPr' && child.name.local != 'pPr')
        .expand((child) => _readRuns(child, inherited, relationships, link: link))
        .toList();
  }

  static String _text(XmlElement run) {
    final buffer = StringBuffer();
    void visit(XmlNode node) {
      if (node is! XmlElement) return;
      switch (node.name.local) {
        case 'rPr':
        case 'pPr':
          return;
        case 't':
        case 'delText':
          buffer.write(node.innerText);
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
  ) {
    final grid = _child(table, 'tblGrid');
    final widths = grid?.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'gridCol')
            .map((element) => _twips(_attribute(element, 'w')))
            .toList() ??
        <double>[];
    final properties = _child(table, 'tblPr');
    final borders = _readBorders(_child(properties, 'tblBorders'));
    final shading = _attribute(_child(properties, 'shd'), 'fill');
    final rows = <StyledTableRow>[];
    for (final row in table.children.whereType<XmlElement>().where(
          (element) => element.name.local == 'tr',
        )) {
      final cells = <StyledTableCell>[];
      for (final cell in row.children.whereType<XmlElement>().where(
            (element) => element.name.local == 'tc',
          )) {
        final tcPr = _child(cell, 'tcPr');
        final span = int.tryParse(_attribute(_child(tcPr, 'gridSpan'), 'val') ?? '1') ?? 1;
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
            ));
          } else if (content.name.local == 'tbl') {
            cellBlocks.add(_readTable(
              content,
              styles,
              numbering,
              relationships,
              media,
              notes,
            ));
          }
        }
        cells.add(StyledTableCell(
          blocks: cellBlocks,
          gridSpan: span < 1 ? 1 : span,
          vMerge: merge,
          borders: _readBorders(_child(tcPr, 'tcBorders')),
          shading: _attribute(_child(tcPr, 'shd'), 'fill'),
        ));
      }
      rows.add(
        StyledTableRow(
          cells,
          isHeader: _child(_child(row, 'trPr'), 'tblHeader') != null,
        ),
      );
    }
    return StyledTable(
      rows: rows,
      columnWidths: widths,
      borders: borders,
      shading: shading,
    );
  }

  static Map<String, String> _readBorders(XmlElement? element) {
    if (element == null) return const {};
    final result = <String, String>{};
    for (final border in element.children.whereType<XmlElement>()) {
      final side = border.name.local;
      final value = _attribute(border, 'val');
      if (value == null || value == 'nil' || value == 'none') continue;
      final size = (double.tryParse(_attribute(border, 'sz') ?? '') ?? 4) / 8;
      final color = _attribute(border, 'color');
      result[side] = '${size.clamp(0.25, 6)}pt ${value == 'dashed' ? 'dashed' : 'solid'} ${_safeColor(color)}';
    }
    return result;
  }

  static Map<String, double> _readPageSetup(XmlElement section) {
    final size = _child(section, 'pgSz');
    final margins = _child(section, 'pgMar');
    return {
      if (_twips(_attribute(size, 'w')) > 0) 'width': _twips(_attribute(size, 'w')),
      if (_twips(_attribute(size, 'h')) > 0) 'height': _twips(_attribute(size, 'h')),
      if (_attribute(margins, 'top') != null) 'top': _twips(_attribute(margins, 'top')),
      if (_attribute(margins, 'right') != null) 'right': _twips(_attribute(margins, 'right')),
      if (_attribute(margins, 'bottom') != null) 'bottom': _twips(_attribute(margins, 'bottom')),
      if (_attribute(margins, 'left') != null) 'left': _twips(_attribute(margins, 'left')),
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
      'txbxContent',
      'pict',
      'sp',
      'wsp',
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
    return files.keys.any((name) =>
        RegExp(r'^word/(header|footer)\d+\.xml$').hasMatch(name) ||
        name.startsWith('word/diagrams/'));
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

  static double _twips(String? value) =>
      (double.tryParse(value ?? '') ?? 0) / 20;

  static String _safeColor(String? color) {
    if (color == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(color)) {
      return '#000000';
    }
    return '#$color';
  }
}

class _StyleDefinition {
  final String id;
  final String? basedOn;
  final String? name;
  final Map<String, dynamic> run;
  final Map<String, dynamic> paragraph;

  const _StyleDefinition({
    required this.id,
    this.basedOn,
    this.name,
    this.run = const {},
    this.paragraph = const {},
  });
}

class _NumberDefinition {
  final Map<int, _NumberLevel> levels;
  const _NumberDefinition(this.levels);
}

class _NumberLevel {
  final String format;
  final String marker;
  const _NumberLevel(this.format, this.marker);
}
