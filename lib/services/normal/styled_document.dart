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
  final String visibleText;
  final List<StyledBlock> header;
  final List<StyledBlock> footer;
  final Map<String, List<StyledBlock>> headerStories;
  final Map<String, List<StyledBlock>> footerStories;
  final bool evenAndOddHeaders;
  final List<StyledFootnote> footnotes;

  const StyledDocument({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.marginTop = 72,
    this.marginRight = 72,
    this.marginBottom = 72,
    this.marginLeft = 72,
    this.blocks = const [],
    this.notes = const [],
    this.visibleText = '',
    this.header = const [],
    this.footer = const [],
    this.headerStories = const {},
    this.footerStories = const {},
    this.evenAndOddHeaders = false,
    this.footnotes = const [],
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
  final String? background;
  final String? fontFamily;
  final double? fontSize;
  final bool superscript;
  final bool subscript;
  final String? link;
  final String? footnoteId;
  final Uint8List? imageBytes;
  final String? imageMime;
  final double? imageWidth;
  final double? imageHeight;
  final String? imageAlt;
  final StyledShape? shape;
  final Map<String, double> imageCrop;
  final double imageRotation;
  final String wrapMode;

  const StyledRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.superscript = false,
    this.subscript = false,
    this.link,
    this.footnoteId,
    this.imageBytes,
    this.imageMime,
    this.imageWidth,
    this.imageHeight,
    this.imageAlt,
    this.shape,
    this.imageCrop = const {},
    this.imageRotation = 0,
    this.wrapMode = 'inline',
  });
}

class StyledListInfo {
  final String id;
  final int level;
  final String format;
  final String marker;
  final String? markerFontFamily;
  final double leftIndent;
  final double hangingIndent;
  final int start;

  const StyledListInfo({
    required this.id,
    required this.level,
    required this.format,
    required this.marker,
    this.markerFontFamily,
    this.leftIndent = 0,
    this.hangingIndent = 0,
    this.start = 1,
  });
}

class StyledParagraph extends StyledBlock {
  final List<StyledRun> runs;
  final String alignment;
  final double spacingBefore;
  final double spacingAfter;
  final double? lineSpacing;
  final String lineSpacingRule;
  final double indentLeft;
  final double indentRight;
  final double firstLineIndent;
  final int? headingLevel;
  final StyledListInfo? listInfo;
  final Map<String, String> borders;
  final String? shading;
  final double borderPadding;

  const StyledParagraph({
    required this.runs,
    this.alignment = 'left',
    this.spacingBefore = 0,
    this.spacingAfter = 0,
    this.lineSpacing,
    this.lineSpacingRule = 'auto',
    this.indentLeft = 0,
    this.indentRight = 0,
    this.firstLineIndent = 0,
    this.headingLevel,
    this.listInfo,
    this.borders = const {},
    this.shading,
    this.borderPadding = 0,
  });
}

class StyledTable extends StyledBlock {
  final List<StyledTableRow> rows;
  final List<double> columnWidths;
  final Map<String, String> borders;
  final String? shading;
  final double? width;
  final String widthType;
  final String layout;

  const StyledTable({
    required this.rows,
    this.columnWidths = const [],
    this.borders = const {},
    this.shading,
    this.width,
    this.widthType = 'auto',
    this.layout = 'autofit',
  });
}

class StyledTableRow {
  final List<StyledTableCell> cells;
  final bool isHeader;
  final double? height;
  final bool exactHeight;
  final bool cantSplit;

  const StyledTableRow(
    this.cells, {
    this.isHeader = false,
    this.height,
    this.exactHeight = false,
    this.cantSplit = false,
  });
}

class StyledTableCell {
  final List<StyledBlock> blocks;
  final int gridSpan;
  final String? vMerge;
  final Map<String, String> borders;
  final String? shading;
  final double? marginTop;
  final double? marginRight;
  final double? marginBottom;
  final double? marginLeft;
  final String verticalAlignment;

  const StyledTableCell({
    required this.blocks,
    this.gridSpan = 1,
    this.vMerge,
    this.borders = const {},
    this.shading,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
    this.verticalAlignment = 'top',
  });
}

class StyledImage extends StyledBlock {
  final Uint8List bytes;
  final String mime;
  final double? width;
  final double? height;
  final String alt;
  final String position;
  final Map<String, double> crop;
  final double rotation;
  final String wrapMode;

  const StyledImage({
    required this.bytes,
    required this.mime,
    this.width,
    this.height,
    this.alt = 'Image',
    this.position = 'block',
    this.crop = const {},
    this.rotation = 0,
    this.wrapMode = 'none',
  });
}

class StyledShape extends StyledBlock {
  final String geometry;
  final String? fill;
  final String? outline;
  final double outlineWidth;
  final double width;
  final double height;
  final String text;

  const StyledShape({
    required this.geometry,
    required this.width,
    required this.height,
    this.fill,
    this.outline,
    this.outlineWidth = 1,
    this.text = '',
  });
}

class StyledFootnote {
  final String id;
  final List<StyledBlock> blocks;

  const StyledFootnote({required this.id, required this.blocks});
}

class SectionBreak extends StyledBlock {
  final double? pageWidth;
  final double? pageHeight;
  final double? marginTop;
  final double? marginRight;
  final double? marginBottom;
  final double? marginLeft;
  final double? headerDistance;
  final double? footerDistance;
  final int columns;
  final String type;
  final bool finalSection;
  final Map<String, String> headerReferences;
  final Map<String, String> footerReferences;
  final bool titlePage;

  const SectionBreak({
    this.pageWidth,
    this.pageHeight,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
    this.headerDistance,
    this.footerDistance,
    this.columns = 1,
    this.type = 'nextPage',
    this.finalSection = false,
    this.headerReferences = const {},
    this.footerReferences = const {},
    this.titlePage = false,
  });
}

class PageBreak extends StyledBlock {
  const PageBreak();
}
