class ContentSafety {
  static Map<String, dynamic> scanText(String text) {
    final issues = <Map<String, dynamic>>[];
    final artifactLines = <String>[];

    for (final line in text.split(RegExp(r'\r\n|\r|\n'))) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && _isArtifactLine(trimmed)) {
        artifactLines.add(trimmed);
      }
    }

    final pdfArtifacts = _matchCount(r'\b(?:\d+\s+\d+\s+obj|endobj|xref|startxref|trailer|stream|endstream)\b', text);
    if (pdfArtifacts['count'] > 0) {
      issues.add({
        'code': 'pdf_artifacts',
        'title': 'PDF extraction artifacts detected',
        'message': 'The source appears to contain PDF object markers such as "endobj" or "xref". These can leak into the final document.',
        'count': pdfArtifacts['count'],
        'samples': artifactLines.isNotEmpty ? artifactLines.take(5).toList() : pdfArtifacts['samples'],
      });
    }

    final emojiMatches = _matchChars(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', text);
    if (emojiMatches['count'] > 0) {
      issues.add({
        'code': 'emoji',
        'title': 'Emoji characters detected',
        'message': 'Emoji or pictographic characters may render badly or break parts of the generated output.',
        'count': emojiMatches['count'],
        'samples': emojiMatches['samples'],
      });
    }

    final symbolMatches = _matchChars(r'[\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{25A0}-\u{25FF}\u{2700}-\u{27BF}]', text);
    if (symbolMatches['count'] > 0) {
      issues.add({
        'code': 'symbols',
        'title': 'Uncommon symbols detected',
        'message': 'Decorative or uncommon symbols were found. Some of them may not map cleanly into DOCX/PDF output.',
        'count': symbolMatches['count'],
        'samples': symbolMatches['samples'],
      });
    }

    final replacement = _matchChars(r'\u{FFFD}', text);
    if (replacement['count'] > 0) {
      issues.add({
        'code': 'replacement_character',
        'title': 'Broken text encoding detected',
        'message': 'The source contains replacement characters, which usually means corrupted text extraction.',
        'count': replacement['count'],
        'samples': replacement['samples'],
      });
    }

    return {
      'has_issues': issues.isNotEmpty,
      'issue_count': issues.length,
      'issues': issues,
      'artifact_lines': artifactLines.toSet().toList(),
    };
  }

  static bool _isArtifactLine(String line) {
    final trimmed = line.trim();
    return RegExp(r'^(?:\d+\s+\d+\s+obj|endobj|xref|startxref|trailer|stream|endstream)$', caseSensitive: false).hasMatch(trimmed);
  }

  static Map<String, dynamic> sanitizeDataModel(Map<String, dynamic> dataModel) {
    _sanitizeValue(dataModel);
    dataModel['meta'] ??= {};
    dataModel['meta']['sanitized_for_output'] = true;
    return dataModel;
  }

  static void _sanitizeValue(dynamic value) {
    if (value is String) {
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.value is String) {
          value[entry.key] = sanitizeText(entry.value as String);
        } else if (entry.value is Map || entry.value is List) {
          _sanitizeValue(entry.value);
        }
      }
    }
    if (value is List) {
      for (int i = 0; i < value.length; i++) {
        if (value[i] is String) {
          value[i] = sanitizeText(value[i] as String);
        } else if (value[i] is Map || value[i] is List) {
          _sanitizeValue(value[i]);
        }
      }
    }
  }

  static String sanitizeText(String text) {
    text = text.replaceAll(RegExp(r'\b\d+\s+\d+\s+obj\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\b(?:endobj|xref|startxref|trailer|stream|endstream)\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), ' ');
    text = text.replaceAll(RegExp(r'[\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{25A0}-\u{25FF}\u{2700}-\u{27BF}]', unicode: true), ' ');
    text = text.replaceAll(RegExp(r'[^\P{C}\n\t]', unicode: true), ' ');
    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static Map<String, dynamic> _matchCount(String pattern, String text) {
    final matches = RegExp(pattern, caseSensitive: false).allMatches(text).toList();
    final found = matches.map((m) => m.group(0)!).toSet().toList();
    return {
      'count': matches.length,
      'samples': found.take(5).toList(),
    };
  }

  static Map<String, dynamic> _matchChars(String pattern, String text) {
    if (pattern.isEmpty) {
      return {
        'count': 0,
        'samples': <String>[],
      };
    }

    final matches = RegExp(pattern, unicode: true).allMatches(text).toList();
    final found = matches.map((m) => m.group(0)!).toSet().toList();
    return {
      'count': matches.length,
      'samples': found.take(8).toList(),
    };
  }
}
