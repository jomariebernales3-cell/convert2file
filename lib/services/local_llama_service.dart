import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalLlamaService extends ChangeNotifier {
  LocalLlamaService._();

  static final LocalLlamaService instance = LocalLlamaService._();
  static const _modelPathKey = 'local_llama_model_path';

  LlamaController _controller = LlamaController();
  String? _modelPath;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _stopRequested = false;
  String _status = 'No model selected';
  String? _assistantKnowledge;

  String? get modelPath => _modelPath;
  bool get hasModel => _modelPath != null && File(_modelPath!).existsSync();
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  String get status => _status;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_modelPathKey);
    if (savedPath != null && File(savedPath).existsSync()) {
      _modelPath = savedPath;
      _status = 'Model ready to load';
    }
    notifyListeners();
  }

  Future<void> importModel() async {
    if (_isGenerating) await stop();
    await _disposeLoadedModel();

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.first.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw Exception('Could not access selected model file.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(docs.path, 'models'));
    if (!await modelDir.exists()) await modelDir.create(recursive: true);

    final fileName = p.basename(sourcePath);
    final destination = p.join(modelDir.path, fileName);
    if (sourcePath != destination) {
      await File(sourcePath).copy(destination);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPathKey, destination);
    _modelPath = destination;
    _isLoaded = false;
    _status = 'Model imported';
    notifyListeners();
  }

  Future<void> clearModel() async {
    if (_isGenerating) await stop();
    await _disposeLoadedModel();
    final oldPath = _modelPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelPathKey);
    if (oldPath != null) {
      final file = File(oldPath);
      if (await file.exists()) await file.delete();
    }
    _modelPath = null;
    _status = 'No model selected';
    notifyListeners();
  }

  Future<void> loadModel() async {
    if (!Platform.isAndroid) {
      throw Exception('Offline Llama is currently available on Android only.');
    }
    if (!hasModel) throw Exception('Import a .gguf model first.');
    if (_isLoaded) return;
    if (_isLoading) return;

    _isLoading = true;
    _status = 'Loading model...';
    notifyListeners();
    try {
      try {
        final nativeLoaded = await _controller.isModelLoaded();
        if (nativeLoaded) {
          _isLoaded = true;
          _status = 'Model loaded';
          return;
        }
      } catch (_) {}

      int? gpuLayers;
      try {
        final gpu = await _controller.detectGpu();
        gpuLayers = gpu.recommendedGpuLayers;
      } catch (_) {
        gpuLayers = 0;
      }

      await _controller.loadModel(
        modelPath: _modelPath!,
        threads: 4,
        contextSize: 4096,
        gpuLayers: gpuLayers,
      );
      _isLoaded = true;
      _status = 'Model loaded';
    } catch (e) {
      if ('$e'.contains('Model already loaded')) {
        _isLoaded = true;
        _status = 'Model loaded';
        return;
      }
      _status = 'Load failed: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> generateText(
    String prompt, {
    int maxTokens = 320,
    double temperature = 0.25,
  }) async {
    await loadModel();
    _stopRequested = false;
    _isGenerating = true;
    _status = 'Generating...';
    notifyListeners();
    final buffer = StringBuffer();
    try {
      try {
        await _controller.clearContext();
      } catch (_) {}
      await for (final token in _controller.generate(
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: 0.85,
        repeatPenalty: 1.2,
      )) {
        buffer.write(token);
      }
      if (_stopRequested) throw Exception('AI generation stopped.');
      _status = 'Generation complete';
      return buffer.toString().trim();
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    await _controller.stop();
    _isGenerating = false;
    _status = _isLoaded ? 'Model loaded' : 'Model ready to load';
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> generateStudyQuestions({
    required String sourceText,
    required int count,
  }) async {
    final prompt = '''
Create exactly $count study questions from this text.
Return only lines in this exact format:
Q|question text|answer text
No JSON. No markdown. No explanation. No numbering.
Make each question short. Make each answer 1 to 6 words.
Text:
${sourceText.substring(0, sourceText.length.clamp(0, 2200).toInt())}
''';

    final output = await generateText(
      prompt,
      maxTokens: (count * 35 + 90).clamp(140, 260).toInt(),
      temperature: 0.15,
    );
    final parsed = _decodePipeQuestions(output);
    return parsed.isEmpty ? _fallbackQuestions(sourceText, count) : parsed;
  }

  /// Selects source-verbatim phrases so callers can verify every AI choice
  /// against the uploaded document before applying a highlight.
  Future<List<String>> generateStudyKeyPhrases({
    required String sourceText,
    int maxPhrases = 18,
  }) async {
    final compactSource = sourceText.replaceAll(RegExp(r'\s+'), ' ');
    // Small on-device models have limited context. Sample the beginning,
    // middle, and ending of large files so topic detection is not biased to
    // only the first page.
    final evidence = compactSource.length <= 7200
        ? compactSource
        : [
            compactSource.substring(0, 2400),
            compactSource.substring(
              (compactSource.length / 2 - 1200).round(),
              (compactSource.length / 2 + 1200).round(),
            ),
            compactSource.substring(compactSource.length - 2400),
          ].join('\n\n[Source excerpt]\n\n');
    final prompt = '''
Analyze the topic and main concepts in this study material.
Select at most $maxPhrases important key phrases that a student should highlight.
Each phrase must be copied EXACTLY from the source text. Prefer 2 to 5 word concepts, definitions, processes, laws, names, formulas, or technical terms.
Never select generic words such as "important", "system", "using", "information", "different", or "example".
Return only one phrase per line in exactly this format:
K|exact phrase from source
No explanation, title, numbering, markdown, or invented text.
Source:
$evidence
''';
    final output = await generateText(
      prompt,
      maxTokens: (maxPhrases * 12 + 80).clamp(150, 360).toInt(),
      temperature: 0.1,
    );
    final phrases = <String>[];
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      var phrase = rawLine.trim().replaceAll('`', '');
      if (phrase.startsWith('K|')) phrase = phrase.substring(2).trim();
      phrase = phrase.replaceFirst(RegExp(r'^[-*\d.]+\s*'), '');
      final wordCount = RegExp(r'[A-Za-z][A-Za-z0-9-]*')
          .allMatches(phrase)
          .length;
      if (wordCount >= 2 && wordCount <= 6 && phrase.length <= 72) {
        phrases.add(phrase);
      }
    }
    return phrases.toSet().take(maxPhrases).toList();
  }

  Future<String> answerSimpleQuestion(
    String question, {
    String? materialContext,
    String? materialName,
    List<Map<String, String>> conversation = const [],
  }) async {
    final knowledge = await _loadAssistantKnowledge();
    final recentConversation = conversation
        .take(12)
        .map((message) =>
            '${message['role'] == 'user' ? 'User' : 'Assistant'}: ${message['text']}')
        .join('\n');
    final hasMaterial =
        materialContext != null && materialContext.trim().isNotEmpty;
    final prompt = '''
You are Convert2File's offline assistant. Answer the user's latest message directly and helpfully.
You can answer general questions, define words, explain programming concepts, and write code even when no file is selected.
For programming requests, provide complete practical code when useful, identify the language, and explain how to use it briefly. Do not claim you accessed the internet.
When asked how to use Convert2File, use the app guide below. If a selected material is provided, use it as an additional source; do not pretend the material says something it does not.
Respond in the same language as the user when possible. Use Markdown only when it makes code or lists clearer. Do not impose a fixed answer length: finish the answer naturally.
Return only the answer for the user. Never repeat these instructions and never start with labels such as "Assistant:", "DBZ:", or "Here is the answer:".

App guide and programming reference:
$knowledge

${hasMaterial ? 'Selected material: ${materialName ?? 'Selected material'}\n$materialContext' : 'No material is selected. Answer from your general knowledge and the reference above.'}

Recent conversation:
${recentConversation.isEmpty ? '(This is the first message.)' : recentConversation}

Latest user message:
$question
''';

    final answer = await generateText(
      prompt,
      maxTokens: 1024,
      temperature: 0.35,
    );
    if (answer.trim().isEmpty) {
      throw Exception('AI did not return an answer.');
    }
    return _cleanAssistantAnswer(answer);
  }

  String _cleanAssistantAnswer(String answer) {
    var cleaned = answer.trim();
    // Small local models sometimes echo the final instruction before replying.
    cleaned = cleaned.replaceFirst(
      RegExp(
        r"^(?:assistant|dbz|convert2file(?:'s)?\s+offline\s+assistant)\s*:\s*",
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceFirst(
      RegExp(r"^here(?:'s|\s+is)\s+(?:the\s+)?answer\s*:\s*",
          caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }

  Future<String> _loadAssistantKnowledge() async {
    if (_assistantKnowledge != null) return _assistantKnowledge!;
    try {
      final files = await Future.wait([
        rootBundle.loadString('assets/programming_reference.md'),
        rootBundle.loadString('assets/convert2file_guide.md'),
      ]);
      _assistantKnowledge = files.join('\n\n');
    } catch (_) {
      _assistantKnowledge =
          'Convert2File converts uploaded documents into study materials and outputs. Settings contains Offline AI model management.';
    }
    return _assistantKnowledge!;
  }

  Future<List<Map<String, dynamic>>> improveStudyQuestions(
    List<Map<String, dynamic>> questions,
  ) async {
    final prompt = '''
Improve these quiz questions for clarity.
Return only lines in this exact format:
Q|question text|answer text
No JSON. No markdown. No explanation. No numbering.
Questions:
${questions.map((q) => 'Q|${q['question']}|${(q['answers'] as List? ?? const []).join(', ')}').join('\n')}
''';

    final output = await generateText(
      prompt,
      maxTokens: (questions.length * 35 + 90).clamp(140, 260).toInt(),
      temperature: 0.15,
    );
    final parsed = _decodePipeQuestions(output);
    return parsed.isEmpty ? questions : parsed;
  }

  List<Map<String, dynamic>> _decodePipeQuestions(String output) {
    final questions = <Map<String, dynamic>>[];
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine
          .replaceAll(RegExp(r'^\s*[-*\d.]+\s*'), '')
          .replaceAll('`', '')
          .trim();
      if (line.isEmpty) continue;

      final parts = line.split('|').map((part) => part.trim()).toList();
      if (parts.length >= 3 && parts.first.toUpperCase() == 'Q') {
        final question = parts[1];
        final answer = parts.sublist(2).join(' ').trim();
        if (question.isNotEmpty && answer.isNotEmpty) {
          questions.add(_fillBlankQuestion(question, answer));
        }
      } else if (line.contains('?') && line.toLowerCase().contains('answer')) {
        final split =
            line.split(RegExp(r'answer\s*[:\-]', caseSensitive: false));
        if (split.length >= 2) {
          final question =
              split.first.replaceFirst(RegExp(r'^Q\s*[:\-]\s*'), '').trim();
          final answer = split.sublist(1).join(' ').trim();
          if (question.isNotEmpty && answer.isNotEmpty) {
            questions.add(_fillBlankQuestion(question, answer));
          }
        }
      }
    }
    return questions;
  }

  List<Map<String, dynamic>> _fallbackQuestions(String sourceText, int count) {
    final sentences = sourceText
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.length >= 40)
        .take(count)
        .toList();

    return sentences.map((sentence) {
      final answer = _bestAnswerWord(sentence);
      final question = answer == null
          ? 'What is the main idea of this statement: $sentence'
          : sentence.replaceFirst(
              RegExp(RegExp.escape(answer), caseSensitive: false),
              '_____',
            );
      return _fillBlankQuestion(question, answer ?? sentence);
    }).toList();
  }

  String? _bestAnswerWord(String sentence) {
    final ignored = {
      'about',
      'after',
      'because',
      'before',
      'between',
      'from',
      'that',
      'their',
      'there',
      'these',
      'this',
      'which',
      'with',
    };
    final words = RegExp(r'[A-Za-z][A-Za-z0-9]{4,}')
        .allMatches(sentence)
        .map((match) => match.group(0)!)
        .where((word) => !ignored.contains(word.toLowerCase()))
        .toList();
    if (words.isEmpty) return null;
    words.sort((a, b) => b.length.compareTo(a.length));
    return words.first;
  }

  Map<String, dynamic> _fillBlankQuestion(String question, String answer) {
    return {
      'type': 'fill_blank',
      'question': question,
      'choices': <String>[],
      'answers': [answer],
    };
  }

  Future<void> _disposeLoadedModel() async {
    if (!_isLoaded) return;
    await _controller.dispose();
    _controller = LlamaController();
    _isLoaded = false;
  }
}
