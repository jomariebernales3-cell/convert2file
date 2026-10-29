import '../models/data_model.dart';
import 'math_formula_service.dart';

class TemplateEngine {
  static Map<String, dynamic> buildDirectDocumentPayload(
    DataModel dataModel, {
    String fallbackTitle = 'Converted Document',
    bool cleanGrammar = true,
    bool summarize = false,
  }) {
    var title = dataModel.title.trim();
    if (title.isEmpty) title = fallbackTitle;

    final sections = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentSection;
    final sectionIndexByHeading = <String, int>{};
    final extractionNotes = _sourceWarningSection(
      dataModel.meta['source_warnings'] as List? ?? [],
    );
    if (extractionNotes != null) {
      sections.add(extractionNotes);
    }

    for (final block in dataModel.blocks) {
      final type = block['type'] as String? ?? '';

      if (type == 'heading') {
        if (currentSection != null) {
          _storeDirectSection(sections, sectionIndexByHeading, currentSection);
        }

        var heading = (block['text'] as String? ?? '').trim();
        if (heading.isEmpty) {
          heading = 'Document Section ${sections.length + 1}';
        }

        currentSection = {
          'heading': heading,
          'items': <Map<String, dynamic>>[],
        };
        continue;
      }

      currentSection ??= {
        'heading': 'Document Content',
        'items': <Map<String, dynamic>>[],
      };

      if (type == 'paragraph') {
        final text = (block['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          currentSection['items'].add({'type': 'paragraph', 'text': text});
        }
        continue;
      }

      if (type == 'formula') {
        final sourceText = (block['text'] as String? ?? '').trim();
        final parsedFormula = MathFormulaService.parse(sourceText);
        final text = parsedFormula?.displayText ?? sourceText;
        final formulaError = (block['error'] as String?)?.isNotEmpty == true
            ? block['error'] as String
            : parsedFormula?.warning;
        if (text.isNotEmpty) {
          currentSection['items'].add({
            'type': 'formula',
            'text': text,
            'latex': sourceText,
            'confidence': block['confidence'] as String? ?? 'strong',
            // Reflow exports use [text]; DOCX can reuse the original full
            // equation paragraph so Office Math fractions/subscripts remain
            // professionally rendered instead of becoming flat text.
            if ((block['source_paragraph_xml'] as String?)?.isNotEmpty == true)
              'source_formula_xml': block['source_paragraph_xml'],
            if ((block['source_math_xml'] as String?)?.isNotEmpty == true)
              'source_math_xml': block['source_math_xml'],
            if (parsedFormula?.omml.isNotEmpty == true)
              'formula_omml': parsedFormula!.omml,
            if (formulaError?.isNotEmpty == true) 'error': formulaError,
          });
        }
        continue;
      }

      if (type == 'list') {
        final items = (block['items'] as List? ?? [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (items.isNotEmpty) {
          currentSection['items'].add({'type': 'list', 'items': items});
        }
        continue;
      }

      if (type == 'table') {
        final rows = <List<String>>[];
        for (final row in block['rows'] as List? ?? []) {
          final cells = (row as List).map((e) => e.toString()).toList();
          if (cells.isNotEmpty) rows.add(cells);
        }
        if (rows.isNotEmpty) {
          currentSection['items'].add({
            'type': 'table',
            'rows': rows,
            if ((block['source_table_xml'] as String?)?.isNotEmpty == true)
              'source_table_xml': block['source_table_xml'],
          });
        }
        continue;
      }

      if (type == 'image') {
        final path = (block['path'] as String? ?? '').trim();
        if (path.isNotEmpty) {
          currentSection['items'].add({
            'type': 'image',
            'path': path,
            'caption': (block['caption'] as String? ?? '').trim(),
            'width_percent': (block['width_percent'] as num?)?.toDouble() ?? 80,
          });
        }
        continue;
      }

      if (type == 'key_value') {
        final text = (block['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          currentSection['items'].add({'type': 'paragraph', 'text': text});
        }
      }
    }

    if (currentSection != null) {
      _storeDirectSection(sections, sectionIndexByHeading, currentSection);
    }

    if (sections.isEmpty) {
      final fallbackItems = <Map<String, dynamic>>[];
      final paragraph = dataModel.paragraphs.isNotEmpty
          ? dataModel.paragraphs.first.trim()
          : 'Content converted from uploaded source.';
      if (paragraph.isNotEmpty) {
        fallbackItems.add({
          'type': 'paragraph',
          'text': _postProcessDirectText(paragraph, cleanGrammar, summarize),
        });
      }
      sections.add({
        'heading': 'Document Content',
        'items': fallbackItems,
      });
    }

    final images = dataModel.meta['images'] as List? ?? [];
    final unplacedImageBlocks = _attachImagesToDirectSections(sections, images);
    if (unplacedImageBlocks.isNotEmpty) {
      sections.add({
        'heading': 'Visual References',
        'items': unplacedImageBlocks,
      });
    }

    final diagrams = dataModel.meta['diagrams'] as List? ?? [];
    final unplacedDiagramBlocks =
        _attachDiagramsToDirectSections(sections, diagrams);
    if (unplacedDiagramBlocks.isNotEmpty) {
      sections.add({
        'heading': 'Diagram Notes',
        'items': unplacedDiagramBlocks,
      });
    }

    final formulaRefSection = _formulaReferenceSection(
      dataModel.meta['formula_references'] as List? ?? [],
      dataModel.meta['formula_pages'] as List? ?? [],
      dataModel.meta['formula_renderer_available'] as bool? ?? false,
    );
    if (formulaRefSection != null) {
      sections.add(formulaRefSection);
    }

    final finalizedSections =
        _finalizeDirectSections(sections, cleanGrammar, summarize);

    final structure = {
      'title': title,
      'headings': <Map<String, dynamic>>[],
      'sections': <Map<String, dynamic>>[],
      'tables': <Map<String, dynamic>>[],
      'lists': <Map<String, dynamic>>[],
      'raw_lines': <String>[],
    };

    final mapping = <String, dynamic>{'{{TITLE}}': title};
    final sourceWarnings = List<String>.from(
      dataModel.meta['source_warnings'] as List? ?? [],
    );
    final qualityScore = _directConversionQualityScore(dataModel, sourceWarnings);
    // Kept outside the document placeholders so it is shown in Preview & Export,
    // not written into the user's converted file.
    mapping['{{CONVERSION_DIAGNOSTICS}}'] = {
      'score': qualityScore,
      'warnings': sourceWarnings,
      'source_block_count': dataModel.blocks.length,
    };
    mapping['{{EMPHASIS_TERMS}}'] =
        dataModel.meta['emphasized_terms'] as List? ?? [];
    final usedHeadingPlaceholders = <String, int>{};
    final usedContentPlaceholders = <String, int>{};

    for (int i = 0; i < finalizedSections.length; i++) {
      final sectionData = finalizedSections[i];
      final heading =
          _repairDirectTextArtifacts(sectionData['heading'] as String);
      final placeholder = _uniqueDirectPlaceholder(
          'SECTION', heading, i + 1, usedHeadingPlaceholders);
      final contentPlaceholder = _uniqueDirectPlaceholder(
          'CONTENT', heading, i + 1, usedContentPlaceholders);

      (structure['headings'] as List)
          .add({'text': heading, 'placeholder': placeholder});
      (structure['sections'] as List).add({
        'heading': heading,
        'placeholder': placeholder,
        'content_placeholder': contentPlaceholder,
        'content': <Map<String, dynamic>>[],
      });
      mapping[placeholder] = heading;
      mapping[contentPlaceholder] = sectionData['items'];
    }

    return {
      'template_model': {
        'structure': structure,
        'placeholders': mapping,
      },
      'mapping': mapping,
    };
  }

  static void _storeDirectSection(
    List<Map<String, dynamic>> sections,
    Map<String, dynamic> sectionIndexByHeading,
    Map<String, dynamic> section,
  ) {
    var heading = (section['heading'] as String? ?? '').trim();
    if (heading.isEmpty) {
      heading = 'Document Section ${sections.length + 1}';
      section['heading'] = heading;
    }

    final key = heading.toLowerCase();
    if (sectionIndexByHeading.containsKey(key)) {
      final index = sectionIndexByHeading[key] as int;
      (sections[index]['items'] as List).addAll(section['items'] as List);
      return;
    }

    sectionIndexByHeading[key] = sections.length;
    sections.add(section);
  }

  static int _directConversionQualityScore(
    DataModel dataModel,
    List<String> warnings,
  ) {
    var score = 100;
    if (dataModel.blocks.isEmpty) score -= 55;
    if (dataModel.paragraphs.isEmpty && dataModel.tables.isEmpty) score -= 25;
    if (dataModel.title.trim().isEmpty) score -= 10;
    score -= warnings.length * 12;
    return score.clamp(0, 100);
  }

  static Map<String, dynamic>? _sourceWarningSection(List<dynamic> warnings) {
    final items = warnings
        .map((warning) => warning.toString().trim())
        .where((warning) => warning.isNotEmpty)
        .toList();
    if (items.isEmpty) return null;

    return {
      'heading': 'Extraction Notes',
      'items': [
        {
          'type': 'list',
          'items': items,
        }
      ],
    };
  }

  static List<Map<String, dynamic>> _finalizeDirectSections(
    List<Map<String, dynamic>> sections,
    bool cleanGrammar,
    bool summarize,
  ) {
    final finalSections = <Map<String, dynamic>>[];

    for (final section in sections) {
      final items = <Map<String, dynamic>>[];
      final seen = <String, bool>{};

      for (final item in section['items'] as List? ?? []) {
        final type = item['type'] as String? ?? '';

        if (type == 'paragraph') {
          var text = _postProcessDirectText(
              item['text'] as String? ?? '', cleanGrammar, summarize);
          if (text.isEmpty) continue;
          final key = 'paragraph:${text.toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({'type': 'paragraph', 'text': text});
          continue;
        }

        if (type == 'list') {
          var listItems = (item['items'] as List? ?? [])
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          if (summarize) listItems = listItems.take(6).toList();
          if (listItems.isEmpty) continue;
          final key = 'list:${listItems.join('|').toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({'type': 'list', 'items': listItems});
          continue;
        }

        if (type == 'formula') {
          final text = (item['text'] as String? ?? '').trim();
          if (text.isEmpty) continue;
          final key = 'formula:${text.toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({
            'type': 'formula',
            'text': text,
            if ((item['latex'] as String?)?.isNotEmpty == true)
              'latex': item['latex'],
            'confidence': item['confidence'] as String? ?? 'strong',
            if ((item['source_formula_xml'] as String?)?.isNotEmpty == true)
              'source_formula_xml': item['source_formula_xml'],
            if ((item['source_math_xml'] as String?)?.isNotEmpty == true)
              'source_math_xml': item['source_math_xml'],
            if ((item['formula_omml'] as String?)?.isNotEmpty == true)
              'formula_omml': item['formula_omml'],
            if ((item['error'] as String?)?.isNotEmpty == true)
              'error': item['error'],
          });
          continue;
        }

        if (type == 'table') {
          final rows = <List<String>>[];
          for (final row in item['rows'] as List? ?? []) {
            final normalizedRow = (row as List)
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (normalizedRow.isNotEmpty) rows.add(normalizedRow);
          }
          if (summarize) rows.take(6).toList();
          if (rows.isEmpty) continue;
          final key = 'table:${rows.toString().toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({
            'type': 'table',
            'rows': rows,
            if ((item['source_table_xml'] as String?)?.isNotEmpty == true)
              'source_table_xml': item['source_table_xml'],
          });
          continue;
        }

        if (type == 'image') {
          final path = (item['path'] as String? ?? '').trim();
          if (path.isEmpty) continue;
          final caption = (item['caption'] as String? ?? '').trim();
          final key = 'image:${path.toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({
            'type': 'image',
            'path': path,
            'caption': caption,
            'width_percent': (item['width_percent'] as num?)?.toDouble() ?? 80,
          });
          continue;
        }

        if (type == 'diagram') {
          final title = (item['title'] as String? ?? 'Diagram').trim();
          final summary = (item['summary'] as String? ?? '').trim();
          final points = (item['points'] as List? ?? [])
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .take(12)
              .toList();
          final key =
              'diagram:${title.toLowerCase()}|${points.join('|').toLowerCase()}';
          if (seen.containsKey(key)) continue;
          seen[key] = true;
          items.add({
            'type': 'diagram',
            'title': title.isNotEmpty ? title : 'Diagram',
            'summary': summary,
            'points': points,
            'diagram_type':
                (item['diagram_type'] as String? ?? 'diagram').trim(),
          });
        }
      }

