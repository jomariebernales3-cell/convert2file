import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FontDiagnostic {
  int count = 0;
  final List<String> samples = <String>[];

  void add(String text) {
    count++;
    final sample = text.trim();
    if (sample.isNotEmpty && samples.length < 3) samples.add(sample);
  }
}

void _logFontDiagnostics(String level, Map<String, _FontDiagnostic> stats) {
  for (final entry in stats.entries) {
    debugPrint('[PdfFonts] $level ${entry.key} count=${entry.value.count} samples=${entry.value.samples.join(' | ')}');
  }
}

class PdfTextWordData {
  final String text;
  final double left, top, width, height, fontSize;
  final String fontName;
  bool bold, italic, underline;

  PdfTextWordData({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.fontName,
    required this.bold,
    required this.italic,
    required this.underline,
  });
}

class PdfTextLineData {
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  final double fontSize;
  final String fontName;
  final bool bold;
  final bool italic;
  final List<PdfTextWordData> words;

  const PdfTextLineData({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.fontName,
    required this.bold,
    required this.italic,
    this.words = const [],
  });
}

class PdfTextPageData {
  final int pageNumber;
  final double width;
  final double height;
  final List<PdfTextLineData> lines;

  const PdfTextPageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.lines,
  });
}

class PdfTextReadResult {
  final List<PdfTextPageData> pages;
  final List<String> notes;

  const PdfTextReadResult(this.pages, this.notes);
}

