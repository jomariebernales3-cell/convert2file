import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

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
      fontFallback: [fallback, ...fonts.symbols],
    );
    final output = pw.Document(theme: theme);
    final sections = _splitSections(document.blocks, writerNotes);
    for (final section in sections) {
      final setup = section.setup;
      final pageWidth =
          _positive(setup?.pageWidth ?? document.pageWidth, 595.28);
      final pageHeight =
          _positive(setup?.pageHeight ?? document.pageHeight, 841.89);
      final marginLeft =
          _safeMargin(setup?.marginLeft ?? document.marginLeft, pageWidth);
      final marginRight =
          _safeMargin(setup?.marginRight ?? document.marginRight, pageWidth);
      final marginTop =
          _safeMargin(setup?.marginTop ?? document.marginTop, pageHeight);
      final marginBottom =
          _safeMargin(setup?.marginBottom ?? document.marginBottom, pageHeight);
      final headerDistance =
          _safeMargin(setup?.headerDistance ?? 36, pageHeight);
      final footerDistance =
          _safeMargin(setup?.footerDistance ?? 36, pageHeight);
      final contentWidth =
          math.max(1.0, pageWidth - marginLeft - marginRight).toDouble();
      final contentHeight =
          math.max(1.0, pageHeight - marginTop - marginBottom).toDouble();
      final sectionHeaderStories = [
        for (final target
            in setup == null ? const <String>[] : setup.headerReferences.values)
          if (document.headerStories[target] != null)
            document.headerStories[target]!,
      ];
      if (sectionHeaderStories.isEmpty && document.header.isNotEmpty) {
        sectionHeaderStories.add(document.header);
      }
      final sectionFooterStories = [
        for (final target
            in setup == null ? const <String>[] : setup.footerReferences.values)
          if (document.footerStories[target] != null)
            document.footerStories[target]!,
      ];
      if (sectionFooterStories.isEmpty && document.footer.isNotEmpty) {
        sectionFooterStories.add(document.footer);
      }
      final estimatedHeaderHeight = sectionHeaderStories.isEmpty
          ? 0.0
          : sectionHeaderStories
              .map((story) => _estimateStoryHeight(story, contentWidth))
              .reduce(math.max);
      final estimatedFooterHeight = sectionFooterStories.isEmpty
          ? 0.0
          : sectionFooterStories
              .map((story) => _estimateStoryHeight(story, contentWidth))
              .reduce(math.max);
      const storyGap = 4.0;
      final layoutMarginTop = math.max(
        headerDistance + storyGap,
        marginTop - estimatedHeaderHeight,
      );
      final layoutMarginBottom = math.max(
        footerDistance + storyGap,
        marginBottom - estimatedFooterHeight,
      );
      if ((setup?.columns ?? 1) > 1) {
        writerNotes.add(
          'Section with ${setup!.columns} columns was flowed as one column.',
        );
      }
      var lastSectionPage = -1;
      var sectionPageIndex = 0;
      bool isFirstSectionPage(int pageNumber) {
        if (pageNumber != lastSectionPage) {
          lastSectionPage = pageNumber;
          sectionPageIndex++;
        }
        return sectionPageIndex == 1;
      }

      output.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat(pageWidth, pageHeight),
          margin: pw.EdgeInsets.fromLTRB(
              marginLeft, layoutMarginTop, marginRight, layoutMarginBottom),
          theme: theme,
          maxPages: 10000,
          header: (context) {
            final isFirst = isFirstSectionPage(context.pageNumber);
            final story = _selectStory(
              document.headerStories,
              setup?.headerReferences ?? const {},
              document.header,
              context.pageNumber,
              isFirst,
              setup?.titlePage ?? false,
              document.evenAndOddHeaders,
            );
            final headerWidget = pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: _buildPagePart(
                story,
                fonts,
                fallback,
                context.pageNumber,
                context.pagesCount,
                contentWidth: contentWidth,
                contentHeight: marginTop,
              ),
            );
            return pw.Transform.translate(
              offset: pdf.PdfPoint(0, layoutMarginTop - headerDistance),
              child: headerWidget,
            );
          },
          footer: (context) {
            final isFirst = isFirstSectionPage(context.pageNumber);
            final footer = _buildFooter(
              document,
              fonts,
              fallback,
              context.pageNumber,
              context.pagesCount,
              contentWidth: contentWidth,
              contentHeight: marginBottom,
              blocks: _selectStory(
                document.footerStories,
                setup?.footerReferences ?? const {},
                document.footer,
                context.pageNumber,
                isFirst,
                setup?.titlePage ?? false,
                document.evenAndOddHeaders,
              ),
            );
            return pw.Transform.translate(
              offset: pdf.PdfPoint(0, footerDistance - layoutMarginBottom),
              child: footer,
            );
          },
          build: (context) => _buildBlocks(
            section.blocks,
            fonts,
            fallback,
            contentWidth,
            contentHeight,
            writerNotes,
            footnotes: {
              for (final note in document.footnotes) note.id: note,
            },
          ),
        ),
      );
    }
    final pdfBytes = await output.save();
    await File(outputPath).writeAsBytes(pdfBytes);
    _checkRenderedText(document.visibleText, pdfBytes, writerNotes);
    return writerNotes.toList();
  }

  static void _checkRenderedText(
    String sourceText,
    List<int> pdfBytes,
    Set<String> notes,
  ) {
    final expected = _textTokens(sourceText);
    if (expected.isEmpty) return;
    sf.PdfDocument? pdfDocument;
    try {
      pdfDocument = sf.PdfDocument(inputBytes: pdfBytes);
      final rendered = sf.PdfTextExtractor(pdfDocument).extractText();
      final actual = _textTokens(rendered);
      var cursor = 0;
      var matched = 0;
      for (final token in expected) {
        while (cursor < actual.length && actual[cursor] != token) {
          cursor++;
        }
        if (cursor >= actual.length) break;
        matched++;
        cursor++;
      }
      if (matched != expected.length) {
        notes.add(
          'PDF text check matched $matched of ${expected.length} DOCX text tokens in order.',
        );
      }
    } on Object catch (error) {
      notes.add('PDF text check could not run ($error).');
    } finally {
      pdfDocument?.dispose();
    }
  }

  static double _estimateStoryHeight(
    List<StyledBlock> blocks,
    double availableWidth,
  ) {
    double estimateBlock(StyledBlock block, double width) {
      if (block is StyledParagraph) {
        var fontSize = 11.0;
        var textLength = 0;
        var objectHeight = 0.0;
        for (final run in block.runs) {
          if (run.fontSize != null && run.fontSize! > fontSize) {
            fontSize = run.fontSize!;
          }
          textLength += run.text.length;
          objectHeight = math.max(objectHeight, run.imageHeight ?? 0);
          objectHeight = math.max(objectHeight, run.shape?.height ?? 0);
        }
        final lineWidth = math.max(
          1.0,
          width - block.indentLeft - block.indentRight,
        );
        final approximateLineCount = math.max(
          1,
          (textLength * fontSize * 0.5 / lineWidth).ceil(),
        );
        final lineHeight = _lineHeight(block, fontSize) * fontSize;
        return block.spacingBefore +
            block.spacingAfter +
            math.max(objectHeight, approximateLineCount * lineHeight) +
            block.borderPadding * 2;
      }
      if (block is StyledImage) return block.height ?? 24;
      if (block is StyledShape) return block.height;
      if (block is StyledTable) {
        var total = 0.0;
        for (final row in block.rows) {
          var rowHeight = row.height ?? 0;
          for (final cell in row.cells) {
            final cellWidth = block.columnWidths.isEmpty
                ? width / math.max(1, row.cells.length)
                : block.columnWidths.reduce((a, b) => a + b) /
                    math.max(1, block.columnWidths.length) *
                    cell.gridSpan;
            final cellHeight = cell.blocks.fold<double>(
              0,
              (sum, child) => sum + estimateBlock(child, cellWidth),
            );
            rowHeight = math.max(
              rowHeight,
              cellHeight + (cell.marginTop ?? 4) + (cell.marginBottom ?? 4),
            );
          }
          total += rowHeight;
        }
        return total;
      }
      return 0;
    }

    return blocks.fold<double>(
      0,
      (sum, block) => sum + estimateBlock(block, availableWidth),
    );
  }

  static List<String> _textTokens(String value) => value
      .replaceAll(RegExp(r'\{(?:PAGE|NUMPAGES|SECTIONPAGES|DATE)\}'), '')
      .split(RegExp(r'[\s\u00a0]+'))
      .map((token) => token.trim().toLowerCase())
      .where((token) => token.isNotEmpty)
      .toList();

  static List<_SectionSegment> _splitSections(
    List<StyledBlock> blocks,
    Set<String> notes,
  ) {
    final result = <_SectionSegment>[];
    final current = <StyledBlock>[];
    var inheritedHeaders = <String, String>{};
    var inheritedFooters = <String, String>{};
    var finalSetup = const SectionBreak(finalSection: true);
    for (final block in blocks) {
      if (block is! SectionBreak) {
        current.add(block);
        continue;
      }
      finalSetup = SectionBreak(
        pageWidth: block.pageWidth,
        pageHeight: block.pageHeight,
        marginTop: block.marginTop,
        marginRight: block.marginRight,
        marginBottom: block.marginBottom,
        marginLeft: block.marginLeft,
        headerDistance: block.headerDistance,
        footerDistance: block.footerDistance,
        columns: block.columns,
        type: block.type,
        finalSection: block.finalSection,
        headerReferences: {
          ...inheritedHeaders,
          ...block.headerReferences,
        },
        footerReferences: {
          ...inheritedFooters,
          ...block.footerReferences,
        },
        titlePage: block.titlePage,
      );
      inheritedHeaders = finalSetup.headerReferences;
      inheritedFooters = finalSetup.footerReferences;
      if (block.type == 'continuous' && !block.finalSection) {
        notes.add(
          'Continuous section <sectPr> layout was merged into the current flow.',
        );
        continue;
      }
      if (block.type == 'nextColumn') {
        notes.add(
          'Section break <type nextColumn> was moved to a new page.',
        );
      } else if (block.type == 'oddPage' || block.type == 'evenPage') {
        notes.add(
          'Section break <type ${block.type}> starts on the next available page.',
        );
      }
      if (current.isNotEmpty) {
        result.add(_SectionSegment(List<StyledBlock>.of(current), finalSetup));
      }
      current.clear();
    }
    if (current.isNotEmpty) {
      result.add(_SectionSegment(current, finalSetup));
    } else if (result.isEmpty) {
      result.add(_SectionSegment(const [], finalSetup));
    }
    return result;
  }

  static List<StyledBlock> _selectStory(
    Map<String, List<StyledBlock>> stories,
    Map<String, String> references,
    List<StyledBlock> fallback,
    int pageNumber,
    bool isFirstPage,
    bool titlePage,
    bool evenAndOddHeaders,
  ) {
    final variant = isFirstPage && titlePage
        ? 'first'
        : evenAndOddHeaders && pageNumber.isEven
            ? 'even'
            : 'default';
    final target = references[variant] ?? references['default'];
    if (target != null && stories.containsKey(target)) return stories[target]!;
    if (variant != 'default') {
      final variantTarget = references[variant];
      if (variantTarget != null && stories.containsKey(variantTarget)) {
        return stories[variantTarget]!;
      }
    }
    if (fallback.isNotEmpty) return fallback;
    if (stories.isNotEmpty) return stories.values.first;
    return const [];
  }

  static List<pw.Widget> _buildBlocks(
    List<StyledBlock> blocks,
    _FontFamilies fonts,
    pw.Font unicodeFallback,
    double contentWidth,
    double contentHeight,
    Set<String> notes, {
    bool forceBold = false,
    Map<String, StyledFootnote> footnotes = const {},
  }) {
    final widgets = <pw.Widget>[];
    final listCounters = <String, int>{};
    var drewFootnoteSeparator = false;
    for (final block in blocks) {
      if (block is StyledParagraph) {
        final list = block.listInfo;
        final prefix = list == null ? '' : _listMarker(list, listCounters);
        widgets.add(
          _buildParagraph(
            block,
            fonts,
            unicodeFallback,
            forceBold: forceBold,
            prefix: prefix,
            notes: notes,
            listIndent: (list?.leftIndent ?? 0) > 0 ? list!.leftIndent : null,
          ),
        );
        final referencedNotes = <StyledFootnote>{};
        for (final run in block.runs) {
          final note =
              run.footnoteId == null ? null : footnotes[run.footnoteId];
          if (note != null) referencedNotes.add(note);
        }
        for (final note in referencedNotes) {
          if (!drewFootnoteSeparator) {
            widgets.add(pw.Container(
              width: 36,
              height: 0.6,
              color: pdf.PdfColors.grey700,
              margin: const pw.EdgeInsets.only(top: 3, bottom: 3),
            ));
            drewFootnoteSeparator = true;
          }
          widgets.addAll(_buildBlocks(
            note.blocks,
            fonts,
            unicodeFallback,
            contentWidth,
            contentHeight,
            notes,
          ));
        }
      } else if (block is StyledTable) {
        widgets.add(
          _buildTable(
            block,
            fonts,
            unicodeFallback,
            contentWidth,
            contentHeight,
            notes,
            footnotes,
          ),
        );
      } else if (block is StyledImage) {
        widgets.add(
          _buildImage(block, contentWidth, contentHeight, notes),
        );
      } else if (block is StyledShape) {
        widgets.add(_buildShape(block, notes: notes));
      } else if (block is PageBreak) {
        widgets.add(pw.NewPage());
      } else if (block is SectionBreak &&
          !block.finalSection &&
          block.type != 'continuous') {
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
    double? listIndent,
    int? pageNumber,
    int? pagesCount,
    Set<String>? notes,
  }) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
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
      height: _lineHeight(paragraph, headingSize),
      additionalFallbacks: _fontFallbacks(fonts),
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
      if (run.shape != null) {
        spans.add(pw.WidgetSpan(child: _buildShape(run.shape!, notes: notes)));
        continue;
      }
      if (run.imageBytes != null) {
        try {
          _noteImageLimitations(
            run.imageCrop,
            run.imageRotation,
            run.wrapMode,
            notes,
          );
          final image = _memoryImage(run.imageBytes!, run.imageMime);
          final width = (run.imageWidth ?? 24).clamp(1, 360).toDouble();
          final height = (run.imageHeight ?? 24).clamp(1, 360).toDouble();
          spans.add(pw.WidgetSpan(
            child: pw.Image(image,
                width: width, height: height, fit: pw.BoxFit.contain),
          ));
        } on Object {
          spans.add(
              pw.WidgetSpan(child: _imagePlaceholder(run.imageAlt ?? 'Image')));
        }
        continue;
      }
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
        background: _color(run.background) == null
            ? null
            : pw.BoxDecoration(color: _color(run.background)),
        additionalFallbacks: _fontFallbacks(fonts),
        height: _lineHeight(paragraph, size),
        underline: run.underline,
        strike: run.strike,
      );
      spans.add(
        pw.TextSpan(
          text: _mapLegacySymbolText(run.text, run.fontFamily)
              .replaceAll('{PAGE}', '${pageNumber ?? 1}')
              .replaceAll('{NUMPAGES}', '${pagesCount ?? 1}')
              .replaceAll('{SECTIONPAGES}', '${pagesCount ?? 1}')
              .replaceAll('{DATE}', date),
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
    final isEmptyParagraph =
        paragraph.runs.every((run) => run.text.isEmpty) && prefix.isEmpty;
    if (spans.isEmpty || isEmptyParagraph) {
      return pw.SizedBox(
        height: paragraph.spacingBefore +
            paragraph.spacingAfter +
            _lineHeight(paragraph, fontSize) * fontSize,
      );
    }
    final alignment = switch (paragraph.alignment) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      'justify' => pw.TextAlign.justify,
      _ => pw.TextAlign.left,
    };
    _noteBorderStyles(paragraph.borders, notes);
    final leftIndent =
        math.max(0.0, listIndent ?? paragraph.indentLeft).toDouble();
    final textContent = pw.Padding(
      padding: pw.EdgeInsets.only(
        left: leftIndent,
        right: paragraph.indentRight,
      ),
      child: pw.RichText(
        text: pw.TextSpan(style: baseStyle, children: spans),
        textAlign: alignment,
        softWrap: true,
      ),
    );
    final decorated = paragraph.borders.isEmpty && paragraph.shading == null
        ? textContent
        : pw.Container(
            padding: pw.EdgeInsets.all(paragraph.borderPadding),
            decoration: pw.BoxDecoration(
              color: _color(paragraph.shading),
              border: _paragraphBorder(paragraph.borders),
            ),
            child: textContent,
          );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (paragraph.spacingBefore > 0)
          pw.SizedBox(height: paragraph.spacingBefore),
        decorated,
        if (paragraph.spacingAfter > 0)
          pw.SizedBox(height: paragraph.spacingAfter),
      ],
    );
  }

  static double _lineHeight(StyledParagraph paragraph, double fontSize) {
    final spacing = paragraph.lineSpacing;
    if (spacing == null || spacing <= 0) return 1;
    if (paragraph.lineSpacingRule == 'exact') return spacing / fontSize;
    if (paragraph.lineSpacingRule == 'atLeast') {
      return math.max(1, spacing / fontSize).toDouble();
    }
    return spacing;
  }

  static List<pw.Widget> _buildPagePart(List<StyledBlock> blocks,
          _FontFamilies fonts, pw.Font fallback, int pageNumber, int pagesCount,
          {double contentWidth = 480, double contentHeight = 120}) =>
      [
        for (final block in blocks)
          if (block is StyledParagraph)
            _buildParagraph(block, fonts, fallback,
                pageNumber: pageNumber, pagesCount: pagesCount)
          else if (block is StyledImage)
            _buildImage(block, contentWidth, contentHeight, <String>{})
          else if (block is StyledShape)
            _buildShape(block)
          else if (block is StyledTable)
            _buildTable(
              block,
              fonts,
              fallback,
              contentWidth,
              contentHeight,
              <String>{},
              const {},
            ),
      ];

  static pw.Widget _buildFooter(StyledDocument document, _FontFamilies fonts,
      pw.Font fallback, int pageNumber, int pagesCount,
      {List<StyledBlock>? blocks,
      double contentWidth = 480,
      double contentHeight = 120}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        ..._buildPagePart(
          blocks ?? document.footer,
          fonts,
          fallback,
          pageNumber,
          pagesCount,
          contentWidth: contentWidth,
          contentHeight: contentHeight,
        ),
      ],
    );
  }

  static pw.Widget _buildShape(StyledShape shape, {Set<String>? notes}) {
    if (!const {'rect', 'ellipse', 'rightArrow', 'roundRect', 'line'}
        .contains(shape.geometry)) {
      notes?.add(
        'Unsupported shape geometry <${shape.geometry}> was drawn as a rectangle.',
      );
    }
    final borderSide = pw.BorderSide(
      color: _color(shape.outline) ?? pdf.PdfColors.black,
      width: shape.outlineWidth,
    );
    final decoration = switch (shape.geometry) {
      'ellipse' => pw.BoxDecoration(
          color: _color(shape.fill),
          shape: pw.BoxShape.circle,
          border: pw.Border.fromBorderSide(borderSide),
        ),
      'roundRect' => pw.BoxDecoration(
          color: _color(shape.fill),
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.fromBorderSide(borderSide),
        ),
      'line' => pw.BoxDecoration(
          border: pw.Border(bottom: borderSide),
        ),
      _ => pw.BoxDecoration(
          color: _color(shape.fill),
          border: pw.Border.fromBorderSide(borderSide),
        ),
    };
    return pw.Container(
      width: shape.width,
      height: shape.height,
      margin: const pw.EdgeInsets.symmetric(vertical: 3),
      decoration: decoration,
      alignment: pw.Alignment.center,
      child: shape.geometry == 'rightArrow'
          ? pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              if (shape.text.isNotEmpty) pw.Text(shape.text),
              pw.Text('➜', style: const pw.TextStyle(fontSize: 16)),
            ])
          : (shape.text.isEmpty ? null : pw.Text(shape.text)),
    );
  }

  static pw.Border? _paragraphBorder(Map<String, String> borders) {
    if (borders.isEmpty) return null;
    return pw.Border(
      left: _borderSide(borders['left']),
      top: _borderSide(borders['top']),
      right: _borderSide(borders['right']),
      bottom: _borderSide(borders['bottom']),
    );
  }

  static void _noteBorderStyles(
    Map<String, String> borders,
    Set<String>? notes,
  ) {
    for (final value in borders.values) {
      final match = RegExp(r'pt\s+([a-zA-Z]+)\s+').firstMatch(value);
      if (match == null) continue;
      final kind = match.group(1)!.toLowerCase();
      if (kind == 'double' || kind == 'wave' || kind == 'triple') {
        notes?.add('Border <val $kind> was approximated with a solid line.');
      }
    }
  }

  static pw.Widget _buildTable(
    StyledTable table,
    _FontFamilies fonts,
    pw.Font unicodeFallback,
    double contentWidth,
    double contentHeight,
    Set<String> notes,
    Map<String, StyledFootnote> footnotes,
  ) {
    if (table.rows.isEmpty) return pw.SizedBox();
    _noteBorderStyles(table.borders, notes);
    for (final row in table.rows) {
      for (final cell in row.cells) {
        _noteBorderStyles(cell.borders, notes);
      }
    }
    var columnCount = 0;
    for (final row in table.rows) {
      final rowColumns = row.cells.fold<int>(
        0,
        (count, cell) => count + (cell.gridSpan < 1 ? 1 : cell.gridSpan),
      );
      if (rowColumns > columnCount) columnCount = rowColumns;
    }
    if (columnCount == 0) return pw.SizedBox();
    if (table.rows.any((row) => row.cells.any((cell) => cell.gridSpan > 1))) {
      notes.add(
          'Table cells with <gridSpan> keep text but cannot span columns.');
    }
    final tableWidth = table.width == null
        ? contentWidth
        : (table.widthType == 'pct'
                ? contentWidth * table.width! / 100
                : table.width!)
            .clamp(1, contentWidth)
            .toDouble();
    final widths = <int, pw.TableColumnWidth>{};
    if (table.columnWidths.isNotEmpty) {
      final grid = List<double>.generate(
        columnCount,
        (index) =>
            index < table.columnWidths.length ? table.columnWidths[index] : 0,
      );
      final gridTotal = grid.fold<double>(0, (sum, width) => sum + width);
      if (gridTotal > 0) {
        for (var index = 0; index < columnCount; index++) {
          if (grid[index] > 0) {
            widths[index] = pw.FixedColumnWidth(
              tableWidth * grid[index] / gridTotal,
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
          tableWidth,
          contentHeight,
          notes,
          forceBold: row.isHeader,
          rowHeight: row.height,
          footnotes: footnotes,
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
    final renderedTable = pw.Table(
      children: rows,
      columnWidths: widths,
      defaultColumnWidth: const pw.FlexColumnWidth(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      border: _tableBorder(table.borders),
      tableWidth: pw.TableWidth.max,
    );
    return pw.SizedBox(width: tableWidth, child: renderedTable);
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
    double? rowHeight,
    Map<String, StyledFootnote> footnotes = const {},
  }) {
    final borderMap =
        cell.borders.isEmpty ? const <String, String>{} : cell.borders;
    final fill = _color(
        cell.shading ?? (cell.vMerge == 'continue' ? null : table.shading));
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
              footnotes: footnotes,
            ),
          );
    return pw.Container(
      constraints:
          rowHeight == null ? null : pw.BoxConstraints(minHeight: rowHeight),
      padding: pw.EdgeInsets.fromLTRB(
        cell.marginLeft ?? 4,
        cell.marginTop ?? 4,
        cell.marginRight ?? 4,
        cell.marginBottom ?? 4,
      ),
      decoration: pw.BoxDecoration(
        color: fill,
        border: borderMap.isEmpty ? null : _cellBorder(borderMap),
      ),
      alignment: switch (cell.verticalAlignment) {
        'center' => pw.Alignment.center,
        'bottom' => pw.Alignment.bottomCenter,
        _ => pw.Alignment.topLeft,
      },
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
      _noteImageLimitations(image.crop, image.rotation, image.wrapMode, notes);
      if (!image.mime.startsWith('image/')) {
        notes.add(
            'Unsupported image element <${image.mime}>; kept an image marker.');
        return _imagePlaceholder(image.alt);
      }
      final provider = _memoryImage(image.bytes, image.mime);
      final originalWidth =
          image.width ?? provider.width?.toDouble() ?? contentWidth;
      final originalHeight =
          image.height ?? provider.height?.toDouble() ?? contentHeight;
      final scale = math
          .min(
            1.0,
            math.min(
                contentWidth / originalWidth, contentHeight / originalHeight),
          )
          .toDouble();
      final width = originalWidth * scale;
      final height = originalHeight * scale;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Align(
          alignment: image.position == 'floating'
              ? pw.Alignment.centerRight
              : pw.Alignment.center,
          child: pw.Image(
            provider,
            width: width,
            height: height,
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    } on Object {
      notes.add(
          'Unsupported or malformed image element <image>; kept an image marker.');
      return _imagePlaceholder(image.alt);
    }
  }

  static pw.Widget _imagePlaceholder(String alt) => pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: pdf.PdfColors.grey600, width: 0.5),
        ),
        child: pw.Text(alt.isEmpty ? '[image]' : alt),
      );

  static void _noteImageLimitations(
    Map<String, double> crop,
    double rotation,
    String wrapMode,
    Set<String>? notes,
  ) {
    if (crop.values.any((value) => value != 0)) {
      notes?.add('Image <srcRect> cropping was not applied.');
    }
    if (rotation != 0) notes?.add('Image <xfrm rot> was not applied.');
    if (wrapMode != 'inline' && wrapMode != 'wrapNone') {
      notes?.add(
          'Image <$wrapMode> position was approximated without text wrap.');
    }
  }

  static pw.MemoryImage _memoryImage(Uint8List bytes, String? mime) {
    if (mime == 'image/png' || mime == 'image/jpeg') {
      return pw.MemoryImage(bytes);
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw UnsupportedError('No offline decoder for image MIME type $mime');
    }
    // Convert formats supported by the bundled image package into PDF-safe PNG.
    return pw.MemoryImage(Uint8List.fromList(img.encodePng(decoded)));
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
    if (value == 'none') return pw.BorderSide.none;
    final match = RegExp(r'([\d.]+)pt\s+([a-zA-Z]+)\s+(#[0-9a-fA-F]{6})')
        .firstMatch(value);
    if (match == null) return pw.BorderSide.none;
    return pw.BorderSide(
      width: double.tryParse(match.group(1)!) ?? 0.5,
      style: switch (match.group(2)!.toLowerCase()) {
        'dot' || 'dotted' => pw.BorderStyle.dotted,
        'dash' || 'dashed' => pw.BorderStyle.dashed,
        _ => pw.BorderStyle.solid,
      },
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
    pw.BoxDecoration? background,
    List<pw.Font> additionalFallbacks = const [],
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
      background: background,
      // Keep the bundled math font first, then retry glyphs in the selected family.
      fontFallback: [unicodeFallback, font.regular, ...additionalFallbacks],
      decoration: decorations.isEmpty
          ? pw.TextDecoration.none
          : pw.TextDecoration.combine(decorations),
    );
  }

  static List<pw.Font> _fontFallbacks(_FontFamilies fonts) => [
        fonts.sans.regular,
        fonts.serif.regular,
        fonts.mono.regular,
        fonts.carlito.regular,
        ...fonts.symbols,
      ];

  static String _listMarker(
    StyledListInfo list,
    Map<String, int> counters,
  ) {
    if (list.format == 'bullet') {
      final marker = list.marker.isEmpty ? '•' : list.marker;
      return '${_mapLegacySymbolText(marker, list.markerFontFamily)} ';
    }
    final key = '${list.id}:${list.level}';
    final number = (counters[key] ?? (list.start - 1)) + 1;
    counters[key] = number;
    var formatted = _formatNumber(number, list.format);
    final marker = list.marker.isEmpty ? '%1.' : list.marker;
    final result = marker.replaceAll('%${list.level + 1}', formatted);
    return result.contains('%') ? '$formatted. ' : '$result ';
  }

  static String _mapLegacySymbolText(String text, String? fontFamily) {
    final font = (fontFamily ?? '').toLowerCase().replaceAll(' ', '');
    final mapping = switch (font) {
      'wingdings' => const <int, int>{
          0xf028: 0x260e,
          0xf02a: 0x2709,
          0xf0a7: 0x25aa,
          0xf0ab: 0x2605,
          0xf0ef: 0x21e6,
          0xf0f0: 0x21e8,
          0xf0f1: 0x21e7,
          0xf0f2: 0x21e9,
          0xf0fb: 0x2717,
          0xf0fc: 0x2713,
          0xf0fd: 0x2612,
          0xf0fe: 0x2611,
        },
      'wingdings2' => const <int, int>{
          0xf050: 0x1f4cb,
          0xf052: 0x2611,
          0xf054: 0x2612,
        },
      'wingdings3' => const <int, int>{
          0xf021: 0x2b60,
          0xf022: 0x2b62,
          0xf023: 0x2b61,
          0xf024: 0x2b63,
        },
      'webdings' => const <int, int>{
          0xf028: 0x260e,
          0xf02a: 0x2709,
          0xf061: 0x2714,
        },
      _ => const <int, int>{},
    };
    if (mapping.isEmpty) return text;
    return String.fromCharCodes(text.runes.map((codePoint) {
      final privateUseCode = codePoint >= 0x20 && codePoint <= 0xff
          ? codePoint + 0xf000
          : codePoint;
      return mapping[codePoint] ?? mapping[privateUseCode] ?? codePoint;
    }));
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
    if (family.contains('times') ||
        family.contains('serif') ||
        family.contains('georgia') ||
        family.contains('cambria') ||
        family.contains('garamond') ||
        family.contains('palatino') ||
        family.contains('baskerville')) return fonts.serif;
    if (family.contains('courier') ||
        family.contains('mono') ||
        family.contains('consolas') ||
        family.contains('menlo') ||
        family.contains('monaco')) return fonts.mono;
    if (family.contains('calibri') || family.contains('carlito'))
      return fonts.carlito;
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
      symbols: [
        await _loadFont(
          'assets/docx_render/fonts/NotoSansSymbols2-Regular.ttf',
        ),
        await _loadFont(
          'assets/docx_render/fonts/NotoSansSymbols-Regular.ttf',
        ),
      ],
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
  final List<pw.Font> symbols;

  const _FontFamilies({
    required this.sans,
    required this.serif,
    required this.mono,
    required this.carlito,
    required this.symbols,
  });
}

class _SectionSegment {
  final List<StyledBlock> blocks;
  final SectionBreak? setup;

  const _SectionSegment(this.blocks, this.setup);
}