      if (items.isNotEmpty) {
        finalSections.add({
          'heading': section['heading'],
          'items': items,
        });
      }
    }

    return finalSections;
  }

  static List<Map<String, dynamic>> _attachImagesToDirectSections(
    List<Map<String, dynamic>> sections,
    List<dynamic> images,
  ) {
    final unplaced = <Map<String, dynamic>>[];
    for (final image in images) {
      final path = (image['path'] as String? ?? '').trim();
      if (path.isEmpty) continue;

      final block = {
        'type': 'image',
        'path': path,
        'caption':
            ((image['label'] ?? image['original_name']) as String? ?? 'Image')
                .trim(),
      };

      final targetIndex = _bestDirectImageSectionIndex(sections, image);
      if (targetIndex == null) {
        unplaced.add(block);
        continue;
      }

      (sections[targetIndex]['items'] as List).add(block);
    }
    return unplaced;
  }

  static List<Map<String, dynamic>> _attachDiagramsToDirectSections(
    List<Map<String, dynamic>> sections,
    List<dynamic> diagrams,
  ) {
    final unplaced = <Map<String, dynamic>>[];
    for (final diagram in diagrams) {
      final title =
          ((diagram['label'] ?? diagram['title']) as String? ?? 'Diagram')
              .trim();
      final points = (diagram['points'] as List? ?? [])
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final summary = (diagram['summary'] as String? ?? '').trim();

      if (title.isEmpty && points.isEmpty && summary.isEmpty) continue;

      final block = {
        'type': 'diagram',
        'title': title.isNotEmpty ? title : 'Diagram',
        'summary': summary,
        'points': points.take(12).toList(),
        'diagram_type':
            (diagram['diagram_type'] as String? ?? 'diagram').trim(),
      };

      final targetIndex = _bestDirectDiagramSectionIndex(sections, diagram);
      if (targetIndex == null) {
        unplaced.add(block);
        continue;
      }

      (sections[targetIndex]['items'] as List).add(block);
    }
    return unplaced;
  }

  static Map<String, dynamic>? _formulaReferenceSection(
    List<dynamic> references,
    List<dynamic> formulaPages,
    bool rendererAvailable,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final reference in references) {
      final path = (reference['path'] as String? ?? '').trim();
      if (path.isEmpty) continue;

      final pageNumber = reference['page_number'] as int? ?? 0;
      var caption =
          ((reference['label'] ?? 'Formula Reference') as String).trim();
      final preview = (reference['formula_preview'] as String? ?? '').trim();
      if (preview.isNotEmpty) {
        caption += ' - $preview';
      } else if (pageNumber > 0) {
        caption += ' - PDF page $pageNumber';
      }

      items.add({
        'type': 'image',
        'path': path,
        'caption': caption,
        'width_percent': 100,
      });
    }

    if (items.isNotEmpty) {
      return {
        'heading': 'Formula References',
        'items': items,
      };
    }

    if (formulaPages.isNotEmpty && !rendererAvailable) {
      return {
        'heading': 'Formula References',
        'items': [
          {
            'type': 'paragraph',
            'text':
                'Formula-heavy PDF pages were detected, but exact formula preview images are unavailable because no PDF page renderer is installed on the server.',
          },
        ],
      };
    }

    return null;
  }

  static int? _bestDirectImageSectionIndex(
      List<Map<String, dynamic>> sections, dynamic image) {
    if (sections.isEmpty) return null;
    int? bestIndex;
    double bestScore = 0;

    for (int i = 0; i < sections.length; i++) {
      final score = _directImageSectionScore(
          sections[i]['heading'] as String? ?? '', image);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex != null && bestScore >= 18) return bestIndex;
    return sections.isEmpty ? null : sections.length - 1;
  }

  static double _directImageSectionScore(String sectionHeading, dynamic image) {
    final heading = sectionHeading.toLowerCase().trim();
    if (heading.isEmpty) return 0;

    final contextHeading =
        (image['context_heading'] as String? ?? '').toLowerCase().trim();
    final contextText =
        (image['context_text'] as String? ?? '').toLowerCase().trim();
    final caption =
        ((image['label'] ?? image['original_name']) as String? ?? '')
            .toLowerCase()
            .trim();

    double score = 0;
    if (contextHeading.isNotEmpty) {
      score = _similarityScore(heading, contextHeading);
      if (contextHeading.contains(heading) ||
          heading.contains(contextHeading)) {
        score = score.clamp(95, 100);
      }
    }

    if (contextText.isNotEmpty) {
      final textScore = _similarityScore(heading, contextText) * 0.55;
      score = score > textScore ? score : textScore;
      if (contextText.contains(heading)) {
        score = score > 72 ? score : 72;
      }
    }

    if (caption.isNotEmpty) {
      final captionScore = _similarityScore(heading, caption) * 0.4;
      score = score > captionScore ? score : captionScore;
    }

    return score;
  }

  static int? _bestDirectDiagramSectionIndex(
      List<Map<String, dynamic>> sections, dynamic diagram) {
    if (sections.isEmpty) return null;
    int? bestIndex;
    double bestScore = 0;

    for (int i = 0; i < sections.length; i++) {
      final score = _directDiagramSectionScore(
          sections[i]['heading'] as String? ?? '', diagram);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex != null && bestScore >= 16) return bestIndex;
    return sections.isEmpty ? null : sections.length - 1;
  }

  static double _directDiagramSectionScore(
      String sectionHeading, dynamic diagram) {
    final heading = sectionHeading.toLowerCase().trim();
    if (heading.isEmpty) return 0;

    final contextHeading =
        (diagram['context_heading'] as String? ?? '').toLowerCase().trim();
    final contextText =
        (diagram['context_text'] as String? ?? '').toLowerCase().trim();
    final title = ((diagram['label'] ?? diagram['title']) as String? ?? '')
        .toLowerCase()
        .trim();
    final summary = (diagram['summary'] as String? ?? '').toLowerCase().trim();

    double score = 0;
    for (final candidate in [contextHeading, title]) {
      if (candidate.isEmpty) continue;
      final candidateScore = _similarityScore(heading, candidate);
      score = score > candidateScore ? score : candidateScore;
      if (candidate.contains(heading) || heading.contains(candidate)) {
        score = score > 92 ? score : 92;
      }
    }

    for (final candidate in [contextText, summary]) {
      if (candidate.isEmpty) continue;
      final candidateScore = _similarityScore(heading, candidate) * 0.55;
      score = score > candidateScore ? score : candidateScore;
      if (candidate.contains(heading)) {
        score = score > 70 ? score : 70;
      }
    }

    return score;
  }

  static String _postProcessDirectText(
      String text, bool cleanGrammar, bool summarize) {
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';

    text = _repairDirectTextArtifacts(text);

    if (cleanGrammar) {
      text = text.replaceAll(RegExp(r'\s+([,.!?;:])'), r'$1');
      text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
      text = text[0].toUpperCase() + text.substring(1);
    }

    if (summarize) {
      text = _summarizeText(text, 2);
    }

    return text.trim();
  }

  static String _repairDirectTextArtifacts(String text) {
    text = text.replaceAll(
        RegExp(r'(?<=[A-Za-z])(?=[αμσ₁₂])|(?<=[αμσ₁₂])(?=[A-Za-z])',
            unicode: true),
        ' ');
    text = text.replaceAll(RegExp(r'(?<=\d)(?=[A-Za-z])'), ' ');
    text = text.replaceAll(RegExp(r'(?<=[A-Za-z])(?=\d)'), ' ');
    text = text.replaceAll(RegExp(r'(?<=:)(?=[^\s\)\]}])'), ' ');
    text = text.replaceAll(RegExp(r'\s*=\s*'), ' = ');
    text = text.replaceAll(RegExp(r',(?=[^\s])'), ', ');

    final replacements = {
      'Acompany': 'A company',
      'comparestwo': 'compares two',
      'websiteversions': 'website versions',
      'TestofMeansforTwo': 'Test of Means for Two',
      'Testof': 'Test of',
      'Meansfor': 'Means for',
      'Solutionto': 'Solution to',
      'forPerforming': 'for Performing',
      'forPerforminga': 'for Performing a',
      'Performinga': 'Performing a',
      'Standarddeviation': 'Standard deviation',
      'Meanresponsetime': 'Mean response time',
      'Samplesize': 'Sample size',
      'significantdifference': 'significant difference',
      'Twomobileappsaretested': 'Two mobile apps are tested',
      'TestRun': 'Test Run',
      'testif': 'test if',
      'ifthere': 'if there',
      'therea': 'there a',
      'thetwo': 'the two',
      'twodatabase': 'two database',
      'twodatabase systems': 'two database systems',
      'databasesystems': 'database systems',
      'inthemeanexecutiontimes': 'in the mean execution times',
      'twodatabasesystems': 'two database systems',
      'Atα': 'At α',
    };

    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
    return text.trim();
  }

  static String _summarizeText(String text, int sentenceLimit) {
    final placeholders = {
      'Ex.': 'Ex__DOT__',
      'e.g.': 'eg__DOT__',
      'i.e.': 'ie__DOT__',
      'ff.': 'ff__DOT__',
      'Mr.': 'Mr__DOT__',
      'Mrs.': 'Mrs__DOT__',
      'Ms.': 'Ms__DOT__',
      'Dr.': 'Dr__DOT__',
      'Prof.': 'Prof__DOT__',
    };

    var prepared = text;
    for (final entry in placeholders.entries) {
      prepared = prepared.replaceAll(entry.key, entry.value);
    }

    final sentences = prepared.split(RegExp(r'(?<=[.!?])\s+'));
    var summary = sentences.take(sentenceLimit).join(' ');

    for (final entry in placeholders.entries) {
      summary = summary.replaceAll(entry.value, entry.key);
    }

    return summary;
  }

  static Map<String, dynamic> analyze(String text,
      {String title = 'Untitled Template'}) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final structure = {
      'title': title,
      'headings': <Map<String, dynamic>>[],
      'sections': <Map<String, dynamic>>[],
      'tables': <Map<String, dynamic>>[],
      'lists': <Map<String, dynamic>>[],
      'raw_lines': lines,
    };

    Map<String, dynamic>? currentSection;
    for (final line in lines) {
      if (_isArtifactLine(line)) continue;

      if (_isHeading(line)) {
        final placeholder = _headingPlaceholder(
            line, (structure['headings'] as List).length + 1);
        (structure['headings'] as List)
            .add({'text': line, 'placeholder': placeholder});
        if (currentSection != null) {
          (structure['sections'] as List).add(currentSection);
        }
        currentSection = {
          'heading': line,
          'placeholder': placeholder,
          'content': <String>[],
        };
        continue;
      }

      currentSection ??= {
        'heading': 'Introduction',
        'placeholder': '{{SECTION_1}}',
        'content': <String>[],
      };

      if (_isTableRow(line)) {
        final placeholder =
            '{{TABLE_${(structure['tables'] as List).length + 1}}}';
        final cells = line
            .split(RegExp(r'\||\t'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        (structure['tables'] as List).add({
          'source': line,
          'placeholder': placeholder,
          'column_count': cells.isEmpty ? 1 : cells.length,
        });
        (currentSection['content'] as List).add(placeholder);
        continue;
      }

      if (_isListItem(line)) {
        final placeholder =
            '{{LIST_${(structure['lists'] as List).length + 1}}}';
        (structure['lists'] as List)
            .add({'source': line, 'placeholder': placeholder});
        (currentSection['content'] as List).add(placeholder);
        continue;
      }

      (currentSection['content'] as List).add(line);
    }

    if (currentSection != null) {
      (structure['sections'] as List).add(currentSection);
    }

    if ((structure['headings'] as List).isEmpty && lines.isNotEmpty) {
      return _buildFallbackStructure(lines, title);
    }

    return {
      'structure': structure,
      'placeholders': _buildPlaceholderMap(structure),
    };
  }

  static bool _isHeading(String line) {
    return RegExp(
            r'^(chapter|module|lesson|section|unit|\d+(\.\d+)*|[A-Z][A-Z\s]{4,})',
            caseSensitive: false)
        .hasMatch(line);
  }

  static bool _isTableRow(String line) {
    return line.contains('|') || RegExp(r'\t.{2,}\t').hasMatch(line);
  }

  static bool _isListItem(String line) {
    return RegExp(r'^(\-|\*|\d+\.)\s+').hasMatch(line);
  }

  static bool _isArtifactLine(String line) {
    final trimmed = line.trim();
    return RegExp(
      r'^(?:\d+\s+\d+\s+obj|endobj|xref|startxref|trailer|stream|endstream)$',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static String _headingPlaceholder(String heading, int index) {
    final normalized =
        heading.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase();
    return '{{SECTION_${normalized.isNotEmpty ? normalized : index.toString()}}}';
  }

  static String _uniqueDirectPlaceholder(
    String prefix,
    String heading,
    int index,
    Map<String, int> used,
  ) {
    final normalized =
        heading.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase();
    final base =
        '{{${prefix}_${normalized.isNotEmpty ? normalized : index.toString()}}}';

    if (!used.containsKey(base)) {
      used[base] = 1;
      return base;
    }

    used[base] = (used[base] ?? 1) + 1;
    return '{{${prefix}_${normalized.isNotEmpty ? normalized : index.toString()}_${used[base]}}}';
  }

  static Map<String, dynamic> _buildPlaceholderMap(
      Map<String, dynamic> structure) {
    final map = <String, dynamic>{'{{TITLE}}': structure['title']};
    for (final heading in structure['headings'] as List) {
      map[heading['placeholder'] as String] = heading['text'];
      map[_contentPlaceholderForHeading(heading['text'] as String)] = [];
    }
    for (final table in structure['tables'] as List) {
      map[table['placeholder'] as String] = [];
    }
    for (final list in structure['lists'] as List) {
      map[list['placeholder'] as String] = [];
    }
    return map;
  }

  static String _contentPlaceholderForHeading(String heading) {
    final label =
        heading.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase();
    return '{{CONTENT_${label.replaceAll(RegExp(r'^_+|_+$'), '')}}}';
  }

  static Map<String, dynamic> _buildFallbackStructure(
      List<String> lines, String title) {
    final chunkSize = (lines.length / 4).ceil().clamp(1, 6);
    final chunks = <List<String>>[];
    for (int i = 0; i < lines.length; i += chunkSize) {
      chunks.add(lines.sublist(i, (i + chunkSize).clamp(0, lines.length)));
    }

    final sections = <Map<String, dynamic>>[];
    final headings = <Map<String, dynamic>>[];

    for (int i = 0; i < chunks.length; i++) {
      final heading = i == 0 ? 'Template Body' : 'Template Block ${i + 1}';
      final placeholder = '{{SECTION_${i + 1}}}';
      headings.add({'text': heading, 'placeholder': placeholder});
      sections.add({
        'heading': heading,
        'placeholder': placeholder,
        'content': chunks[i],
      });
    }

    return {
      'structure': {
        'title': title,
        'headings': headings,
        'sections': sections,
        'tables': [],
        'lists': [],
        'raw_lines': lines,
      },
      'placeholders': _buildPlaceholderMap({
        'title': title,
        'headings': headings,
        'sections': sections,
        'tables': [],
        'lists': [],
        'raw_lines': lines,
      }),
    };
  }

  static double _similarityScore(String s1, String s2) {
    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();
    if (s1 == s2) return 100;

    final longer = s1.length > s2.length ? s1 : s2;
    final shorter = s1.length > s2.length ? s2 : s1;
    if (longer.isEmpty) return 100;

    final distance = _levenshteinDistance(longer, shorter);
    return ((longer.length - distance) / longer.length) * 100;
  }

  static int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final previousRow = List<int>.generate(s2.length + 1, (i) => i);

    for (int i = 0; i < s1.length; i++) {
      final currentRow = [i + 1];
      for (int j = 0; j < s2.length; j++) {
        final insertions = previousRow[j + 1] + 1;
        final deletions = currentRow[j] + 1;
        final substitutions = previousRow[j] + (s1[i] != s2[j] ? 1 : 0);
        currentRow.add([insertions, deletions, substitutions]
            .reduce((a, b) => a < b ? a : b));
      }
      for (int j = 0; j <= s2.length; j++) {
        previousRow[j] = currentRow[j];
      }
    }

    return previousRow[s2.length];
  }
}
