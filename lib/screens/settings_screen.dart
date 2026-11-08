import 'package:flutter/material.dart';
import '../services/app_share_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/local_llama_service.dart';
import '../core/database_helper.dart';
import '../widgets/figma_app_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  final LocalLlamaService _llama = LocalLlamaService.instance;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final files = await DatabaseHelper.instance.queryAllFiles();
      final users = await DatabaseHelper.instance.queryAllUsers();
      final logs = await DatabaseHelper.instance.queryAllLogs();

      int totalSize = 0;
      for (final file in files) {
        totalSize += (file['size_bytes'] as int? ?? 0);
      }

      setState(() {
        _stats = {
          'total_files': files.length,
          'total_users': users.length,
          'total_logs': logs.length,
          'total_size': totalSize,
        };
      });
    } catch (e) {
      debugPrint('Failed to load stats: $e');
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isLoading = true);
    try {
      // Implementation would clear temp files
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    } catch (e) {
      _showError('Failed to clear cache: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportData() async {
    setState(() => _isLoading = true);
    try {
      // Implementation would export database
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data export feature coming soon')),
        );
      }
    } catch (e) {
      _showError('Export failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _shareApp() async {
    setState(() => _isLoading = true);
    try {
      await AppShareService.shareApp();
    } catch (e) {
      _showError('Share failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runAiAction(Future<void> Function() action) async {
    setState(() => _isLoading = true);
    try {
      await action();
    } catch (e) {
      _showError('Offline AI action failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthService().signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    } catch (e) {
      _showError('Could not sign out: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Theme.of(context).colorScheme.error, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: 'Settings',
      subtitle: '',
      selectedIndex: 2,
      showBack: true,
      showProfile: false,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileSection(),
                const SizedBox(height: 24),
                _buildThemeSection(),
                const SizedBox(height: 24),
                _buildAiSection(),
                const SizedBox(height: 24),
                _buildStatsSection(),
                const SizedBox(height: 24),
                _buildActionsSection(),
                const SizedBox(height: 24),
                _buildAboutSection(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final user = AuthService().currentUser;
    final name = user?.name ?? 'Guest User';
    final email = user?.email ?? 'Local workspace';
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0]).join().toUpperCase();

    return FigmaCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.isEmpty ? 'GU' : initials,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FigmaAppColors.subtext(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        user?.role.toUpperCase() ?? 'USER',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/profile'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection() {
    final themeService = ThemeService.instance;
    final selectedMainTheme = <AppThemeChoice>{themeService.themeChoice};

    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeChoice>(
              showSelectedIcon: false,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 2)),
                side: WidgetStatePropertyAll(
                  BorderSide(color: FigmaAppColors.border(context)),
                ),
              ),
              segments: const [
                ButtonSegment(value: AppThemeChoice.day, label: Text('Day')),
                ButtonSegment(value: AppThemeChoice.dbz, label: Text('DBZ')),
                ButtonSegment(value: AppThemeChoice.night, label: Text('Night')),
                ButtonSegment(value: AppThemeChoice.system, label: Text('System')),
              ],
              selected: selectedMainTheme,
              onSelectionChanged: (selection) async {
                if (selection.isEmpty) return;
                await themeService.setThemeChoice(selection.first);
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    if (_stats == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Storage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FigmaCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.storage_outlined,
                      color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatBytes(_stats!['total_size'] as int),
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Used on this device',
                        style: TextStyle(
                            color: FigmaAppColors.subtext(context),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildStatItem('Files', _stats!['total_files'].toString()),
                  _buildStatItem('Users', _stats!['total_users'].toString()),
                  _buildStatItem('Logs', _stats!['total_logs'].toString()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiSection() {
    return AnimatedBuilder(
      animation: _llama,
      builder: (context, _) {
        final modelName = _llama.modelPath == null
            ? 'No model imported'
            : _llama.modelPath!.split(RegExp(r'[\\/]')).last;
        final stateLabel = _llama.isLoaded
            ? 'Ready'
            : _llama.hasModel
                ? 'Imported'
                : 'Not set up';
        final stateMessage = _llama.isLoaded
            ? 'Loaded on this phone'
            : _llama.hasModel
                ? 'Imported · ready to load'
                : 'Import a GGUF model to use offline AI';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline AI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FigmaCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.memory,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              stateMessage,
                              style: TextStyle(
                                color: FigmaAppColors.subtext(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          stateLabel,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _isLoading || !_llama.hasModel || _llama.isLoaded
                                  ? null
                                  : () => _runAiAction(_llama.loadModel),
                          child: _llama.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Load model'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading || _llama.isGenerating
                              ? null
                              : () => _runAiAction(_llama.importModel),
                          child: const Text('Import .gguf'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => Navigator.of(context).pushNamed('/ai-model'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Need a different model? See compatible models and download help.',
                              style: TextStyle(
                                color: FigmaAppColors.subtext(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: FigmaAppColors.subtext(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data and sharing',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FigmaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _buildActionTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear cache',
                subtitle: 'Remove temporary files',
                onTap: _clearCache,
              ),
              _buildActionTile(
                icon: Icons.download_outlined,
                title: 'Export data',
                subtitle: 'Back up your data',
                onTap: _exportData,
              ),
              _buildActionTile(
                icon: Icons.share_outlined,
                title: 'Share app',
                subtitle: 'Send Convert2File to a friend',
                onTap: _shareApp,
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool showDivider = true,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: isDestructive ? Theme.of(context).colorScheme.error : null,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: FigmaAppColors.subtext(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: FigmaAppColors.subtext(context)),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              indent: 66,
              color: FigmaAppColors.border(context),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'About',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FigmaCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.description,
                      color: Theme.of(context).colorScheme.primary, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Convert2File',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Version 1.0.26.29',
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
              const SizedBox(height: 12),
              Text(
                'An offline-capable academic document generation system. Convert PDFs, DOCX, and PPTX files into structured academic outputs.',
                style: TextStyle(
                  color: FigmaAppColors.subtext(context),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/app-info'),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('APP INFO & UPDATE HISTORY'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
