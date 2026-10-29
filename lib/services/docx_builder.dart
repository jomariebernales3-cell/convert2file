import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/generation_options.dart';

class DocxBuilder {
  static Future<String> generate(
    Map<String, dynamic> templateModel,
    Map<String, dynamic> mapping,
    GenerationOptions options,
    String baseName,
  ) async {
    final media = await _collectMedia(mapping);
    final documentXml =
        _buildDocumentXml(templateModel, mapping, options, media);
    final archive = Archive();

    archive.addFile(ArchiveFile('[Content_Types].xml',
        _contentTypesXml(media).length, _contentTypesXml(media).codeUnits));
    archive.addFile(ArchiveFile('_rels/.rels', _rootRelationshipsXml().length,
        _rootRelationshipsXml().codeUnits));
    archive.addFile(ArchiveFile(
        'word/document.xml', documentXml.length, documentXml.codeUnits));
    archive.addFile(ArchiveFile(
        'word/_rels/document.xml.rels',
        _documentRelationshipsXml(media).length,
        _documentRelationshipsXml(media).codeUnits));
    archive.addFile(ArchiveFile(
        'word/styles.xml', _stylesXml().length, _stylesXml().codeUnits));
    archive.addFile(ArchiveFile('word/numbering.xml', _numberingXml().length,
        _numberingXml().codeUnits));
    archive.addFile(ArchiveFile(
        'word/settings.xml', _settingsXml().length, _settingsXml().codeUnits));
    archive.addFile(ArchiveFile('word/fontTable.xml', _fontTableXml().length,
        _fontTableXml().codeUnits));

    for (final item in media) {
      archive.addFile(ArchiveFile(
        'word/media/${item.fileName}',
        item.bytes.length,
        item.bytes,
      ));
    }

    final encoded = ZipEncoder().encode(archive);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$baseName.docx');
    await file.writeAsBytes(encoded);
    return file.path;
  }