class PdfTextReader {
  static Future<PdfTextReadResult> read(
    String sourcePath, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final pages = <PdfTextPageData>[];
    final notes = <String>{};
    try {
      onProgress?.call(0, 'Reading text');
      for (var pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
        final lineFontStats = <String, _FontDiagnostic>{};
        final wordFontStats = <String, _FontDiagnostic>{};
        final glyphFontStats = <String, _FontDiagnostic>{};
        final rawFontNames = <String>{};
        var width = 595.28;
        var height = 841.89;
        try {
          final size = document.pages[pageIndex].size;
          if (size.width.isFinite && size.width > 0) width = size.width;
          if (size.height.isFinite && size.height > 0) height = size.height;
        } on Object {
          notes.add('Some PDF page sizes were simplified.');
        }

        final lines = <PdfTextLineData>[];
        try {
          final extracted = PdfTextExtractor(document).extractTextLines(
            startPageIndex: pageIndex,
            endPageIndex: pageIndex,
          );
          for (final line in extracted) {
            try {
              final text = line.text;
              if (text.isEmpty) continue;
              final lineFont = line.fontName;
              final lineStyle = line.fontStyle.join(',');
              lineFontStats.putIfAbsent('$lineFont | $lineStyle | ${line.fontSize}', _FontDiagnostic.new).add(text);
              rawFontNames.add(lineFont);
              final bounds = line.bounds;
              double safe(double value) => value.isFinite ? value : 0;
              final words = <PdfTextWordData>[];
              for (final word in line.wordCollection) {
                try {
                  final wordBounds = word.bounds;
                  final style = word.fontStyle;
                  final wordFont = word.fontName;
                  final wordStyle = style.join(',');
                  wordFontStats.putIfAbsent('$wordFont | $wordStyle | ${word.fontSize}', _FontDiagnostic.new).add(word.text);
                  rawFontNames.add(wordFont);
                  for (final glyph in word.glyphs) {
                    final glyphStyle = glyph.fontStyle.join(',');
                    glyphFontStats.putIfAbsent('${glyph.fontName} | $glyphStyle | ${glyph.fontSize}', _FontDiagnostic.new).add(glyph.text);
                    rawFontNames.add(glyph.fontName);
                  }
                  words.add(PdfTextWordData(
                    text: word.text,
                    left: safe(wordBounds.left),
                    top: safe(wordBounds.top),
                    width: safe(wordBounds.width).clamp(0, width).toDouble(),
                    height: safe(wordBounds.height).clamp(0, height).toDouble(),
                    fontSize: word.fontSize.isFinite && word.fontSize > 0
                        ? word.fontSize
                        : safe(wordBounds.height),
                    fontName: cleanPdfFontName(word.fontName),
                    bold: style.contains(PdfFontStyle.bold),
                    italic: style.contains(PdfFontStyle.italic),
                    underline: style.contains(PdfFontStyle.underline),
                  ));
                } on Object {
                  notes.add('Some PDF text words were simplified.');
                }
              }
              lines.add(
                PdfTextLineData(
                  text: text,
                  left: safe(bounds.left),
                  top: safe(bounds.top),
                  width: safe(bounds.width).clamp(0, width).toDouble(),
                  height: safe(bounds.height).clamp(0, height).toDouble(),
                  fontSize: line.fontSize.isFinite && line.fontSize > 0
                      ? line.fontSize
                      : safe(bounds.height),
                  fontName: cleanPdfFontName(line.fontName),
                  bold: line.fontStyle.contains(PdfFontStyle.bold),
                  italic: line.fontStyle.contains(PdfFontStyle.italic),
                  words: words,
                ),
              );
            } on Object {
              notes.add('Some PDF text lines were skipped.');
            }
          }
        } on Object {
          notes.add('Some PDF page text could not be extracted.');
        }
        lines.sort((a, b) {
          final byTop = a.top.compareTo(b.top);
          return byTop == 0 ? a.left.compareTo(b.left) : byTop;
        });
        _logFontDiagnostics('page=${pageIndex + 1} TextLine', lineFontStats);
        _logFontDiagnostics('page=${pageIndex + 1} TextWord', wordFontStats);
        _logFontDiagnostics('page=${pageIndex + 1} TextGlyph', glyphFontStats);
        if (pageIndex == 0) {
          debugPrint('[PdfFonts] page=1 raw extracted font names=${rawFontNames.join(' | ')}');
          debugPrint('[PdfFonts] page=1 raw PDF font-resource enumeration is not exposed by the public Syncfusion API.');
        }
        pages.add(
          PdfTextPageData(
            pageNumber: pageIndex + 1,
            width: width,
            height: height,
            lines: lines,
          ),
        );
        final pageCount = document.pages.count;
        onProgress?.call(
          pageCount == 0 ? 0.15 : 0.15 * ((pageIndex + 1) / pageCount),
          'Reading text on page ${pageIndex + 1} of $pageCount',
        );
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      document.dispose();
    }
    return PdfTextReadResult(pages, notes.toList());
  }

  static List<List<PdfTextLineData>> groupParagraphs(
    List<PdfTextLineData> lines,
  ) {
    if (lines.isEmpty) return const [];
    final ordered = List<PdfTextLineData>.from(lines)
      ..sort((a, b) {
        final byTop = a.top.compareTo(b.top);
        return byTop == 0 ? a.left.compareTo(b.left) : byTop;
      });
    final paragraphs = <List<PdfTextLineData>>[];
    var current = <PdfTextLineData>[ordered.first];
    for (final line in ordered.skip(1)) {
      final previous = current.last;
      final codeLine = RegExp(r'consolas|courier|mono', caseSensitive: false)
          .hasMatch(line.fontName);
      final previousCodeLine = RegExp(r'consolas|courier|mono', caseSensitive: false)
          .hasMatch(previous.fontName);
      if (codeLine || previousCodeLine) {
        paragraphs.add(current);
        current = <PdfTextLineData>[line];
        continue;
      }
      final gap = line.top - (previous.top + previous.height);
      final lineHeight = previous.height > line.height
          ? previous.height
          : line.height;
      final sameLeft = (line.left - previous.left).abs() <=
          (lineHeight * 0.55).clamp(4, 8);
      final sameSize = previous.fontSize <= 0 || line.fontSize <= 0 ||
          (line.fontSize - previous.fontSize).abs() <=
              math.max(2.0, previous.fontSize * 0.28);
      final normalPitch = (line.top - previous.top).abs() <=
          (lineHeight * 1.75).clamp(10, 24);
      double? valueColumn;
      for (final blockLine in current) {
        for (var i = 0; i + 1 < blockLine.words.length; i++) {
          if (const {'TO:', 'SUBJECT:', 'FROM:', 'DATE:'}
              .contains(blockLine.words[i].text.trim().toUpperCase())) {
            valueColumn = blockLine.words[i + 1].left;
            break;
          }
        }
        if (valueColumn != null) break;
      }
      final isLabelContinuation = valueColumn != null &&
          (line.left - valueColumn).abs() <= 10 &&
          gap <= (lineHeight * 1.4).clamp(10, 20);
      if ((gap <= (lineHeight * 0.5).clamp(3, 7) &&
          sameLeft &&
          sameSize &&
          normalPitch) || isLabelContinuation) {
        current.add(line);
      } else {
        paragraphs.add(current);
        current = <PdfTextLineData>[line];
      }
    }
    paragraphs.add(current);
    return paragraphs;
  }

  static String paragraphText(List<PdfTextLineData> lines) {
    final result = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      if (index > 0 && !lines[index - 1].text.endsWith('-')) {
        result.write(' ');
      }
      result.write(lines[index].text);
    }
    return result.toString();
  }

  static String cleanPdfFontName(String value) {
    var family = value.trim().replaceFirst(RegExp(r'^[A-Z]{6}\+'), '');
    family = family.replaceAll(
      RegExp(
        r'[-, ]?(?:bolditalic|italicbold|semibold|boldmt|italicmt|demi|heavy|black|oblique|bold|italic|regular|mt)$',
        caseSensitive: false,
      ),
      '',
    );
    return family.trim().isEmpty ? 'Arial' : family.trim();
  }

  static bool _fontNameIsBold(String value) =>
      RegExp(r'bold|black|heavy|semibold|demi', caseSensitive: false)
          .hasMatch(value);

  static bool _fontNameIsItalic(String value) =>
      RegExp(r'italic|oblique', caseSensitive: false).hasMatch(value);
}
