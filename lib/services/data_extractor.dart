import '../models/data_model.dart';
import 'math_formula_service.dart';

enum _FormulaState { none, review, strong }

class DataExtractor {
  static const int structureVersion = 2;

  /// Builds the same app data model from a document parser that already knows
  /// the source order. This avoids running DOCX tables and images through the
  /// line-based text detector, which is what previously moved them away from
  /// their surrounding labels and paragraphs.
  static DataModel fromStructuredBlocks(
    List<Map<String, dynamic>> sourceBlocks, {
    String sourceFormat = 'docx',
  }) {
    final headings = <String>[];
    final paragraphs = <String>[];
    final lists = <List<String>>[];
    final tables = <List<List<String>>>[];
    final importantPoints = <String>[];
    final keyValues = <Map<String, String>>[];
    final blocks = <Map<String, dynamic>>[];
    var title = 'Converted Document';

    for (final rawBlock in sourceBlocks) {
      final block = Map<String, dynamic>.from(rawBlock);
      final type = block['type'] as String? ?? '';
      final text = (block['text'] as String? ?? '').trim();

      if (type == 'heading') {
        if (text.isEmpty) continue;
        headings.add(text);
        importantPoints.add(text);
        if (title == 'Converted Document') title = text;
        blocks.add(block);
        continue;
      }

      if (type == 'paragraph') {
        if (text.isEmpty) continue;
        paragraphs.add(text);
        blocks.add(block);
        continue;
      }

      if (type == 'formula') {
        if (text.isEmpty) continue;
        paragraphs.add(text);
        importantPoints.add(text);
        blocks.add(block);
        continue;
      }

      if (type == 'table') {
        final rows = <List<String>>[];
        for (final rawRow in block['rows'] as List? ?? []) {
          if (rawRow is! List) continue;
          final row = rawRow.map((cell) => cell.toString()).toList();
          if (row.isNotEmpty) rows.add(row);
        }
        if (rows.isEmpty) continue;
        tables.add(rows);
        block['rows'] = rows;
        blocks.add(block);
        continue;
      }

      if (type == 'list') {
        final items = (block['items'] as List? ?? [])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (items.isEmpty) continue;
        lists.add(items);
        block['items'] = items;
        blocks.add(block);
        continue;
      }

      // Image blocks intentionally have no text requirement. Their physical
      // placement is represented by their position in [blocks].
      if (type == 'image') {
        final path = (block['path'] as String? ?? '').trim();
        if (path.isNotEmpty) blocks.add(block);
      }
    }

    if (title == 'Converted Document' && paragraphs.isNotEmpty) {
      title = _detectTitle(paragraphs);
    }

    return DataModel(
      title: title,
      headings: headings,
      paragraphs: paragraphs,
      lists: lists,
      tables: tables,
      importantPoints: importantPoints.toSet().toList(),
      keyValues: keyValues,
      blocks: blocks,
      meta: {
        'structure_version': structureVersion,
        'has_explicit_emphasis': false,
        'emphasized_count': 0,
        'emphasized_terms': <String>[],
        'source_format': sourceFormat,
        'preserves_source_order': true,
      },
    );
  }

  static DataModel extract(String text,
      {Map<String, dynamic> hints = const {}}) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final emphasizedTerms =
        _normalizeEmphasizedTerms(hints['emphasized_terms'] as List? ?? []);
    final emphasizedLines = <String, bool>{};
    for (final line in hints['emphasized_lines'] as List? ?? []) {
      final normalized = _normalizeLine(line.toString());
      if (normalized.isNotEmpty) emphasizedLines[normalized] = true;
    }

    final result = DataModel(
      title: _detectTitle(lines),
      headings: [],
      paragraphs: [],
      lists: [],
      tables: [],
      importantPoints: [],
      keyValues: [],
      blocks: [],
      meta: {
        'structure_version': structureVersion,
        'has_explicit_emphasis': emphasizedLines.isNotEmpty,
        'emphasized_count': emphasizedLines.length,
        'emphasized_terms': emphasizedTerms,
      },
    );

    final paragraphBuffer = <String>[];
    String? pendingStandaloneEnumerator;

