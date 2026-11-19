import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/file_storage.dart';
import '../widgets/figma_app_chrome.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  List<int> _activityCounts = List.filled(7, 0);
  List<Map<String, dynamic>> _recentLogs = [];
  int _materialCount = 0;
  int _outputCount = 0;
  int _studySetCount = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final user = await _auth.requireLocalUser();
    final files = await DatabaseHelper.instance.queryFilesByUser(user.id!);
    final sets = await DatabaseHelper.instance.queryStudySetsByUser(user.id!);
    final logs = await DatabaseHelper.instance.queryLogsByUser(user.id!);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final counts = List.filled(7, 0);
    for (final log in logs) {
      final created = DateTime.tryParse(log['created_at'] as String? ?? '');
      if (created == null) continue;
      final day = DateTime(created.year, created.month, created.day);
      final offset = day.difference(start).inDays;
      if (offset >= 0 && offset < counts.length) counts[offset]++;
    }
    final materials = files.where((file) {
      final kind = file['kind'] as String? ?? '';
      return !kind.startsWith('output_') && kind != 'qr';
    }).length;
    final outputs = files.length - materials;
    if (!mounted) return;
    setState(() {
      _materialCount = materials;
      _outputCount = outputs;
      _studySetCount = sets.length;
      _activityCounts = counts;
      _recentLogs = logs.take(5).toList();
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear saved outputs?'),
        content: const Text(
            'This deletes converted outputs and QR records saved on this device. Your source files and study sets stay in place.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear outputs')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final user = await _auth.requireLocalUser();
      final files = await DatabaseHelper.instance.queryFilesByUser(user.id!);
      final outputIds = files
          .where((file) {
            final kind = file['kind'] as String? ?? '';
            return kind.startsWith('output_') || kind == 'qr';
          })
          .map((file) => file['id'] as int)
          .toList();
      await FileStorage.deleteFiles(outputIds);
      await _loadProfileData();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved outputs cleared.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not clear outputs: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetGuestProfile() async {
    final user = _auth.currentUser;
    if (user == null ||
        user.supabaseUserId != null ||
        user.email != 'guest@convert2file.local') return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset guest profile?'),
        content: const Text(
            'This resets the guest name, bio, contact details, and profile photo on this device. Saved files remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset profile')),
        ],
      ),
    );
    if (confirm != true) return;
    await _auth.resetGuestProfile();
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted)
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const FigmaAppShell(
          title: 'Profile',
          subtitle: 'Your account and study activity',
          selectedIndex: 2,
          child: Center(child: CircularProgressIndicator()));
    }
    return FigmaAppShell(
      title: 'Profile',
      subtitle: 'Your account and study activity',
      selectedIndex: 2,
      showBack: true,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadProfileData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _profileHero(user),
                const SizedBox(height: 16),
                _securityCard(user),
                const SizedBox(height: 16),
                _activityCard(),
                const SizedBox(height: 16),
                _recentActivityCard(),
                const SizedBox(height: 16),
                _dataActionsCard(user),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out')),
              ],
            ),
          ),
          if (_busy)
            const Positioned.fill(
                child: ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator()))),
        ],
      ),
    );
  }

  Widget _profileHero(UserModel user) {
    final imagePath = user.profileImagePath;
    final hasImage = imagePath != null && File(imagePath).existsSync();
    return FigmaCard(
      child: Column(
        children: [
          CircleAvatar(
              radius: 42,
              backgroundImage: hasImage ? FileImage(File(imagePath)) : null,
              child: hasImage
                  ? null
                  : Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 28))),
          const SizedBox(height: 12),
          Text(user.name,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(user.email,
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 8),
          Chip(
              visualDensity: VisualDensity.compact,
              label: Text(user.role.toUpperCase())),
          if ((user.bio ?? '').isNotEmpty)
            Text(user.bio!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () async {
                final changed =
                    await Navigator.of(context).pushNamed('/edit-profile');
                if (changed == true && mounted) setState(() {});
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile')),
          const SizedBox(height: 8),
          Row(
            children: [
              _countTile('Materials', _materialCount),
              _countTile('Study sets', _studySetCount),
              _countTile('Outputs', _outputCount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countTile(String label, int count) => Expanded(
          child: Column(children: [
        Text('$count',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))
      ]));

  Widget _securityCard(UserModel user) {
    final hasAccount = user.supabaseUserId != null;
    return FigmaCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Text('Account and security',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Edit profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/edit-profile')),
        ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            subtitle: Text(hasAccount
                ? 'Update your account password'
                : 'Sign in to an account to change its password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: hasAccount
                ? () => Navigator.of(context).pushNamed('/change-password')
                : null),
        ListTile(
            leading: const Icon(Icons.phonelink_lock_outlined),
            title: const Text('App lock'),
            subtitle: const Text('Protect this device with a six digit PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/app-lock')),
      ]),
    );
  }

  Widget _activityCard() {
    final maxCount = _activityCounts.fold<int>(
      1,
      (max, count) => count > max ? count : max,
    );
    return FigmaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activity · last 7 days',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxCount.toDouble() + 1,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final labels = _dayLabels();
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(labels[index],
                              style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < _activityCounts.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: _activityCounts[index].toDouble(),
                          width: 16,
                          borderRadius: BorderRadius.circular(5),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentActivityCard() => FigmaCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text('Recent activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          if (_recentLogs.isEmpty)
            const ListTile(title: Text('No recent activity yet')),
          for (final log in _recentLogs)
            ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(log['message'] as String? ??
                    log['event_type'] as String? ??
                    'Activity'),
                subtitle: Text(log['created_at'] as String? ?? '')),
        ]),
      );

  Widget _dataActionsCard(UserModel user) => FigmaCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text('Data and sharing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear history'),
              subtitle: const Text('Remove saved outputs from this device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _clearHistory),
          if (user.supabaseUserId == null &&
              user.email == 'guest@convert2file.local')
            ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset guest profile'),
                subtitle: const Text('Reset profile details; keep saved files'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _resetGuestProfile),
        ]),
      );

  List<String> _dayLabels() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    return List.generate(
        7, (index) => labels[start.add(Duration(days: index)).weekday - 1]);
  }
}
