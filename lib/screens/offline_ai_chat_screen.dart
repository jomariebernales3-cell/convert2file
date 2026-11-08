import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../services/document_parser.dart';
import '../services/file_storage.dart';
import '../services/local_llama_service.dart';
import '../widgets/figma_app_chrome.dart';
import '../theme/app_colors.dart';

class OfflineAiChatScreen extends StatefulWidget {
  const OfflineAiChatScreen({super.key});

  @override
  State<OfflineAiChatScreen> createState() => _OfflineAiChatScreenState();
}

class _OfflineAiChatScreenState extends State<OfflineAiChatScreen> {
  static const _chatHistoryKey = 'offline_ai_chat_history_v1';
  static const _chatStopWords = {
    'the',
    'and',
    'for',
    'with',
    'what',
    'when',
    'where',
    'which',
    'why',
    'how',
    'are',
    'is',
    'this',
    'that',
    'from',
    'about',
  };

  final _messageController = TextEditingController();
  final _threadController = ScrollController();
  final _authService = AuthService();
  final List<Map<String, String>> _messages = [];
  List<Map<String, dynamic>> _materials = [];
  Map<String, dynamic>? _selectedMaterial;
  String? _selectedMaterialText;
  bool _loadingMaterials = true;
  bool _loadingMaterial = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadMaterials();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _threadController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_chatHistoryKey);
    if (saved == null) return;
    try {
      final decoded = jsonDecode(saved) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(decoded
              .whereType<Map>()
              .map((item) => {
                    'role': item['role']?.toString() ?? 'assistant',
                    'text': item['text']?.toString() ?? '',
                  })
              .where((item) => item['text']!.isNotEmpty));
      });
      _scrollToBottom();
    } catch (_) {
      // Ignore an invalid local history cache and let the user start a new chat.
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatHistoryKey, jsonEncode(_messages));
  }

  Future<void> _loadMaterials() async {
    try {
      final ownerId = _authService.currentUser?.id ??
          await DatabaseHelper.instance.getOrCreateGuestUserId();
      final records = await DatabaseHelper.instance.queryFilesByUser(ownerId);
      if (!mounted) return;
      setState(() {
        _materials = records.where(_isReadableMaterial).toList();
        _loadingMaterials = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMaterials = false);
    }
  }

  bool _isReadableMaterial(Map<String, dynamic> file) {
    final extension = (file['extension'] as String? ?? '').toLowerCase();
    return const {'txt', 'docx', 'pdf', 'ppt', 'pptx'}.contains(extension);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_threadController.hasClients) return;
      _threadController.animateTo(
        _threadController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage([String? preset]) async {
    final question = (preset ?? _messageController.text).trim();
    if (question.isEmpty || _asking) return;

    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Import a GGUF model to use Offline AI.'),
          action: SnackBarAction(
            label: 'SET UP',
            onPressed: () => Navigator.of(context).pushNamed('/ai-model'),
          ),
        ),
      );
      return;
    }

    setState(() {
      _asking = true;
      _messages.add({'role': 'user', 'text': question});
      _messageController.clear();
    });
    _scrollToBottom();
    await _saveHistory();

    final materialContext =
        _selectedMaterialText == null || _selectedMaterialText!.trim().isEmpty
            ? null
            : _relevantMaterialContext(_selectedMaterialText!, question);
    try {
      final answer = await llama.answerSimpleQuestion(
        question,
        materialContext: materialContext,
        materialName: _selectedMaterial?['original_name'] as String?,
        conversation: _messages,
      );
      if (!mounted) return;
      setState(() => _messages.add({'role': 'assistant', 'text': answer}));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': materialContext == null
              ? 'I could not generate an answer. Try again or use a smaller GGUF model.'
              : 'I could not generate a full answer. Here is the most relevant text from your material:\n\n$materialContext',
        });
      });
    } finally {
      if (mounted) {
        setState(() => _asking = false);
        await _saveHistory();
        _scrollToBottom();
      }
    }
  }

  Future<void> _stopGeneration() async {
    await LocalLlamaService.instance.stop();
    if (mounted) setState(() => _asking = false);
  }

  Future<void> _chooseMaterial() async {
    if (_loadingMaterials) return;
    if (_materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No readable materials found.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: _materials.length,
          itemBuilder: (context, index) {
            final file = _materials[index];
            return ListTile(
              leading: Icon(Icons.description_outlined,
                  color: FigmaAppColors.primary(context)),
              title: Text(
                file['original_name'] as String? ?? 'Untitled material',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${(file['extension'] as String? ?? '').toUpperCase()} · ${FileStorage.formatFileSize(file['size_bytes'] as int? ?? 0)}',
              ),
              onTap: () => Navigator.of(sheetContext).pop(file),
            );
          },
        ),
      ),
    );
    if (selected != null) await _loadSelectedMaterial(selected);
  }

  Future<void> _loadSelectedMaterial(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    final extension = file['extension'] as String? ?? '';
    if (path.isEmpty) return;

    setState(() => _loadingMaterial = true);
    try {
      final text = await DocumentParser.extractText(path, extension);
      if (!mounted) return;
      setState(() {
        _selectedMaterial = file;
        _selectedMaterialText = text;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read material: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingMaterial = false);
    }
  }

  String _relevantMaterialContext(String text, String question) {
    final chunks = _materialChunks(text);
    if (chunks.isEmpty) return text.substring(0, text.length.clamp(0, 2400));
    final terms = RegExp(r'[a-zA-Z][a-zA-Z0-9]{2,}')
        .allMatches(question.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => !_chatStopWords.contains(term))
        .toSet();
    final scored = chunks.map((chunk) {
      final lower = chunk.toLowerCase();
      final score = terms.fold<int>(
        0,
        (sum, term) => sum + (lower.contains(term) ? 1 : 0),
      );
      return MapEntry(chunk, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final selected = scored
        .where((entry) => entry.value > 0)
        .take(4)
        .map((entry) => entry.key)
        .toList();
    final contextText =
        (selected.isEmpty ? chunks.take(3) : selected).join('\n\n');
    return contextText.substring(0, contextText.length.clamp(0, 2600));
  }

  List<String> _materialChunks(String text) {
    final sentences = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((part) => part.trim())
        .where((part) => part.length >= 40);
    final chunks = <String>[];
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (buffer.length + sentence.length > 650 && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.write('$sentence ');
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks;
  }

  Future<void> _startNewChat() async {
    if (_asking) await _stopGeneration();
    if (_messages.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new chat?'),
          content:
              const Text('This clears the saved conversation on this phone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear chat'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _messages.clear();
      _selectedMaterial = null;
      _selectedMaterialText = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatHistoryKey);
  }

  @override
  Widget build(BuildContext context) {
    final llama = LocalLlamaService.instance;
    final modelName = llama.modelPath == null
        ? 'No model imported'
        : llama.modelPath!.split(RegExp(r'[\\/]')).last;

    return Scaffold(
      backgroundColor: FigmaAppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(modelName),
            Expanded(
              child: ListView.builder(
                controller: _threadController,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                itemCount: _messages.isEmpty ? 1 : _messages.length,
                itemBuilder: (context, index) => _messages.isEmpty
                    ? _buildWelcomeMessage(llama.hasModel)
                    : _buildMessage(_messages[index]),
              ),
            ),
            _buildSuggestions(),
            if (_selectedMaterial != null) _buildAttachmentChip(),
            _buildComposer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Runs on your phone. Answers can be wrong, so check important facts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: FigmaAppColors.subtext(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String modelName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: FigmaAppColors.border(context))),
      ),
      child: Row(
        children: [
          _headerButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline AI',
                  style: TextStyle(
                    color: FigmaAppColors.text(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$modelName · runs on this phone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: FigmaAppColors.subtext(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _headerButton(
            icon: Icons.edit_outlined,
            tooltip: 'New chat',
            onPressed: _startNewChat,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: FigmaAppColors.fill(context),
          foregroundColor: FigmaAppColors.text(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage(bool hasModel) {
    return _assistantMessage(
      hasModel
          ? 'Ask me a question, or tap + to attach a material and ask about its contents.'
          : 'I can answer questions using a model stored on this phone. Import a GGUF model to get started.',
      showModelSetup: !hasModel,
    );
  }

  Widget _buildMessage(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final text = message['text'] ?? '';
    if (!isUser) return _assistantMessage(text);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: FigmaAppColors.fill(context),
          border: Border.all(color: FigmaAppColors.border(context)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: SelectableText(
          text,
          style: TextStyle(
            color: FigmaAppColors.text(context),
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _assistantMessage(String text, {bool showModelSetup = false}) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colors.highlight, colors.accent],
              ),
            ),
            child: Text(
              'AI',
              style: TextStyle(
                color: colors.highlightInk,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text,
                  style: TextStyle(
                    color: FigmaAppColors.text(context),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                if (showModelSetup) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/ai-model'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.accent,
                      side: BorderSide(color: colors.accent),
                    ),
                    child: const Text('Set up Offline AI'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    const suggestions = [
      'Summarize a file',
      'Make a quiz',
      'Explain a topic',
      'Make flashcards',
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => OutlinedButton(
          onPressed: _asking ? null : () => _sendSuggestion(suggestions[index]),
          style: OutlinedButton.styleFrom(
            foregroundColor: FigmaAppColors.text(context),
            side: BorderSide(color: FigmaAppColors.border(context)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
          ),
          child: Text(
            suggestions[index],
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Future<void> _sendSuggestion(String label) async {
    if (label == 'Summarize a file' && _selectedMaterial == null) {
      await _chooseMaterial();
      if (_selectedMaterial == null) return;
    }
    final prompt = switch (label) {
      'Summarize a file' =>
        'Summarize the attached material in clear bullet points.',
      'Make a quiz' => 'Make 5 quiz questions from the attached material.',
      'Explain a topic' =>
        'Explain the main topic in the attached material simply.',
      _ => 'Make flashcards from the attached material.',
    };
    await _sendMessage(prompt);
  }

  Widget _buildAttachmentChip() {
    final name = _selectedMaterial?['original_name'] as String? ?? 'Material';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: FigmaAppColors.fill(context),
            border: Border.all(color: FigmaAppColors.border(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 17, color: FigmaAppColors.primary(context)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Remove material',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _selectedMaterial = null;
                  _selectedMaterialText = null;
                }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final accent = FigmaAppColors.primary(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FigmaAppColors.card(context),
        border: Border.all(color: FigmaAppColors.border(context)),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton.filledTonal(
              tooltip: 'Attach material',
              onPressed: _loadingMaterial ? null : _chooseMaterial,
              icon: _loadingMaterial
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 22),
              style: IconButton.styleFrom(
                backgroundColor: FigmaAppColors.fill(context),
                foregroundColor: FigmaAppColors.text(context),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              style:
                  TextStyle(color: FigmaAppColors.text(context), fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Message Offline AI',
                hintStyle: TextStyle(color: FigmaAppColors.subtext(context)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              tooltip: _asking ? 'Stop generation' : 'Send message',
              onPressed: _asking ? _stopGeneration : _sendMessage,
              icon: Icon(_asking ? Icons.stop_rounded : Icons.arrow_upward),
              style: IconButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
