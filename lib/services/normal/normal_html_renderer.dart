import 'dart:convert';

import 'styled_document.dart';

class NormalHtmlRenderer {
  static String renderDocx(StyledDocument document, String title) {
    final contentWidth = document.pageWidth -
        document.marginLeft -
        document.marginRight;
    final body = _renderBlocks(document.blocks, document);
    return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<style>
*{box-sizing:border-box}body{margin:0;padding:24px;background:#ededed;color:#111;font-family:Calibri,Arial,sans-serif}
.docx-page{width:${contentWidth.toStringAsFixed(2)}pt;max-width:calc(100vw - 48px);min-height:${(document.pageHeight - document.marginTop - document.marginBottom).toStringAsFixed(2)}pt;margin:0 auto;padding:0;background:#fff;overflow-wrap:anywhere}
p{margin-top:0}table{border-collapse:collapse;max-width:100%;width:100%}td{vertical-align:top;padding:4pt;overflow-wrap:anywhere}
img{max-width:100%;height:auto}a{color:inherit} .page-break{break-before:page;page-break-before:always}
@media print{body{padding:0;background:#fff}.docx-page{max-width:none;margin:0}}
</style></head><body><main class="docx-page">$body</main></body></html>''';
  }

  static String renderText(String text, String title) {
    final paragraphs = text
        .split(RegExp(r'\r\n|\n|\r'))
        .map((line) => '<p>${_escape(line)}</p>')
        .join();
    return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<style>body{font-family:Arial,sans-serif;max-width:850px;margin:32px auto;padding:24px;color:#111;background:#fff}p{white-space:pre-wrap;margin:0 0 1em}</style>
</head><body>$paragraphs</body></html>''';
  }

  static String _renderBlocks(List<StyledBlock> blocks, StyledDocument document) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < blocks.length) {
      final block = blocks[index];
      if (block is StyledParagraph && block.listInfo != null) {
        final items = <StyledParagraph>[block];
        final list = block.listInfo!;
        index++;
        while (index < blocks.length && blocks[index] is StyledParagraph) {
          final next = blocks[index] as StyledParagraph;
          final nextList = next.listInfo;
          if (nextList == null ||
              nextList.id != list.id ||
              nextList.level != list.level ||
              nextList.format != list.format) {
            break;
          }
          items.add(next);
          index++;
        }
        buffer.write(_renderList(items, list));
        continue;
      }
      if (block is StyledParagraph) {
        buffer.write(_renderParagraph(block));
      } else if (block is StyledTable) {
        buffer.write(_renderTable(block, document));
      } else if (block is StyledImage) {
        final data = base64Encode(block.bytes);
        final size = block.width == null ? '' : 'width="${block.width!.toStringAsFixed(1)}pt"';
        buffer.write(
          '<figure><img src="data:${_escapeAttribute(block.mime)};base64,$data" '
          'alt="${_escapeAttribute(block.alt)}" $size></figure>',
        );
      } else if (block is PageBreak) {
        buffer.write('<div class="page-break"></div>');
      }
      index++;
    }
    return buffer.toString();
  }

  static String _renderParagraph(StyledParagraph paragraph) {
    final styles = _paragraphStyles(paragraph);
    final content = paragraph.runs.map(_renderRun).join();
    final heading = paragraph.headingLevel;
    if (heading != null && heading > 0) {
      final boundedHeading = heading < 1 ? 1 : (heading > 6 ? 6 : heading);
      final tag = 'h$boundedHeading';
      return '<$tag style="${styles.join(';')}">$content</$tag>';
    }
    return '<p style="${styles.join(';')}">$content</p>';
  }

  static String _renderList(
    List<StyledParagraph> paragraphs,
    StyledListInfo list,
  ) {
    final ordered = list.format != 'bullet';
    final tag = ordered ? 'ol' : 'ul';
    final listStyle = ordered ? _numberStyle(list.format) : 'disc';
    final indentation = (list.level * 18).toString();
    final items = paragraphs.map((paragraph) {
      final content = paragraph.runs.map(_renderRun).join();
      return '<li style="${_paragraphStyles(paragraph).join(';')}">$content</li>';
    }).join();
    return '<$tag style="margin:0;padding-left:${indentation}pt;list-style-type:$listStyle">$items</$tag>';
  }

  static List<String> _paragraphStyles(StyledParagraph paragraph) => [
        'text-align:${paragraph.alignment}',
        'margin-top:${paragraph.spacingBefore}pt',
        'margin-bottom:${paragraph.spacingAfter}pt',
        'margin-left:${paragraph.indentLeft}pt',
        'margin-right:${paragraph.indentRight}pt',
        'text-indent:${paragraph.firstLineIndent}pt',
        if (paragraph.lineSpacing != null)
          'line-height:${paragraph.lineSpacing!.toStringAsFixed(3)}',
      ];

  static String _renderRun(StyledRun run) {
    var content = _escape(run.text).replaceAll('\n', '<br>').replaceAll('\t', '&#9;');
    if (run.bold) content = '<strong>$content</strong>';
    if (run.italic) content = '<em>$content</em>';
    if (run.underline) content = '<u>$content</u>';
    if (run.strike) content = '<s>$content</s>';
    if (run.superscript) content = '<sup>$content</sup>';
    if (run.subscript) content = '<sub>$content</sub>';
    final styles = <String>[];
    final color = _color(run.color);
    if (color != null) styles.add('color:$color');
    if (run.fontFamily != null && run.fontFamily!.isNotEmpty) {
      styles.add('font-family:"${_escapeAttribute(run.fontFamily!)}"');
    }
    if (run.fontSize != null) styles.add('font-size:${run.fontSize}pt');
    if (styles.isNotEmpty) content = '<span style="${styles.join(';')}">$content</span>';
    if (run.link != null && run.link!.isNotEmpty) {
      content = '<a href="${_escapeAttribute(run.link!)}">$content</a>';
    }
    return content;
  }

  static String _renderTable(StyledTable table, StyledDocument document) {
    final buffer = StringBuffer('<table style="');
    final tableBorders = _borderStyle(table.borders);
    if (table.shading != null) {
      final fill = _color(table.shading);
      if (fill != null) buffer.write('background-color:$fill;');
    }
    if (tableBorders.isNotEmpty) buffer.write('$tableBorders;');
    buffer.write('"><colgroup>');
    for (final width in table.columnWidths) {
      buffer.write('<col style="width:${width}pt">');
    }
    buffer.write('</colgroup><tbody>');
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      buffer.write('<tr>');
      for (var cellIndex = 0; cellIndex < row.cells.length; cellIndex++) {
        final cell = row.cells[cellIndex];
        if (cell.vMerge == 'continue') continue;
        var rowSpan = 1;
        if (cell.vMerge == 'restart') {
          for (var next = rowIndex + 1; next < table.rows.length; next++) {
            if (cellIndex >= table.rows[next].cells.length ||
                table.rows[next].cells[cellIndex].vMerge != 'continue') {
              break;
            }
            rowSpan++;
          }
        }
        final styles = <String>[];
        final fill = _color(cell.shading);
        if (fill != null) styles.add('background-color:$fill');
        final borders = _borderStyle(
          cell.borders.isEmpty ? table.borders : cell.borders,
        );
        if (borders.isNotEmpty) styles.add(borders);
        buffer.write('<td colspan="${cell.gridSpan}"');
        if (rowSpan > 1) buffer.write(' rowspan="$rowSpan"');
        buffer.write(' style="${styles.join(';')}">');
        buffer.write(_renderBlocks(cell.blocks, document));
        buffer.write('</td>');
      }
      buffer.write('</tr>');
    }
    buffer.write('</tbody></table>');
    return buffer.toString();
  }

  static String _borderStyle(Map<String, String> borders) {
    return borders.entries
        .where((entry) => const {'top', 'bottom', 'left', 'right', 'insideH', 'insideV'}.contains(entry.key))
        .map((entry) => 'border-${_borderSide(entry.key)}:${entry.value}')
        .join(';');
  }

  static String _borderSide(String side) => switch (side) {
        'insideH' => 'top',
        'insideV' => 'left',
        _ => side,
      };

  static String _numberStyle(String format) => switch (format) {
        'lowerLetter' => 'lower-alpha',
        'upperLetter' => 'upper-alpha',
        'lowerRoman' => 'lower-roman',
        'upperRoman' => 'upper-roman',
        _ => 'decimal',
      };

  static String? _color(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
    return '#$normalized';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeAttribute(String value) =>
      _escape(value).replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}
