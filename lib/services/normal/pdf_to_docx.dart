import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import 'pdf_text_reader.dart';
import 'pdf_graphics_extractor.dart';
import 'pdf_table_detector.dart';

class PdfToDocxCancelled implements Exception {
  const PdfToDocxCancelled();
}

class _PageXmlElement {
  final double top;
  final String xml;
  final bool isTable;
  const _PageXmlElement(this.top, this.xml, this.isTable);
}

class PdfToDocx {
  static const note =
      'Best effort. Tables, columns and images may not match the PDF.';

  static Future<List<String>> convert(
    String sourcePath,
    String outputPath,
    {void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,}
  ) async {
    Future<void> report(double progress, String message) async {
      if (isCancelled?.call() == true) throw const PdfToDocxCancelled();
      onProgress?.call(progress.clamp(0, 1).toDouble(), message);
      await Future<void>.delayed(Duration.zero);
    }
    final textWatch = Stopwatch()..start();
    var bytes = Uint8List(0);
    var extraction = const PdfTextReadResult(<PdfTextPageData>[], <String>[]);
    final notes = <String>{note};
    try {
      await report(0, 'Reading text');
      bytes = await File(sourcePath).readAsBytes();
      extraction = await PdfTextReader.read(
        sourcePath,
        onProgress: (progress, message) {
          if (isCancelled?.call() == true) throw const PdfToDocxCancelled();
          onProgress?.call(progress, message);
        },
      );
      await report(0.15, 'Text extraction complete');
      notes.addAll(extraction.notes);
      final lines = extraction.pages.fold<int>(0, (sum, page) => sum + page.lines.length);
      final words = extraction.pages.fold<int>(0,
          (sum, page) => sum + page.lines.fold<int>(0, (n, line) => n + line.words.length));
      debugPrint('[PdfToDocx] text extraction pages=${extraction.pages.length} lines=$lines words=$words ms=${textWatch.elapsedMilliseconds}');
    } on Object catch (error, stackTrace) {
      if (error is PdfToDocxCancelled) rethrow;
      notes.add('Text extraction failed.');
      debugPrint('[PdfToDocx] text extraction failed: $error\n$stackTrace');
    }
    final firstPage = extraction.pages.isEmpty ? null : extraction.pages.first;
    final pageWidth = firstPage?.width ?? 595.28;
    final pageHeight = firstPage?.height ?? 841.89;
    if (extraction.pages.any((page) =>
        (page.width - pageWidth).abs() > 0.5 ||
        (page.height - pageHeight).abs() > 0.5)) {
      notes.add('Some PDF page sizes were simplified.');
    }
    final storedImages = <String, Uint8List>{};
    final imageRelationships = <String>[];
    final storyParts = <String, String>{};
    final storyRelationships = <String, String>{};
    final storyDocRelationships = <String>[];
    final storyContentTypes = <String>[];
    final headerIds = <int, String>{};
    final footerIds = <int, String>{};
    var sharedHeaderWritten = false;
    var sharedFooterWritten = false;
    final body = StringBuffer();
    final bodySize = _bodyFontSize(
      extraction.pages.expand((page) => page.lines).toList(),
    );
    var imageId = 0;

    final pageCount = extraction.pages.length;
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final page = extraction.pages[pageIndex];
      final pageStart = 0.15 + 0.70 * (pageIndex / math.max(1, pageCount));
      await report(pageStart, 'Converting page ${pageIndex + 1} of $pageCount');
      var pageContentAdded = false;
      var headerBandLines = <PdfTextLineData>[];
      var footerBandLines = <PdfTextLineData>[];
      final repeatedHeader = _isRepeatedBand(extraction.pages, page, header: true);
      final repeatedFooter = _isRepeatedBand(extraction.pages, page, header: false);
      if (page.lines.isEmpty) {
        try {
          final raster = await Printing.raster(
            bytes,
            pages: [page.pageNumber - 1],
            dpi: 120,
          ).first;
          final png = await raster.toPng();
          imageId++;
          final mediaName = 'page_${page.pageNumber}.png';
          final relationshipId = 'rId${imageId + 2}';
          storedImages['word/media/$mediaName'] = png;
          imageRelationships.add(
            '<Relationship Id="$relationshipId" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
            'Target="media/$mediaName"/>',
          );
          body.write(
            _imageParagraph(
              relationshipId,
              imageId,
              page.width,
              page.height,
              raster.width,
              raster.height,
            ),
          );
          pageContentAdded = true;
        } on Object catch (error, stackTrace) {
          notes.add('Some scanned PDF pages were skipped.');
          debugPrint('[PdfToDocx] scanned-page image page=${page.pageNumber} failed: $error\n$stackTrace');
        }
      } else {
        headerBandLines = page.lines
            .where((line) => line.top + line.height <= page.height * 0.2)
            .toList();
        footerBandLines = page.lines
            .where((line) => line.top >= page.height * 0.8)
            .toList();
        final allBodyLines = page.lines
        .where((line) =>
                !headerBandLines.contains(line) && !footerBandLines.contains(line))
            .toList();
        var detectedTables = <PdfDetectedTable>[];
        List<PdfGraphicRegion> imageRegions = const <PdfGraphicRegion>[];
        List<PdfGraphicRegion> decorationRegions = const <PdfGraphicRegion>[];
        Uint8List? pagePng;
        final graphicWords = page.lines.expand((line) => line.words).toList();
        final imageWatch = Stopwatch()..start();
        try {
          final raster = await Printing.raster(
            bytes,
            pages: [page.pageNumber - 1],
            dpi: 200,
          ).first;
          pagePng = Uint8List.fromList(await raster.toPng());
          await report(pageStart + 0.18 / math.max(1, pageCount),
              'Rendered page ${pageIndex + 1} of $pageCount');
          await report(pageStart + 0.25 / math.max(1, pageCount),
              'Detecting tables on page ${pageIndex + 1} of $pageCount');
          try {
            detectedTables = await PdfTableDetector.detect(
              pagePng: pagePng!,
              pageWidth: page.width,
              pageHeight: page.height,
            );
            if (detectedTables.isEmpty) {
              notes.add('No tables detected on page ${page.pageNumber}; using paragraph layout.');
            }
          } on Object catch (error, stackTrace) {
            detectedTables = <PdfDetectedTable>[];
            notes.add('Table detection failed on page ${page.pageNumber}; using paragraph layout.');
            debugPrint('[PdfToDocx] table detection page=${page.pageNumber} failed: $error\n$stackTrace');
          }
          await report(pageStart + 0.35 / math.max(1, pageCount),
              'Detecting tables on page ${pageIndex + 1} of $pageCount');
          await report(pageStart + 0.40 / math.max(1, pageCount),
              'Detecting images on page ${pageIndex + 1} of $pageCount');
          imageRegions = await PdfGraphicsExtractor.extract(
            pagePng: pagePng,
            pageWidth: page.width,
            pageHeight: page.height,
            words: graphicWords,
            includeImages: true,
            includeRules: false,
            includeUnderline: false,
          );
          imageRegions.removeWhere((region) => _overlapsAnyTable(region, detectedTables));
          debugPrint('[PdfToDocx] image/bands page=${page.pageNumber} images=${imageRegions.where((r) => r.kind == 'image').length} headerFooter=${imageRegions.where((r) => r.kind == 'headerBand' || r.kind == 'footerBand').length} ms=${imageWatch.elapsedMilliseconds}');
        } on Object catch (error, stackTrace) {
          if (error is PdfToDocxCancelled) rethrow;
          notes.add('Image detection failed on page ${page.pageNumber}.');
          debugPrint('[PdfToDocx] image/bands page=${page.pageNumber} failed: $error\n$stackTrace');
        }
        await report(pageStart + 0.52 / math.max(1, pageCount),
            'Detecting images on page ${pageIndex + 1} of $pageCount');
        final ruleWatch = Stopwatch()..start();
        try {
          await report(pageStart + 0.54 / math.max(1, pageCount),
              'Detecting rules on page ${pageIndex + 1} of $pageCount');
          if (pagePng != null) {
            decorationRegions = await PdfGraphicsExtractor.extract(
              pagePng: pagePng,
              pageWidth: page.width,
              pageHeight: page.height,
              words: graphicWords,
              includeImages: false,
              includeRules: true,
              includeUnderline: true,
            );
          } else {
            throw StateError('Page render unavailable');
          }
          final rules = decorationRegions.where((r) => r.kind == 'rule').length;
          decorationRegions.removeWhere((region) => _overlapsAnyTable(region, detectedTables));
          final underlines = graphicWords.where((word) => word.underline).length;
          debugPrint('[PdfToDocx] rules/underline page=${page.pageNumber} rules=$rules underlines=$underlines ms=${ruleWatch.elapsedMilliseconds}');
        } on Object catch (error, stackTrace) {
          if (error is PdfToDocxCancelled) rethrow;
          notes.add('Rule/underline detection failed on page ${page.pageNumber}.');
          debugPrint('[PdfToDocx] rules/underline page=${page.pageNumber} failed: $error\n$stackTrace');
        }
        await report(pageStart + 0.60 / math.max(1, pageCount),
            'Detecting rules on page ${pageIndex + 1} of $pageCount');
        var bodyLines = _removeTableText(allBodyLines, detectedTables);
        await report(pageStart + 0.70 / math.max(1, pageCount),
            'Building XML for page ${pageIndex + 1} of $pageCount');
        final tableMarkup = <PdfDetectedTable, String>{};
        try {
          final pageLeftMargin = allBodyLines.isEmpty
              ? 36.0
              : allBodyLines.map((line) => line.left).reduce((a, b) => a < b ? a : b);
          for (final table in detectedTables) {
            tableMarkup[table] = _tableXml(
              table,
              page.lines,
              bodySize,
              page.width,
              pageLeftMargin,
            );
          }
        } on Object catch (error, stackTrace) {
          notes.add('Table writing failed on page ${page.pageNumber}; using paragraph layout.');
          debugPrint('[PdfToDocx] table XML page=${page.pageNumber} failed: $error\n$stackTrace');
          detectedTables = <PdfDetectedTable>[];
          tableMarkup.clear();
          bodyLines = allBodyLines;
        }
        for (final table in detectedTables) {
          imageRegions.removeWhere((region) => _overlapsTable(region, table));
          decorationRegions.removeWhere((region) => _overlapsTable(region, table));
        }
        final styleWatch = Stopwatch()..start();
        try {
          final bold = graphicWords.where((word) => word.bold).length;
          final italic = graphicWords.where((word) => word.italic).length;
          debugPrint('[PdfToDocx] font styles page=${page.pageNumber} boldWords=$bold italicWords=$italic ms=${styleWatch.elapsedMilliseconds}');
        } on Object catch (error, stackTrace) {
          notes.add('Bold/italic detection failed on page ${page.pageNumber}.');
          debugPrint('[PdfToDocx] bold/italic page=${page.pageNumber} failed: $error\n$stackTrace');
        }
        final regions = <PdfGraphicRegion>[...imageRegions, ...decorationRegions];
        final paragraphs = PdfTextReader.groupParagraphs(bodyLines);
        final pageParagraphXml = <String>[];
        final orderedBody = List<PdfTextLineData>.from(bodyLines)
          ..sort((a, b) => a.top.compareTo(b.top));
        var runningY = orderedBody.isEmpty
            ? 36.0
            : math.max(36.0, orderedBody.first.top).toDouble();
        var pageBodyFlushed = false;
        void flushPageBody() {
          if (pageBodyFlushed) return;
          final pageElements = <_PageXmlElement>[];
          for (var i = 0; i < pageParagraphXml.length; i++) {
            final top = i < paragraphs.length ? paragraphs[i].first.top : 0.0;
            pageElements.add(_PageXmlElement(top, pageParagraphXml[i], false));
          }
          for (final entry in tableMarkup.entries) {
            pageElements.add(_PageXmlElement(entry.key.top, entry.value, true));
          }
          pageElements.sort((a, b) => a.top.compareTo(b.top));
          for (var i = 0; i < pageElements.length; i++) {
            if (i > 0 && pageElements[i - 1].isTable && pageElements[i].isTable) {
              body.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>');
            }
            body.write(pageElements[i].xml);
          }
          pageBodyFlushed = true;
        }
        for (var paragraphIndex = 0;
            paragraphIndex < paragraphs.length;
            paragraphIndex++) {
          final paragraph = paragraphs[paragraphIndex];
          try {
            final firstText = paragraph.first.text;
            final list = _detectList(firstText);
            final spacingBefore = math.max(0.0, paragraph.first.top - runningY).toDouble();
            final paragraphPitch = paragraph.length > 1
                ? (paragraph[1].top - paragraph[0].top).abs()
                : paragraph.first.fontSize * 1.2;
            final paragraphLineHeight = math.max(
              paragraph.map((line) => math.max(line.height, line.fontSize))
                  .reduce((a, b) => a > b ? a : b),
              paragraphPitch,
            ).toDouble();
            final textAreaLines = bodyLines.isEmpty ? page.lines : bodyLines;
            final leftMargin = textAreaLines.isEmpty
                ? 0.0
                : textAreaLines.map((line) => line.left).reduce(
                    (a, b) => a < b ? a : b,
                  );
            final rightEdge = textAreaLines.isEmpty
                ? page.width
                : textAreaLines
                    .map((line) => line.left + line.width)
                    .reduce((a, b) => a > b ? a : b);
            pageParagraphXml.add(_paragraphXml(
              paragraph,
              list,
              list?.numId,
              bodySize,
              spacingBefore: spacingBefore,
              leftMargin: leftMargin,
              rightEdge: rightEdge,
              pageWidth: page.width,
              graphics: regions,
            ));
            runningY += spacingBefore + paragraphLineHeight * paragraph.length;
            pageContentAdded = true;
          } on Object catch (error, stackTrace) {
            notes.add('Some PDF text paragraphs were skipped.');
            debugPrint('[PdfToDocx] text paragraph page=${page.pageNumber} failed: $error\n$stackTrace');
          }
        }
        await report(pageStart + 0.82 / math.max(1, pageCount),
            'Built XML for page ${pageIndex + 1} of $pageCount');
        try {
          final headerDrawing = StringBuffer();
          final footerDrawing = StringBuffer();
          final headerPartRels = <String>[];
          final footerPartRels = <String>[];
          var headerImageIndex = 0;
          var footerImageIndex = 0;
          for (final region in imageRegions) {
            if (region.kind == 'rule' || region.kind == 'underline' || region.png.isEmpty) {
              continue;
            }
            imageId++;
            final mediaName = 'region_${page.pageNumber}_$imageId.png';
            storedImages['word/media/$mediaName'] = region.png;
            if (region.kind == 'headerBand') {
              headerImageIndex++;
              final relationshipId = 'rId$headerImageIndex';
              headerPartRels.add(_imageRelationship(relationshipId, mediaName));
              headerDrawing.write(_anchoredGraphic(
                relationshipId, imageId, region.left, region.top,
                region.width, region.height, region.kind,
              ));
            } else if (region.kind == 'footerBand') {
              footerImageIndex++;
              final relationshipId = 'rId$footerImageIndex';
              footerPartRels.add(_imageRelationship(relationshipId, mediaName));
              footerDrawing.write(_anchoredGraphic(
                relationshipId, imageId, region.left, region.top,
                region.width, region.height, region.kind,
              ));
            } else {
              final relationshipId = 'rId${imageId + 2}';
              imageRelationships.add(_imageRelationship(relationshipId, mediaName));
              final ownerIndex = _nearestParagraphIndex(paragraphs, region.top);
              if (ownerIndex >= 0 && ownerIndex < pageParagraphXml.length) {
                final offset = region.top - paragraphs[ownerIndex].first.top;
                final anchor = _anchoredGraphic(
                relationshipId, imageId, region.left, region.top,
                region.width, region.height, region.kind,
                paragraphRelative: true,
                verticalOffset: offset,
                embeddedInParagraph: true,
              );
                pageParagraphXml[ownerIndex] = pageParagraphXml[ownerIndex]
                    .replaceFirst('</w:p>', '$anchor</w:p>');
              } else {
                body.write(_anchoredGraphic(
                  relationshipId, imageId, region.left, region.top,
                  region.width, region.height, region.kind,
                ));
              }
            }
            pageContentAdded = true;
          }
          flushPageBody();
          for (final paragraph in PdfTextReader.groupParagraphs(headerBandLines)) {
            var xml = _paragraphXml(paragraph, null, null, bodySize,
                pageWidth: page.width, graphics: regions);
            if (repeatedHeader) xml = _addPageField(xml);
            headerDrawing.write(xml);
          }
          for (final paragraph in PdfTextReader.groupParagraphs(footerBandLines)) {
            var xml = _paragraphXml(paragraph, null, null, bodySize,
                pageWidth: page.width, graphics: regions);
            if (repeatedFooter) xml = _addPageField(xml);
            footerDrawing.write(xml);
          }
          if (headerDrawing.isNotEmpty || headerImageIndex > 0) {
            if (repeatedHeader) {
              headerIds[page.pageNumber] = 'rIdHeaderRepeated';
              if (!sharedHeaderWritten) {
                const partName = 'header_repeated';
                storyParts['word/$partName.xml'] = _storyXml(headerDrawing.toString(), true);
                storyRelationships['word/_rels/$partName.xml.rels'] = _relationshipsXml(headerPartRels);
                storyDocRelationships.add('<Relationship Id="rIdHeaderRepeated" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="$partName.xml"/>');
                storyContentTypes.add('<Override PartName="/word/$partName.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>');
                sharedHeaderWritten = true;
              }
            } else {
              final partName = 'header${page.pageNumber}';
              final relId = 'rIdHeader${page.pageNumber}';
              headerIds[page.pageNumber] = relId;
              storyParts['word/$partName.xml'] = _storyXml(headerDrawing.toString(), true);
              storyRelationships['word/_rels/$partName.xml.rels'] = _relationshipsXml(headerPartRels);
              storyDocRelationships.add('<Relationship Id="$relId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="$partName.xml"/>');
              storyContentTypes.add('<Override PartName="/word/$partName.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>');
            }
          }
          if (footerDrawing.isNotEmpty || footerImageIndex > 0) {
            if (repeatedFooter) {
              footerIds[page.pageNumber] = 'rIdFooterRepeated';
              if (!sharedFooterWritten) {
                const partName = 'footer_repeated';
                storyParts['word/$partName.xml'] = _storyXml(footerDrawing.toString(), false);
                storyRelationships['word/_rels/$partName.xml.rels'] = _relationshipsXml(footerPartRels);
                storyDocRelationships.add('<Relationship Id="rIdFooterRepeated" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="$partName.xml"/>');
                storyContentTypes.add('<Override PartName="/word/$partName.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>');
                sharedFooterWritten = true;
              }
            } else {
              final partName = 'footer${page.pageNumber}';
              final relId = 'rIdFooter${page.pageNumber}';
              footerIds[page.pageNumber] = relId;
              storyParts['word/$partName.xml'] = _storyXml(footerDrawing.toString(), false);
              storyRelationships['word/_rels/$partName.xml.rels'] = _relationshipsXml(footerPartRels);
              storyDocRelationships.add('<Relationship Id="$relId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="$partName.xml"/>');
              storyContentTypes.add('<Override PartName="/word/$partName.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>');
            }
          }
        } on Object catch (error, stackTrace) {
          notes.add('Some PDF images and rules were simplified.');
          debugPrint('[PdfToDocx] header/footer writing page=${page.pageNumber} failed: $error\n$stackTrace');
          flushPageBody();
          for (final paragraph in PdfTextReader.groupParagraphs(headerBandLines)) {
            body.write(_paragraphXml(paragraph, null, null, bodySize,
                pageWidth: page.width));
          }
          for (final paragraph in PdfTextReader.groupParagraphs(footerBandLines)) {
            body.write(_paragraphXml(paragraph, null, null, bodySize,
                pageWidth: page.width));
          }
          if (headerBandLines.isNotEmpty || footerBandLines.isNotEmpty) {
            pageContentAdded = true;
          }
        }
      }
      if (page.pageNumber < extraction.pages.length) {
        body.write('<w:p><w:pPr>${_sectionProperties(
            page,
            nextPage: true,
            headerId: headerIds[page.pageNumber],
            footerId: footerIds[page.pageNumber],
          )}</w:pPr></w:p>');
      }
      if (!pageContentAdded && page.lines.isNotEmpty) {
        notes.add('Some PDF page content was skipped.');
      }
      await report(
        0.15 + 0.70 * ((pageIndex + 1) / math.max(1, pageCount)),
        'Converting page ${pageIndex + 1} of $pageCount',
      );
    }

    await report(0.85, 'Building document');
    final lastPage = extraction.pages.isEmpty ? null : extraction.pages.last;
    final section = lastPage == null
        ? '<w:sectPr><w:pgSz w:w="${_twips(pageWidth)}" '
            'w:h="${_twips(pageHeight)}"/><w:pgMar w:top="720" '
            'w:right="720" w:bottom="720" w:left="720"/></w:sectPr>'
        : _sectionProperties(
            lastPage,
            headerId: headerIds[lastPage.pageNumber],
            footerId: footerIds[lastPage.pageNumber],
          );
    final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>${body.toString()}$section</w:body></w:document>';
    final contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
        '${storyContentTypes.join()}'
        '</Types>';
    const rootRelationships = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    final documentRelationships = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
        '${imageRelationships.join()}${storyDocRelationships.join()}</Relationships>';
    final writeWatch = Stopwatch()..start();
    try {
    await report(0.98, 'Writing DOCX');
    final archive = Archive();
    _addUtf8(archive, '[Content_Types].xml', contentTypes);
    _addUtf8(archive, '_rels/.rels', rootRelationships);
    _addUtf8(archive, 'word/document.xml', documentXml);
    _addUtf8(archive, 'word/styles.xml', _stylesXml);
    _addUtf8(archive, 'word/numbering.xml', _numberingXml);
    _addUtf8(archive, 'word/_rels/document.xml.rels', documentRelationships);
    for (final entry in storyParts.entries) {
      _addUtf8(archive, entry.key, entry.value);
    }
    for (final entry in storyRelationships.entries) {
      _addUtf8(archive, entry.key, entry.value);
    }
    for (final entry in storedImages.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final encoded = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(encoded);
    debugPrint('[PdfToDocx] DOCX writing pages=${extraction.pages.length} ms=${writeWatch.elapsedMilliseconds}');
    await report(1, 'Conversion complete');
    return notes.toList();
    } on Object catch (error, stackTrace) {
      notes.add('DOCX writing failed.');
      debugPrint('[PdfToDocx] DOCX writing failed: $error\n$stackTrace');
      rethrow;
    }
  }

  static String _paragraphXml(
    List<PdfTextLineData> lines,
    _DetectedList? list,
    int? numId,
    double bodySize,
    {double spacingBefore = 0,
    double leftMargin = 0,
    double rightEdge = double.infinity,
    double pageWidth = 0,
    List<PdfGraphicRegion> graphics = const <PdfGraphicRegion>[],}
  ) {
    final sizes = lines.map((line) => line.fontSize).where((size) => size > 0).toList();
    final fontSize = sizes.isEmpty
        ? 11.0
        : sizes.reduce((first, second) => first > second ? first : second);
    final headingLevel = fontSize >= bodySize * 1.8
        ? 1
        : fontSize >= bodySize * 1.45
            ? 2
            : fontSize >= bodySize * 1.2
                ? 3
                : null;
    final pPr = StringBuffer('<w:pPr>');
    if (headingLevel != null) {
      pPr.write('<w:pStyle w:val="Heading$headingLevel"/>');
    }
    if (list != null && numId != null) {
      pPr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="$numId"/></w:numPr>');
    }
    final ruleLeft = lines.map((line) => line.left).reduce((a, b) => a < b ? a : b);
    final ruleRight = lines.map((line) => line.left + line.width).reduce((a, b) => math.max(a, b).toDouble());
    final topRules = <PdfGraphicRegion>[];
    final bottomRules = <PdfGraphicRegion>[];
    for (final rule in graphics.where((item) => item.kind == 'rule')) {
      if (rule.left >= ruleRight || rule.left + rule.width <= ruleLeft) continue;
      if ((rule.top - lines.first.top).abs() <= 8) topRules.add(rule);
      if ((rule.top - (lines.last.top + lines.last.height)).abs() <= 8) bottomRules.add(rule);
    }
    if (topRules.isNotEmpty || bottomRules.isNotEmpty) {
      String border(PdfGraphicRegion rule, String edge) {
        final size = (rule.height * 8).round().clamp(4, 24);
        return '<w:$edge w:val="single" w:sz="$size" w:space="1" w:color="${rule.color}"/>';
      }
      pPr.write('<w:pBdr>');
      if (topRules.isNotEmpty) pPr.write(border(topRules.first, 'top'));
      if (bottomRules.isNotEmpty) pPr.write(border(bottomRules.first, 'bottom'));
      pPr.write('</w:pBdr>');
    }
    final measuredPitch = lines.length > 1
        ? (lines[1].top - lines[0].top).abs()
        : fontSize * 1.2;
    final lineTwips = _twips(math.max(fontSize, measuredPitch).toDouble());
    pPr.write('<w:spacing w:before="${_twips(spacingBefore)}" '
        'w:after="0" w:line="$lineTwips" w:lineRule="exact"/>');
    final firstLeft = lines
        .map((line) => line.left)
        .reduce((a, b) => a < b ? a : b);
    final paragraphRight = lines
        .map((line) => line.left + line.width)
        .reduce((a, b) => math.max(a, b).toDouble());
    final indent = math.max(0, firstLeft - leftMargin).round();
    final blockLeft = lines.map((line) => line.left).reduce(math.min);
    final textAreaRight = rightEdge.isFinite ? rightEdge : paragraphRight;
    final textAreaWidth = math.max(1.0, textAreaRight - leftMargin);
    final nearRight = lines.take(math.max(0, lines.length - 1).toInt()).where(
      (line) => textAreaRight - (line.left + line.width) <= textAreaWidth * 0.08,
    ).length;
    final flowing = lines.length > 1 && nearRight == lines.length - 1;
    final labelBlock = lines.any((line) => line.words.any((word) =>
        const {'TO:', 'SUBJECT:', 'FROM:', 'DATE:'}.contains(word.text.trim().toUpperCase())));
    final labelTabPositions = <int>{};
    for (final line in lines) {
      for (var wordIndex = 0; wordIndex + 1 < line.words.length; wordIndex++) {
        if (const {'TO:', 'SUBJECT:', 'FROM:', 'DATE:'}
            .contains(line.words[wordIndex].text.toUpperCase())) {
          final valueWord = line.words[wordIndex + 1];
          final gap = valueWord.left -
              (line.words[wordIndex].left + line.words[wordIndex].width);
          if (gap > valueWord.fontSize * 2) {
            labelTabPositions.add(
              _twips(math.max(0.0, valueWord.left - leftMargin).toDouble()),
            );
          }
        }
      }
    }
    if (topRules.isNotEmpty || bottomRules.isNotEmpty) {
      final rule = topRules.isNotEmpty ? topRules.first : bottomRules.first;
      final ruleLeftIndent = math.max(0.0, rule.left - leftMargin).toDouble();
      final ruleRightIndent = math.max(0.0, textAreaRight - (rule.left + rule.width)).toDouble();
      pPr.write('<w:ind w:left="${_twips(ruleLeftIndent)}" '
          'w:right="${_twips(ruleRightIndent)}"/>');
    } else if (labelTabPositions.isNotEmpty) {
      final tab = labelTabPositions.reduce((a, b) => a < b ? a : b);
      pPr.write('<w:tabs><w:tab w:val="left" w:pos="$tab"/></w:tabs>'
          '<w:ind w:left="$tab" w:hanging="$tab"/>');
    } else if (indent > 0) {
      pPr.write('<w:ind w:left="${_twips(indent.toDouble())}"/>');
    }
    if (flowing && !labelBlock) {
      pPr.write('<w:jc w:val="both"/>');
    } else if (lines.length > 1) {
      final rightEdges = lines.map((line) => line.left + line.width).toList();
      final areaCenter = pageWidth > 0 ? (leftMargin + rightEdge) / 2 : 0;
      final centers = lines.map((line) => line.left + line.width / 2).toList();
      if (areaCenter > 0 && centers.every((center) => (center - areaCenter).abs() <= 8)) {
        pPr.write('<w:jc w:val="center"/>');
      } else if (rightEdge.isFinite &&
          lines.every((line) => (rightEdge - (line.left + line.width)).abs() <= 4)) {
        pPr.write('<w:jc w:val="right"/>');
      }
    }
    pPr.write('</w:pPr>');
    final runs = StringBuffer();
    var pendingText = '';
    var pendingFont = 'Arial';
    var pendingSize = 11.0;
    var pendingBold = false, pendingItalic = false, pendingUnderline = false;
    String styleKey(String font, double size, bool bold, bool italic, bool underline) =>
        '$font|$size|$bold|$italic|$underline';
    var pendingKey = '';
    void flushRun() {
      if (pendingText.isNotEmpty) {
        runs.write(_textRun(pendingText, pendingFont, pendingSize,
            bold: pendingBold, italic: pendingItalic, underline: pendingUnderline));
        pendingText = '';
      }
    }
    void addText(String text, String font, double size, bool bold, bool italic, bool underline) {
      if (text.isEmpty) return;
      final key = styleKey(font, size, bold, italic, underline);
      if (pendingText.isNotEmpty && pendingKey != key) flushRun();
      if (pendingText.isEmpty) {
        pendingFont = font; pendingSize = size; pendingBold = bold;
        pendingItalic = italic; pendingUnderline = underline; pendingKey = key;
      }
      pendingText += text;
    }
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final words = line.words
          .where((word) => word.text.trim().isNotEmpty)
          .toList();
      if (lineIndex > 0) {
        final previous = lines[lineIndex - 1];
        final shortLine = textAreaRight - (previous.left + previous.width) >
            textAreaWidth * 0.08;
        if (labelBlock || shortLine) {
          flushRun();
          runs.write('<w:r><w:br/></w:r>');
        } else if (!previous.text.trimRight().endsWith('-')) {
          addText(' ', line.fontName, line.fontSize,
              line.bold, line.italic, false);
        }
      }
      if (words.isEmpty) {
        var text = line.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (lineIndex == 0 && list != null) {
          final match = list.pattern.firstMatch(text);
          if (match != null) text = text.substring(match.end);
        }
        addText(text, line.fontName, line.fontSize, line.bold, line.italic, false);
        continue;
      }
      final sourceText = line.text;
      final starts = <int>[];
      var cursor = 0;
      var matched = true;
      for (final word in words) {
        final index = sourceText.indexOf(word.text.trim(), cursor);
        if (index < cursor || index < 0) { matched = false; break; }
        starts.add(index);
        cursor = index + word.text.trim().length;
      }
      if (matched && starts.length == words.length) {
        cursor = 0;
        for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
          final word = words[wordIndex];
          final wordText = word.text.trim();
          final start = starts[wordIndex];
          var prefix = sourceText.substring(cursor, start);
          if (wordIndex > 0) {
            final previous = words[wordIndex - 1];
            final gap = word.left - (previous.left + previous.width);
            final label = const {'TO:', 'SUBJECT:', 'FROM:', 'DATE:'}
                .contains(previous.text.trim().toUpperCase());
            if (label && gap > word.fontSize * 2) prefix = '\t';
          }
          var text = '$prefix$wordText';
          if (lineIndex == 0 && wordIndex == 0 && list != null) {
            final listMatch = list.pattern.firstMatch(text);
            if (listMatch != null) text = text.substring(listMatch.end);
          }
          addText(text, word.fontName, word.fontSize,
              word.bold, word.italic, word.underline);
          cursor = start + wordText.length;
        }
        final tail = sourceText.substring(cursor);
        if (tail.trim().isNotEmpty && words.isNotEmpty) {
          final last = words.last;
          addText(tail, last.fontName, last.fontSize,
              last.bold, last.italic, last.underline);
        }
      } else {
        for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
          final word = words[wordIndex];
          final text = word.text.trim();
          if (wordIndex > 0) {
            final previous = words[wordIndex - 1];
            final gap = word.left - (previous.left + previous.width);
            final label = const {'TO:', 'SUBJECT:', 'FROM:', 'DATE:'}
                .contains(previous.text.trim().toUpperCase());
            if (label && gap > word.fontSize * 2) {
              flushRun(); runs.write('<w:r><w:tab/></w:r>');
            } else if (gap >= 0) {
              addText(' ', word.fontName, word.fontSize,
                  word.bold, word.italic, word.underline);
            }
          }
          addText(text, word.fontName, word.fontSize,
              word.bold, word.italic, word.underline);
        }
      }
    }
    flushRun();
    return '<w:p>${pPr.toString()}${runs.toString()}</w:p>';
  }

  static String _textRun(
    String text,
    String sourceFont,
    double fontSize, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
  }) {
    final family = _mappedFont(sourceFont);
    final normalizedStyle = sourceFont.toLowerCase();
    bold = bold || RegExp(r'bold|black|heavy|semibold|demi').hasMatch(normalizedStyle);
    italic = italic || RegExp(r'italic|oblique').hasMatch(normalizedStyle);
    final halfPoints = ((fontSize > 0 ? fontSize : 11) * 2)
        .round()
        .clamp(2, 400);
    return '<w:r><w:rPr><w:rFonts w:ascii="${_escape(family)}" '
        'w:hAnsi="${_escape(family)}" w:cs="${_escape(family)}"/>'
        '<w:sz w:val="$halfPoints"/><w:szCs w:val="$halfPoints"/>'
        '${bold ? '<w:b/><w:bCs/>' : ''}'
        '${italic ? '<w:i/><w:iCs/>' : ''}'
        '${underline ? '<w:u w:val="single"/>' : ''}'
        '</w:rPr><w:t xml:space="preserve">${_escape(text)}</w:t></w:r>';
  }

  static String _mappedFont(String sourceFont) {
    final family = PdfTextReader.cleanPdfFontName(sourceFont).trim();
    return family.isEmpty ? 'Arial' : family;
  }

  static double _bodyFontSize(List<PdfTextLineData> lines) {
    if (lines.isEmpty) return 11;
    final counts = <int, int>{};
    for (final line in lines) {
      if (line.fontSize <= 0 || !line.fontSize.isFinite) continue;
      final key = (line.fontSize * 2).round();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return 11;
    final common = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return common / 2;
  }

  static String _sectionProperties(
    PdfTextPageData page, {
    bool nextPage = false,
    String? headerId,
    String? footerId,
  }) {
    var left = 36.0;
    var right = 36.0;
    var top = 36.0;
    var bottom = 36.0;
    if (page.lines.isNotEmpty) {
      final bodyLines = page.lines.where((line) =>
          line.top >= page.height * 0.2 && line.top < page.height * 0.8);
      final contentLines = bodyLines.isEmpty ? page.lines : bodyLines.toList();
      final ordered = List<PdfTextLineData>.from(contentLines)
        ..sort((a, b) => a.top.compareTo(b.top));
      var leftEdge = page.width;
      var rightEdge = 0.0;
      for (final line in ordered) {
        if (line.left < leftEdge) leftEdge = line.left;
        if (line.left + line.width > rightEdge) {
          rightEdge = line.left + line.width;
        }
      }
      left = math.max(36.0, leftEdge).toDouble();
      right = math.max(36.0, page.width - rightEdge).toDouble();
      top = math.max(36.0, ordered.first.top).toDouble();
      final footerLines = page.lines.where((line) => line.top >= page.height * 0.8);
      bottom = footerLines.isEmpty
          ? 36.0
          : math.max(36.0, page.height - footerLines
              .map((line) => line.top)
              .reduce((a, b) => a < b ? a : b) + 6).toDouble();
    }
    String marginTwips(double points) => points == 0 ? '0' : '${_twips(points)}';
    return '<w:sectPr>'
        '${headerId == null ? '' : '<w:headerReference w:type="default" r:id="$headerId"/>'}'
        '${footerId == null ? '' : '<w:footerReference w:type="default" r:id="$footerId"/>'}'
        '${nextPage ? '<w:type w:val="nextPage"/>' : ''}'
        '<w:pgSz w:w="${_twips(page.width)}" w:h="${_twips(page.height)}"/>'
        '<w:pgMar w:top="${marginTwips(top)}" w:right="${marginTwips(right)}" '
        'w:bottom="${marginTwips(bottom)}" w:left="${marginTwips(left)}" '
        'w:header="${marginTwips(top == 0 ? 0 : math.max(18.0, top / 2).toDouble())}" '
        'w:footer="${marginTwips(bottom == 0 ? 0 : math.max(18.0, bottom / 2).toDouble())}" '
        'w:gutter="0"/></w:sectPr>';
  }

  static bool _isRepeatedBand(
    List<PdfTextPageData> pages,
    PdfTextPageData page, {
    required bool header,
  }) {
    if (pages.length < 3) return false;
    String signature(PdfTextPageData candidate) => candidate.lines
        .where((line) => header
            ? line.top < candidate.height * 0.2
            : line.top + line.height > candidate.height * 0.8)
        .map((line) => '${(line.top / candidate.height * 100).round()}|'
            '${line.text.trim().toLowerCase().replaceAll(RegExp(r'\d+'), '#')}')
        .where((text) => text.isNotEmpty)
        .join('|');
    final current = signature(page);
    if (current.isEmpty) return false;
    return pages.where((candidate) => signature(candidate) == current).length >= 3;
  }

  static String _addPageField(String paragraphXml) {
    final expression = RegExp(
      r'<w:r>(.*?)<w:t([^>]*)>([^<]*?\bpage\s*)\d+([^<]*)</w:t></w:r>',
      caseSensitive: false,
    );
    return paragraphXml.replaceFirstMapped(expression, (match) {
      final properties = match.group(1) ?? '';
      final attributes = match.group(2) ?? '';
      final prefix = match.group(3) ?? 'Page ';
      final suffix = match.group(4) ?? '';
      return '<w:r>$properties<w:t$attributes>$prefix</w:t></w:r>'
          '<w:fldSimple w:instr=" PAGE "><w:r>$properties<w:t>1</w:t></w:r></w:fldSimple>'
          '${suffix.isEmpty ? '' : '<w:r>$properties<w:t>$suffix</w:t></w:r>'}';
    });
  }

  static int _nearestParagraphIndex(
    List<List<PdfTextLineData>> paragraphs,
    double imageTop,
  ) {
    if (paragraphs.isEmpty) return -1;
    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < paragraphs.length; i++) {
      final top = paragraphs[i].first.top;
      if (top >= imageTop && top - imageTop < bestDistance) {
        bestDistance = top - imageTop;
        bestIndex = i;
      }
    }
    return bestIndex >= 0 ? bestIndex : paragraphs.length - 1;
  }

  static bool _containsTablePoint(PdfDetectedTable table, double x, double y) =>
      x >= table.left && x <= table.right && y >= table.top && y <= table.bottom;

  static bool _overlapsTable(PdfGraphicRegion region, PdfDetectedTable table) =>
      region.left < table.right && region.left + region.width > table.left &&
      region.top < table.bottom && region.top + region.height > table.top;

  static bool _overlapsAnyTable(
    PdfGraphicRegion region,
    List<PdfDetectedTable> tables,
  ) => tables.any((table) => _overlapsTable(region, table));

  static List<PdfTextLineData> _removeTableText(
    List<PdfTextLineData> lines,
    List<PdfDetectedTable> tables,
  ) {
    if (tables.isEmpty) return lines;
    final result = <PdfTextLineData>[];
    for (final line in lines) {
      if (line.words.isEmpty) {
        if (!tables.any((table) => _containsTablePoint(
            table, line.left + line.width / 2, line.top + line.height / 2))) {
          result.add(line);
        }
        continue;
      }
      final words = line.words.where((word) => !tables.any((table) =>
          _containsTablePoint(table, word.left + word.width / 2, word.top + word.height / 2))).toList();
      if (words.isEmpty) continue;
      final left = words.map((word) => word.left).reduce((a, b) => a < b ? a : b);
      final right = words.map((word) => word.left + word.width).reduce((a, b) => a > b ? a : b);
      result.add(PdfTextLineData(
        text: words.map((word) => word.text.trim()).where((text) => text.isNotEmpty).join(' '),
        left: left,
        top: line.top,
        width: right - left,
        height: line.height,
        fontSize: line.fontSize,
        fontName: line.fontName,
        bold: line.bold,
        italic: line.italic,
        words: words,
      ));
    }
    return result;
  }

  static String _tableXml(
    PdfDetectedTable table,
    List<PdfTextLineData> lines,
    double bodySize,
    double pageWidth,
    double pageLeftMargin,
  ) {
    final columnWidths = <double>[];
    for (var i = 0; i + 1 < table.columns.length; i++) {
      columnWidths.add(table.columns[i + 1] - table.columns[i]);
    }
    final tableWidth = table.right - table.left;
    final rows = StringBuffer();
    final firstRowFill = table.fills.isNotEmpty ? table.fills.first : <String?>[];
    final otherFills = table.fills.skip(1).expand((row) => row).toSet();
    var headerRow = firstRowFill.any((fill) => fill != null && !otherFills.contains(fill));
    if (!headerRow && table.rows.length > 1) {
      headerRow = lines.any((line) => line.top >= table.rows[0] && line.top < table.rows[1] &&
          line.words.any((word) => word.bold));
    }
    for (var row = 0; row + 1 < table.rows.length; row++) {
      rows.write('<w:tr><w:trPr><w:cantSplit/>${row == 0 && headerRow ? '<w:tblHeader/>' : ''}</w:trPr>');
      var col = 0;
      while (col < columnWidths.length) {
        var colEnd = col + 1;
        while (colEnd < columnWidths.length && row < table.verticalEdges.length &&
            colEnd < table.verticalEdges[row].length && !table.verticalEdges[row][colEnd]) {
          colEnd++;
        }
        final left = table.columns[col], right = table.columns[colEnd];
        final top = table.rows[row], bottom = table.rows[row + 1];
        final verticalContinuation = row > 0 &&
            row < table.horizontalEdges.length && col < table.horizontalEdges[row].length &&
            !table.horizontalEdges[row][col];
        final verticalRestart = row + 1 < table.horizontalEdges.length &&
            col < table.horizontalEdges[row + 1].length &&
            !table.horizontalEdges[row + 1][col];
        final cellLines = <PdfTextLineData>[];
        for (final line in verticalContinuation ? const <PdfTextLineData>[] : lines) {
          final selected = line.words.where((word) {
            final x = word.left + word.width / 2, y = word.top + word.height / 2;
            return x >= left && x < right && y >= top && y < bottom;
          }).toList();
          if (selected.isEmpty) continue;
          final cellLeft = selected.map((word) => word.left).reduce((a, b) => a < b ? a : b);
          final cellRight = selected.map((word) => word.left + word.width).reduce((a, b) => a > b ? a : b);
          cellLines.add(PdfTextLineData(
            text: selected.map((word) => word.text.trim()).join(' '),
            left: cellLeft,
            top: line.top,
            width: cellRight - cellLeft,
            height: line.height,
            fontSize: line.fontSize,
            fontName: line.fontName,
            bold: line.bold,
            italic: line.italic,
            words: selected,
          ));
        }
        final paragraphs = PdfTextReader.groupParagraphs(cellLines);
        final content = paragraphs.isEmpty
            ? '<w:p/>'
            : paragraphs.map((paragraph) => _paragraphXml(
                paragraph,
                null,
                null,
                bodySize,
                leftMargin: left,
                rightEdge: right,
                pageWidth: pageWidth,
              )).join();
        final fill = !verticalContinuation && row < table.fills.length && col < table.fills[row].length
            ? table.fills[row][col]
            : null;
        final tcWidth = right - left;
        final tcPr = StringBuffer('<w:tcPr><w:tcW w:w="${_twips(tcWidth)}" w:type="dxa"/>');
        if (colEnd - col > 1) tcPr.write('<w:gridSpan w:val="${colEnd - col}"/>');
        if (verticalContinuation) {
          tcPr.write('<w:vMerge/>');
        } else if (verticalRestart) {
          tcPr.write('<w:vMerge w:val="restart"/>');
        }
        if (fill != null) tcPr.write('<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>');
        tcPr.write('<w:tcBorders>'
            '<w:top w:val="single" w:sz="4" w:color="A6A6A6"/>'
            '<w:left w:val="single" w:sz="4" w:color="A6A6A6"/>'
            '<w:bottom w:val="single" w:sz="4" w:color="A6A6A6"/>'
            '<w:right w:val="single" w:sz="4" w:color="A6A6A6"/>'
            '</w:tcBorders><w:tcMar><w:top w:w="60" w:type="dxa"/>'
            '<w:left w:w="100" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/>'
            '<w:right w:w="100" w:type="dxa"/></w:tcMar><w:vAlign w:val="top"/></w:tcPr>');
        rows.write('<w:tc>${tcPr.toString()}$content</w:tc>');
        col = colEnd;
      }
      rows.write('</w:tr>');
    }
    final grid = columnWidths.map((width) => '<w:gridCol w:w="${_twips(width)}"/>').join();
    return '<w:tbl><w:tblPr><w:tblW w:w="${_twips(tableWidth)}" w:type="dxa"/>'
        '<w:tblInd w:w="${_twips(math.max(0.0, table.left - pageLeftMargin).toDouble())}" w:type="dxa"/>'
        '<w:tblLayout w:type="fixed"/><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '<w:left w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '<w:right w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="A6A6A6"/>'
        '</w:tblBorders></w:tblPr><w:tblGrid>$grid</w:tblGrid>$rows</w:tbl>';
  }

  static String _imageRelationship(String id, String mediaName) =>
      '<Relationship Id="$id" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/$mediaName"/>';

  static String _relationshipsXml(List<String> relationships) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${relationships.join()}</Relationships>';

  static String _storyXml(String content, bool header) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:${header ? 'hdr' : 'ftr'} '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '$content</w:${header ? 'hdr' : 'ftr'}>';

  static String _anchoredGraphic(
    String relationshipId,
    int imageIndex,
    double left,
    double top,
    double width,
    double height,
    String kind,
    {bool paragraphRelative = false,
    double verticalOffset = 0,
    bool embeddedInParagraph = false,}
  ) {
    final cx = (width * 12700).round().clamp(1, 20000000);
    final cy = (height * 12700).round().clamp(1, 20000000);
    final paragraphProperties = '<w:pPr><w:spacing w:before="0" w:after="0" '
        'w:line="1" w:lineRule="exact"/></w:pPr>';
    final anchorRun = '<w:r><w:drawing>'
        '<wp:anchor distT="0" distB="0" distL="0" distR="0" '
        'simplePos="0" relativeHeight="251658240" behindDoc="0" '
        'locked="0" layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="page"><wp:posOffset>${(left * 12700).round()}</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="${paragraphRelative ? 'paragraph' : 'page'}">'
        '<wp:posOffset>${((paragraphRelative ? verticalOffset : top) * 12700).round()}</wp:posOffset></wp:positionV>'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:wrapNone/><wp:docPr id="$imageIndex" name="PDF $kind $imageIndex"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$imageIndex" name="PDF region $imageIndex"/>'
        '<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$relationshipId"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm>'
        '<a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>';
    return embeddedInParagraph
        ? anchorRun
        : '<w:p>$paragraphProperties$anchorRun</w:p>';
  }

  static _DetectedList? _detectList(String text) {
    final bullet = RegExp(r'^\s*([•·▪◦‣⁃])\s+').firstMatch(text);
    if (bullet != null) return _DetectedList(1, 'bullet', RegExp(r'^\s*([•·▪◦‣⁃])\s+'));
    final numeric = RegExp(r'^\s*(\d+)([.)])\s+').firstMatch(text);
    if (numeric != null) {
      final kind = numeric.group(2) == ')' ? 'decimalParen' : 'decimal';
      return _DetectedList(_numberId(kind), kind, RegExp(r'^\s*\d+[.)]\s+'));
    }
    final alpha = RegExp(r'^\s*([A-Za-z])([.)])\s+').firstMatch(text);
    if (alpha != null) {
      final kind = alpha.group(2) == ')' ? 'letterParen' : 'letter';
      return _DetectedList(_numberId(kind), kind, RegExp(r'^\s*[A-Za-z][.)]\s+'));
    }
    return null;
  }

  static int _numberId(String kind) => switch (kind) {
        'bullet' => 1,
        'decimal' => 2,
        'decimalParen' => 3,
        'letter' => 4,
        'letterParen' => 5,
        _ => 2,
      };

  static String _imageParagraph(
    String relationshipId,
    int imageIndex,
    double pageWidth,
    double pageHeight,
    int pixelWidth,
    int pixelHeight,
  ) {
    final scale = math.min(
      pageWidth / pixelWidth,
      pageHeight / pixelHeight,
    );
    final cx = (pixelWidth * scale * 12700).round();
    final cy = (pixelHeight * scale * 12700).round();
    return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$imageIndex" name="Scanned PDF page $imageIndex"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$imageIndex" name="Page $imageIndex"/>'
        '<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$relationshipId"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm>'
        '<a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
  }

  static String _numberingXml = _makeNumberingXml();

  static String _makeNumberingXml() {
    const levels = <(int, String, String)>[
      (0, 'bullet', '•'),
      (1, 'decimal', '%1.'),
      (2, 'decimal', '%1)'),
      (3, 'lowerLetter', '%1.'),
      (4, 'lowerLetter', '%1)'),
    ];
    final xml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    for (final level in levels) {
      xml.write('<w:abstractNum w:abstractNumId="${level.$1}"><w:multiLevelType w:val="singleLevel"/>'
          '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="${level.$2}"/>'
          '<w:lvlText w:val="${level.$3}"/><w:lvlJc w:val="left"/>'
          '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>');
      if (level.$2 == 'bullet') {
        xml.write('<w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol"/></w:rPr>');
      }
      xml.write('</w:lvl></w:abstractNum>');
    }
    for (var index = 0; index < levels.length; index++) {
      xml.write('<w:num w:numId="${index + 1}"><w:abstractNumId w:val="$index"/></w:num>');
    }
    xml.write('</w:numbering>');
    return xml.toString();
  }

  static const _stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>'
      '<w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
      '<w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
      '<w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/>'
      '<w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>'
      '</w:styles>';

  static int _twips(double points) =>
      (points * 20).round().clamp(1, 31680).toInt();

  static void _addUtf8(Archive archive, String name, String value) {
    final data = utf8.encode(value);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _DetectedList {
  final int numId;
  final String kind;
  final RegExp pattern;

  const _DetectedList(this.numId, this.kind, this.pattern);
}
