import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../services/data_extractor.dart';
import '../services/document_parser.dart';
import '../services/local_llama_service.dart';
import '../widgets/figma_app_chrome.dart';

enum StudyQuestionType {
  trueFalse,
  abcd,
  multipleChoice,
  fillBlank,
}

extension StudyQuestionTypeLabel on StudyQuestionType {
  String get label {
    return switch (this) {
      StudyQuestionType.trueFalse => 'True or False',
      StudyQuestionType.abcd => 'ABCD',
      StudyQuestionType.multipleChoice => 'Multiple Choice',
      StudyQuestionType.fillBlank => 'Fill in the Blank',
    };
  }

  String get value {
    return switch (this) {
      StudyQuestionType.trueFalse => 'true_false',
      StudyQuestionType.abcd => 'abcd',
      StudyQuestionType.multipleChoice => 'multiple_choice',
      StudyQuestionType.fillBlank => 'fill_blank',
    };
  }
}

StudyQuestionType _typeFromValue(String? value) {
  return StudyQuestionType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => StudyQuestionType.abcd,
  );
}

enum _StudyBuilderMode { manual, ai }

enum _AutoStudySource { file, link, topic }

enum _StudyNoteDensity { quick, normal, detailed }

class StudyBuilderScreen extends StatefulWidget {
  final bool generateQuizOnly;
  final PlatformFile? initialQuizFile;

  const StudyBuilderScreen({
    super.key,
    this.generateQuizOnly = false,
    this.initialQuizFile,
  });

  @override
  State<StudyBuilderScreen> createState() => _StudyBuilderScreenState();
}

class _StudyBuilderScreenState extends State<StudyBuilderScreen> {
  final _authService = AuthService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  final _topicController = TextEditingController();
  final _totalQuestionsController = TextEditingController(text: '10');
  final List<_EditableQuestion> _questions = [];

  Map<String, dynamic>? _editingSet;
  _StudyBuilderMode _builderMode = _StudyBuilderMode.manual;
  _AutoStudySource _autoSource = _AutoStudySource.file;
  PlatformFile? _autoFile;
  List<Map<String, dynamic>> _savedStudySets = [];
  bool _isLoading = true;
  bool _isAiGenerating = false;
  bool _loadedRouteStudySet = false;
  PlatformFile? _studyGuideFile;
  String _studyGuideText = '';
  List<String> _studyGuideSentences = [];
  List<int?> _studyGuidePages = [];
  Set<String> _studyGuideTerms = {};
  Set<String> _disabledStudyTerms = {};
  bool _isPreparingStudyGuide = false;
  int? _explainingStudySentence;
  _StudyNoteDensity _studyNoteDensity = _StudyNoteDensity.normal;
  bool _areKeyTermsExpanded = false;
  bool _isGeneratingAiHighlights = false;
  double _aiHighlightProgress = 0;
  String _aiHighlightStatus = '';
  Timer? _aiHighlightTimer;

  @override
  void initState() {
    super.initState();
    if (widget.generateQuizOnly) {
      _builderMode = _StudyBuilderMode.ai;
      _autoFile = widget.initialQuizFile;
    }
    _loadStudySets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedRouteStudySet) return;
    _loadedRouteStudySet = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editStudySet(args);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    _topicController.dispose();
    _totalQuestionsController.dispose();
    _aiHighlightTimer?.cancel();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  void _newStudySet() {
    _clearEditor();
    setState(() {
      _editingSet = null;
      _builderMode = _StudyBuilderMode.manual;
      _questions.add(_EditableQuestion());
    });
  }

  void _editStudySet(Map<String, dynamic> set) {
    _clearEditor();
    final decoded = jsonDecode(set['questions_json'] as String? ?? '[]');
    final questions = decoded is List ? decoded : const [];
    setState(() {
      _editingSet = set;
      _builderMode = _StudyBuilderMode.manual;
      _titleController.text = set['title'] as String? ?? '';
      _descriptionController.text = set['description'] as String? ?? '';
      _questions.addAll(
        questions.whereType<Map>().map((item) => _EditableQuestion.fromJson(
              Map<String, dynamic>.from(item),
            )),
      );
      if (_questions.isEmpty) _questions.add(_EditableQuestion());
    });
  }

  void _clearEditor() {
    for (final question in _questions) {
      question.dispose();
    }
    _questions.clear();
    _titleController.clear();
    _descriptionController.clear();
  }

  Future<int> _ownerId() async {
    return _authService.currentUser?.id ??
        await DatabaseHelper.instance.getOrCreateGuestUserId();
  }