    for (final line in lines) {
      if (_isArtifactLine(line) || _isGarbageLine(line)) {
        result.meta['ignored_artifact_lines'] =
            (result.meta['ignored_artifact_lines'] as List? ?? [])..add(line);
        continue;
      }

      if (_isStandaloneEnumerator(line)) {
        _flushParagraph(paragraphBuffer, result);
        pendingStandaloneEnumerator = line;
        continue;
      }

      final isEmphasized = emphasizedLines.containsKey(_normalizeLine(line));

      final heading = _heading(line);
      if (heading != null) {
        _flushParagraph(paragraphBuffer, result);
        pendingStandaloneEnumerator = null;
        result.headings.add(heading);
        if (isEmphasized || emphasizedLines.isEmpty) {
          result.importantPoints.add(heading);
        }
        result.blocks
            .add({'type': 'heading', 'text': heading, 'important': true});
        continue;
      }

      if (_isTable(line)) {
        _flushParagraph(paragraphBuffer, result);
        pendingStandaloneEnumerator = null;
        final row = line
            .split(RegExp(r'\||\t'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        if (result.blocks.isNotEmpty && result.blocks.last['type'] == 'table') {
          result.tables.last.add(row);
          (result.blocks.last['rows'] as List).add(row);
        } else {
          result.tables.add([row]);
          result.blocks.add({
            'type': 'table',
            'rows': [row]
          });
        }
        continue;
      }

      final formulaState = _formulaState(line);
      if (formulaState != _FormulaState.none) {
        _flushParagraph(paragraphBuffer, result);
        final formula =
            _prefixStandaloneEnumerator(line, pendingStandaloneEnumerator);
        pendingStandaloneEnumerator = null;
        result.blocks.add({
          'type': 'formula',
          'text': formula,
          'confidence':
              formulaState == _FormulaState.strong ? 'strong' : 'review',
          if (formulaState == _FormulaState.review)
            'error':
                'This line looks mathematical, but the formula parser could not fully confirm it. Please review the exact expression.',
        });
        result.importantPoints.add(formula);
        if (formulaState == _FormulaState.review) {
          result.meta['formula_detection_warnings'] =
              (result.meta['formula_detection_warnings'] as List? ?? [])
                ..add(formula);
        }
        continue;
      }

      if (_isList(line)) {
        _flushParagraph(paragraphBuffer, result);
        final value = line.replaceFirst(RegExp(r'^(\-|\*|\d+\.)\s+'), '');
        final prefixedValue =
            _prefixStandaloneEnumerator(value, pendingStandaloneEnumerator);
        pendingStandaloneEnumerator = null;

        if (result.blocks.isNotEmpty && result.blocks.last['type'] == 'list') {
          result.lists.last.add(prefixedValue);
          (result.blocks.last['items'] as List).add(prefixedValue);
        } else {
          result.lists.add([prefixedValue]);
          result.blocks.add({
            'type': 'list',
            'items': [prefixedValue]
          });
        }

        if (isEmphasized || emphasizedLines.isEmpty) {
          result.importantPoints.add(prefixedValue);
        }
        continue;
      }

      final keyValue = _parseKeyValue(line);
      if (keyValue != null) {
        _flushParagraph(paragraphBuffer, result);
        final displayText = _prefixStandaloneEnumerator(
            '${keyValue['key']}: ${keyValue['value']}',
            pendingStandaloneEnumerator);
        pendingStandaloneEnumerator = null;
        result.keyValues.add(keyValue);
        result.importantPoints.add(displayText);
        result.blocks.add({
          'type': 'key_value',
          'key': keyValue['key'],
          'value': keyValue['value'],
          'text': displayText,
          'important': true,
        });
        continue;
      }

      if (isEmphasized ||
          (emphasizedLines.isEmpty && _isImportantSentence(line))) {
        _flushParagraph(paragraphBuffer, result);
        final prefixedLine =
            _prefixStandaloneEnumerator(line, pendingStandaloneEnumerator);
        pendingStandaloneEnumerator = null;
        result.importantPoints.add(prefixedLine);
        result.blocks.add(
            {'type': 'paragraph', 'text': prefixedLine, 'important': true});
        continue;
      }

      paragraphBuffer
          .add(_prefixStandaloneEnumerator(line, pendingStandaloneEnumerator));
      pendingStandaloneEnumerator = null;
    }

    if (pendingStandaloneEnumerator != null) {
      paragraphBuffer.add(pendingStandaloneEnumerator);
    }

    _flushParagraph(paragraphBuffer, result);
    final uniqueImportantPoints = result.importantPoints.toSet().toList();
    result.importantPoints
      ..clear()
      ..addAll(uniqueImportantPoints);
    return result;
  }

  static String _detectTitle(List<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          _isStandalonePageMarker(trimmed) ||
          _isStandaloneEnumerator(trimmed) ||
          _isGarbageLine(trimmed)) {
        continue;
      }
      if (RegExp(r'[A-Za-z]').hasMatch(trimmed)) {
        return trimmed;
      }
    }
    return 'Generated Academic Document';
  }

  static String? _heading(String line) {
    final trimmed = line.trim();
    if (_isGarbageLine(trimmed) ||
        _isStandalonePageMarker(trimmed) ||
        _isStandaloneEnumerator(trimmed)) {
      return null;
    }

    if (RegExp(r'^(chapter|module|lesson|section|unit)\b', caseSensitive: false)
        .hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(
            r'^(introduction|overview|summary|conclusion|exercises?|activities?|appendix|references?)\b',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^(example|exercise|problem|solution(?:\s*to)?|steps?)\b',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^\d+(?:\.\d+)*\s+[A-Za-z].*$').hasMatch(trimmed)) {
      return trimmed;
    }

    final letters = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    final wordCount =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (letters >= 4 &&
        wordCount >= 3 &&
        wordCount <= 12 &&
        _looksLikeTitleCaseHeading(trimmed)) {
      return trimmed;
    }

    if (letters >= 6 &&
        (wordCount >= 2 || trimmed.length >= 12) &&
        trimmed.toUpperCase() == trimmed) {
      return line;
    }

    return null;
  }

  static _FormulaState _formulaState(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 3 || _isGarbageLine(trimmed)) {
      return _FormulaState.none;
    }
    if (_isUrlLike(trimmed) || _isStandaloneGradeRange(trimmed)) {
      return _FormulaState.none;
    }
    if (MathFormulaService.isFormulaLike(trimmed)) {
      return _FormulaState.strong;
    }

    final hasEquation = RegExp(r'[=≈≠≤≥<>]').hasMatch(trimmed);
    final hasOperator =
        RegExp(r'[\+\-*/^√∑∫]|\\frac|\\sqrt|\\sum|\\int').hasMatch(trimmed);
    final hasMathSymbol = RegExp(
      r'[αβγδθλμπσφω∞₀₁₂₃₄₅₆₇₈₉²³]|(?:\b[a-zA-Z]\s*\^\s*\d)',
      unicode: true,
    ).hasMatch(trimmed);
    final hasVariablesAndNumbers = RegExp(r'[A-Za-z]').hasMatch(trimmed) &&
        RegExp(r'\d').hasMatch(trimmed);
    final hasFractionLike =
        RegExp(r'(?:\([^)]+\)|\w+)\s*/\s*(?:\([^)]+\)|\w+)').hasMatch(trimmed);

    if (hasEquation &&
        (hasOperator || hasMathSymbol || hasVariablesAndNumbers)) {
      return _FormulaState.strong;
    }
    if ((hasOperator || hasFractionLike) && hasVariablesAndNumbers) {
      return _FormulaState.strong;
    }
    if (hasEquation || hasMathSymbol || hasFractionLike) {
      return _FormulaState.review;
    }
    return _FormulaState.none;
  }

  static bool _isUrlLike(String line) {
    return RegExp(r'\b(?:https?://|www\.)\S+', caseSensitive: false)
        .hasMatch(line);
  }

  static bool _isStandaloneGradeRange(String line) {
    return RegExp(r'^\(?\s*[<>]?\s*\d+(?:\s*[-–—]\s*\d+)?\s*%?\s*\)?$',
            unicode: true)
        .hasMatch(line);
  }

  static void _flushParagraph(List<String> buffer, DataModel result) {
    if (buffer.isEmpty) return;
    final text = buffer.join(' ').trim();
    result.paragraphs.add(text);
    result.blocks.add({'type': 'paragraph', 'text': text});
    buffer.clear();
  }

  static bool _isTable(String line) {
    return line.contains('|') ||
        RegExp(r'\t.{2,}\t').hasMatch(line) ||
        RegExp(r'(?:\S.{0,40}\t){2,}\S').hasMatch(line);
  }

  static bool _isList(String line) {
    return RegExp(r'^(\-|\*|\d+\.)\s+').hasMatch(line);
  }

  static Map<String, String>? _parseKeyValue(String line) {
    final match =
        RegExp(r'^\s*([^:;\-–—]{2,80}?)(?:\s*[:\-–—]\s+)(.+)$', unicode: true)
            .firstMatch(line);
    if (match == null) return null;
    final key = match.group(1)!.trim();
    final value = match.group(2)!.trim();
    if (key.isEmpty || value.isEmpty) return null;
    return {'key': key, 'value': value};
  }

  static bool _isImportantSentence(String line) {
    if (line.length > 180) return false;
    if (RegExp(r'^[A-Z0-9 \/\-&\(\)]+$').hasMatch(line)) {
      return true;
    }
    return RegExp(
            r'\b(important|key|purpose|definition|types|example|examples|benefits|steps|components|requirements|features|advantages)\b',
            caseSensitive: false)
        .hasMatch(line);
  }

  static String _normalizeLine(String line) {
    return line.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isGarbageLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    if (_isStandalonePageMarker(trimmed)) {
      return true;
    }
    if (RegExp(r'^\{[A-F0-9\-]{20,}\}$', caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[[:punct:]\s]+$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[A-Z]\.$').hasMatch(trimmed)) {
      return true;
    }
    return trimmed.length <= 2 && RegExp(r'[A-Za-z]').hasMatch(trimmed);
  }

  static bool _isStandalonePageMarker(String line) {
    return RegExp(r'^\d{1,3}$').hasMatch(line.trim());
  }

  static bool _isStandaloneEnumerator(String line) {
    return RegExp(r'^\d+[.)]$').hasMatch(line.trim());
  }

  static String _prefixStandaloneEnumerator(String text, String? pending) {
    if (pending == null) return text;
    final result = '${pending.trim()} ${text.trimLeft()}'.trim();
    return result;
  }

  static bool _looksLikeTitleCaseHeading(String line) {
    if (RegExp(r'[.!?]$').hasMatch(line)) return false;
    final normalized =
        line.replaceAll(RegExp(r'[^\p{L}\p{N}\s\/&()\-:]', unicode: true), ' ');
    final words =
        normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 3 || words.length > 12) return false;

    final lowerWords = {
      'a',
      'an',
      'and',
      'as',
      'at',
      'by',
      'for',
      'from',
      'in',
      'of',
      'on',
      'or',
      'the',
      'to',
      'with'
    };
    int matchingWords = 0;

    for (final word in words) {
      if (RegExp(r'^\d+$').hasMatch(word)) {
        matchingWords++;
        continue;
      }
      if (lowerWords.contains(word.toLowerCase())) {
        matchingWords++;
        continue;
      }
      if (RegExp(r'^[A-Z][\p{L}\p{N}\/&()\-:]*$', unicode: true)
          .hasMatch(word)) {
        matchingWords++;
      }
    }

    return matchingWords >= (words.length * 0.7).ceil();
  }

  static bool _isArtifactLine(String line) {
    final trimmed = line.trim();
    return RegExp(
            r'^(?:\d+\s+\d+\s+obj|endobj|xref|startxref|trailer|stream|endstream)$',
            caseSensitive: false)
        .hasMatch(trimmed);
  }

  static List<String> _normalizeEmphasizedTerms(List<dynamic> terms) {
    final normalized = <String, int>{};
    for (final term in terms) {
      var value = term.toString().trim();
      value = value.replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty || _isGarbageLine(value)) continue;

      final wordCount =
          value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (value.length < 4 ||
          value.length > 48 ||
          wordCount > 6 ||
          !RegExp(r'[A-Za-z]').hasMatch(value)) {
        continue;
      }
      normalized[value] = value.length;
    }

    final sorted = normalized.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).take(40).toList();
  }
}
