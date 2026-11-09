import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

import 'styled_document.dart';

class PdfStyleWriter {
  static Future<List<String>> write(
    StyledDocument document,
    String outputPath,
  ) async {
    final fonts = await _loadFonts();
    final writerNotes = <String>{};
    final fallback = await _loadFont('assets/fonts/NotoSansMath-Regular.ttf');
    final theme = pw.ThemeData.withFont(
      base: fonts.sans.regular,
      bold: fonts.sans.bold,
      italic: fonts.sans.italic,
      boldItalic: fonts.sans.boldItalic,
      fontFallback: [fallback],
    );
    final pageWidth = _positive(document.pageWidth, 595.28);
    final pageHeight = _positive(document.pageHeight, 841.89);
    final marginLeft = _safeMargin(document.marginLeft, pageWidth);
    final marginRight = _safeMargin(document.marginRight, pageWidth);
    final marginTop = _safeMargin(document.marginTop, pageHeight);
    final marginBottom = _safeMargin(document.marginBottom, pageHeight);
    final contentWidth =
        math.max(1.0, pageWidth - marginLeft - marginRight).toDouble();
    final contentHeight =
        math.max(1.0, pageHeight - marginTop - marginBottom).toDouble();
    final page = pdf.PdfPageFormat(pageWidth, pageHeight);
    final output = pw.Document(theme: theme);
    output.addPage(
      pw.MultiPage(
        pageFormat: page,
        margin: pw.EdgeInsets.fromLTRB(
          marginLeft,
          marginTop,
          marginRight,
          marginBottom,
        ),
        theme: theme,
        maxPages: 1000,
        build: (context) => _buildBlocks(
          document.blocks,
          fonts,
          fallback,
          contentWidth,
          contentHeight,
          writerNotes,
        ),
      ),
    );
    await File(outputPath).writeAsBytes(await output.save());
    return writerNotes.toList();
  }

  static List<pw.Widget> _buildBlocks(
    List<StyledBlock> blocks,
    _FontFamilies fonts,
    pw.Font unicodeFallback,
    double contentWidth,
    double contentHeight,
    Set<String> notes, {
    bool forceBold = false,
  }) {
    final widgets = <pw.Widget>[];
    final listCounters = <String, int>{};
    for (final block in blocks) {
      if (block is StyledParagraph) {
        final list = block.listInfo;
        final prefix = list == null
            ? ''
            : _listMarker(list, listCounters);
        widgets.add(
          _buildParagraph(
            block,
            fonts,
            unicodeFallback,
            forceBold: forceBold,
            prefix: prefix,
          ),
        );
      } else if (block is StyledTable) {
        widgets.add(
          _buildTable(
            block,
            fonts,
            unicodeFallback,
            contentWidth,
            contentHeight,
            notes,
          ),
        );
      } else if (block is StyledImage) {
        widgets.add(
          _buildImage(block, contentWidth, contentHeight, notes),
        );
      } else if (block is PageBreak) {
        widgets.add(pw.NewPage());
      }
    }
    return widgets;
  }