  Future<void> _loadStudySets() async {
    try {
      final sets = await DatabaseHelper.instance.queryStudySetsByUser(
        await _ownerId(),
      );
      if (!mounted) return;
      setState(() {
        _savedStudySets = sets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Could not load study sets: $e', isError: true);
    }
  }

  List<Map<String, dynamic>> _questionsFromSet(Map<String, dynamic> set) {
    try {
      final decoded = jsonDecode(set['questions_json'] as String? ?? '[]');
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
              (item) => (item['question'] as String? ?? '').trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _startQuiz(Map<String, dynamic> set) async {
    final questions = _questionsFromSet(set);
    if (questions.isEmpty) {
      _showMessage('This study set has no answerable questions.',
          isError: true);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StudyQuizScreen(
          studySet: set,
          questions: questions,
          onSavedScore: _loadStudySets,
        ),
      ),
    );
    if (mounted) _loadStudySets();
  }

  Future<void> _deleteStudySet(int id) async {
    await DatabaseHelper.instance.deleteStudySet(id);
    if (_editingSet?['id'] == id) {
      _clearEditor();
      _editingSet = null;
    }
    await _loadStudySets();
    _showMessage('Study set deleted.');
  }

  Future<void> _pickAutoFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'docx', 'pdf', 'ppt', 'pptx'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _autoFile = result.files.first);
  }

  Future<void> _createStudyGuide() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'docx', 'pdf', 'ppt', 'pptx'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      _showMessage('The selected file is unavailable.', isError: true);
      return;
    }

    setState(() => _isPreparingStudyGuide = true);
    try {
      final text = await DocumentParser.extractText(path, _extensionOf(file.name));
      final data = DataExtractor.extract(text);
      final termScores = <String, int>{};
      void scoreTerms(Iterable<String> values, int weight) {
        for (final value in values) {
          for (final word in RegExp(r'[A-Za-z][A-Za-z0-9-]{3,}')
              .allMatches(value)
              .map((match) => match.group(0)!.toLowerCase())) {
            if (!_studyStopWords.contains(word)) {
              termScores[word] = (termScores[word] ?? 0) + weight;
            }
          }
        }
      }

      scoreTerms(data.headings, 5);
      scoreTerms(data.importantPoints, 3);
      scoreTerms(
          List<String>.from(data.meta['emphasized_terms'] as List? ?? []), 7);

      final sentences = <String>[];
      final pages = <int?>[];
      if (_extensionOf(file.name) == 'pdf') {
        final pageTexts = await DocumentParser.extractPdfPageTexts(path);
        for (final entry in pageTexts.entries) {
          for (final sentence in _splitStudySentences(entry.value)) {
            if (sentences.length >= 80) break;
            sentences.add(sentence);
            pages.add(entry.key);
          }
        }
      } else {
        for (final sentence in _splitStudySentences(text)) {
          if (sentences.length >= 80) break;
          sentences.add(sentence);
          pages.add(null);
        }
      }
      if (sentences.isEmpty) {
        throw Exception('No readable sentences were found in this file.');
      }
      final sortedTerms = termScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (!mounted) return;
      setState(() {
        _studyGuideFile = file;
        _studyGuideText = text;
        _studyGuideSentences = sentences;
        _studyGuidePages = pages;
        _studyGuideTerms = sortedTerms.map((entry) => entry.key).take(28).toSet();
        _disabledStudyTerms = {};
        _areKeyTermsExpanded = false;
        _studyNoteDensity = _StudyNoteDensity.normal;
      });
    } catch (e) {
      _showMessage('Could not prepare study guide: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPreparingStudyGuide = false);
    }
  }

  static const _studyStopWords = {
    'about', 'after', 'also', 'been', 'between', 'could', 'does', 'each',
    'from', 'have', 'into', 'more', 'most', 'other', 'over', 'same', 'some',
    'than', 'that', 'their', 'there', 'these', 'they', 'this', 'through',
    'using', 'were', 'what', 'when', 'which', 'with', 'would', 'your',
  };

  List<String> _splitStudySentences(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.length >= 24)
      .toList();

