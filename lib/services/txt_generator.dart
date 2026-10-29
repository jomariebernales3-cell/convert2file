import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/generation_options.dart';

class TxtGenerator {
  static Future<String> generate(
    Map<String, dynamic> mapping,
    GenerationOptions options,
    String baseName,
  ) async {
    final lines = <String>[];

    lines.add(mapping['{{TITLE}}'] as String? ?? 'Generated Document');
    lines.add('');

    final sections = _extractSections(mapping);
    for (final section in sections) {
      final heading = section['heading'] as String? ?? '';
      if (heading.trim().isNotEmpty || options.workspaceMode != 'text') {
        lines.add(heading);
        lines.add('');
      }

      for (final item in section['content'] as List? ?? []) {
        final type = item['type'] as String? ?? '';

        if (type == 'paragraph') {
          lines.add(item['text'] as String? ?? '');
          lines.add('');
        } else if (type == 'formula') {
          lines.add('[Formula] ${item['text'] as String? ?? ''}');
          final error = (item['error'] as String? ?? '').trim();
          if (error.isNotEmpty) {
            lines.add('Formula detection note: $error');
          }
          lines.add('');
        } else if (type == 'list') {
          for (final listItem in item['items'] as List? ?? []) {
            lines.add('- ${listItem.toString()}');
          }
          lines.add('');
        } else if (type == 'table') {
          for (final row in item['rows'] as List? ?? []) {
            lines.add((row as List).map((c) => c.toString()).join(' | '));
          }
          lines.add('');
        } else if (type == 'image') {
          final caption = (item['caption'] as String? ?? '').trim();
          lines.add('[Image] ${caption.isNotEmpty ? caption : 'Image'}');
          lines.add('');
        } else if (type == 'diagram') {
          lines.add('[Diagram] ${item['title'] as String? ?? 'Diagram'}');
          final summary = item['summary'] as String? ?? '';
          if (summary.isNotEmpty) {
            lines.add(summary);
          }
          for (final point in (item['points'] as List? ?? []).take(8)) {
            lines.add('- ${point.toString()}');
          }
          lines.add('');
        }
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$baseName.txt');
    await file.writeAsString(lines.join('\n'));
    return file.path;
  }

  static List<Map<String, dynamic>> _extractSections(
      Map<String, dynamic> mapping) {
    final sections = <Map<String, dynamic>>[];
    final usedPlaceholders = <String>{};

    for (final key in mapping.keys) {
      if (key.startsWith('{{SECTION_') && !key.contains('_CONTENT')) {
        final heading = mapping[key] as String? ?? '';
        final contentKey = key.replaceFirst('{{SECTION_', '{{CONTENT_');
        final content = mapping[contentKey] as List? ?? [];

        if (!usedPlaceholders.contains(key)) {
          usedPlaceholders.add(key);
          sections.add({
            'heading': heading,
            'content': content,
          });
        }
      }
    }

    return sections;
  }
}
