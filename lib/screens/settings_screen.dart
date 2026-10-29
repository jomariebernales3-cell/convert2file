import 'package:flutter/material.dart';
import '../services/app_share_service.dart';
import '../services/theme_service.dart';
import '../core/database_helper.dart';
import '../widgets/figma_app_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FigmaAppShell(
      title: 'Settings',
      subtitle: 'Application specs & diagnostic details',
      selectedIndex: 2,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FigmaPrimaryButton(
                  label: 'Share App',
                  icon: Icons.share_outlined,
                  onPressed: _shareApp,
                ),
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
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
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
            'Theme',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeChoice>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(
                  value: AppThemeChoice.day,
                  icon: Icon(Icons.light_mode),
                  label: Text('Day'),
                ),
                ButtonSegment(
                  value: AppThemeChoice.dbz,
                  icon: Icon(Icons.bolt),
                  label: Text('DBZ'),
                ),
                ButtonSegment(
                  value: AppThemeChoice.night,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Night'),
                ),
              ],
              selected: selectedMainTheme,
              onSelectionChanged: (selection) async {
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
          'Storage Statistics',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatItem('Files', _stats!['total_files'].toString()),
            _buildStatItem('Users', _stats!['total_users'].toString()),
            _buildStatItem('Logs', _stats!['total_logs'].toString()),
          ],
        ),
        const SizedBox(height: 8),
        FigmaCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.storage, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Storage Used',
                        style: TextStyle(fontSize: 12)),
                    Text(
                      _formatBytes(_stats!['total_size'] as int),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Offline AI',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildActionTile(
          icon: Icons.memory,
          title: 'Llama Model',
          subtitle: 'Import a .gguf model for offline study generation',
          onTap: () => Navigator.of(context).pushNamed('/ai-model'),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FigmaCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(
                  color: FigmaAppColors.subtext(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildActionTile(
          icon: Icons.cleaning_services,
          title: 'Clear Cache',
          subtitle: 'Remove temporary files',
          onTap: _clearCache,
        ),
        _buildActionTile(
          icon: Icons.download,
          title: 'Export Data',
          subtitle: 'Backup your data',
          onTap: _exportData,
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
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? Colors.red : Colors.grey),
        title: Text(title,
            style: TextStyle(color: isDestructive ? Colors.red : null)),
        subtitle: Text(subtitle,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
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