  static String _buildDocumentXml(
    Map<String, dynamic> templateModel,
    Map<String, dynamic> mapping,
    GenerationOptions options,
    List<_DocxMedia> media,
  ) {
    final mediaByPath = {for (final item in media) item.sourcePath: item};
    final isModern = options.styleProfile == 'modern';
    final documentFont = isModern ? 'Aptos' : 'Times New Roman';
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.write('<w:document '
        'xmlns:ve="http://schemas.openxmlformats.org/markup-compatibility/2006" '
        'xmlns:o="urn:schemas-microsoft-com:office:office" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
        'xmlns:v="urn:schemas-microsoft-com:vml" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:w10="urn:schemas-microsoft-com:office:word" '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml">');
    buffer.write('<w:body>');

    buffer.write(_paragraphXml(
      mapping['{{TITLE}}'] as String? ?? 'Generated Document',
      isBold: true,
      fontFamily: documentFont,
      fontSize: isModern ? 44 : 40,
      spacingAfter: isModern ? 300 : 280,
    ));

    final sections = _extractSections(mapping);
    for (final section in sections) {
      final heading = section['heading'] as String? ?? '';
      if (heading.trim().isNotEmpty || options.workspaceMode != 'text') {
        buffer.write(_paragraphXml(
          heading,
          isBold: true,
          fontFamily: documentFont,
          fontSize: isModern ? 32 : 28,
          spacingBefore: isModern ? 260 : 240,
          spacingAfter: 120,
        ));
      }

      for (final item in section['content'] as List? ?? []) {
        final type = item['type'] as String? ?? '';

        if (type == 'paragraph') {
          buffer.write(_paragraphXml(
            item['text'] as String? ?? '',
            isBold: item['bold'] == true,
            isItalic: item['italic'] == true,
            highlight: item['highlight'] == true,
            highlightColor: item['highlightColor'] as String? ?? 'FFF2A6',
            textColor: item['textColor'] as String? ?? '111111',
            alignment: item['align'] as String? ?? 'left',
            fontFamily: documentFont,
            fontSize: isModern ? 22 : 24,
            spacingAfter: isModern ? 150 : 140,
            line: isModern ? 276 : 360,
          ));
        } else if (type == 'formula') {
          final sourceFormulaXml =
              item['source_formula_xml'] as String? ?? '';
          if (sourceFormulaXml.isNotEmpty) {
            // A structured DOCX formula retains its OMML and associated Word
            // run properties. Reusing this paragraph avoids flattening ANOVA
            // fractions, Greek letters, subscripts, and superscripts.
            buffer.write(sourceFormulaXml);
          } else {
            final omml = item['formula_omml'] as String? ?? '';
            buffer.write(omml.isNotEmpty
                ? _formulaParagraphXml(omml)
                : _paragraphXml(
                    item['text'] as String? ?? '',
                    isBold: true,
                    fontFamily: 'Cambria Math',
                    spacingAfter: 80,
                    line: 360,
                  ));
          }
          final error = (item['error'] as String? ?? '').trim();
          if (error.isNotEmpty) {
            buffer.write(_paragraphXml(
              'Formula detection note: $error',
              fontSize: 20,
              spacingAfter: 140,
              line: 300,
            ));
          }
        } else if (type == 'list') {
          for (final listItem in item['items'] as List? ?? []) {
            buffer.write(_paragraphXml(
              listItem.toString(),
              isBullet: true,
              spacingAfter: 80,
            ));
          }
        } else if (type == 'table') {
          final sourceTableXml = item['source_table_xml'] as String? ?? '';
          buffer.write(sourceTableXml.isNotEmpty
              ? sourceTableXml
              : _tableXml(item['rows'] as List? ?? []));
        } else if (type == 'image') {
          final imagePath = item['path'] as String? ?? '';
          final image = mediaByPath[imagePath];
          if (image != null) {
            final widthPercent =
                (item['width_percent'] as num?)?.toDouble() ?? 80;
            buffer.write(_imageXml(image, widthPercent: widthPercent));
          } else {
            final caption = item['caption'] as String? ?? 'Image';
            buffer.write(_paragraphXml(
              caption,
              isBold: true,
              spacingAfter: 140,
              line: 360,
            ));
          }
        }
      }
    }

    // Direct mode can still use regular page margins, but we do NOT declare
    // header/footer space to avoid repeated header/footer rendering.
    // (If a header/footer is required by a blueprint template, it should be
    // explicitly defined there.)
    buffer.write('<w:sectPr>');
    buffer.write('<w:pgSz w:orient="portrait" w:w="11906" w:h="16838"/>');
    buffer.write('<w:pgMar w:top="1000" w:right="1000" w:bottom="1000" '
        'w:left="1000" w:gutter="0"/>');
    buffer.write('<w:cols w:num="1" w:space="720"/>');
    buffer.write('</w:sectPr>');

    buffer.write('</w:body>');
    buffer.write('</w:document>');

    return buffer.toString();
  }

  static String _paragraphXml(
    String text, {
    bool isBold = false,
    bool isBullet = false,
    int fontSize = 24,
    int spacingBefore = 0,
    int spacingAfter = 140,
    int line = 0,
    String fontFamily = 'Times New Roman',
    bool highlight = false,
    String highlightColor = 'FFF2A6',
    String textColor = '111111',
    bool isItalic = false,
    String alignment = 'left',
  }) {
    final escaped = _escapeXml(text)
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '</w:t><w:br/><w:t xml:space="preserve">');
    final boldTag = isBold ? '<w:b w:val="1"/><w:bCs w:val="1"/>' : '';
    final italicTag = isItalic ? '<w:i w:val="1"/><w:iCs w:val="1"/>' : '';
    final spacing = '<w:spacing'
        '${spacingBefore > 0 ? ' w:before="$spacingBefore"' : ''}'
        '${spacingAfter > 0 ? ' w:after="$spacingAfter"' : ''}'
        '${line > 0 ? ' w:line="$line" w:lineRule="auto"' : ''}/>';
    final bullet = isBullet
        ? '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
        : '';
    final justification = switch (alignment) {
      'center' => '<w:jc w:val="center"/>',
      'right' => '<w:jc w:val="right"/>',
      'justify' => '<w:jc w:val="both"/>',
      _ => '',
    };
    final font = _escapeXml(fontFamily);
    final runPr = '<w:rPr><w:rFonts w:ascii="$font" '
        'w:hAnsi="$font" w:eastAsia="$font" '
        'w:cs="$font"/><w:color w:val="${_sanitizeHex(textColor, '111111')}"/>'
        '<w:sz w:val="$fontSize"/><w:szCs w:val="$fontSize"/>'
        '${highlight ? '<w:shd w:val="clear" w:color="auto" w:fill="${_sanitizeHex(highlightColor, 'FFF2A6')}"/>' : ''}'
        '$boldTag$italicTag</w:rPr>';

    return '<w:p><w:pPr>$bullet$justification$spacing</w:pPr>'
        '<w:r>$runPr'
        '<w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
  }

  static String _sanitizeHex(String value, String fallback) {
    final cleaned = value.replaceAll('#', '').toUpperCase();
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(cleaned) ? cleaned : fallback;
  }

  static String _formulaParagraphXml(String omml) {
    return '<w:p><w:pPr><w:jc w:val="center"/>'
        '<w:spacing w:after="120" w:line="360" w:lineRule="auto"/>'
        '</w:pPr>$omml</w:p>';
  }

