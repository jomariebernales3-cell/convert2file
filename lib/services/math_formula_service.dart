/// Formula recognition and rendering shared by the DOCX, PDF, HTML, and
/// preview paths. DOCX uses Office Math Markup Language (OMML), which Word
/// and WPS Office understand as a real equation object. Other outputs receive
/// a Unicode presentation string backed by the bundled math font.
class MathFormula {
  final String displayText;
  final String omml;
  final String? warning;

  const MathFormula({
    required this.displayText,
    required this.omml,
    this.warning,
  });
}

class MathFormulaService {
  static const _latexCommands = <String, String>{
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'theta': 'θ',
    'lambda': 'λ',
    'mu': 'μ',
    'pi': 'π',
    'rho': 'ρ',
    'sigma': 'σ',
    'phi': 'φ',
    'omega': 'ω',
    'Gamma': 'Γ',
    'Delta': 'Δ',
    'Theta': 'Θ',
    'Lambda': 'Λ',
    'Pi': 'Π',
    'Sigma': 'Σ',
    'Phi': 'Φ',
    'Omega': 'Ω',
    'times': '×',
    'cdot': '·',
    'div': '÷',
    'pm': '±',
    'leq': '≤',
    'geq': '≥',
    'neq': '≠',
    'infty': '∞',
    'rightarrow': '→',
    'leftarrow': '←',
  };

  static bool isFormulaLike(String input) {
    final value = input.trim();
    if (value.length < 3 || value.length > 600) return false;
    if (RegExp(r'\\(?:frac|dfrac|tfrac|sqrt|sum|int|prod|lim|begin\s*\{cases\}|alpha|beta|gamma|sigma|theta|mu|pi)')
        .hasMatch(value)) {
      return true;
    }
    if (value.contains(RegExp(r'[=≈≠≤≥]')) &&
        (RegExp(r'[A-Za-zα-ωΑ-Ω]').hasMatch(value)) &&
        (RegExp(r'[\d_\^+\-*/√∑∫]').hasMatch(value))) {
      return true;
    }
    return RegExp(r'\b[A-Za-z][A-Za-z0-9]*\s*(?:_\{?\w+\}?|\^\{?[A-Za-z0-9]+\}?)')
            .hasMatch(value) &&
        RegExp(r'[=+\-*/()]').hasMatch(value);
  }

  /// Returns null for normal prose, allowing the surrounding conversion
  /// pipeline to continue treating it as a paragraph.
  static MathFormula? parse(String input) {
    if (!isFormulaLike(input)) return null;
    try {
      final root = _FormulaParser(_normalize(input)).parse();
      final display = root.display.trim();
      if (display.isEmpty) return null;
      return MathFormula(
        displayText: display,
        omml: '<m:oMath>${root.omml}</m:oMath>',
      );
    } catch (_) {
      // Keep the source expression visible and editable if it is too complex
      // for the lightweight parser. It must never silently disappear.
      return MathFormula(
        displayText: _plainDisplay(input),
        omml: '<m:oMath>${_TextNode(_plainDisplay(input)).omml}</m:oMath>',
        warning: 'This formula could not be fully structured. Review it before sharing.',
      );
    }
  }

  static String _normalize(String value) {
    return value
        .trim()
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '')
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'$', '');
  }

  static String _plainDisplay(String input) {
    var value = _normalize(input);
    for (final entry in _latexCommands.entries) {
      value = value.replaceAll('\\${entry.key}', entry.value);
    }
    return value.replaceAll(r'\,', ' ').replaceAll(r'\ ', ' ');
  }
}

abstract class _MathNode {
  String get display;
  String get omml;
}

class _TextNode extends _MathNode {
  final String value;
  _TextNode(this.value);

  @override
  String get display => value;

  @override
  String get omml => value.isEmpty
      ? '<m:r><m:t></m:t></m:r>'
      : '<m:r><m:t>${_xml(value)}</m:t></m:r>';
}

class _SequenceNode extends _MathNode {
  final List<_MathNode> children;
  _SequenceNode(this.children);

  @override
  String get display => children.map((node) => node.display).join();

  @override
  String get omml => children.map((node) => node.omml).join();
}

class _FractionNode extends _MathNode {
  final _MathNode numerator;
  final _MathNode denominator;
  _FractionNode(this.numerator, this.denominator);

