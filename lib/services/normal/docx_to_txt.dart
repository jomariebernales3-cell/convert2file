import 'dart:convert';
import 'dart:io';

import 'docx_style_reader.dart';
import 'styled_document.dart';

class DocxToTxt {
  static Future<List<String>> convert(
    String sourcePath,
    String outputPath,
  ) async {
    final document = await DocxStyleReader.read(sourcePath);
    final notes = <String>{...document.notes};
    final counters = <String, int>{};
    final outputBlocks = <String>[];
    for (final block in document.blocks) {
      try {
        if (block is StyledParagraph) {
          final text = block.runs.map((run) => run.text).join().replaceAll(
                RegExp(r'\r\n|\r|\n'),
                ' ',
              );
          final list = block.listInfo;
          outputBlocks.add(list == null ? text : '${_marker(list, counters)}$text');
        } else if (block is StyledTable) {
          outputBlocks.add(
            block.rows.map((row) => row.cells.map((cell) {
              try {
                return cell.blocks.map(_blockText).where((text) => text.isNotEmpty).join(' ');
              } on Object {
                notes.add('Some DOCX table cells were skipped.');
                return '';
              }
            }).join('\t')).join('\n'),
          );
        } else if (block is PageBreak) {
          outputBlocks.add('\f');
        } else if (block is StyledImage) {
          notes.add('Some DOCX images were omitted from the text file.');
        }
      } on Object {
        notes.add('Some DOCX content was skipped.');
      }
    }
    await File(outputPath).writeAsBytes(
      utf8.encode(outputBlocks.join('\n\n')),
    );
    return notes.toList();
  }

  static String _blockText(StyledBlock block) {
    if (block is StyledParagraph) {
      return block.runs.map((run) => run.text).join().replaceAll(
            RegExp(r'\r\n|\r|\n'),
            ' ',
          );
    }
    if (block is StyledTable) {
      return block.rows
          .map((row) => row.cells.map((cell) => cell.blocks.map(_blockText).join(' ')).join('\t'))
          .join('\n');
    }
    return '';
  }

  static String _marker(StyledListInfo list, Map<String, int> counters) {
    if (list.format.toLowerCase() == 'bullet') {
      return '${list.marker.isEmpty || list.marker.startsWith('%') ? '•' : list.marker} ';
    }
    final key = '${list.id}:${list.level}';
    final count = (counters[key] ?? 0) + 1;
    counters[key] = count;
    final marker = list.marker.isEmpty ? '%1.' : list.marker;
    return '${marker.replaceAll('%${list.level + 1}', '$count')} ';
  }
}