  static String _tableXml(List<dynamic> rows) {
    if (rows.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.write('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>');
    buffer
        .write('<w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write(
        '<w:left w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write(
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write(
        '<w:right w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write(
        '<w:insideH w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write(
        '<w:insideV w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
    buffer.write('</w:tblBorders></w:tblPr>');

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i] as List;
      buffer.write('<w:tr>');
      for (final cell in row) {
        final isHeader = i == 0;
        buffer.write('<w:tc><w:tcPr><w:tcW w:w="3200" w:type="dxa"/>'
            '${isHeader ? '<w:shd w:fill="EDEDED"/>' : ''}</w:tcPr>');
        buffer.write(_paragraphXml(
          cell.toString(),
          isBold: isHeader,
          spacingAfter: 0,
          line: 0,
        ));
        buffer.write('</w:tc>');
      }
      buffer.write('</w:tr>');
    }

    buffer.write('</w:tbl>');
    return buffer.toString();
  }

  static String _imageXml(_DocxMedia image, {required double widthPercent}) {
    final widthPt = (420 * (widthPercent / 100)).clamp(126, 420).toDouble();
    final heightPt = widthPt * 0.72;
    return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:pict>'
        '<v:shape type="#_x0000_t75" stroked="f" '
        'style="width:${widthPt.toStringAsFixed(2)}pt; '
        'height:${heightPt.toStringAsFixed(2)}pt; margin-left:0pt; '
        'margin-top:0pt; mso-position-horizontal:left; '
        'mso-position-vertical:top; '
        'mso-position-horizontal-relative:char; '
        'mso-position-vertical-relative:line;">'
        '<w10:wrap type="inline"/>'
        '<v:imagedata r:id="${image.relationshipId}" o:title=""/>'
        '</v:shape></w:pict></w:r></w:p>';
  }

  static Future<List<_DocxMedia>> _collectMedia(
      Map<String, dynamic> mapping) async {
    final media = <_DocxMedia>[];
    var index = 1;

    for (final section in _extractSections(mapping)) {
      for (final item in section['content'] as List? ?? []) {
        if (item is! Map || item['type'] != 'image') continue;
        final sourcePath = item['path'] as String? ?? '';
        if (sourcePath.isEmpty || !await File(sourcePath).exists()) continue;

        final extension = p.extension(sourcePath).toLowerCase();
        if (!['.png', '.jpg', '.jpeg', '.gif'].contains(extension)) continue;

        final bytes = await File(sourcePath).readAsBytes();
        final normalizedExt = extension == '.jpeg' ? '.jpg' : extension;
        media.add(_DocxMedia(
          sourcePath: sourcePath,
          fileName: 'section_image$index$normalizedExt',
          relationshipId: 'rId${index + 6}',
          contentType: _imageContentType(normalizedExt),
          bytes: bytes,
        ));
        index++;
      }
    }

    return media;
  }

  static String _imageContentType(String extension) {
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      default:
        return 'image/png';
    }
  }

  static String _escapeXml(String text) {
    final safeText = text
        .replaceAll('\u0013', '-')
        .replaceAll('\u0014', '-')
        .replaceAll('\u0018', "'")
        .replaceAll('\u0019', "'")
        .replaceAll('\u001c', '"')
        .replaceAll('\u001d', '"')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    return safeText
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _contentTypesXml(List<_DocxMedia> media) {
    final imageDefaults = {
      for (final image in media)
        p.extension(image.fileName).replaceFirst('.', ''): image.contentType,
    };
    final imageXml = imageDefaults.entries
        .map((entry) =>
            '<Default Extension="${entry.key}" ContentType="${entry.value}"/>')
        .join('\n  ');
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  $imageXml
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
</Types>''';
  }

  static String _rootRelationshipsXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
  }

  static String _documentRelationshipsXml(List<_DocxMedia> media) {
    final imageRels = media
        .map((image) =>
            '<Relationship Id="${image.relationshipId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${image.fileName}"/>')
        .join('\n  ');
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>
  $imageRels
</Relationships>''';
  }

  static String _stylesXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>
        <w:sz w:val="24"/><w:szCs w:val="24"/>
        <w:lang w:val="en-US"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
  </w:style>
  <w:style w:type="character" w:styleId="FootnoteReference">
    <w:name w:val="Footnote Reference"/>
    <w:semiHidden/><w:unhideWhenUsed/>
    <w:rPr><w:vertAlign w:val="superscript"/></w:rPr>
  </w:style>
</w:styles>''';
  }

  static String _numberingXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="1">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:suff w:val="tab"/>
      <w:lvlText w:val="•"/>
      <w:lvlJc w:val="left"/>
      <w:pPr>
        <w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs>
        <w:ind w:left="720" w:hanging="360"/>
      </w:pPr>
      <w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:cs="Symbol"/></w:rPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';
  }

  static String _settingsXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:zoom w:percent="100"/>
  <w:defaultTabStop w:val="720"/>
  <w:compat/>
</w:settings>''';
  }

  static String _fontTableXml() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:font w:name="Times New Roman"><w:family w:val="roman"/></w:font>
  <w:font w:name="Arial"><w:family w:val="swiss"/></w:font>
  <w:font w:name="Symbol"><w:family w:val="decorative"/></w:font>
</w:fonts>''';
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
}

class _DocxMedia {
  final String sourcePath;
  final String fileName;
  final String relationshipId;
  final String contentType;
  final List<int> bytes;

  const _DocxMedia({
    required this.sourcePath,
    required this.fileName,
    required this.relationshipId,
    required this.contentType,
    required this.bytes,
  });
}