  @override
  String get display => '${numerator.display}⁄${denominator.display}';

  @override
  String get omml => '<m:f><m:num>${numerator.omml}</m:num>'
      '<m:den>${denominator.omml}</m:den></m:f>';
}

class _RootNode extends _MathNode {
  final _MathNode expression;
  final _MathNode? degree;
  _RootNode(this.expression, [this.degree]);

  @override
  String get display => degree == null
      ? '√(${expression.display})'
      : '√[${degree!.display}](${expression.display})';

  @override
  String get omml => '<m:rad>'
      '${degree == null ? '<m:radPr><m:degHide m:val="1"/></m:radPr>' : '<m:deg>${degree!.omml}</m:deg>'}'
      '<m:e>${expression.omml}</m:e></m:rad>';
}

class _ScriptNode extends _MathNode {
  final _MathNode base;
  final _MathNode? subscript;
  final _MathNode? superscript;
  _ScriptNode(this.base, {this.subscript, this.superscript});

  @override
  String get display => '${base.display}'
      '${subscript == null ? '' : _toSubscript(subscript!.display)}'
      '${superscript == null ? '' : _toSuperscript(superscript!.display)}';

  @override
  String get omml {
    if (subscript != null && superscript != null) {
      return '<m:sSubSup><m:e>${base.omml}</m:e><m:sub>${subscript!.omml}</m:sub>'
          '<m:sup>${superscript!.omml}</m:sup></m:sSubSup>';
    }
    if (subscript != null) {
      return '<m:sSub><m:e>${base.omml}</m:e><m:sub>${subscript!.omml}</m:sub></m:sSub>';
    }
    return '<m:sSup><m:e>${base.omml}</m:e><m:sup>${superscript!.omml}</m:sup></m:sSup>';
  }
}

class _NaryNode extends _MathNode {
  final String symbol;
  final _MathNode? lower;
  final _MathNode? upper;
  _NaryNode(this.symbol, {this.lower, this.upper});

  @override
  String get display => '$symbol'
      '${lower == null ? '' : _toSubscript(lower!.display)}'
      '${upper == null ? '' : _toSuperscript(upper!.display)}';

  @override
  String get omml => '<m:nary><m:naryPr><m:chr m:val="${_xml(symbol)}"/>'
      '</m:naryPr><m:sub>${(lower ?? _TextNode('')).omml}</m:sub>'
      '<m:sup>${(upper ?? _TextNode('')).omml}</m:sup>'
      '<m:e><m:r><m:t></m:t></m:r></m:e></m:nary>';
}

class _CasesNode extends _MathNode {
  final List<List<_MathNode>> rows;
  _CasesNode(this.rows);

  @override
  String get display => '{\n${rows.map((row) => '  ${row.map((node) => node.display).join('  ')}').join('\n')}\n}';

  @override
  String get omml {
    final matrixRows = rows
        .map((row) => '<m:mr>${row.map((node) => '<m:e>${node.omml}</m:e>').join()}</m:mr>')
        .join();
    return '<m:d><m:dPr><m:begChr m:val="{"/><m:endChr m:val=""/>'
        '</m:dPr><m:e><m:m><m:mPr><m:plcHide m:val="1"/></m:mPr>'
        '$matrixRows</m:m></m:e></m:d>';
  }
}

class _FormulaParser {
  final String input;
  int index = 0;
  _FormulaParser(this.input);

  _MathNode parse() {
    final node = _sequence();
    if (index < input.length) throw const FormatException('Unexpected formula input');
    return node;
  }

  _MathNode _sequence({String? end}) {
    final nodes = <_MathNode>[];
    while (index < input.length) {
      if (end != null && input[index] == end) {
        index++;
        break;
      }
      if (_startsWith(r'\end{cases}')) break;
      if (input[index].trim().isEmpty) {
        index++;
        if (nodes.isNotEmpty && nodes.last.display != ' ') nodes.add(_TextNode(' '));
        continue;
      }

      var node = _atom();
      _MathNode? subscript;
      _MathNode? superscript;
      while (index < input.length && (input[index] == '_' || input[index] == '^')) {
        final marker = input[index++];
        final script = _scriptArgument();
        if (marker == '_') {
          subscript = script;
        } else {
          superscript = script;
        }
      }
      if (node is _NaryNode && (subscript != null || superscript != null)) {
        node = _NaryNode(node.symbol, lower: subscript, upper: superscript);
      } else if (subscript != null || superscript != null) {
        node = _ScriptNode(node, subscript: subscript, superscript: superscript);
      }
      nodes.add(node);
    }
    return nodes.length == 1 ? nodes.first : _SequenceNode(nodes);
  }

