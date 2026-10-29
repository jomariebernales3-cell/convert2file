import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../services/file_download.dart';
import '../services/file_share_service.dart';
import '../services/file_storage.dart';
import '../widgets/figma_app_chrome.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _pageSize = 10;
  final _auth = AuthService();
  final _selectedFiles = <int>{};
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String _tab = 'Users';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        DatabaseHelper.instance.queryAllUsers(),
        DatabaseHelper.instance.queryAllFiles(),
        DatabaseHelper.instance.queryAllLogs(),
        DatabaseHelper.instance.queryAllBugReports(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = values[0];
        _files = values[1];
        _logs = values[2];
        _reports = values[3];
        _loading = false;
        _page = 0;
        _selectedFiles.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _message('Could not load admin data: $error', error: true);
      }
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? Colors.red : null, content: Text(text)),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        ) ??
        false;
  }

  List<Map<String, dynamic>> get _activeRows => switch (_tab) {
        'Users' => _users,
        'Files' => _files,
        'Logs' => _logs,
        _ => _reports,
      };

  List<Map<String, dynamic>> get _pageRows {
    final start = _page * _pageSize;
    if (start >= _activeRows.length) return const [];
    return _activeRows.skip(start).take(_pageSize).toList();
  }

  int get _pageCount => (_activeRows.length / _pageSize).ceil().clamp(1, 999999);

  String _userName(dynamic id) {
    final match = _users.where((user) => user['id'] == id).toList();
    if (match.isEmpty) return 'Unknown user';
    return match.first['name'] as String? ?? 'Unnamed user';
  }

  Future<void> _setUserStatus(Map<String, dynamic> user, String status) async {
    await DatabaseHelper.instance.updateUserStatus(user['id'] as int, status);
    await _load();
    _message('User marked $status.');
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (!await _confirm('Delete local user?', 'This removes the local profile for ${user['email']}. It does not delete the Supabase account.')) return;
    await DatabaseHelper.instance.deleteUser(user['id'] as int);
    await _load();
  }

  Future<void> _deleteFiles(Iterable<int> ids) async {
    final targetIds = ids.toList();
    if (targetIds.isEmpty) return;
    if (!await _confirm('Delete ${targetIds.length} file(s)?', 'The stored files and their local records will be permanently deleted.')) return;
    await FileStorage.deleteFiles(targetIds);
    await _load();
    _message('Deleted ${targetIds.length} file(s).');
  }

  Future<void> _deleteFilesByDate() async {
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
      helpText: 'Select start date',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
      helpText: 'Select end date',
    );
    if (end == null) return;
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    final ids = _files.where((file) {
      final created = DateTime.tryParse(file['created_at'] as String? ?? '');
      return created != null && !created.isBefore(start) && created.isBefore(endExclusive);
    }).map((file) => file['id'] as int);
    await _deleteFiles(ids);
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    final path = file['path'] as String? ?? '';
    if (!await File(path).exists()) {
      _message('The stored file cannot be found.', error: true);
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) _message(result.message, error: true);
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    try {
      final target = await FileDownload.copyToDownloadsFolder(file['path'] as String? ?? '');
      _message('Downloaded to $target');
    } catch (error) {
      _message('Download failed: $error', error: true);
    }
  }

  Future<void> _shareFile(Map<String, dynamic> file) async {
    try {
      await FileShareService.shareFileWithName(
        sourcePath: file['path'] as String? ?? '',
        fileName: file['original_name'] as String? ?? 'file',
      );
    } catch (error) {
      _message('Share failed: $error', error: true);
    }
  }

  Future<void> _setReportStatus(Map<String, dynamic> report, String status) async {
    await DatabaseHelper.instance.updateBugReportStatus(report['id'] as int, status);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isAdmin) {
      return FigmaAppShell(
        title: 'Admin Console',
        subtitle: 'Restricted area',
        selectedIndex: 4,
        showBack: true,
        child: const Center(child: Text('Administrator access is required.')),
      );
    }
    return FigmaAppShell(
      title: 'Admin Console',
      subtitle: 'Local users, files, activity, and reports',
      selectedIndex: 4,
      showBack: true,
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _summary(),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Users', icon: Icon(Icons.people_outline), label: Text('Users')),
                      ButtonSegment(value: 'Files', icon: Icon(Icons.folder_outlined), label: Text('Files')),
                      ButtonSegment(value: 'Logs', icon: Icon(Icons.receipt_long_outlined), label: Text('Logs')),
                      ButtonSegment(value: 'Reports', icon: Icon(Icons.bug_report_outlined), label: Text('Reports')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selected) => setState(() {
                      _tab = selected.first;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 'Files') _fileActions(),
                  if (_tab == 'Users') ..._pageRows.map(_userCard),
                  if (_tab == 'Files') ..._pageRows.map(_fileCard),
                  if (_tab == 'Logs') ..._pageRows.map(_logCard),
                  if (_tab == 'Reports') ..._pageRows.map(_reportCard),
                  if (_activeRows.isEmpty) const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('No records yet.')),
                  ),
                  _pagination(),
                ],
              ),
      ),
    );
  }

  Widget _summary() => Row(children: [
        _stat('Users', _users.length, Icons.people_outline),
        const SizedBox(width: 8),
        _stat('Files', _files.length, Icons.folder_outlined),
        const SizedBox(width: 8),
        _stat('Reports', _reports.length, Icons.bug_report_outlined),
      ]);

  Widget _stat(String label, int count, IconData icon) => Expanded(
        child: FigmaCard(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon, color: FigmaAppColors.primary(context), size: 20),
            const SizedBox(height: 6),
            Text('$count', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text(label, style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
          ]),
        ),
      );

  Widget _userCard(Map<String, dynamic> user) => FigmaCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(child: Text((user['name'] as String? ?? 'U').substring(0, 1).toUpperCase())),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user['name'] as String? ?? 'Unnamed user', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(user['email'] as String? ?? '', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
            const SizedBox(height: 4),
            Text('${user['role']} • ${user['status']} • ${_files.where((f) => f['user_id'] == user['id']).length} files', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
          ])),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteUser(user);
              } else {
                _setUserStatus(user, value);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'active', child: Text('Mark active')),
              PopupMenuItem(value: 'disabled', child: Text('Disable locally')),
              PopupMenuItem(value: 'delete', child: Text('Delete local profile')),
            ],
          ),
        ]),
      );

  Widget _fileActions() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_selectedFiles.isNotEmpty) FilledButton.icon(
          onPressed: () => _deleteFiles(_selectedFiles),
          icon: const Icon(Icons.delete_outline),
          label: Text('Delete selected (${_selectedFiles.length})'),
        ),
        OutlinedButton.icon(
          onPressed: _deleteFilesByDate,
          icon: const Icon(Icons.date_range_outlined),
          label: const Text('Delete files by date range'),
        ),
        OutlinedButton.icon(
          onPressed: _files.isEmpty ? null : () => _deleteFiles(_files.map((file) => file['id'] as int)),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete all files'),
        ),
        const SizedBox(height: 8),
      ]);

  Widget _fileCard(Map<String, dynamic> file) {
    final id = file['id'] as int;
    return FigmaCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
      child: Row(children: [
        Checkbox(value: _selectedFiles.contains(id), onChanged: (selected) => setState(() {
          selected == true ? _selectedFiles.add(id) : _selectedFiles.remove(id);
        })),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(file['original_name'] as String? ?? 'Untitled file', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${file['kind']} • ${_userName(file['user_id'])}', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
          Text(file['created_at'] as String? ?? '', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 11)),
        ])),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'open': _openFile(file);
              case 'download': _downloadFile(file);
              case 'share': _shareFile(file);
              case 'delete': _deleteFiles([id]);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'download', child: Text('Download')),
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
    );
  }

  Widget _logCard(Map<String, dynamic> log) => FigmaCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${log['level'] ?? 'info'} • ${log['event_type'] ?? 'event'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(log['message'] as String? ?? ''),
          const SizedBox(height: 4),
          Text('${_userName(log['user_id'])} • ${log['created_at'] ?? ''}', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
        ]),
      );

  Widget _reportCard(Map<String, dynamic> report) => FigmaCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('#${report['id']} ${report['subject'] ?? 'Untitled report'}', style: const TextStyle(fontWeight: FontWeight.w800))),
            PopupMenuButton<String>(
              onSelected: (status) => _setReportStatus(report, status),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('Mark new')),
                PopupMenuItem(value: 'reviewing', child: Text('Mark reviewing')),
                PopupMenuItem(value: 'resolved', child: Text('Mark resolved')),
              ],
            ),
          ]),
          Text(report['reporter_email'] as String? ?? '', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
          const SizedBox(height: 6),
          Text(report['message'] as String? ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text('${report['status'] ?? 'new'} • ${report['created_at'] ?? ''}', style: TextStyle(color: FigmaAppColors.subtext(context), fontSize: 12)),
        ]),
      );

  Widget _pagination() => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left)),
          Text('Page ${_page + 1} of $_pageCount'),
          IconButton(onPressed: _page >= _pageCount - 1 ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right)),
        ]),
      );
}
