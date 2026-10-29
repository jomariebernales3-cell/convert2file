import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/generation_options.dart';

class HtmlGenerator {
  static Future<String> generate(
    Map<String, dynamic> mapping,
    GenerationOptions options,
    String baseName,
  ) async {
    final profile = _resolvedProfile(options.styleProfile);
    final css = _previewCss(profile);
    final body = _renderHtmlBody(mapping, options.styleProfile, options.workspaceMode);

    final html = '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Convert2File Preview</title>
<style>$css</style>
</head>
<body>$body</body>
</html>''';

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$baseName.html');
    await file.writeAsString(html);
    return file.path;
  }

  static String _renderHtmlBody(
      Map<String, dynamic> mapping, String styleProfile, String workspaceMode) {
    final buffer = StringBuffer();
    buffer.write('<article class="preview-doc">');
    buffer.write(
        '<h1>${_escapeHtml(mapping['{{TITLE}}'] as String? ?? 'Generated Document')}</h1>');

    final sections = _extractSections(mapping);
    for (final section in sections) {
      buffer.write('<section class="preview-section">');
      final heading = section['heading'] as String? ?? '';
      if (heading.trim().isNotEmpty || workspaceMode != 'text') {
        buffer.write('<h2>${_escapeHtml(heading)}</h2>');
      }

      for (final item in section['content'] as List? ?? []) {
        final type = item['type'] as String? ?? '';

        if (type == 'list') {
          buffer.write('<ul>');
          for (final listItem in item['items'] as List? ?? []) {
            buffer.write('<li>${_escapeHtml(listItem.toString())}</li>');
          }
          buffer.write('</ul>');
        } else if (type == 'formula') {
          buffer.write(
              '<div class="preview-formula">${_escapeHtml(item['text'] as String? ?? '')}</div>');
          final error = (item['error'] as String? ?? '').trim();
          if (error.isNotEmpty) {
            buffer.write(
                '<p class="preview-formula-note">${_escapeHtml(error)}</p>');
          }
        } else if (type == 'table') {
          buffer.write('<table><tbody>');
          for (final row in item['rows'] as List? ?? []) {
            buffer.write('<tr>');
            for (final cell in row as List) {
              buffer.write('<td>${_escapeHtml(cell.toString())}</td>');
            }
            buffer.write('</tr>');
          }
          buffer.write('</tbody></table>');
        } else if (type == 'image') {
          final caption = (item['caption'] as String? ?? '').trim();
          buffer.write('<figure>');
          buffer.write(
              '<figcaption>${_escapeHtml(caption.isNotEmpty ? caption : 'Image')}</figcaption>');
          buffer.write('</figure>');
        } else if (type == 'diagram') {
          buffer.write('<section class="preview-diagram">');
          buffer.write(
              '<span class="preview-diagram-type">${_escapeHtml(item['diagram_type'] as String? ?? 'diagram')}</span>');
          buffer.write(
              '<div class="preview-diagram-title">${_escapeHtml(item['title'] as String? ?? 'Diagram')}</div>');
          final summary = item['summary'] as String? ?? '';
          if (summary.isNotEmpty) {
            buffer.write('<p>${_escapeHtml(summary)}</p>');
          }
          final points = item['points'] as List? ?? [];
          if (points.isNotEmpty) {
            buffer.write('<ul>');
            for (final point in points.take(8)) {
              buffer.write('<li>${_escapeHtml(point.toString())}</li>');
            }
            buffer.write('</ul>');
          }
          buffer.write('</section>');
        } else {
          final paragraph = item['text'] as String? ?? '';
          if (paragraph.trim().isNotEmpty) {
            final align = item['align'] as String? ?? 'left';
            final styles = <String>['text-align:$align'];
            if (item['bold'] == true) styles.add('font-weight:700');
            if (item['italic'] == true) styles.add('font-style:italic');
            styles.add('color:#${item['textColor'] as String? ?? '374151'}');
            if (item['highlight'] == true) styles.add('background:#${item['highlightColor'] as String? ?? 'FFF2A6'};padding:3px');
            final htmlText = _escapeHtml(paragraph).replaceAll('\n', '<br>');
            buffer.write('<p style="${styles.join(';')}">$htmlText</p>');
          }
        }
      }

      buffer.write('</section>');
    }

    buffer.write('</article>');
    return buffer.toString();
  }

  static String _previewCss(Map<String, dynamic> profile) {
    final styleProfile = profile['style_profile'] as String? ?? 'academic';
    final bodyFont = profile['body_font'] as String? ?? 'Times New Roman';
    final headingFont = profile['heading_font'] as String? ?? 'Times New Roman';
    final titleFont = profile['title_font'] as String? ?? 'Times New Roman';
    final bodySize = profile['body_size'] as int? ?? 16;
    final headingSize = profile['heading_size'] as int? ?? 20;
    final titleSize = profile['title_size'] as int? ?? 26;
    final bodyColor = profile['body_color'] as String? ?? '#222222';
    final headingColor = profile['heading_color'] as String? ?? '#111111';
    final titleColor = profile['title_color'] as String? ?? '#111111';
    final tableBorder = profile['table_border'] as String? ?? '#111111';
    final pageBackground = profile['page_background'] as String? ?? '#fffdf8';

    final titleDecoration = styleProfile == 'modern'
        ? 'padding-bottom:10px;'
        : styleProfile == 'module'
        ? 'border-left:6px solid #2563eb;padding-left:14px;'
        : styleProfile == 'clean'
            ? 'border-bottom:1px solid #dddddd;padding-bottom:10px;'
            : 'border-bottom:2px solid #111111;padding-bottom:8px;';

    final headingDecoration = styleProfile == 'module'
        ? 'background:#eef5ff;padding:10px 12px;border-radius:8px;'
        : '';

    return '''
body{font-family:"$bodyFont",Arial,sans-serif;background:$pageBackground;color:$bodyColor;margin:44px;line-height:1.5}
h1{font-family:"$titleFont",Arial,sans-serif;color:$titleColor;font-size:${titleSize}px;font-weight:700;$titleDecoration;margin:0 0 20px}
h2{font-family:"$headingFont",Arial,sans-serif;color:$headingColor;font-size:${headingSize}px;font-weight:700;margin:30px 0 14px;$headingDecoration}
p,li,td,th{font-family:"$bodyFont",Arial,sans-serif;font-size:${bodySize}px;color:$bodyColor}
p{margin:0 0 14px}
figure{margin:20px 0;text-align:center}
figcaption{margin-top:8px;font-size:${bodySize - 1}px;color:#6b625d}
.preview-diagram{margin:20px 0;padding:14px 16px;border:1px solid #d8c8bb;border-radius:12px;background:#fff}
.preview-diagram-title{font-weight:700;font-size:${headingSize - 1}px;color:#2f2a26;margin-bottom:8px}
.preview-diagram-type{display:inline-block;margin-bottom:8px;padding:3px 8px;border-radius:999px;background:#f6eee7;color:#7a5d45;font-size:${bodySize - 2}px;text-transform:uppercase;letter-spacing:.04em}
.preview-diagram p{margin:8px 0 0}
.preview-diagram ul{margin:8px 0 0;padding-left:20px}
.preview-formula{margin:14px 0;padding:10px 12px;border-left:4px solid #2563eb;background:#f7fbff;font-family:"Cambria Math","Times New Roman",serif;font-size:${bodySize + 1}px;color:#111;white-space:pre-wrap}
.preview-formula-note{margin-top:-6px;color:#8a5a00;font-size:${bodySize - 2}px}
table{width:100%;border-collapse:collapse;margin:16px 0;background:#fff}
td,th{border:1px solid $tableBorder;padding:8px}
ul{padding-left:22px;margin:0 0 14px}
.preview-doc{max-width:900px;margin:0 auto}
.preview-doc strong{font-weight:700}
.module-mark{padding:0 4px;border-radius:4px;background:#fde68a;color:#92400e;font-weight:700}
''';
  }

  static Map<String, dynamic> _resolvedProfile(String styleProfile) {
    switch (styleProfile) {
      case 'modern':
        return {
          'style_profile': 'modern',
          'body_font': 'Aptos',
          'heading_font': 'Aptos Display',
          'title_font': 'Aptos Display',
          'body_size': 15,
          'heading_size': 19,
          'title_size': 29,
          'body_color': '#374151',
          'heading_color': '#1F2937',
          'title_color': '#111827',
          'table_border': '#D1D5DB',
          'page_background': '#FFFFFF',
        };
      case 'module':
        return {
          'style_profile': 'module',
          'body_font': 'Arial',
          'heading_font': 'Arial',
          'title_font': 'Arial',
          'body_size': 15,
          'heading_size': 18,
          'title_size': 24,
          'body_color': '#222222',
          'heading_color': '#153A5B',
          'title_color': '#153A5B',
          'table_border': '#9DB9D8',
          'page_background': '#fbfaf7',
        };
      case 'clean':
        return {
          'style_profile': 'clean',
          'body_font': 'Calibri',
          'heading_font': 'Calibri',
          'title_font': 'Calibri',
          'body_size': 15,
          'heading_size': 17,
          'title_size': 22,
          'body_color': '#111111',
          'heading_color': '#111111',
          'title_color': '#111111',
          'table_border': '#BBBBBB',
          'page_background': '#ffffff',
        };
      default:
        return {
          'style_profile': 'academic',
          'body_font': 'Times New Roman',
          'heading_font': 'Times New Roman',
          'title_font': 'Times New Roman',
          'body_size': 16,
          'heading_size': 20,
          'title_size': 26,
          'body_color': '#222222',
          'heading_color': '#111111',
          'title_color': '#111111',
          'table_border': '#111111',
          'page_background': '#fffdf8',
        };
    }
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
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
