import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_text_reader.dart';

class PdfToHtml {
  static const note = 'Pages are shown as images with selectable text.';

  static Future<List<String>> convert(
    String sourcePath,
    String outputPath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final extraction = await PdfTextReader.read(sourcePath);
    final notes = <String>{...extraction.notes};
    final html = StringBuffer('''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PDF conversion</title>
<style>
*{box-sizing:border-box}body{margin:0;padding:16px;background:#e8e8e8}
.page{position:relative;width:100%;max-width:900px;margin:0 auto 16px;background:#fff;
  overflow:hidden;container-type:inline-size;box-shadow:0 2px 9px #0003}
.page img{position:absolute;inset:0;width:100%;height:100%;object-fit:fill}
.text-layer{position:absolute;inset:0;user-select:text;-webkit-user-select:text}
.text-layer span{position:absolute;display:block;overflow:visible;color:transparent;
  white-space:pre;line-height:1;user-select:text;-webkit-user-select:text}
</style></head><body>
''');

    for (var index = 0; index < extraction.pages.length; index++) {
      final page = extraction.pages[index];
      late final Uint8List png;
      try {
        final raster = await Printing.raster(
          bytes,
          pages: [page.pageNumber - 1],
          dpi: 120,
        ).first;
        png = await raster.toPng();
      } on Object {
        notes.add('Some PDF pages were skipped.');
        continue;
      }
      final ratioWidth = page.width.isFinite && page.width > 0 ? page.width : 1;
      final ratioHeight = page.height.isFinite && page.height > 0 ? page.height : 1;
      html.write(
        '<section class="page" style="aspect-ratio:${ratioWidth.toStringAsFixed(3)}/${ratioHeight.toStringAsFixed(3)}">',
      );
      html.write(
        '<img alt="PDF page ${page.pageNumber}" src="data:image/png;base64,${base64Encode(png)}">',
      );
      html.write('<div class="text-layer" aria-label="Selectable page text">');
      for (final line in page.lines) {
        try {
          final left = line.left / ratioWidth * 100;
          final top = line.top / ratioHeight * 100;
          final width = line.width / ratioWidth * 100;
          final height = line.height / ratioHeight * 100;
          final fontSize = (line.height > 0 ? line.height : line.fontSize) /
              ratioWidth *
              100;
          html.write(
            '<span style="left:${left.toStringAsFixed(4)}%;top:${top.toStringAsFixed(4)}%;width:${width.toStringAsFixed(4)}%;height:${height.toStringAsFixed(4)}%;font-size:${fontSize.toStringAsFixed(4)}cqw">${_escape(line.text)}</span>',
          );
        } on Object {
          notes.add('Some PDF text lines were skipped.');
        }
      }
      html.write('</div></section>\n');
    }
    html.write('</body></html>');
    await File(outputPath).writeAsBytes(utf8.encode(html.toString()));
    notes.add(note);
    return notes.toList();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
