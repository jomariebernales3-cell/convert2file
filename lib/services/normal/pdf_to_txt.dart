import 'dart:convert';
import 'dart:io';

import 'normal_unsupported.dart';
import 'pdf_text_reader.dart';

class PdfToTxt {
  static Future<List<String>> convert(
    String sourcePath,
    String outputPath,
  ) async {
    final extraction = await PdfTextReader.read(sourcePath);
    if (!extraction.pages.any((page) => page.lines.isNotEmpty)) {
      throw const NormalUnsupported(
        'pdf',
        'txt',
        message: 'This PDF has no selectable text (scanned).',
      );
    }
    final output = StringBuffer();
    for (var index = 0; index < extraction.pages.length; index++) {
      final page = extraction.pages[index];
      if (index > 0) output.write('\n\n');
      output.write('---- Page ${page.pageNumber} ----');
      final paragraphs = PdfTextReader.groupParagraphs(page.lines)
          .map(PdfTextReader.paragraphText)
          .toList();
      if (paragraphs.isNotEmpty) output.write('\n${paragraphs.join('\n\n')}');
    }
    await File(outputPath).writeAsBytes(utf8.encode(output.toString()));
    return extraction.notes;
  }
}
