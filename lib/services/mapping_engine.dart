class MappingEngine {
  static Map<String, dynamic> map(
    Map<String, dynamic> templateModel,
    Map<String, dynamic> dataModel, {
    bool cleanGrammar = true,
    bool summarize = false,
  }) {
    final mapping =
        Map<String, dynamic>.from(templateModel['placeholders'] as Map? ?? {});
    mapping['{{TITLE}}'] = (dataModel['title'] as String? ?? '').isNotEmpty
        ? dataModel['title']
        : (templateModel['structure'] as Map? ?? {})['title'] ?? 'Untitled';

    final headings = List<String>.from(dataModel['headings'] as List? ?? []);
    final paragraphs =
        List<String>.from(dataModel['paragraphs'] as List? ?? []);
    final lists = (dataModel['lists'] as List? ?? [])
        .map((e) => List<String>.from(e as List))
        .toList();
    final tables =
        _normalizeExtractedTables(dataModel['tables'] as List? ?? []);
    final importantPoints =
        List<String>.from(dataModel['important_points'] as List? ?? []);
    final keyValues = (dataModel['key_values'] as List? ?? [])
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
    final images = _normalizeImages(
        (dataModel['meta'] as Map? ?? {})['images'] as List? ?? []);
    final diagrams = _normalizeDiagrams(
        (dataModel['meta'] as Map? ?? {})['diagrams'] as List? ?? []);
    final hasExplicitEmphasis =
        (dataModel['meta'] as Map? ?? {})['has_explicit_emphasis'] as bool? ??
            false;
    final globalEmphasisTerms = List<String>.from(
        (dataModel['meta'] as Map? ?? {})['emphasized_terms'] as List? ?? []);
    mapping['{{EMPHASIS_TERMS}}'] = globalEmphasisTerms;

    final structureSections = List<Map<String, dynamic>>.from(
        (templateModel['structure'] as Map? ?? {})['sections'] as List? ?? []);

    final imageAssignments = _assignImagesToSections(structureSections, images);
    final tableAssignments = _assignTablesToSections(structureSections, tables);
    final diagramAssignments =
        _assignDiagramsToSections(structureSections, diagrams);

    for (int index = 0; index < structureSections.length; index++) {
      final section = structureSections[index];

      mapping[section['placeholder'] as String] = _bestHeadingMatch(
            section['heading'] as String? ?? '',
            headings,
          ) ??
          section['heading'];

      final content = <Map<String, dynamic>>[];

      final sectionImportant = _matchSectionImportantPoints(
        section['heading'] as String? ?? '',
        importantPoints,
        hasExplicitEmphasis,
      );
      final sectionKeyValues = _matchSectionKeyValues(
          section['heading'] as String? ?? '', keyValues);
      final assignedSectionTables = tableAssignments[index] ?? [];
      final sectionTable = _matchSectionTable(
        List<String>.from(section['content'] as List? ?? []),
        assignedSectionTables,
        sectionKeyValues,
        sectionImportant,
      );
      final sectionEmphasisTerms = _matchSectionEmphasisTerms(
        section['heading'] as String? ?? '',
        globalEmphasisTerms,
        sectionImportant,
        index < paragraphs.length ? paragraphs[index] : null,
        sectionKeyValues,
        _mergeSectionTableCandidates(assignedSectionTables, sectionTable),
      );

      for (final table in assignedSectionTables) {
        content.add({
          'type': 'table',
          'rows': table['rows'],
          'emphasis_terms': _matchBlockEmphasisTerms(
              _flattenTableRows(table['rows'] as List), sectionEmphasisTerms),
        });
      }

      if (sectionTable != null) {
        content.add({
          'type': 'table',
          'rows': sectionTable,
          'emphasis_terms': _matchBlockEmphasisTerms(
              _flattenTableRows(sectionTable), sectionEmphasisTerms),
        });
      }

      final sectionList = _matchSectionList(section['heading'] as String? ?? '',
          lists, sectionImportant, hasExplicitEmphasis);
      if (sectionList.isNotEmpty) {
        content.add({
          'type': 'list',
          'items': sectionList,
          'emphasis_terms':
              _matchBlockEmphasisTerms(sectionList, sectionEmphasisTerms),
        });
      }

      final paragraphText = _buildSectionParagraph(
          sectionImportant,
          index < paragraphs.length ? paragraphs[index] : null,
          cleanGrammar,
          summarize);
      if (paragraphText != null) {
        content.add({
          'type': 'paragraph',
          'text': paragraphText,
          'emphasis_terms':
              _matchBlockEmphasisTerms([paragraphText], sectionEmphasisTerms),
        });
      }

      if (content.isEmpty) {
        final fallback = _buildSectionParagraph(
            importantPoints.take(4).toList(),
            paragraphs.isNotEmpty
                ? paragraphs.first
                : 'Content generated from uploaded data.',
            cleanGrammar,
            true);
        final fallbackText =
            fallback ?? 'Content generated from uploaded data.';
        content.add({
          'type': 'paragraph',
          'text': fallbackText,
          'emphasis_terms':
              _matchBlockEmphasisTerms([fallbackText], sectionEmphasisTerms),
        });
      }

      for (final image in imageAssignments[index] ?? []) {
        content.add({
          'type': 'image',
          'path': image['path'],
          'caption': image['caption'],
        });
      }

      for (final diagram in diagramAssignments[index] ?? []) {
        content.add({
          'type': 'diagram',
          'title': diagram['title'],
          'summary': diagram['summary'],
          'points': diagram['points'],
          'diagram_type': diagram['diagram_type'],
        });
      }

      mapping[_contentPlaceholderForHeading(
          section['heading'] as String? ?? '')] = content;
    }

    return mapping;
  }

  static String? _bestHeadingMatch(
      String templateHeading, List<String> candidates) {
    final lowerTemplate = templateHeading.toLowerCase();
    String? best;
    double bestScore = 0;

    for (final candidate in candidates) {
      final score = _similarityScore(lowerTemplate, candidate.toLowerCase());
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return bestScore >= 25 ? best : null;
  }

  static String _postProcess(String text, bool cleanGrammar, bool summarize) {
    text = text.trim();
    if (cleanGrammar) {
      text = text.replaceAll(RegExp(r'\s+([,.!?;:])'), r'$1');
      text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
      text = text[0].toUpperCase() + text.substring(1);
    }

    if (summarize) {
      text = _summarizeText(text, 3);
    }

    return text;
  }

  static List<String> _matchSectionImportantPoints(
      String heading, List<String> importantPoints, bool hasExplicitEmphasis) {
    final matched = <String>[];
    final headingLower = heading.toLowerCase();

    for (final point in importantPoints) {
      final pointText = point.trim();
      if (pointText.isEmpty) continue;

      final score = _similarityScore(headingLower, pointText.toLowerCase());
      if (score >= (hasExplicitEmphasis ? 28 : 20) ||
          pointText.toLowerCase().contains(headingLower)) {
        matched.add(pointText);
      }
    }

    return matched.take(hasExplicitEmphasis ? 4 : 6).toList();
  }

  static List<Map<String, String>> _matchSectionKeyValues(
      String heading, List<Map<String, String>> keyValues) {
    final matched = <Map<String, String>>[];
    final headingLower = heading.toLowerCase();

    for (final pair in keyValues) {
      final key = (pair['key'] ?? '').toLowerCase();
      final value = (pair['value'] ?? '').trim();
      if (key.isEmpty || value.isEmpty) continue;

      final score = _similarityScore(headingLower, key);
      if (score >= 18 ||
          headingLower.contains(key) ||
          key.contains(headingLower)) {
        matched.add({'key': pair['key']!, 'value': value});
      }
    }

    return matched.take(5).toList();
  }

  static List<List<String>>? _matchSectionTable(
    List<String> sectionContent,
    List<Map<String, dynamic>> assignedTables,
    List<Map<String, String>> sectionKeyValues,
    List<String> sectionImportant,
  ) {
    var expectsTable = false;
    for (final item in sectionContent) {
      if (RegExp(r'^\{\{TABLE_\d+\}\}$').hasMatch(item)) {
        expectsTable = true;
        break;
      }
    }

    if (!expectsTable &&
        sectionKeyValues.isEmpty &&
        assignedTables.isNotEmpty) {
      return null;
    }

    if (!expectsTable && sectionKeyValues.isEmpty && assignedTables.isEmpty) {
      return null;
    }

    if (sectionKeyValues.isNotEmpty) {
      final rows = [
        ['Key', 'Value']
      ];
      for (final pair in sectionKeyValues) {
        rows.add([pair['key']!, pair['value']!]);
      }
      return rows.take(6).toList();
    }

    if (sectionImportant.isNotEmpty) {
      final rows = [
        ['Important Points']
      ];
      for (final point in sectionImportant) {
        rows.add([point]);
      }
      return rows.take(6).toList();
    }

    return null;
  }

  static List<String> _matchSectionList(
    String heading,
    List<List<String>> lists,
    List<String> sectionImportant,
    bool hasExplicitEmphasis,
  ) {
    for (final list in lists) {
      if (list.length >= 2) {
        return list.take(hasExplicitEmphasis ? 4 : 6).toList();
      }
    }

    if (sectionImportant.isNotEmpty) {
      return sectionImportant.take(hasExplicitEmphasis ? 4 : 5).toList();
    }

    return [];
  }

  static String? _buildSectionParagraph(List<String> sectionImportant,
      String? fallbackParagraph, bool cleanGrammar, bool summarize) {
    if (sectionImportant.isNotEmpty) {
      final selected = sectionImportant.take(summarize ? 2 : 3).toList();
      return _postProcess(selected.join('\n'), cleanGrammar, false);
    }

    if (fallbackParagraph != null && fallbackParagraph.trim().isNotEmpty) {
      return _postProcess(fallbackParagraph, cleanGrammar, true);
    }

    return null;
  }

  static List<String> _matchSectionEmphasisTerms(
    String heading,
    List<String> globalEmphasisTerms,
    List<String> sectionImportant,
    String? paragraphText,
    List<Map<String, String>> sectionKeyValues,
    List<List<List<String>>> sectionTables,
  ) {
    final candidates = [heading];
    for (final point in sectionImportant) {
      candidates.add(point);
    }
    if (paragraphText != null) {
      candidates.add(paragraphText);
    }
    for (final pair in sectionKeyValues) {
      candidates.add('${pair['key']} ${pair['value']}');
    }
    for (final table in sectionTables) {
      candidates.addAll(_flattenTableRows(table));
    }

    final matched = <String>[];
    for (final term in globalEmphasisTerms) {
      final termTrimmed = term.trim();
      if (termTrimmed.isEmpty) continue;

      for (final candidate in candidates) {
        if (_termMatchesCandidate(termTrimmed, candidate)) {
          matched.add(termTrimmed);
          break;
        }
      }
    }

    return matched.toSet().toList();
  }

  static List<String> _matchBlockEmphasisTerms(
      List<String> texts, List<String> sectionEmphasisTerms) {
    final matched = <String>[];
    for (final term in sectionEmphasisTerms) {
      for (final text in texts) {
        if (_termMatchesCandidate(term, text)) {
          matched.add(term);
          break;
        }
      }
    }
    return matched.toSet().toList();
  }

  static List<Map<String, dynamic>> _normalizeExtractedTables(
      List<dynamic> tables) {
    final normalized = <Map<String, dynamic>>[];
    for (final table in tables) {
      final dynamic rowsSource = table is Map ? table['rows'] : table;
      final rows = _normalizeRows(rowsSource as List? ?? []);
      if (rows.isNotEmpty) {
        normalized.add({'rows': rows});
      }
    }
    return normalized;
  }

  static List<Map<String, dynamic>> _normalizeImages(List<dynamic> images) {
    return images
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .where((image) => (image['path'] as String? ?? '').trim().isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _normalizeDiagrams(List<dynamic> diagrams) {
    return diagrams
        .whereType<Map>()
        .map((diagram) => Map<String, dynamic>.from(diagram))
        .where((diagram) {
      final title =
          (diagram['title'] ?? diagram['label'] ?? '').toString().trim();
      final summary = (diagram['summary'] ?? '').toString().trim();
      final points = diagram['points'] as List? ?? [];
      return title.isNotEmpty || summary.isNotEmpty || points.isNotEmpty;
    }).toList();
  }

  static Map<int, List<Map<String, dynamic>>> _assignImagesToSections(
    List<Map<String, dynamic>> sections,
    List<Map<String, dynamic>> images,
  ) {
    return _assignBlocksToSections(sections, images);
  }

  static Map<int, List<Map<String, dynamic>>> _assignTablesToSections(
    List<Map<String, dynamic>> sections,
    List<Map<String, dynamic>> tables,
  ) {
    return _assignBlocksToSections(sections, tables);
  }

  static Map<int, List<Map<String, dynamic>>> _assignDiagramsToSections(
    List<Map<String, dynamic>> sections,
    List<Map<String, dynamic>> diagrams,
  ) {
    return _assignBlocksToSections(sections, diagrams);
  }

  static Map<int, List<Map<String, dynamic>>> _assignBlocksToSections(
    List<Map<String, dynamic>> sections,
    List<Map<String, dynamic>> blocks,
  ) {
    final assignments = <int, List<Map<String, dynamic>>>{};
    if (sections.isEmpty) return assignments;

    for (final block in blocks) {
      var bestIndex = 0;
      var bestScore = 0.0;
      final blockText = [
        block['context_heading'],
        block['context_text'],
        block['caption'],
        block['label'],
        block['title'],
        block['summary'],
      ].whereType<String>().join(' ').toLowerCase();

      for (int i = 0; i < sections.length; i++) {
        final heading = (sections[i]['heading'] as String? ?? '').toLowerCase();
        final score = _similarityScore(heading, blockText);
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }

      assignments.putIfAbsent(bestIndex, () => []).add(block);
    }

    return assignments;
  }

  static List<List<List<String>>> _mergeSectionTableCandidates(
    List<Map<String, dynamic>> assignedTables,
    List<List<String>>? sectionTable,
  ) {
    final tables = <List<List<String>>>[];
    for (final table in assignedTables) {
      tables.add(_normalizeRows(table['rows'] as List? ?? []));
    }
    if (sectionTable != null) {
      tables.add(sectionTable);
    }
    return tables.where((table) => table.isNotEmpty).toList();
  }

  static List<String> _flattenTableRows(List<dynamic> rows) {
    return _normalizeRows(rows).expand((row) => row).toList();
  }

  static List<List<String>> _normalizeRows(List<dynamic> rows) {
    final normalized = <List<String>>[];
    for (final row in rows) {
      final cells = (row as List? ?? [])
          .map((cell) => cell.toString().trim())
          .where((cell) => cell.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) normalized.add(cells);
    }
    return normalized;
  }

  static String _contentPlaceholderForHeading(String heading) {
    final label = heading
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toUpperCase();
    return '{{CONTENT_${label.isNotEmpty ? label : 'SECTION'}}}';
  }

  static double _similarityScore(String s1, String s2) {
    s1 = s1.toLowerCase().trim();
    s2 = s2.toLowerCase().trim();
    if (s1.isEmpty || s2.isEmpty) return 0;
    if (s1 == s2) return 100;
    if (s1.contains(s2) || s2.contains(s1)) return 75;

    final words1 = s1.split(RegExp(r'\s+')).toSet();
    final words2 = s2.split(RegExp(r'\s+')).toSet();
    final shared = words1.intersection(words2).length;
    final total = words1.union(words2).length;
    if (total == 0) return 0;
    return (shared / total) * 100;
  }

  static String _summarizeText(String text, int sentenceLimit) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return text;
    return sentences.take(sentenceLimit).join(' ');
  }

  static bool _termMatchesCandidate(String term, String candidate) {
    final normalizedTerm = term.toLowerCase().trim();
    final normalizedCandidate = candidate.toLowerCase();
    if (normalizedTerm.isEmpty || normalizedCandidate.isEmpty) return false;
    return normalizedCandidate.contains(normalizedTerm) ||
        _similarityScore(normalizedTerm, normalizedCandidate) >= 35;
  }
}
