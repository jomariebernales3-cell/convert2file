import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:open_filex/open_filex.dart';
import '../core/database_helper.dart';
import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/file_storage.dart';
import '../services/auth_service.dart';
import 'output_image_screen.dart';
import '../widgets/figma_app_chrome.dart';
import '../widgets/report_problem_entry.dart';

class HistoryScreen extends StatefulWidget {
  final bool savedFilesMode;
  final String initialSection;

  const HistoryScreen({
    super.key,
    this.savedFilesMode = false,
    this.initialSection = 'files',
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _authService = AuthService();
  final _searchController = TextEditingController();
  final _materialsScrollController = ScrollController();
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _studySets = [];
  bool _isLoading = true;
  String _filterKind = 'all';
  String _sortMode = 'newest';
  String _savedSection = 'files';
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isMultiSelectMode = false;
  final Set<int> _selectedFileIds = <int>{};
  int _currentPage = 0;
  static const int _pageSize = 10;
  static const int _materialsPageSize = 10;
  final Map<String, int> _materialsPages = {
    'files': 0,
    'sets': 0,
    'outputs': 0,
  };
  final Map<String, String> _materialsSortModes = {
    'files': 'newest',
    'sets': 'newest',
    'outputs': 'newest',
  };
  final Map<String, String> _materialsTypeFilters = {
    'files': 'all',
    'sets': 'all',
    'outputs': 'all',
  };
  int _materialsTotalCount = 0;
  int _loadGeneration = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _savedSection = widget.initialSection;
    _materialsScrollController.addListener(_hideKeyboardWhileScrolling);
    _loadFiles();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _materialsScrollController
      ..removeListener(_hideKeyboardWhileScrolling)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() => _isLoading = true);
    try {
      final ownerId = await _historyOwnerId();
      if (widget.savedFilesMode) {
        var page = _materialsPages[_savedSection] ?? 0;
        var result = await DatabaseHelper.instance.fetchMaterials(
          kind: _savedSection,
          query: _searchController.text,
          userId: ownerId,
          page: page,
          pageSize: _materialsPageSize,
          sort: _materialsSortModes[_savedSection] ?? 'newest',
          typeFilter: _materialsTypeFilters[_savedSection] ?? 'all',
        );
        var totalCount = result['totalCount'] as int? ?? 0;
        final lastPage = totalCount == 0
            ? 0
            : (totalCount - 1) ~/ _materialsPageSize;
        if (page > lastPage) {
          page = lastPage;
          _materialsPages[_savedSection] = page;
          result = await DatabaseHelper.instance.fetchMaterials(
            kind: _savedSection,
            query: _searchController.text,
            userId: ownerId,
            page: page,
            pageSize: _materialsPageSize,
            sort: _materialsSortModes[_savedSection] ?? 'newest',
            typeFilter: _materialsTypeFilters[_savedSection] ?? 'all',
          );
          totalCount = result['totalCount'] as int? ?? 0;
        }
        if (!mounted || generation != _loadGeneration) return;
        final items = (result['items'] as List<Map<String, dynamic>>?) ?? [];
        setState(() {
          _files = _savedSection == 'sets' ? [] : items;
          _studySets = _savedSection == 'sets' ? items : [];
          _materialsTotalCount = totalCount;
          _isLoading = false;
        });
        return;
      }

      final files = await DatabaseHelper.instance.queryFilesByUser(ownerId);
      final studySets =
          await DatabaseHelper.instance.queryStudySetsByUser(ownerId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _files = files;
        _studySets = studySets;
        _isLoading = false;
        _currentPage = 0;
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
      _showError('Failed to load files: $e');
    }
  }

  void _handleSearchChanged(String _) {
    if (!widget.savedFilesMode) {
      setState(() => _currentPage = 0);
      return;
    }
    _searchDebounce?.cancel();
    setState(() {
      _materialsPages[_savedSection] = 0;
      _materialsTotalCount = 0;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 300), _loadFiles);
  }

  void _hideKeyboardWhileScrolling() {
    if (_materialsScrollController.hasClients &&
        _materialsScrollController.position.isScrollingNotifier.value &&
        FocusManager.instance.primaryFocus?.hasFocus == true) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _changeSavedSection(String section) {
    if (section == _savedSection) return;
    _searchDebounce?.cancel();
    setState(() {
      _savedSection = section;
      _materialsTotalCount = 0;
      _filterKind = 'all';
    });
    _loadFiles();
  }

  Future<void> _goToMaterialsPage(int page) async {
    final pageCount = (_materialsTotalCount / _materialsPageSize).ceil();
    if (page < 0 || page >= pageCount || page == (_materialsPages[_savedSection] ?? 0)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (_materialsScrollController.hasClients) {
      _materialsScrollController.jumpTo(0);
    }
    setState(() => _materialsPages[_savedSection] = page);
    await _loadFiles();
  }

  void _changeMaterialsSort(String sort) {
    if ((_materialsSortModes[_savedSection] ?? 'newest') == sort) return;
    setState(() {
      _materialsSortModes[_savedSection] = sort;
      _materialsPages[_savedSection] = 0;
      _materialsTotalCount = 0;
    });
    if (_materialsScrollController.hasClients) {
      _materialsScrollController.jumpTo(0);
    }
    _loadFiles();
  }

  void _changeMaterialsTypeFilter(String filter) {
    if ((_materialsTypeFilters[_savedSection] ?? 'all') == filter) return;
    setState(() {
      _materialsTypeFilters[_savedSection] = filter;
      _materialsPages[_savedSection] = 0;
      _materialsTotalCount = 0;
    });
    if (_materialsScrollController.hasClients) {
      _materialsScrollController.jumpTo(0);
    }
    _loadFiles();
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
            child: Text('DELETE', style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        content: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredFiles {
    if (widget.savedFilesMode) return _files;
    Iterable<Map<String, dynamic>> results = _files;

    if (widget.savedFilesMode) {
      if (_savedSection == 'sets') return const [];
      if (_savedSection == 'outputs') {
        results = results
            .where((f) => (f['kind'] as String? ?? '').startsWith('output_'))
            .toList();
      } else {
        results = results
            .where((f) => !(f['kind'] as String? ?? '').startsWith('output_'))
            .toList();
      }
    }

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
    if (widget.savedFilesMode) return filtered;
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
      title: widget.savedFilesMode ? 'My materials' : 'History',
      subtitle: widget.savedFilesMode
          ? ''
          : 'Your local files, outputs, and study materials',
      selectedIndex: -1,
      showBack: true,
      referenceHeader: widget.savedFilesMode,
      showProfile: !widget.savedFilesMode,
      child: _isLoading && !widget.savedFilesMode
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: FigmaAppColors.bg(context),
                  elevation: widget.savedFilesMode ? 0 : 3,
                  shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.12),
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
                if (!widget.savedFilesMode) _buildPaginationControls(),
              ],
            ),
    );
  }

  /// The controls above and page footer below remain fixed; this is the only
  /// section that scrolls.
  Widget _buildScrollableResults() {
    if (widget.savedFilesMode && _isLoading) {
      return ListView(
        controller: _materialsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (widget.savedFilesMode && _savedSection == 'sets') {
      return _buildStudySetHistory();
    }
    if (_filteredFiles.isEmpty) {
      final query = _searchController.text.trim();
      if (widget.savedFilesMode && query.isNotEmpty) {
        return _buildNoSearchResults(query);
      }
      return ListView(
        controller: widget.savedFilesMode ? _materialsScrollController : null,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(
            height: 280,
            child: _buildEmptyState(
              message: widget.savedFilesMode && _savedSection == 'outputs'
                  ? 'No outputs yet'
                  : (_files.isEmpty ? 'No files yet' : 'No matching files'),
            ),
          ),
        ],
      );
    }
    if (widget.savedFilesMode) {
      return ListView.builder(
        controller: _materialsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        itemCount: _files.length + (_shouldShowMaterialsPager ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _files.length) return _buildMaterialsPager();
          return _buildFileCard(_files[index]);
        },
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: _pagedFiles.length,
      itemBuilder: (context, index) => _buildFileCard(_pagedFiles[index]),
    );
  }

  Widget _buildNoSearchResults(String query) {
    return ListView(
      controller: _materialsScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        SizedBox(
          height: 240,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No results for “$query”',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FigmaAppColors.subtext(context)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _searchController.clear(),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Clear search'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool get _shouldShowMaterialsPager =>
      _materialsTotalCount > _materialsPageSize;

  Widget _buildMaterialsPager() {
    final page = _materialsPages[_savedSection] ?? 0;
    final pageCount = (_materialsTotalCount / _materialsPageSize).ceil();
    final firstItem = page * _materialsPageSize + 1;
    final lastItem = (firstItem + _files.length + _studySets.length - 1)
        .clamp(firstItem, _materialsTotalCount);
    final lineColor = FigmaAppColors.border(context);
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      side: BorderSide(color: lineColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: buttonStyle,
                  onPressed: page == 0 ? null : () => _goToMaterialsPage(page - 1),
                  child: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Page ${page + 1} of $pageCount',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    color: FigmaAppColors.text(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: buttonStyle,
                  onPressed: page >= pageCount - 1
                      ? null
                      : () => _goToMaterialsPage(page + 1),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Showing $firstItem-$lastItem of $_materialsTotalCount',
            style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12),
          ),
        ],
      ),
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
    if (widget.savedFilesMode) {
      final hint = switch (_savedSection) {
        'sets' => 'Search study sets',
        'outputs' => 'Search outputs',
        _ => 'Search files',
      };
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          children: [
            FigmaSegmentControl<String>(
              options: const [
                FigmaSegmentOption(value: 'files', label: 'Files'),
                FigmaSegmentOption(value: 'sets', label: 'Study sets'),
                FigmaSegmentOption(value: 'outputs', label: 'Outputs'),
              ],
              selected: _savedSection,
              onChanged: _changeSavedSection,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: FigmaAppColors.fill(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: FigmaAppColors.border(context)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _handleSearchChanged,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: FigmaAppColors.text(context)),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hint,
                        hintStyle: TextStyle(color: FigmaAppColors.subtext(context)),
                        prefixIcon: Icon(
                          Icons.search,
                          color: FigmaAppColors.subtext(context),
                        ),
                        suffixIconConstraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                                onPressed: () => _searchController.clear(),
                                icon: const Icon(Icons.close),
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_savedSection != 'sets') ...[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: FigmaAppColors.fill(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: FigmaAppColors.border(context)),
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'Filter by file type',
                      initialValue: _materialsTypeFilters[_savedSection] ?? 'all',
                      onSelected: _changeMaterialsTypeFilter,
                      icon: Icon(Icons.filter_list, color: FigmaAppColors.subtext(context)),
                      itemBuilder: (context) => [
                        _typeFilterItem('all', 'All types'),
                        _typeFilterItem('qr', 'QR code'),
                        _typeFilterItem('pdf', 'PDF'),
                        _typeFilterItem('docx', 'DOCX'),
                        _typeFilterItem('pptx', 'PPTX'),
                        _typeFilterItem('txt', 'TXT'),
                        _typeFilterItem('html', 'HTML'),
                        _typeFilterItem('image', 'Images'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: FigmaAppColors.fill(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: FigmaAppColors.border(context)),
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'Sort materials',
                    initialValue: _materialsSortModes[_savedSection] ?? 'newest',
                    onSelected: _changeMaterialsSort,
                    icon: Icon(Icons.sort, color: FigmaAppColors.subtext(context)),
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(
                        value: 'newest',
                        checked: (_materialsSortModes[_savedSection] ?? 'newest') == 'newest',
                        child: const Text('Date added: newest first'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'oldest',
                        checked: _materialsSortModes[_savedSection] == 'oldest',
                        child: const Text('Date added: oldest first'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'az',
                        checked: _materialsSortModes[_savedSection] == 'az',
                        child: const Text('Name: A to Z'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'za',
                        checked: _materialsSortModes[_savedSection] == 'za',
                        child: const Text('Name: Z to A'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      color: FigmaAppColors.bg(context),
      child: Column(
        children: [
          if (widget.savedFilesMode) ...[
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'files',
                  icon: Icon(Icons.description_outlined),
                  label: Text('Files'),
                ),
                ButtonSegment(
                  value: 'sets',
                  icon: Icon(Icons.school_outlined),
                  label: Text('Study sets'),
                ),
                ButtonSegment(
                  value: 'outputs',
                  icon: Icon(Icons.task_alt_outlined),
                  label: Text('Outputs'),
                ),
              ],
              selected: {_savedSection},
              onSelectionChanged: (selection) {
                setState(() {
                  _savedSection = selection.first;
                  _currentPage = 0;
                  _filterKind = 'all';
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
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'all', child: Text('All Files')),
                        const PopupMenuItem(
                            value: 'template_upload',
                            child: Text('Uploaded Materials')),
                        const PopupMenuItem(
                            value: 'data_upload', child: Text('Data Sources')),
                        if (!widget.savedFilesMode)
                          const PopupMenuItem(
                              value: 'output', child: Text('Outputs')),
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
              onChanged: _handleSearchChanged,
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
                widget.savedFilesMode && _savedSection == 'sets'
                    ? '${widget.savedFilesMode ? _materialsTotalCount : _filteredStudySets.length} study quiz(zes) found'
                    : '${widget.savedFilesMode ? _materialsTotalCount : _filteredFiles.length} file(s) found',
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

  CheckedPopupMenuItem<String> _typeFilterItem(String value, String label) =>
      CheckedPopupMenuItem<String>(
        value: value,
        checked: (_materialsTypeFilters[_savedSection] ?? 'all') == value,
        child: Text(label),
      );

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
              color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
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
          Icon(Icons.folder_open, size: 64, color: FigmaAppColors.subtext(context)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Generated documents will appear here',
            style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredStudySets {
    if (widget.savedFilesMode) return _studySets;
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
      final query = _searchController.text.trim();
      if (query.isNotEmpty) return _buildNoSearchResults(query);
      return ListView(
        controller: _materialsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          FigmaCard(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('No study sets yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Create a study guide or quiz from one of your files.', textAlign: TextAlign.center, style: TextStyle(color: FigmaAppColors.subtext(context), height: 1.5)),
                const SizedBox(height: 16),
                SizedBox(height: 52, child: ElevatedButton(onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false), child: const Text('Back to actions'))),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _materialsScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      itemCount: sets.length + (_shouldShowMaterialsPager ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == sets.length) return _buildMaterialsPager();
        return _buildStudySetCard(sets[index]);
      },
    );
  }

  Widget _buildStudySetCard(Map<String, dynamic> set) {
    final questions = jsonDecode(set['questions_json'] as String? ?? '[]');
    final count = questions is List ? questions.length : 0;
    final lastScore = set['last_score'];
    final lastTotal = set['last_total'];
    final updatedAt = set['updated_at'] as String? ?? '';
    final details = [
      '$count questions',
      if (lastScore != null && lastTotal != null)
        'Last score: $lastScore/$lastTotal',
      if (updatedAt.isNotEmpty) _libraryDateLabel(updatedAt),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pushNamed(
            '/study-builder',
            arguments: set,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: FigmaAppColors.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FigmaAppColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.school_outlined,
                    color: Theme.of(context).colorScheme.primary, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        set['title'] as String? ?? 'Untitled study quiz',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: FigmaAppColors.subtext(context),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
  String _libraryFileMetadata(String kind, String extension, int size, String createdAt) {
    final ext = extension.replaceFirst('.', '').toUpperCase();
    final date = _libraryDateLabel(createdAt);
    if (kind == 'qr') return 'QR · PNG · ${FileStorage.formatFileSize(size)} · ${_libraryDateTimeLabel(createdAt)}';
    final type = kind.startsWith('output_') ? 'Converted · $ext' : ext;
    return '$type · ${FileStorage.formatFileSize(size)} · $date';
  }

  Future<void> _openSavedOutput(Map<String, dynamic> file) async {
    final filePath = file['path'] as String? ?? '';
    if (!await File(filePath).exists()) {
      await _showMissingOutput(file);
      return;
    }
    final extension = (file['extension'] as String? ?? '')
        .toLowerCase()
        .replaceFirst('.', '');
    if (const {'png', 'jpg', 'jpeg'}.contains(extension)) {
      final deleted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OutputImageScreen(file: file),
        ),
      );
      if (deleted == true) await _loadFiles();
      return;
    }
    await _openFile(file);
  }

  Future<void> _showMissingOutput(Map<String, dynamic> file) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('This file was moved or deleted'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove entry')),
        ],
      ),
    );
    if (remove == true && mounted) await _deleteFile(file['id'] as int);
  }
  Future<void> _openQrOutput(Map<String, dynamic> file) async {
    final deleted = await Navigator.of(context).pushNamed<bool>(
      '/qr-output',
      arguments: file,
    );
    if (deleted == true) _loadFiles();
  }

  String _libraryDateTimeLabel(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    final dateLabel = _libraryDateLabel(raw);
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '$dateLabel · $hour:$minute $period';
  }
  String _libraryDateLabel(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final shortDate = '${months[date.month - 1]} ${date.day}';
    return date.year == DateTime.now().year
        ? shortDate
        : '$shortDate, ${date.year}';
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
        iconColor = Theme.of(context).colorScheme.secondary;
        break;
      case 'data_upload':
        iconData = Icons.upload_file;
        iconColor = Theme.of(context).colorScheme.primary;
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
        iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    Widget historyCard = Padding(
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
                style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12),
              ),
              Text(
                createdAt,
                style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 11),
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


    if (widget.savedFilesMode) iconColor = Theme.of(context).colorScheme.primary;

    Widget card = widget.savedFilesMode
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isMultiSelectMode
                    ? () => _toggleSelection(fileId)
                    : _savedSection == 'outputs'
                        ? kind == 'qr'
                            ? () => _openQrOutput(file)
                            : () => _openSavedOutput(file)
                        : () => _showFileOptions(file),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: FigmaAppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FigmaAppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      if (_isMultiSelectMode)
                        Checkbox(value: _selectedFileIds.contains(fileId), onChanged: (_) => _toggleSelection(fileId))
                      else if (kind == 'qr')
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 44,
                            height: 44,
                            color: Theme.of(context).colorScheme.surface,
                            child: Image.file(
                              File(file['path'] as String? ?? ''),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.qr_code_2,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else if (_savedSection == 'outputs' && const {'png', 'jpg', 'jpeg'}.contains(ext.toLowerCase()))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(file['path'] as String? ?? ''),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      else
                        Icon(iconData, color: Theme.of(context).colorScheme.primary, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(originalName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(_libraryFileMetadata(kind, ext, size, createdAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : historyCard;
    if (_isMultiSelectMode) return card;

    return Dismissible(
      key: Key('file_$fileId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
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
                  leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                  title:
                      Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report a problem with this file'),
                  onTap: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) openReportProblem(this.context, area: 'my_materials', sourceFilePath: file['path'] as String?);
                    });
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
      await _showMissingOutput(file);
      return;
    }
    try {
      final result = await OpenFilex.open(path);
      if (result.type == ResultType.noAppToOpen) {
        await _shareOutputFallback(file);
      } else if (result.type == ResultType.fileNotFound) {
        await _showMissingOutput(file);
      } else if (result.type != ResultType.done) {
        _showError(result.message);
      }
    } catch (error) {
      debugPrint('[QR] Open output failed: $error');
      try {
        await _shareFile(file);
      } catch (shareError) {
        debugPrint('[QR] Share fallback failed: $shareError');
        _showError('Could not open or share this file.');
      }
    }
  }
  Future<void> _shareOutputFallback(Map<String, dynamic> file) async {
    try {
      await _shareFile(file);
    } catch (error) {
      debugPrint('[Output] Share fallback failed: $error');
      _showError('Could not open or share this file.');
    }
  }
  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    try {
      final destPath = await FileDownload.copyToDownloadsFolder(path);
      if (destPath.isEmpty) return;
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
              style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 13),
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
