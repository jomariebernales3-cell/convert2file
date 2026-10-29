import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:open_filex/open_filex.dart';
import '../core/database_helper.dart';
import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/file_storage.dart';
import '../services/auth_service.dart';
import '../widgets/figma_app_chrome.dart';

class HistoryScreen extends StatefulWidget {
  final bool savedFilesMode;

  const HistoryScreen({
    super.key,
    this.savedFilesMode = false,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _authService = AuthService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _studySets = [];
  bool _isLoading = true;
  String _filterKind = 'all';
  String _sortMode = 'newest';
  String _savedSection = 'materials';
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isMultiSelectMode = false;
  final Set<int> _selectedFileIds = <int>{};
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final files = _authService.isAdmin
          ? await DatabaseHelper.instance.queryAllFiles()
          : await DatabaseHelper.instance
              .queryFilesByUser(await _historyOwnerId());
      final studySets = await DatabaseHelper.instance
          .queryStudySetsByUser(await _historyOwnerId());
      setState(() {
        _files = files;
        _studySets = studySets;
        _isLoading = false;
        _currentPage = 0;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load files: $e');
    }
  }

  Future<void> _deleteFile(int fileId) async {
    try {
      await FileStorage.deleteFile(fileId);
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted')),
        );
      }
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  Future<void> _deleteStudySet(int studySetId) async {
    try {
      await DatabaseHelper.instance.deleteStudySet(studySetId);
      await _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Study quiz deleted')),
        );
      }
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFileIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected files?'),
        content: Text(
          'This will permanently delete ${_selectedFileIds.length} file(s).',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FileStorage.deleteFiles(_selectedFileIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted ${_selectedFileIds.length} file(s)',
            ),
          ),
        );
      }
      setState(() {
        _isMultiSelectMode = false;
        _selectedFileIds.clear();
      });
      _loadFiles();
    } catch (e) {
      _showError('Failed to delete selected files: $e');
    }
  }

  void _toggleSelection(int fileId) {
    setState(() {
      if (_selectedFileIds.contains(fileId)) {
        _selectedFileIds.remove(fileId);
      } else {
        _selectedFileIds.add(fileId);
      }
      if (_selectedFileIds.isEmpty) {
        _isMultiSelectMode = false;
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(message)),
    );
  }

  List<Map<String, dynamic>> get _filteredFiles {
    Iterable<Map<String, dynamic>> results = _files;

    if (widget.savedFilesMode && _savedSection == 'study') return const [];

    if (_filterKind == 'output') {
      results = results
          .where((f) => (f['kind'] as String? ?? '').startsWith('output_'))
          .toList();
    } else if (_filterKind != 'all') {
      results = results.where((f) => f['kind'] == _filterKind);
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((file) {
        final searchable = [
          file['original_name'],
          file['stored_name'],
          file['kind'],
          file['extension'],
          file['mime_type'],
          file['created_at'],
        ].whereType<Object>().join(' ').toLowerCase();
        return searchable.contains(query);
      });
    }

    final start = _startDate;
    final end = _endDate;
    if (start != null || end != null) {
      final startDate =
          start == null ? null : DateTime(start.year, start.month, start.day);
      final endDate = end == null
          ? null
          : DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

      results = results.where((file) {
        final created = DateTime.tryParse(file['created_at'] as String? ?? '');
        if (created == null) return false;
        if (startDate != null && created.isBefore(startDate)) return false;
        if (endDate != null && created.isAfter(endDate)) return false;
        return true;
      });
    }

    final sorted = results.toList();
    sorted.sort(_compareFiles);
    return sorted;
  }

  int _compareFiles(Map<String, dynamic> a, Map<String, dynamic> b) {
    final nameA = (a['original_name'] as String? ?? '').toLowerCase();
    final nameB = (b['original_name'] as String? ?? '').toLowerCase();
    final dateA = DateTime.tryParse(a['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final dateB = DateTime.tryParse(b['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final sizeA = a['size_bytes'] as int? ?? 0;
    final sizeB = b['size_bytes'] as int? ?? 0;

    return switch (_sortMode) {
      'oldest' => dateA.compareTo(dateB),
      'az' => nameA.compareTo(nameB),
      'za' => nameB.compareTo(nameA),
      'size_asc' => sizeA.compareTo(sizeB),
      'size_desc' => sizeB.compareTo(sizeA),
      _ => dateB.compareTo(dateA),
    };
  }

  Future<int> _historyOwnerId() async {
    final currentUserId = _authService.currentUser?.id;
    if (currentUserId != null) return currentUserId;
    return DatabaseHelper.instance.getOrCreateGuestUserId();
  }

  List<Map<String, dynamic>> get _pagedFiles {
    final filtered = _filteredFiles;
    final start = _currentPage * _pageSize;
    if (start >= filtered.length) return const [];
    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  int get _pageCount {
    final count = _filteredFiles.length;
    if (count == 0) return 1;
    return ((count - 1) ~/ _pageSize) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: widget.savedFilesMode ? 'Materials' : 'History',
      subtitle: 'Your local files, outputs, and study materials',
      selectedIndex: -1,
      showBack: true,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: FigmaAppColors.bg(context),
                  elevation: 3,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  child: Column(
                    children: [
                      if (_isMultiSelectMode) _buildListToolbar(),
                      _buildSearchAndFilters(),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadFiles,
                    child: _buildScrollableResults(),
                  ),
                ),
                if (!(widget.savedFilesMode && _savedSection == 'study'))
                  _buildPaginationControls(),
              ],
            ),
    );
  }

  /// The controls above and page footer below remain fixed; this is the only
  /// section that scrolls.
  Widget _buildScrollableResults() {
    if (widget.savedFilesMode && _savedSection == 'study') {
      return _buildStudySetHistory();
    }
    if (_filteredFiles.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(
            height: 280,
            child: _buildEmptyState(
              message: _files.isEmpty ? 'No files yet' : 'No matching files',
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: _pagedFiles.length,
      itemBuilder: (context, index) => _buildFileCard(_pagedFiles[index]),
    );
  }

  Widget _buildListToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: Row(
        children: [
          if (_isMultiSelectMode) ...[
            FigmaIconButton(
              icon: Icons.close,
              onPressed: () {
                setState(() {
                  _isMultiSelectMode = false;
                  _selectedFileIds.clear();
                });
              },
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              _isMultiSelectMode
                  ? '${_selectedFileIds.length} selected'
                  : 'Local file library',
              style: TextStyle(
                color: FigmaAppColors.subtext(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!_isMultiSelectMode)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              onSelected: (value) => setState(() {
                _filterKind = value;
                _currentPage = 0;
              }),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'all', child: Text('All Files')),
                PopupMenuItem(
                    value: 'template_upload',
                    child: Text('Uploaded Materials')),
                PopupMenuItem(
                    value: 'data_upload', child: Text('Data Sources')),
                PopupMenuItem(value: 'output', child: Text('Outputs')),
              ],
            ),
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedFileIds.isEmpty ? null : _deleteSelectedFiles,
              tooltip: 'Delete selected (${_selectedFileIds.length})',
            ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: FigmaAppColors.bg(context),
      child: Column(
        children: [
          if (widget.savedFilesMode) ...[
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'materials',
                  icon: Icon(Icons.auto_awesome),
                  label: Text('Materials'),
                ),
                ButtonSegment(
                  value: 'study',
                  icon: Icon(Icons.school),
                  label: Text('Study'),
                ),
              ],
              selected: {_savedSection},
              onSelectionChanged: (selection) {
                setState(() {
                  _savedSection = selection.first;
                  _currentPage = 0;
                });
              },
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: 46,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search saved files',
                prefixIcon: const Icon(Icons.search),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'File type',
                      icon: const Icon(Icons.filter_list),
                      onSelected: (value) => setState(() {
                        _filterKind = value;
                        _currentPage = 0;
                      }),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'all', child: Text('All Files')),
                        PopupMenuItem(
                            value: 'template_upload',
                            child: Text('Uploaded Materials')),
                        PopupMenuItem(
                            value: 'data_upload', child: Text('Data Sources')),
                        PopupMenuItem(value: 'output', child: Text('Outputs')),
                      ],
                    ),
                    if (_hasActiveSearchFilters)
                      IconButton(
                        tooltip: 'Clear filters',
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearchFilters,
                      ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() => _currentPage = 0),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.date_range),
                  label: Text(_dateLabel(_startDate, 'Start')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event),
                  label: Text(_dateLabel(_endDate, 'End')),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Sort files',
                icon: const Icon(Icons.sort),
                initialValue: _sortMode,
                onSelected: (value) => setState(() {
                  _sortMode = value;
                  _currentPage = 0;
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'newest', child: Text('Newest first')),
                  PopupMenuItem(value: 'oldest', child: Text('Oldest first')),
                  PopupMenuItem(value: 'az', child: Text('A-Z')),
                  PopupMenuItem(value: 'za', child: Text('Z-A')),
                  PopupMenuItem(
                      value: 'size_desc', child: Text('Largest first')),
                  PopupMenuItem(
                      value: 'size_asc', child: Text('Smallest first')),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                widget.savedFilesMode && _savedSection == 'study'
                    ? '${_filteredStudySets.length} study quiz(zes) found'
                    : '${_filteredFiles.length} file(s) found',
                style: TextStyle(
                  color: FigmaAppColors.subtext(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveSearchFilters =>
      _searchController.text.trim().isNotEmpty ||
      _startDate != null ||
      _endDate != null ||
      _sortMode != 'newest' ||
      _filterKind != 'all';

  void _clearSearchFilters() {
    setState(() {
      _searchController.clear();
      _startDate = null;
      _endDate = null;
      _sortMode = 'newest';
      _filterKind = 'all';
      _currentPage = 0;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
      _currentPage = 0;
    });
  }

  String _dateLabel(DateTime? date, String fallback) {
    if (date == null) return fallback;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildPaginationControls() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 3, 20, 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 38,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _currentPage == 0
                    ? null
                    : () => setState(() => _currentPage--),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous page',
              ),
            ),
            Expanded(
              child: Text(
                'Page ${_currentPage + 1} of $_pageCount',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 42,
              height: 38,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _currentPage >= _pageCount - 1
                    ? null
                    : () => setState(() => _currentPage++),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next page',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({String message = 'No files yet'}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Generated documents will appear here',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredStudySets {
    Iterable<Map<String, dynamic>> results = _studySets;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((set) {
        final searchable = [
          set['title'],
          set['description'],
          set['created_at'],
          set['updated_at'],
        ].whereType<Object>().join(' ').toLowerCase();
        return searchable.contains(query);
      });
    }

    final sorted = results.toList();
    sorted.sort((a, b) {
      final titleA = (a['title'] as String? ?? '').toLowerCase();
      final titleB = (b['title'] as String? ?? '').toLowerCase();
      final dateA = DateTime.tryParse(a['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = DateTime.tryParse(b['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return switch (_sortMode) {
        'oldest' => dateA.compareTo(dateB),
        'az' => titleA.compareTo(titleB),
        'za' => titleB.compareTo(titleA),
        _ => dateB.compareTo(dateA),
      };
    });
    return sorted;
  }

  Widget _buildStudySetHistory() {
    final sets = _filteredStudySets;
    if (sets.isEmpty) {
      return _buildEmptyState(message: 'No saved study quizzes');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: sets.length,
      itemBuilder: (context, index) => _buildStudySetCard(sets[index]),
    );
  }

  Widget _buildStudySetCard(Map<String, dynamic> set) {
    final questions = jsonDecode(set['questions_json'] as String? ?? '[]');
    final count = questions is List ? questions.length : 0;
    final lastScore = set['last_score'];
    final lastTotal = set['last_total'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FigmaCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            child: const Icon(Icons.school),
          ),
          title: Text(
            set['title'] as String? ?? 'Untitled study quiz',
            style: const TextStyle(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              '$count question(s)',
              if (lastScore != null && lastTotal != null)
                'Last score: $lastScore/$lastTotal',
              set['updated_at'] as String? ?? '',
            ].where((item) => item.isNotEmpty).join(' • '),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                Navigator.of(context).pushNamed(
                  '/study-builder',
                  arguments: set,
                );
              } else if (value == 'delete') {
                _deleteStudySet(set['id'] as int);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () => Navigator.of(context).pushNamed(
            '/study-builder',
            arguments: set,
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final kind = file['kind'] as String? ?? 'unknown';
    final ext = file['extension'] as String? ?? '';
    final originalName = file['original_name'] as String? ?? 'Unknown';
    final size = file['size_bytes'] as int? ?? 0;
    final createdAt = file['created_at'] as String? ?? '';
    final fileId = file['id'] as int? ?? 0;

    IconData iconData;
    Color iconColor;

    switch (kind) {
      case 'template_upload':
        iconData = Icons.description_outlined;
        iconColor = Colors.blue;
        break;
      case 'data_upload':
        iconData = Icons.upload_file;
        iconColor = Colors.green;
        break;
      case 'output_docx':
      case 'output_pdf':
      case 'output_html':
      case 'output_txt':
        iconData = Icons.description;
        iconColor = Theme.of(context).colorScheme.primary;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey;
    }

    Widget card = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FigmaCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: _isMultiSelectMode
              ? Checkbox(
                  value: _selectedFileIds.contains(fileId),
                  onChanged: (_) {
                    _toggleSelection(fileId);
                  },
                )
              : CircleAvatar(
                  backgroundColor: iconColor.withValues(alpha: 0.2),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
          title: Text(
            originalName,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$ext • ${FileStorage.formatFileSize(size)}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              Text(
                createdAt,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
          trailing: _isMultiSelectMode
              ? null
              : IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showFileOptions(file),
                ),
          onTap: _isMultiSelectMode
              ? () {
                  if (!_selectedFileIds.contains(fileId)) {
                    setState(() {
                      _isMultiSelectMode = true;
                    });
                  }
                  _toggleSelection(fileId);
                }
              : null,
        ),
      ),
    );

    if (_isMultiSelectMode) return card;

    return Dismissible(
      key: Key('file_$fileId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteFile(fileId),
      child: card,
    );
  }

  void _showFileOptions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file['original_name'] as String? ?? 'File',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Open'),
                  onTap: () {
                    Navigator.pop(context);
                    _openFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download'),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share'),
                  onTap: () {
                    Navigator.pop(context);
                    _shareFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteFile(file['id'] as int);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Details'),
                  onTap: () {
                    Navigator.pop(context);
                    _showFileDetails(file);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    if (!await File(path).exists()) {
      _showError('File not found');
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _showError(result.message);
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    try {
      final destPath = await FileDownload.copyToDownloadsFolder(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to: $destPath')),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    }
  }

  Future<void> _shareFile(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    if (!await File(path).exists()) {
      _showError('File not found');
      return;
    }
    await FileShareService.shareFileWithName(
      sourcePath: path,
      fileName: file['original_name'] as String? ?? 'converted-file',
      subject: file['original_name'] as String?,
    );
  }

  void _showFileDetails(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Name', file['original_name'] as String? ?? ''),
            _detailRow('Type', file['kind'] as String? ?? ''),
            _detailRow('Extension', file['extension'] as String? ?? ''),
            _detailRow('Size',
                FileStorage.formatFileSize(file['size_bytes'] as int? ?? 0)),
            _detailRow('MIME Type', file['mime_type'] as String? ?? ''),
            _detailRow('Created', file['created_at'] as String? ?? ''),
            _detailRow('Path', file['path'] as String? ?? '', isPath: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: isPath ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: isPath ? 3 : 1,
            ),
          ),
        ],
      ),
    );
  }
}