  Future<void> _generateAiHighlights() async {
    if (_studyGuideText.trim().isEmpty) return;
    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      _showMessage('Import an Offline AI model in Settings first.', isError: true);
      return;
    }
    setState(() {
      _isGeneratingAiHighlights = true;
      _aiHighlightProgress = 0.10;
      _aiHighlightStatus = 'Loading local AI model...';
    });
    _aiHighlightTimer?.cancel();
    _aiHighlightTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || !_isGeneratingAiHighlights) return;
      setState(() {
        _aiHighlightProgress = (_aiHighlightProgress + 0.035).clamp(0.10, 0.74);
        _aiHighlightStatus = _aiHighlightProgress < 0.32
            ? 'Reading source material...'
            : _aiHighlightProgress < 0.58
                ? 'Identifying the main topic...'
                : 'Selecting important phrases...';
      });
    });
    try {
      final generated = await llama.generateStudyKeyPhrases(
        sourceText: _studyGuideText,
      );
      if (!mounted) return;
      setState(() {
        _aiHighlightProgress = 0.84;
        _aiHighlightStatus = 'Verifying phrases against the source...';
      });
      final verified = <String>{};
      for (final phrase in generated) {
        final match = RegExp(RegExp.escape(phrase), caseSensitive: false)
            .firstMatch(_studyGuideText);
        if (match != null) {
          verified.add(
              _studyGuideText.substring(match.start, match.end).toLowerCase());
        }
      }
      if (verified.isEmpty) {
        throw Exception('AI returned no source-verified key phrases.');
      }
      setState(() {
        _studyGuideTerms = verified;
        _disabledStudyTerms = {};
        _areKeyTermsExpanded = false;
        _aiHighlightProgress = 1;
        _aiHighlightStatus = 'AI highlights ready.';
      });
      _showMessage('${verified.length} AI-verified phrases are highlighted.');
    } catch (e) {
      _showMessage('AI highlights failed: $e', isError: true);
    } finally {
      _aiHighlightTimer?.cancel();
      if (mounted) setState(() => _isGeneratingAiHighlights = false);
    }
  }

  Future<void> _generateWithOfflineAi() async {
    final count = int.tryParse(_totalQuestionsController.text.trim()) ?? 10;
    if (count < 1) {
      _showMessage('Question count must be at least 1.', isError: true);
      return;
    }

    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      _showMessage('Import a GGUF model in Settings > Offline AI first.',
          isError: true);
      return;
    }

    setState(() => _isAiGenerating = true);
    try {
      final sourceText = await _loadAutoSourceText();
      final generated = await llama.generateStudyQuestions(
        sourceText: sourceText,
        count: count.clamp(1, 10),
      );
      if (generated.isEmpty) {
        _showMessage('AI did not return usable questions.', isError: true);
        return;
      }

      _clearEditor();
      setState(() {
        _builderMode = _StudyBuilderMode.ai;
        _questions.addAll(generated.map(_EditableQuestion.fromJson));
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = _defaultAutoTitle();
        }
        if (_descriptionController.text.trim().isEmpty) {
          _descriptionController.text = 'AI-generated draft';
        }
      });
      _showMessage('AI generated ${generated.length} editable question(s).');
    } catch (e) {
      final message = e.toString();
      if (message.contains('stopped')) {
        _showMessage('Offline AI stopped.');
      } else if (message.contains('usable study questions') ||
          message.contains('format')) {
        _showMessage(
          'AI did not make usable questions. Try 1 to 3 questions or shorter text.',
          isError: true,
        );
      } else {
        _showMessage('Offline AI failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isAiGenerating = false);
    }
  }

  Future<void> _stopOfflineAi() async {
    await LocalLlamaService.instance.stop();
    if (mounted) setState(() => _isAiGenerating = false);
    _showMessage('Offline AI stopped.');
  }

  Future<void> _improveDraftWithOfflineAi() async {
    final currentQuestions = _questions
        .map((question) => question.toJson())
        .where((item) => (item['question'] as String).trim().isNotEmpty)
        .toList();
    if (currentQuestions.isEmpty) {
      _showMessage('Add or generate questions first.', isError: true);
      return;
    }

    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      _showMessage('Import a GGUF model in Settings > Offline AI first.',
          isError: true);
      return;
    }

    setState(() => _isAiGenerating = true);
    try {
      final improved = await llama.improveStudyQuestions(currentQuestions);
      if (improved.isEmpty) {
        _showMessage('AI did not return usable improvements.', isError: true);
        return;
      }

      _clearEditor();
      setState(() {
        _questions.addAll(improved.map(_EditableQuestion.fromJson));
        if (_descriptionController.text.trim().isEmpty) {
          _descriptionController.text = 'AI-improved draft';
        }
      });
      _showMessage('AI improved ${improved.length} question(s).');
    } catch (e) {
      _showMessage('Offline AI failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isAiGenerating = false);
    }
  }

  Future<String> _loadAutoSourceText() async {
    return switch (_autoSource) {
      _AutoStudySource.file => _loadAutoFileText(),
      _AutoStudySource.link => _loadLinkText(),
      _AutoStudySource.topic => _loadTopicText(),
    };
  }

  Future<String> _loadAutoFileText() async {
    final file = _autoFile;
    final path = file?.path;
    if (path == null || path.isEmpty) {
      throw Exception('Choose a file first.');
    }
    return DocumentParser.extractText(path, _extensionOf(file!.name));
  }

  Future<String> _loadLinkText() async {
    final rawUrl = _linkController.text.trim();
    if (rawUrl.isEmpty) throw Exception('Paste a link first.');
    final uri = Uri.tryParse(
      rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl',
    );
    if (uri == null) throw Exception('Invalid link.');
    final html = await _fetchText(uri);
    final text = _stripHtml(html);
    if (text.trim().length < 80) {
      throw Exception('The page did not provide enough readable text.');
    }
    return text;
  }

  Future<String> _loadTopicText() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) throw Exception('Enter a topic first.');

    try {
      final uri = Uri.https(
        'en.wikipedia.org',
        '/api/rest_v1/page/summary/${Uri.encodeComponent(topic)}',
      );
      final response = jsonDecode(await _fetchText(uri));
      final extract = response is Map ? response['extract'] as String? : null;
      if (extract != null && extract.trim().length > 80) return extract;
    } on Object {
      // Fall back to the typed topic if the online lookup is unavailable.
    }

    return 'Topic: $topic. Define $topic, explain its key ideas, list its uses, advantages, limitations, and common examples.';
  }

  Future<String> _fetchText(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Convert2File/1.0');
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed with status ${response.statusCode}.');
      }
      return utf8.decode(await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      ));
    } finally {
      client.close(force: true);
    }
  }

  String _stripHtml(String html) {
    final noScripts = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    return noScripts
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _defaultAutoTitle() {
    return switch (_autoSource) {
      _AutoStudySource.file => _autoFile?.name ?? 'File Reviewer',
      _AutoStudySource.link => 'Link Reviewer',
      _AutoStudySource.topic => _topicController.text.trim().isEmpty
          ? 'Topic Reviewer'
          : '${_topicController.text.trim()} Reviewer',
    };
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  Future<void> _saveStudySet() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Add a study set title first.', isError: true);
      return;
    }

    final questions = <Map<String, dynamic>>[];
    for (final question in _questions) {
      final payload = question.toJson();
      final text = payload['question'] as String;
      final answers = (payload['answers'] as List).cast<String>();
      if (text.isEmpty || answers.isEmpty) continue;
      if (question.type != StudyQuestionType.trueFalse &&
          question.type != StudyQuestionType.fillBlank &&
          (payload['choices'] as List).cast<String>().length < 2) {
        continue;
      }
      questions.add(payload);
    }

    if (questions.isEmpty) {
      _showMessage('Add at least one complete question.', isError: true);
      return;
    }

    final now = DateTime.now().toIso8601String();
    final ownerId = await _ownerId();
    final row = {
      'user_id': ownerId,
      'title': title,
      'description': _descriptionController.text.trim(),
      'questions_json': jsonEncode(questions),
      'created_at': _editingSet?['created_at'] ?? now,
      'updated_at': now,
    };

    try {
      final existingId = _editingSet?['id'] as int?;
      if (existingId == null) {
        await DatabaseHelper.instance.insertStudySet(row);
      } else {
        await DatabaseHelper.instance.updateStudySet(existingId, row);
      }
      _clearEditor();
      setState(() => _editingSet = null);
      await _loadStudySets();
      _showMessage(widget.generateQuizOnly ? 'Quiz saved.' : 'Study guide saved.');
    } catch (e) {
      _showMessage('Save failed: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEditorOpen = _questions.isNotEmpty || _editingSet != null;

    return FigmaAppShell(
      title: widget.generateQuizOnly ? 'Generate Quiz' : 'Study',
      subtitle: widget.generateQuizOnly
          ? 'Create an editable quiz from your material'
          : 'Create and manage your study guides',
      selectedIndex: 1,
      showBack: true,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.generateQuizOnly) ...[
                    _buildIntroPanel(isQuizGenerator: true),
                    const SizedBox(height: 16),
                    _buildQuizCreationSelector(),
                    const SizedBox(height: 16),
                    if (_builderMode == _StudyBuilderMode.ai) ...[
                    _buildAiGenerator(),
                    const SizedBox(height: 16),
                    ],
                    if (hasEditorOpen) ...[
                      _buildEditor(),
                      const SizedBox(height: 20),
                    ],
                  ] else ...[
                    _buildStudyReader(),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildIntroPanel({required bool isQuizGenerator}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isQuizGenerator ? Icons.quiz_outlined : Icons.school),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isQuizGenerator
                  ? '1. Choose a file, link, or topic. 2. Set the number of questions. 3. Generate, review, edit, and save your quiz.'
                  : 'Create your own reviewer or study guide manually, then save it for later practice.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizCreationSelector() {
    return FigmaCard(
      padding: const EdgeInsets.all(8),
      child: SegmentedButton<_StudyBuilderMode>(
        segments: const [
          ButtonSegment(
            value: _StudyBuilderMode.ai,
            icon: Icon(Icons.auto_awesome_outlined),
            label: Text('AI Generate'),
          ),
          ButtonSegment(
            value: _StudyBuilderMode.manual,
            icon: Icon(Icons.edit_note_outlined),
            label: Text('Create Manually'),
          ),
        ],
        selected: {_builderMode},
        onSelectionChanged: (selection) {
          final mode = selection.first;
          if (mode == _StudyBuilderMode.manual && _questions.isEmpty) {
            _newStudySet();
          } else {
            setState(() => _builderMode = mode);
          }
        },
      ),
    );
  }

  Widget _buildStudyReader() {
    final keySentences = _studyGuideSentences
        .where((sentence) => _containsStudyTerm(sentence))
        .toList();
    final keyIndexes = <int>[];
    for (var index = 0; index < _studyGuideSentences.length; index++) {
      if (_containsStudyTerm(_studyGuideSentences[index])) keyIndexes.add(index);
    }
    final preferredIndexes = keyIndexes.isEmpty
        ? List<int>.generate(_studyGuideSentences.length, (index) => index)
        : keyIndexes;
    final limit = switch (_studyNoteDensity) {
      _StudyNoteDensity.quick => 8,
      _StudyNoteDensity.normal => 30,
      _StudyNoteDensity.detailed => _studyGuideSentences.length,
    };
    final visibleIndexes = _studyNoteDensity == _StudyNoteDensity.detailed
        ? List<int>.generate(_studyGuideSentences.length, (index) => index)
        : preferredIndexes.take(limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIntroPanel(isQuizGenerator: false),
        const SizedBox(height: 16),
        FigmaPrimaryButton(
          label: _isPreparingStudyGuide ? 'Preparing guide...' : 'Choose Study File',
          icon: Icons.upload_file_outlined,
          onPressed: _isPreparingStudyGuide ? null : _createStudyGuide,
        ),
        if (_studyGuideFile != null) ...[
          const SizedBox(height: 18),
          FigmaCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.menu_book_outlined,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_studyGuideFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${_studyGuideSentences.length} study sentences • ${_activeStudyTerms.length} key terms',
                          style: TextStyle(color: _mutedTextColor(context), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          SegmentedButton<_StudyNoteDensity>(
            segments: const [
              ButtonSegment(value: _StudyNoteDensity.quick, icon: Icon(Icons.bolt_outlined), label: Text('Quick')),
              ButtonSegment(value: _StudyNoteDensity.normal, icon: Icon(Icons.notes_outlined), label: Text('Notes')),
              ButtonSegment(value: _StudyNoteDensity.detailed, icon: Icon(Icons.subject_outlined), label: Text('Detailed')),
            ],
            selected: {_studyNoteDensity},
            onSelectionChanged: (selection) =>
                setState(() => _studyNoteDensity = selection.first),
          ),
          const SizedBox(height: 16),
          _buildKeyTermControls(),
          const SizedBox(height: 16),
          _buildAiHighlightAction(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openStudySource,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open source'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudyBuilderScreen(
                        generateQuizOnly: true,
                        initialQuizFile: _studyGuideFile,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.quiz_outlined),
                  label: const Text('Create Quiz'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Study Notes', style: TextStyle(
              color: FigmaAppColors.text(context), fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final index in visibleIndexes) ...[
            _buildStudySentenceCard(index + 1, _studyGuideSentences[index], _studyGuidePages[index]),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Set<String> get _activeStudyTerms =>
      _studyGuideTerms.difference(_disabledStudyTerms);

  Widget _buildKeyTermControls() {
    final terms = _studyGuideTerms.toList()..sort();
    return FigmaCard(
      padding: const EdgeInsets.all(14),
      color: FigmaAppColors.fill(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _areKeyTermsExpanded = !_areKeyTermsExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Key terms',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Icon(_areKeyTermsExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _areKeyTermsExpanded
                ? 'Tap a term to show or hide its highlight.'
                : '${_activeStudyTerms.length} highlighted terms. Tap to manage.',
            style: TextStyle(color: _mutedTextColor(context), fontSize: 12),
          ),
          if (_areKeyTermsExpanded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: terms.map((term) {
                final enabled = !_disabledStudyTerms.contains(term);
                return FilterChip(
                  label: Text(term),
                  selected: enabled,
                  onSelected: (_) => setState(() {
                    if (enabled) {
                      _disabledStudyTerms.add(term);
                    } else {
                      _disabledStudyTerms.remove(term);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiHighlightAction() {
    if (!_isGeneratingAiHighlights) {
      return OutlinedButton.icon(
        onPressed: _generateAiHighlights,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Generate AI Highlights'),
      );
    }
    return FigmaCard(
      padding: const EdgeInsets.all(14),
      color: FigmaAppColors.fill(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome_outlined,
                color: FigmaAppColors.primary(context)),
            const SizedBox(width: 8),
            const Text('AI Highlighting',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${(_aiHighlightProgress * 100).round()}%',
                style: TextStyle(color: _mutedTextColor(context), fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _aiHighlightProgress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          Text(_aiHighlightStatus,
              style: TextStyle(color: _mutedTextColor(context), fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _openStudySource() async {
    final path = _studyGuideFile?.path;
    if (path == null || path.isEmpty) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _showMessage(result.message.isEmpty ? 'No app can open this file.' : result.message, isError: true);
    }
  }

  bool _containsStudyTerm(String sentence) => _activeStudyTerms.any(
      (term) => RegExp('\\b${RegExp.escape(term)}\\b', caseSensitive: false)
          .hasMatch(sentence));

  Widget _buildStudySentenceCard(int index, String sentence, int? page) {
    final terms = _activeStudyTerms.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final matches = terms.isEmpty
        ? <RegExpMatch>[]
        : RegExp('\\b(${terms.map(RegExp.escape).join('|')})\\b',
                caseSensitive: false)
            .allMatches(sentence)
            .toList();
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
      spans.add(TextSpan(
        text: match.group(0)!,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < sentence.length) spans.add(TextSpan(text: sentence.substring(cursor)));
    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(index.toString().padLeft(2, '0'),
              style: TextStyle(color: FigmaAppColors.primary(context), fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(text: TextSpan(
                  style: TextStyle(color: FigmaAppColors.text(context), fontSize: 15, height: 1.55), children: spans)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(page == null ? 'Source file' : 'PDF page $page',
                      style: TextStyle(color: _mutedTextColor(context), fontSize: 11)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _explainingStudySentence == index
                        ? null
                        : () => _explainStudySentence(index, sentence),
                    icon: _explainingStudySentence == index
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('Explain'),
                  ),
                ],
              ),
            ],
          )),
        ],
      ),
    );
  }

  Future<void> _explainStudySentence(int index, String sentence) async {
    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      _showMessage('Import an Offline AI model in Settings first.', isError: true);
      return;
    }
    setState(() => _explainingStudySentence = index);
    try {
      final answer = await llama.answerSimpleQuestion(
        'Explain this study note simply. Give its meaning and one short example when helpful.',
        materialContext: sentence,
        materialName: _studyGuideFile?.name,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Simple explanation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(answer, style: const TextStyle(height: 1.5)),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      _showMessage('Could not explain this note: $e', isError: true);
    } finally {
      if (mounted) setState(() => _explainingStudySentence = null);
    }
  }

  Widget _buildAiGenerator() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1. Quiz Source & Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Offline AI can be slow on phones. Start with 3 to 5 questions. You can choose each question type while reviewing the draft.',
            style: TextStyle(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 14),
          SegmentedButton<_AutoStudySource>(
            segments: const [
              ButtonSegment(
                value: _AutoStudySource.file,
                icon: Icon(Icons.upload_file),
                label: Text('File'),
              ),
              ButtonSegment(
                value: _AutoStudySource.link,
                icon: Icon(Icons.link),
                label: Text('Link'),
              ),
              ButtonSegment(
                value: _AutoStudySource.topic,
                icon: Icon(Icons.travel_explore),
                label: Text('Topic'),
              ),
            ],
            selected: {_autoSource},
            onSelectionChanged: (selection) {
              setState(() => _autoSource = selection.first);
            },
          ),
          const SizedBox(height: 12),
          _buildAutoSourceInput(),
          const SizedBox(height: 12),
          TextField(
            controller: _totalQuestionsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Number of questions',
              prefixIcon: Icon(Icons.format_list_numbered),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isAiGenerating ? null : _generateWithOfflineAi,
              icon: _isAiGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.memory),
              label: Text(
                _isAiGenerating
                    ? 'Offline AI is working...'
                    : 'Generate Quiz',
              ),
            ),
          ),
          if (_isAiGenerating) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _stopOfflineAi,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop AI Generation'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAutoSourceInput() {
    return switch (_autoSource) {
      _AutoStudySource.file => OutlinedButton.icon(
          onPressed: _pickAutoFile,
          icon: const Icon(Icons.attach_file),
          label: Text(_autoFile?.name ?? 'Choose PDF, DOCX, TXT, PPTX'),
        ),
      _AutoStudySource.link => TextField(
          controller: _linkController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Paste webpage link',
            prefixIcon: Icon(Icons.link),
          ),
        ),
      _AutoStudySource.topic => TextField(
          controller: _topicController,
          decoration: const InputDecoration(
            labelText: 'Topic',
            prefixIcon: Icon(Icons.search),
          ),
        ),
    };
  }

  Widget _buildEditor() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.generateQuizOnly
                      ? (_editingSet == null ? '2. Review Quiz' : 'Edit Quiz')
                      : (_editingSet == null
                          ? 'Create Study Guide'
                          : 'Edit Study Guide'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Improve with Offline AI',
                onPressed: _isAiGenerating ? null : _improveDraftWithOfflineAi,
                icon: _isAiGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
              ),
              TextButton.icon(
                onPressed: _saveStudySet,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description / Subject',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < _questions.length; i++) ...[
            _buildQuestionEditor(i),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _questions.add(_EditableQuestion()));
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Question'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveStudySet,
                  icon: const Icon(Icons.save),
                  label: Text(widget.generateQuizOnly ? 'Save Quiz' : 'Save Study Guide'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionEditor(int index) {
    final question = _questions[index];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: _questions.length == 1
                    ? null
                    : () {
                        setState(() {
                          _questions.removeAt(index).dispose();
                        });
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          DropdownButtonFormField<StudyQuestionType>(
            initialValue: question.type,
            decoration: const InputDecoration(labelText: 'Quiz Type'),
            items: StudyQuestionType.values
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => question.setType(value));
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: question.questionController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Question',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          if (question.type == StudyQuestionType.trueFalse)
            DropdownButtonFormField<String>(
              initialValue: question.answerControllers.first.text.isEmpty
                  ? 'true'
                  : question.answerControllers.first.text,
              decoration: const InputDecoration(labelText: 'Correct Answer'),
              items: const [
                DropdownMenuItem(value: 'true', child: Text('True')),
                DropdownMenuItem(value: 'false', child: Text('False')),
              ],
              onChanged: (value) {
                if (value == null) return;
                question.answerControllers.first.text = value;
              },
            )
          else ...[
            if (question.type != StudyQuestionType.fillBlank) ...[
              const Text(
                'Choices',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (int c = 0; c < question.choiceControllers.length; c++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: question.choiceControllers[c],
                    decoration: InputDecoration(
                      labelText: 'Choice ${String.fromCharCode(65 + c)}',
                    ),
                  ),
                ),
            ],
            TextField(
              controller: question.answerControllers.first,
              decoration: InputDecoration(
                labelText: question.type == StudyQuestionType.multipleChoice
                    ? 'Correct answers, comma separated'
                    : 'Correct answer',
                helperText: question.type == StudyQuestionType.multipleChoice
                    ? 'Example: A, C or exact choice text separated by commas'
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return FigmaCard(
      padding: const EdgeInsets.all(22),
      child: const Column(
        children: [
          Icon(Icons.quiz_outlined, size: 42),
          SizedBox(height: 10),
          Text(
            'No study sets yet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text('Tap New Set to build your own reviewer.'),
        ],
      ),
    );
  }

  Widget _buildSavedStudySets() {
    if (_savedStudySets.isEmpty) return _buildEmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Saved Study Quizzes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadStudySets,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final set in _savedStudySets) ...[
          _buildStudySetCard(set),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildStudySetCard(Map<String, dynamic> set) {
    final questions = _questionsFromSet(set);
    final lastScore = set['last_score'];
    final lastTotal = set['last_total'];
    final hasScore = lastScore != null && lastTotal != null;
    final subtitle = [
      '${questions.length} question(s)',
      if (hasScore) 'Last score: $lastScore/$lastTotal',
    ].join(' • ');

    return FigmaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.16),
                child: const Icon(Icons.school_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      set['title'] as String? ?? 'Untitled study quiz',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(color: _mutedTextColor(context))),
                    if ((set['description'] as String? ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          set['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _editStudySet(set);
                  } else if (value == 'delete') {
                    _deleteStudySet(set['id'] as int);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: questions.isEmpty ? null : () => _startQuiz(set),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Answering'),
            ),
          ),
        ],
      ),
    );
  }

  Color _mutedTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
  }
}

class _EditableQuestion {
  StudyQuestionType type;
  final TextEditingController questionController;
  final List<TextEditingController> choiceControllers;
  final List<TextEditingController> answerControllers;

  _EditableQuestion({
    this.type = StudyQuestionType.abcd,
    String question = '',
    List<String> choices = const ['', '', '', ''],
    List<String> answers = const [''],
  })  : questionController = TextEditingController(text: question),
        choiceControllers = choices
            .take(4)
            .map((choice) => TextEditingController(text: choice))
            .toList(),
        answerControllers = [
          TextEditingController(text: answers.isEmpty ? '' : answers.join(', '))
        ] {
    while (choiceControllers.length < 4) {
      choiceControllers.add(TextEditingController());
    }
    if (type == StudyQuestionType.trueFalse &&
        answerControllers.first.text.isEmpty) {
      answerControllers.first.text = 'true';
    }
  }

  factory _EditableQuestion.fromJson(Map<String, dynamic> json) {
    return _EditableQuestion(
      type: _typeFromValue(json['type'] as String?),
      question: json['question'] as String? ?? '',
      choices: (json['choices'] as List? ?? const []).map((e) => '$e').toList(),
      answers: (json['answers'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  void setType(StudyQuestionType newType) {
    type = newType;
    if (newType == StudyQuestionType.trueFalse) {
      choiceControllers[0].text = 'True';
      choiceControllers[1].text = 'False';
      answerControllers.first.text =
          answerControllers.first.text.toLowerCase() == 'false'
              ? 'false'
              : 'true';
    }
  }

  Map<String, dynamic> toJson() {
    final choices = type == StudyQuestionType.trueFalse
        ? ['True', 'False']
        : type == StudyQuestionType.fillBlank
            ? <String>[]
            : choiceControllers
                .map((controller) => controller.text.trim())
                .where((text) => text.isNotEmpty)
                .toList();
    final answers = answerControllers.first.text
        .split(',')
        .map((answer) => answer.trim())
        .where((answer) => answer.isNotEmpty)
        .toList();

    return {
      'type': type.value,
      'question': questionController.text.trim(),
      'choices': choices,
      'answers': answers,
    };
  }

  void dispose() {
    questionController.dispose();
    for (final controller in choiceControllers) {
      controller.dispose();
    }
    for (final controller in answerControllers) {
      controller.dispose();
    }
  }
}

class _StudyQuizScreen extends StatefulWidget {
  final Map<String, dynamic> studySet;
  final List<Map<String, dynamic>> questions;
  final VoidCallback onSavedScore;

  const _StudyQuizScreen({
    required this.studySet,
    required this.questions,
    required this.onSavedScore,
  });

  @override
  State<_StudyQuizScreen> createState() => _StudyQuizScreenState();
}

class _StudyQuizScreenState extends State<_StudyQuizScreen> {
  late List<Map<String, dynamic>> _activeQuestions;
  final List<_QuizAttemptResult> _results = [];
  final _fillController = TextEditingController();
  final Set<String> _selectedMany = {};
  int _index = 0;
  bool _finished = false;
  String? _selected;

  Map<String, dynamic> get _question => _activeQuestions[_index];
  StudyQuestionType get _type => _typeFromValue(_question['type'] as String?);
  List<String> get _choices =>
      (_question['choices'] as List? ?? const []).map((e) => '$e').toList();
  List<String> get _answers =>
      (_question['answers'] as List? ?? const []).map((e) => '$e').toList();
  int get _score => _results.where((result) => result.isCorrect).length;
  int get _total => _activeQuestions.length;
  List<_QuizAttemptResult> get _mistakes =>
      _results.where((result) => !result.isCorrect).toList();

  @override
  void initState() {
    super.initState();
    _activeQuestions = List<Map<String, dynamic>>.from(widget.questions);
  }

  @override
  void dispose() {
    _fillController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_hasAnswer()) return;
    final selectedAnswers = _currentSelectedAnswers();
    final result = _QuizAttemptResult(
      question: _question,
      selectedAnswers: selectedAnswers,
      correctAnswers: _answers,
      isCorrect: _isCorrect(selectedAnswers),
    );

    if (_index == _activeQuestions.length - 1) {
      final finishedResults = [..._results, result];
      await DatabaseHelper.instance.updateStudySet(
        widget.studySet['id'] as int,
        {
          'last_score': finishedResults.where((item) => item.isCorrect).length,
          'last_total': finishedResults.length,
        },
      );
      widget.onSavedScore();
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(finishedResults);
        _finished = true;
      });
      return;
    }

    setState(() {
      _results.add(result);
      _index++;
      _clearAnswer();
    });
  }

  bool _hasAnswer() {
    if (_type == StudyQuestionType.fillBlank) {
      return _fillController.text.trim().isNotEmpty;
    }
    if (_type == StudyQuestionType.multipleChoice) {
      return _selectedMany.isNotEmpty;
    }
    return _selected != null;
  }

  List<String> _currentSelectedAnswers() {
    if (_type == StudyQuestionType.fillBlank) {
      return [_fillController.text.trim()];
    }
    if (_type == StudyQuestionType.multipleChoice) {
      return _selectedMany.toList();
    }
    return [_selected ?? ''];
  }

  void _clearAnswer() {
    _selected = null;
    _selectedMany.clear();
    _fillController.clear();
  }

  bool _isCorrect(List<String> selectedAnswers) {
    final correctKeys = _answerKeys(_answers);
    final selectedKeys = _answerKeys(selectedAnswers);
    return selectedKeys.length == correctKeys.length &&
        selectedKeys.containsAll(correctKeys);
  }

  Set<String> _answerKeys(List<String> values) {
    return values
        .map((value) => _answerKey(value))
        .where((v) => v.isNotEmpty)
        .toSet();
  }

  String _answerKey(String value) {
    final normalized = _normalize(value);
    final letterIndex = normalized.length == 1
        ? normalized.codeUnitAt(0) - 'a'.codeUnitAt(0)
        : -1;
    if (letterIndex >= 0 && letterIndex < _choices.length) {
      return 'choice:$letterIndex';
    }

    final choiceIndex = _choices.indexWhere(
      (choice) => _normalize(choice) == normalized,
    );
    if (choiceIndex != -1) return 'choice:$choiceIndex';

    if (_type == StudyQuestionType.trueFalse) {
      if (normalized == 'true' || normalized == 't') return 'true';
      if (normalized == 'false' || normalized == 'f') return 'false';
    }
    return normalized;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _practiceMistakes() {
    final missedQuestions = _mistakes.map((result) => result.question).toList();
    setState(() {
      _activeQuestions = missedQuestions;
      _results.clear();
      _index = 0;
      _finished = false;
      _clearAnswer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: widget.studySet['title'] as String? ?? 'Study Quiz',
      subtitle: _finished ? 'Results and review' : 'Answer each question',
      selectedIndex: 1,
      showBack: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _finished ? _buildResults() : _buildQuestion(),
      ),
    );
  }

  Widget _buildQuestion() {
    final progress = (_index + 1) / _activeQuestions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress)),
            const SizedBox(width: 12),
            Text('${_index + 1}/${_activeQuestions.length}'),
          ],
        ),
        const SizedBox(height: 16),
        FigmaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _type.label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _question['question'] as String? ?? '',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              _buildAnswerInput(),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _hasAnswer() ? _submit : null,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _index == _activeQuestions.length - 1
                        ? 'Finish Quiz'
                        : 'Submit Answer',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerInput() {
    if (_type == StudyQuestionType.fillBlank) {
      return TextField(
        controller: _fillController,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Type your answer',
          prefixIcon: Icon(Icons.edit),
        ),
      );
    }

    final choices = _type == StudyQuestionType.trueFalse
        ? const ['True', 'False']
        : _choices;

    if (_type == StudyQuestionType.multipleChoice) {
      return Column(
        children: choices.map((choice) {
          return CheckboxListTile(
            value: _selectedMany.contains(choice),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selectedMany.add(choice);
                } else {
                  _selectedMany.remove(choice);
                }
              });
            },
            title: Text(choice),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          );
        }).toList(),
      );
    }

    return Column(
      children: choices.map((choice) {
        final isSelected = _selected == choice;
        return ListTile(
          onTap: () => setState(() => _selected = choice),
          leading: Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(choice),
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  Widget _buildResults() {
    final percent = ((_score / _total) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FigmaCard(
          child: Column(
            children: [
              const Icon(Icons.workspace_premium_outlined, size: 44),
              const SizedBox(height: 10),
              Text(
                '$_score / $_total',
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
              ),
              Text(
                '$percent% score',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mistakes.isEmpty ? null : _practiceMistakes,
                      icon: const Icon(Icons.replay),
                      label: const Text('Practice Mistakes'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.done),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _mistakes.isEmpty ? 'Review' : 'Review Incorrect Answers',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (_mistakes.isEmpty)
          FigmaCard(
            child: Text(
              'Perfect score. No incorrect answers to review.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          )
        else
          for (final result in _mistakes) ...[
            _buildReviewCard(result),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildReviewCard(_QuizAttemptResult result) {
    return FigmaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.question['question'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text('Your answer: ${result.selectedAnswers.join(', ')}'),
          const SizedBox(height: 4),
          Text(
            'Correct answer: ${result.correctAnswers.join(', ')}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _QuizAttemptResult {
  final Map<String, dynamic> question;
  final List<String> selectedAnswers;
  final List<String> correctAnswers;
  final bool isCorrect;

  const _QuizAttemptResult({
    required this.question,
    required this.selectedAnswers,
    required this.correctAnswers,
    required this.isCorrect,
  });
}
