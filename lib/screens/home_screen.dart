import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../services/document_parser.dart';
import '../services/file_storage.dart';
import '../services/local_llama_service.dart';
import '../widgets/figma_app_chrome.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  final _authService = AuthService();
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  static const _chatHistoryKey = 'offline_ai_chat_history_v1';
  final List<Map<String, String>> _chatHistory = [];
  bool _isLoading = true;
  bool _isAskingAi = false;
  bool _isLoadingMaterial = false;
  Map<String, dynamic>? _selectedMaterial;
  String? _selectedMaterialText;
  List<Map<String, dynamic>> _recentFiles = [];
  List<Map<String, dynamic>> _studySets = [];
  int _totalFiles = 0;
  int _totalOutputs = 0;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
    _loadChatHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTermsAgreement());
  }

  Future<void> _showTermsAgreement() async {
    final prefs = await SharedPreferences.getInstance();
    const agreementKey = 'terms_privacy_agreement_v1';
    if (prefs.getBool(agreementKey) == true || !mounted) return;

    var hasReadTerms = false;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Terms & Privacy Agreement'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please read this before using Convert2File.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  _agreementItem(
                    Icons.folder_outlined,
                    'Your personal files',
                    'Files you choose are used to create conversions, study notes, quizzes, and exports. They are stored and processed locally on this device unless you explicitly use a connected online service.',
                  ),
                  _agreementItem(
                    Icons.person_outline,
                    'Account information',
                    'Your sign-in details are used only to authenticate and manage your account. Authentication is handled by the app’s configured account service; this agreement itself is never uploaded.',
                  ),
                  _agreementItem(
                    Icons.psychology_outlined,
                    'Offline AI',
                    'When you choose a material for Offline AI, relevant text is read on this device by the installed local model. You should review generated content before sharing it.',
                  ),
                  _agreementItem(
                    Icons.camera_alt_outlined,
                    'Device permissions',
                    'Camera permission is requested only when you use QR Scan. Photos/media access is requested only when you save a generated QR image. You can change permissions anytime in Android Settings.',
                  ),
                  _agreementItem(
                    Icons.storage_outlined,
                    'This agreement',
                    'Your agreement is saved only on this device. It is not stored in the online database. Clearing app data or reinstalling the app will show it again.',
                  ),
                  const Divider(height: 24),
                  CheckboxListTile(
                    value: hasReadTerms,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) => setDialogState(
                      () => hasReadTerms = value ?? false,
                    ),
                    title: const Text(
                      'I have read and agree to the Terms & Privacy Agreement.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: hasReadTerms
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Agree and continue'),
            ),
          ],
        ),
      ),
    );
    if (agreed == true) await prefs.setBool(agreementKey, true);
  }

  Widget _agreementItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: FigmaAppColors.primary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: FigmaAppColors.text(context),
                  fontSize: 13,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$title\n',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_chatHistoryKey);
    if (saved == null) return;
    try {
      final decoded = jsonDecode(saved) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _chatHistory
          ..clear()
          ..addAll(decoded
              .whereType<Map>()
              .map((item) => {
                    'role': item['role']?.toString() ?? 'assistant',
                    'text': item['text']?.toString() ?? '',
                  })
              .where((item) => item['text']!.isNotEmpty));
      });
      _scrollChatToBottom();
    } catch (_) {
      // A malformed old cache should not prevent the assistant from opening.
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatHistoryKey, jsonEncode(_chatHistory));
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadHomeData() async {
    setState(() => _isLoading = true);
    try {
      final ownerId = _authService.currentUser?.id ??
          await DatabaseHelper.instance.getOrCreateGuestUserId();
      final files = await DatabaseHelper.instance.queryFilesByUser(ownerId);
      final studySets =
          await DatabaseHelper.instance.queryStudySetsByUser(ownerId);
      if (!mounted) return;
      setState(() {
        _recentFiles = files.take(4).toList();
        _studySets = studySets;
        _totalFiles = files.length;
        _totalOutputs = files
            .where(
              (file) => (file['kind'] as String? ?? '').startsWith('output_'),
            )
            .length;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to load home data: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: 'Convert2File',
      subtitle: 'Ready to create your next study material?',
      selectedIndex: 0,
      child: RefreshIndicator(
        onRefresh: _loadHomeData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  _buildWelcomeCard(),
                  const SizedBox(height: 18),
                  _buildOfflineAiChat(),
                  const SizedBox(height: 22),
                  _buildProgressGrid(),
                  const SizedBox(height: 22),
                  _buildRecentMaterials(),
                ],
              ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    final userName = _authService.currentUser?.name ?? 'Jomarie';
    return FigmaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good day, $userName',
            style: TextStyle(
              color: FigmaAppColors.text(context),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload files, generate study materials, and keep your work saved locally on this device.',
            style: TextStyle(
              color: FigmaAppColors.subtext(context),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askOfflineAi() async {
    final question = _chatController.text.trim();
    if (question.isEmpty) return;

    final llama = LocalLlamaService.instance;
    if (!llama.hasModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              'Import and load a GGUF model in Settings > Offline AI first.'),
        ),
      );
      return;
    }
    setState(() {
      _isAskingAi = true;
      _chatHistory.add({'role': 'user', 'text': question});
    });
    _chatController.clear();
    _scrollChatToBottom();
    await _saveChatHistory();
    final materialContext =
        _selectedMaterialText == null || _selectedMaterialText!.trim().isEmpty
            ? null
            : _relevantMaterialContext(_selectedMaterialText!, question);
    try {
      final answer = await llama.answerSimpleQuestion(
        question,
        materialContext: materialContext,
        materialName: _selectedMaterial?['original_name'] as String?,
        conversation: _chatHistory,
      );
      if (!mounted) return;
      setState(() => _chatHistory.add({'role': 'assistant', 'text': answer}));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatHistory.add({
          'role': 'assistant',
          'text': materialContext == null
              ? 'I could not generate an answer. Please try again or use a smaller GGUF model.'
              : 'I could not generate a full AI answer, but this is the most relevant part from the selected material:\n\n$materialContext',
        });
      });
    } finally {
      if (mounted) {
        setState(() => _isAskingAi = false);
        await _saveChatHistory();
        _scrollChatToBottom();
      }
    }
  }

  Future<void> _stopOfflineAi() async {
    await LocalLlamaService.instance.stop();
    if (mounted) setState(() => _isAskingAi = false);
  }

  Future<void> _chooseMaterial() async {
    final materials = _recentFiles.where(_isReadableMaterial).toList();
    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No readable recent materials found.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: materials.length,
            itemBuilder: (context, index) {
              final file = materials[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  file['original_name'] as String? ?? 'Untitled material',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(file['extension'] as String? ?? '').toUpperCase()} • ${FileStorage.formatFileSize(file['size_bytes'] as int? ?? 0)}',
                ),
                onTap: () => Navigator.pop(context, file),
              );
            },
          ),
        );
      },
    );
    if (selected == null) return;
    await _loadSelectedMaterial(selected);
  }

  Future<void> _loadSelectedMaterial(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    final extension = file['extension'] as String? ?? '';
    if (path.isEmpty) return;

    setState(() => _isLoadingMaterial = true);
    try {
      final text = await DocumentParser.extractText(path, extension);
      if (!mounted) return;
      setState(() {
        _selectedMaterial = file;
        _selectedMaterialText = text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Selected ${file['original_name'] as String? ?? 'material'}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Could not read material: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMaterial = false);
    }
  }

  bool _isReadableMaterial(Map<String, dynamic> file) {
    final extension = (file['extension'] as String? ?? '').toLowerCase();
    return const {'txt', 'docx', 'pdf', 'ppt', 'pptx'}.contains(extension);
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
    final fallback = selected.isEmpty ? chunks.take(3).toList() : selected;
    final contextText = fallback.join('\n\n');
    return contextText.substring(
      0,
      contextText.length.clamp(0, 2600),
    );
  }

  List<String> _materialChunks(String text) {
    final paragraphs = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((part) => part.trim())
        .where((part) => part.length >= 40)
        .toList();
    final chunks = <String>[];
    final buffer = StringBuffer();
    for (final paragraph in paragraphs) {
      if (buffer.length + paragraph.length > 650 && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.write('$paragraph ');
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks;
  }

  Widget _buildOfflineAiChat() {
    final llama = LocalLlamaService.instance;
    final modelName = llama.modelPath == null
        ? 'No model loaded'
        : llama.modelPath!.split(RegExp(r'[\\/]')).last;
    final poweredText = llama.hasModel
        ? 'Powered by local Llama AI: $modelName'
        : 'Offline AI ready: import a Llama GGUF model in Settings';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Offline AI Assistant'),
        const SizedBox(height: 10),
        FigmaCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FigmaAppColors.border(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_alt_outlined,
                      color: FigmaAppColors.primary(context),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        poweredText,
                        style: TextStyle(
                          color: FigmaAppColors.text(context),
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_chatHistory.isNotEmpty) ...[
                SizedBox(
                  height: 330,
                  child: Scrollbar(
                    controller: _chatScrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.only(right: 4),
                      itemCount: _chatHistory.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildChatMessage(_chatHistory[index]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _chatController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Message Offline AI',
                  hintText:
                      'Ask anything: definitions, code, app help, or your selected file',
                  prefixIcon: Icon(Icons.chat_bubble_outline),
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedMaterial != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: FigmaAppColors.fill(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FigmaAppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: FigmaAppColors.primary(context),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Using: ${_selectedMaterial!['original_name'] as String? ?? 'Selected material'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FigmaAppColors.text(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _isLoadingMaterial ? null : _chooseMaterial,
                icon: _isLoadingMaterial
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
                label: Text(
                  _selectedMaterial == null
                      ? 'Select From Recent Materials'
                      : _selectedMaterial!['original_name'] as String? ??
                          'Selected material',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isAskingAi ? null : _askOfflineAi,
                      icon: _isAskingAi
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_isAskingAi ? 'Thinking...' : 'Ask AI'),
                    ),
                  ),
                  if (_isAskingAi) ...[
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Stop AI',
                      onPressed: _stopOfflineAi,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  ],
                  if (_chatHistory.isNotEmpty && !_isAskingAi) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Refresh chat history',
                      onPressed: _clearChatHistory,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatMessage(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final text = message['text'] ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primary.withValues(alpha: 0.14)
              : FigmaAppColors.fill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isUser
                  ? colorScheme.primary.withValues(alpha: 0.35)
                  : FigmaAppColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    isUser
                        ? Icons.person_outline
                        : Icons.psychology_alt_outlined,
                    size: 16,
                    color: isUser
                        ? colorScheme.primary
                        : FigmaAppColors.primary(context)),
                const SizedBox(width: 6),
                Text(isUser ? 'You' : 'DBZ',
                    style: TextStyle(
                        color: FigmaAppColors.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
                const Spacer(),
                if (!isUser)
                  IconButton(
                    tooltip: 'Copy answer',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AI answer copied.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SelectableText(text,
                style: TextStyle(
                    color: FigmaAppColors.text(context), height: 1.45)),
          ],
        ),
      ),
    );
  }

  Future<void> _clearChatHistory() async {
    setState(_chatHistory.clear);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatHistoryKey);
  }

  Widget _buildProgressGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Quick Progress'),
        const SizedBox(height: 10),
        Row(
          children: [
            _progressTile(
                'Files', _totalFiles.toString(), Icons.description_outlined),
            const SizedBox(width: 10),
            _progressTile(
                'Study Sets', _studySets.length.toString(), Icons.school),
            const SizedBox(width: 10),
            _progressTile('Outputs', _totalOutputs.toString(), Icons.task_alt),
          ],
        ),
      ],
    );
  }

  Widget _progressTile(String label, String value, IconData icon) {
    return Expanded(
      child: FigmaCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 19, color: FigmaAppColors.primary(context)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: FigmaAppColors.text(context),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FigmaAppColors.subtext(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMaterials() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('Recent Materials')),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/saved-files'),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentFiles.isEmpty)
          FigmaCard(
            child: Text(
              'No recent materials yet. Start by uploading a file.',
              style: TextStyle(color: FigmaAppColors.subtext(context)),
            ),
          )
        else
          for (final file in _recentFiles) ...[
            _recentFileTile(file),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _recentFileTile(Map<String, dynamic> file) {
    final name = file['original_name'] as String? ?? 'Untitled file';
    final extension = (file['extension'] as String? ?? '').toUpperCase();
    final size = FileStorage.formatFileSize(file['size_bytes'] as int? ?? 0);
    final createdAt = _shortDate(file['created_at'] as String?);
    final kind = _friendlyKind(file);

    return FigmaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              color: FigmaAppColors.primary(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: FigmaAppColors.text(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$kind • $extension • $size • $createdAt',
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
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: FigmaAppColors.text(context),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  String _friendlyKind(Map<String, dynamic> file) {
    final metadata = _metadata(file);
    final mode = metadata['workspace_mode'] as String?;
    if (mode == 'direct') return 'Direct';
    final kind = file['kind'] as String? ?? '';
    if (kind.startsWith('output_')) return 'Output';
    return 'Material';
  }

  Map<String, dynamic> _metadata(Map<String, dynamic> file) {
    final raw = file['metadata_json'] as String?;
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  String _shortDate(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) return 'Recently';
    final now = DateTime.now();
    final diff = now.difference(parsed);
    if (diff.inHours < 1) return 'Just now';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}