  static pw.Widget _buildParagraph(
    StyledParagraph paragraph,
    _FontFamilies fonts,
    pw.Font unicodeFallback, {
    bool forceBold = false,
    String prefix = '',
  }) {
    final headingSize = switch (paragraph.headingLevel) {
      1 => 22.0,
      2 => 18.0,
      3 => 16.0,
      4 => 14.0,
      5 => 12.0,
      _ => 11.0,
    };
    final baseStyle = _textStyle(
      fonts.sans,
      unicodeFallback,
      fontSize: headingSize,
      bold: forceBold || paragraph.headingLevel != null,
      height: paragraph.lineSpacing ?? 1,
    );
    final spans = <pw.InlineSpan>[];
    if (paragraph.firstLineIndent > 0) {
      spans.add(
        pw.WidgetSpan(
          child: pw.SizedBox(width: paragraph.firstLineIndent),
        ),
      );
    }
    if (prefix.isNotEmpty) {
      spans.add(pw.TextSpan(text: prefix, style: baseStyle));
    }
    for (final run in paragraph.runs) {
      final family = _fontFamily(run.fontFamily, fonts);
      final bold = forceBold || run.bold;
      final size = run.fontSize ?? headingSize;
      final style = _textStyle(
        family,
        unicodeFallback,
        fontSize: run.superscript || run.subscript ? size * 0.72 : size,
        bold: bold,
        italic: run.italic,
        color: _color(run.color),
        height: paragraph.lineSpacing ?? 1,
        underline: run.underline,
        strike: run.strike,
      );
      spans.add(
        pw.TextSpan(
          text: run.text,
          style: style,
          baseline: run.superscript
              ? size * 0.32
              : run.subscript
                  ? -size * 0.2
                  : 0,
          annotation: run.link == null || run.link!.isEmpty
              ? null
              : pw.AnnotationUrl(run.link!),
        ),
      );
    }

    var fontSize = headingSize;
    for (final run in paragraph.runs) {
      if (run.fontSize != null && run.fontSize!.isFinite && run.fontSize! > 0) {
        fontSize = run.fontSize!;
        break;
      }
    }
    final isEmptyParagraph = paragraph.runs.every((run) => run.text.isEmpty) &&
        prefix.isEmpty;
    if (spans.isEmpty || isEmptyParagraph) {
      return pw.SizedBox(
        height: paragraph.spacingBefore +
            paragraph.spacingAfter +
            fontSize * (paragraph.lineSpacing ?? 1.2),
      );
    }
    final alignment = switch (paragraph.alignment) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      'justify' => pw.TextAlign.justify,
      _ => pw.TextAlign.left,
    };
    final leftIndent = math
        .max(
          0.0,
          paragraph.indentLeft + math.min(0.0, paragraph.firstLineIndent),
        )
        .toDouble();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (paragraph.spacingBefore > 0)
          pw.SizedBox(height: paragraph.spacingBefore),
        pw.Padding(
          padding: pw.EdgeInsets.only(
            left: leftIndent,
            right: paragraph.indentRight,
          ),
          child: pw.RichText(
            text: pw.TextSpan(style: baseStyle, children: spans),
            textAlign: alignment,
            softWrap: true,
          ),
        ),
        if (paragraph.spacingAfter > 0)
          pw.SizedBox(height: paragraph.spacingAfter),
      ],
    );
  }

  static pw.Widget _buildTable(
    StyledTable table,
    _FontFamilies fonts,
    pw.Font unicodeFallback,
    double contentWidth,
    double contentHeight,
    Set<String> notes,
  ) {
    if (table.rows.isEmpty) return pw.SizedBox();
    var columnCount = 0;
    for (final row in table.rows) {
      final rowColumns = row.cells.fold<int>(
        0,
        (count, cell) => count + (cell.gridSpan < 1 ? 1 : cell.gridSpan),
      );
      if (rowColumns > columnCount) columnCount = rowColumns;
    }
    if (columnCount == 0) return pw.SizedBox();
    final widths = <int, pw.TableColumnWidth>{};
    if (table.columnWidths.isNotEmpty) {
      final grid = List<double>.generate(
        columnCount,
        (index) => index < table.columnWidths.length
            ? table.columnWidths[index]
            : 0,
      );
      final gridTotal = grid.fold<double>(0, (sum, width) => sum + width);
      if (gridTotal > 0) {
        for (var index = 0; index < columnCount; index++) {
          if (grid[index] > 0) {
            widths[index] = pw.FixedColumnWidth(
              contentWidth * grid[index] / gridTotal,
            );
          }
        }
      }
    }
    final rows = <pw.TableRow>[];
    for (final row in table.rows) {
      final cells = <pw.Widget>[];
      for (final cell in row.cells) {
        final cellWidget = _tableCell(
          cell,
          table,
          fonts,
          unicodeFallback,
          contentWidth,
          contentHeight,
          notes,
          forceBold: row.isHeader,
        );
        cells.add(cellWidget);
        for (var index = 1;
            index < (cell.gridSpan < 1 ? 1 : cell.gridSpan);
            index++) {
          cells.add(pw.SizedBox());
        }
      }
      while (cells.length < columnCount) {
        cells.add(pw.SizedBox());
      }
      rows.add(pw.TableRow(children: cells, repeat: row.isHeader));
    }
    return pw.Table(
      children: rows,
      columnWidths: widths,
      defaultColumnWidth: const pw.FlexColumnWidth(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      border: _tableBorder(table.borders),
      tableWidth: pw.TableWidth.max,
    );
  }

  static pw.Widget _tableCell(
    StyledTableCell cell,
    StyledTable table,
    _FontFamilies fonts,
    pw.Font unicodeFallback,
    double contentWidth,
    double contentHeight,
    Set<String> notes, {
    required bool forceBold,
  }) {
    final borderMap = cell.borders.isEmpty ? const <String, String>{} : cell.borders;
    final fill = _color(cell.shading ?? (cell.vMerge == 'continue' ? null : table.shading));
    final child = cell.vMerge == 'continue'
        ? pw.SizedBox(height: 12)
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: _buildBlocks(
              cell.blocks,
              fonts,
              unicodeFallback,
              contentWidth,
              contentHeight,
              notes,
              forceBold: forceBold,
            ),
          );
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: fill,
        border: borderMap.isEmpty ? null : _cellBorder(borderMap),
      ),
      child: child,
    );
  }

  static pw.Widget _buildImage(
    StyledImage image,
    double contentWidth,
    double contentHeight,
    Set<String> notes,
  ) {
    try {
      if (!image.mime.startsWith('image/')) {
        notes.add('Some items were simplified.');
        return pw.SizedBox();
      }
      final provider = pw.MemoryImage(image.bytes);
      final originalWidth = image.width ?? provider.width?.toDouble() ?? contentWidth;
      final originalHeight = image.height ?? provider.height?.toDouble() ?? contentHeight;
      final scale = math.min(
        1.0,
        math.min(contentWidth / originalWidth, contentHeight / originalHeight),
      ).toDouble();
      final width = originalWidth * scale;
      final height = originalHeight * scale;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Center(
          child: pw.Image(
            provider,
            width: width,
            height: height,
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    } on Object {
      notes.add('Some items were simplified.');
      return pw.SizedBox();
    }
  }

  static pw.TableBorder _tableBorder(Map<String, String> borders) {
    return pw.TableBorder(
      left: _borderSide(borders['left']),
      top: _borderSide(borders['top']),
      right: _borderSide(borders['right']),
      bottom: _borderSide(borders['bottom']),
      horizontalInside: _borderSide(borders['insideH']),
      verticalInside: _borderSide(borders['insideV']),
    );
  }

  static pw.Border _cellBorder(Map<String, String> borders) => pw.Border(
        left: _borderSide(borders['left']),
        top: _borderSide(borders['top']),
        right: _borderSide(borders['right']),
        bottom: _borderSide(borders['bottom']),
      );

  static pw.BorderSide _borderSide(String? value) {
    if (value == null || value.isEmpty) return pw.BorderSide.none;
    final match = RegExp(r'([\d.]+)pt\s+(dashed|solid)\s+(#[0-9a-fA-F]{6})')
        .firstMatch(value);
    if (match == null) return pw.BorderSide.none;
    return pw.BorderSide(
      width: double.tryParse(match.group(1)!) ?? 0.5,
      style: match.group(2) == 'dashed'
          ? pw.BorderStyle.dashed
          : pw.BorderStyle.solid,
      color: _color(match.group(3)) ?? pdf.PdfColors.black,
    );
  }

  static pw.TextStyle _textStyle(
    _FontSet font,
    pw.Font unicodeFallback, {
    required double fontSize,
    bool bold = false,
    bool italic = false,
    pdf.PdfColor? color,
    double height = 1,
    bool underline = false,
    bool strike = false,
  }) {
    final decorations = <pw.TextDecoration>[];
    if (underline) decorations.add(pw.TextDecoration.underline);
    if (strike) decorations.add(pw.TextDecoration.lineThrough);
    return pw.TextStyle(
      fontNormal: font.regular,
      fontBold: font.bold,
      fontItalic: font.italic,
      fontBoldItalic: font.boldItalic,
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      color: color ?? pdf.PdfColors.black,
      height: height,
      fontFallback: [unicodeFallback],
      decoration: decorations.isEmpty
          ? pw.TextDecoration.none
          : pw.TextDecoration.combine(decorations),
    );
  }

  static String _listMarker(
    StyledListInfo list,
    Map<String, int> counters,
  ) {
    if (list.format == 'bullet') {
      return '${list.marker.isEmpty ? '•' : list.marker} ';
    }
    final key = '${list.id}:${list.level}';
    final number = (counters[key] ?? 0) + 1;
    counters[key] = number;
    var formatted = _formatNumber(number, list.format);
    final marker = list.marker.isEmpty ? '%1.' : list.marker;
    final result = marker.replaceAll('%${list.level + 1}', formatted);
    return result.contains('%') ? '$formatted. ' : '$result ';
  }

  static String _formatNumber(int value, String format) {
    switch (format) {
      case 'lowerLetter':
      case 'upperLetter':
        var number = value;
        var output = '';
        while (number > 0) {
          number--;
          output = String.fromCharCode(97 + number % 26) + output;
          number ~/= 26;
        }
        return format == 'upperLetter' ? output.toUpperCase() : output;
      case 'lowerRoman':
      case 'upperRoman':
        const roman = <(int, String)>[
          (1000, 'M'),
          (900, 'CM'),
          (500, 'D'),
          (400, 'CD'),
          (100, 'C'),
          (90, 'XC'),
          (50, 'L'),
          (40, 'XL'),
          (10, 'X'),
          (9, 'IX'),
          (5, 'V'),
          (4, 'IV'),
          (1, 'I'),
        ];
        var remaining = value;
        final result = StringBuffer();
        for (final entry in roman) {
          while (remaining >= entry.$1) {
            result.write(entry.$2);
            remaining -= entry.$1;
          }
        }
        final output = result.toString();
        return format == 'lowerRoman' ? output.toLowerCase() : output;
      default:
        return '$value';
    }
  }

  static _FontSet _fontFamily(String? requested, _FontFamilies fonts) {
    final family = (requested ?? '').toLowerCase();
    if (family.contains('times') || family.contains('serif')) return fonts.serif;
    if (family.contains('courier') || family.contains('mono')) return fonts.mono;
    if (family.contains('calibri') || family.contains('carlito')) return fonts.carlito;
    return fonts.sans;
  }

  static Future<_FontFamilies> _loadFonts() async {
    Future<_FontSet> load(String prefix) async => _FontSet(
          regular: await _loadFont('assets/fonts/$prefix-Regular.ttf'),
          bold: await _loadFont('assets/fonts/$prefix-Bold.ttf'),
          italic: await _loadFont('assets/fonts/$prefix-Italic.ttf'),
          boldItalic: await _loadFont('assets/fonts/$prefix-BoldItalic.ttf'),
        );
    return _FontFamilies(
      sans: await load('LiberationSans'),
      serif: await load('LiberationSerif'),
      mono: await load('LiberationMono'),
      carlito: await load('Carlito'),
    );
  }

  static Future<pw.Font> _loadFont(String path) async =>
      pw.Font.ttf(await rootBundle.load(path));

  static pdf.PdfColor? _color(String? value) {
    if (value == null) return null;
    final hex = value.replaceAll('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    final color = int.parse(hex, radix: 16);
    return pdf.PdfColor(
      ((color >> 16) & 0xff) / 255,
      ((color >> 8) & 0xff) / 255,
      (color & 0xff) / 255,
    );
  }

  static double _positive(double value, double fallback) =>
      value.isFinite && value > 0 ? value : fallback;

  static double _safeMargin(double value, double pageExtent) =>
      value.isFinite ? value.clamp(0, pageExtent / 2).toDouble() : 0;
}

class _FontSet {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  const _FontSet({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });
}

class _FontFamilies {
  final _FontSet sans;
  final _FontSet serif;
  final _FontSet mono;
  final _FontSet carlito;

  const _FontFamilies({
    required this.sans,
    required this.serif,
    required this.mono,
    required this.carlito,
  });
}