  _MathNode _atom() {
    if (index >= input.length) throw const FormatException('Missing formula atom');
    final character = input[index];
    if (character == '{') {
      index++;
      return _sequence(end: '}');
    }
    if (character == '\\') return _command();
    index++;
    return _TextNode(character);
  }

  _MathNode _command() {
    index++; // slash
    final start = index;
    while (index < input.length && RegExp(r'[A-Za-z]').hasMatch(input[index])) {
      index++;
    }
    final command = input.substring(start, index);
    switch (command) {
      case 'frac':
      case 'dfrac':
      case 'tfrac':
        return _FractionNode(_requiredGroup(), _requiredGroup());
      case 'sqrt':
        _MathNode? degree;
        if (index < input.length && input[index] == '[') {
          index++;
          degree = _sequence(end: ']');
        }
        return _RootNode(_requiredGroup(), degree);
      case 'sum':
        return _NaryNode('∑');
      case 'int':
        return _NaryNode('∫');
      case 'prod':
        return _NaryNode('∏');
      case 'lim':
        return _NaryNode('lim');
      case 'begin':
        final environment = _groupText();
        if (environment == 'cases') return _cases();
        throw const FormatException('Unsupported math environment');
      case 'text':
      case 'mathrm':
      case 'operatorname':
        return _requiredGroup();
      case 'left':
      case 'right':
        if (index < input.length) return _atom();
        return _TextNode('');
      case '':
        if (index < input.length) return _TextNode(input[index++]);
        throw const FormatException('Incomplete command');
      default:
        final symbol = MathFormulaService._latexCommands[command];
        if (symbol != null) return _TextNode(symbol);
        // Unknown commands remain visible to the user instead of being lost.
        return _TextNode('\\$command');
    }
  }

  _MathNode _requiredGroup() {
    if (index >= input.length || input[index] != '{') {
      throw const FormatException('Expected formula group');
    }
    index++;
    return _sequence(end: '}');
  }

  String _groupText() {
    final node = _requiredGroup();
    return node.display.replaceAll(' ', '');
  }

  _MathNode _scriptArgument() {
    if (index < input.length && input[index] == '{') return _requiredGroup();
    // LaTeX normally braces multi-character scripts, but users commonly type
    // ANOVA variables such as F_out and F_within. Treat the contiguous word
    // as one script instead of applying the subscript only to the first
    // letter (Fₒut).
    if (index < input.length && RegExp(r'[A-Za-z0-9]').hasMatch(input[index])) {
      final start = index;
      while (index < input.length && RegExp(r'[A-Za-z0-9]').hasMatch(input[index])) {
        index++;
      }
      return _TextNode(input.substring(start, index));
    }
    return _atom();
  }

  _MathNode _cases() {
    final end = input.indexOf(r'\end{cases}', index);
    if (end < 0) throw const FormatException('Unclosed cases environment');
    final content = input.substring(index, end);
    index = end + r'\end{cases}'.length;
    final rows = <List<_MathNode>>[];
    for (final rawRow in content.split(r'\\')) {
      final cells = rawRow.split('&');
      rows.add(cells.map((cell) => _FormulaParser(cell).parse()).toList());
    }
    return _CasesNode(rows);
  }

  bool _startsWith(String value) => input.startsWith(value, index);
}

String _toSuperscript(String value) {
  const map = <String, String>{
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵',
    '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻',
    '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
  };
  return value.split('').map((character) => map[character] ?? '^($character)').join();
}

String _toSubscript(String value) {
  const map = <String, String>{
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅',
    '6': '₆', '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋',
    '=': '₌', '(': '₍', ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ',
    'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ',
    'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
    'v': 'ᵥ', 'x': 'ₓ',
  };
  return value.split('').map((character) => map[character] ?? '_($character)').join();
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
