import 'dart:typed_data';

class StyledDocument {
  final double pageWidth;
  final double pageHeight;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;
  final List<StyledBlock> blocks;
  final List<String> notes;

  const StyledDocument({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.marginTop = 72,
    this.marginRight = 72,
    this.marginBottom = 72,
    this.marginLeft = 72,
    this.blocks = const [],
    this.notes = const [],
  });
}

abstract class StyledBlock {
  const StyledBlock();
}

class StyledRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final String? color;
  final String? fontFamily;
  final double? fontSize;
  final bool superscript;
  final bool subscript;
  final String? link;

  const StyledRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.fontFamily,
    this.fontSize,
    this.superscript = false,
    this.subscript = false,
    this.link,
  });
}

class StyledListInfo {
  final String id;
  final int level;
  final String format;
  final String marker;

  const StyledListInfo({
    required this.id,
    required this.level,
    required this.format,
    required this.marker,
  });
}

class StyledParagraph extends StyledBlock {
  final List<StyledRun> runs;
  final String alignment;
  final double spacingBefore;
  final double spacingAfter;
  final double? lineSpacing;
  final double indentLeft;
  final double indentRight;
  final double firstLineIndent;
  final int? headingLevel;
  final StyledListInfo? listInfo;

  const StyledParagraph({
    required this.runs,
    this.alignment = 'left',
    this.spacingBefore = 0,
    this.spacingAfter = 0,
    this.lineSpacing,
    this.indentLeft = 0,
    this.indentRight = 0,
    this.firstLineIndent = 0,
    this.headingLevel,
    this.listInfo,
  });
}

class StyledTable extends StyledBlock {
  final List<StyledTableRow> rows;
  final List<double> columnWidths;
  final Map<String, String> borders;
  final String? shading;

  const StyledTable({
    required this.rows,
    this.columnWidths = const [],
    this.borders = const {},
    this.shading,
  });
}

class StyledTableRow {
  final List<StyledTableCell> cells;
  final bool isHeader;

  const StyledTableRow(this.cells, {this.isHeader = false});
}

class StyledTableCell {
  final List<StyledBlock> blocks;
  final int gridSpan;
  final String? vMerge;
  final Map<String, String> borders;
  final String? shading;

  const StyledTableCell({
    required this.blocks,
    this.gridSpan = 1,
    this.vMerge,
    this.borders = const {},
    this.shading,
  });
}

class StyledImage extends StyledBlock {
  final Uint8List bytes;
  final String mime;
  final double? width;
  final double? height;
  final String alt;

  const StyledImage({
    required this.bytes,
    required this.mime,
    this.width,
    this.height,
    this.alt = 'Image',
  });
}

class PageBreak extends StyledBlock {
  const PageBreak();
}
