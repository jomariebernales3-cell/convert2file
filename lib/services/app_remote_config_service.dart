import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AppRemoteConfig {
  final bool maintenanceEnabled;
  final String latestVersion;
  final String minimumSupportedVersion;
  final Map<String, dynamic> featureFlags;
  final List<Map<String, dynamic>> announcements;

  const AppRemoteConfig({
    this.maintenanceEnabled = false,
    this.latestVersion = '1.0.26',
    this.minimumSupportedVersion = '1.0.0',
    this.featureFlags = const {},
    this.announcements = const [],
  });

  bool featureEnabled(String key) => featureFlags[key] != false;

  bool get updateAvailable => _compareVersions(latestVersion, '1.0.26') > 0;

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final difference = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
      if (difference != 0) return difference.sign;
    }
    return 0;
  }
}

class AppRemoteConfigService {
  const AppRemoteConfigService();

  Future<AppRemoteConfig> load() async {
    if (!SupabaseConfig.isConfigured) return const AppRemoteConfig();
    final client = Supabase.instance.client;
    final results = await Future.wait([
      client.from('app_control_settings').select().eq('id', true).maybeSingle(),
      client.from('admin_announcements').select('id,title,message,created_at')
          .eq('status', 'active').order('created_at', ascending: false).limit(5),
    ]);
    final settings = results[0] as Map<String, dynamic>?;
    final announcementRows = results[1] as List<dynamic>;
    if (settings == null) return const AppRemoteConfig();
    final flags = settings['feature_flags'];
    return AppRemoteConfig(
      maintenanceEnabled: settings['maintenance_enabled'] == true,
      latestVersion: settings['latest_version']?.toString() ?? '1.0.26',
      minimumSupportedVersion:
          settings['minimum_supported_version']?.toString() ?? '1.0.0',
      featureFlags: flags is Map ? Map<String, dynamic>.from(flags) : const {},
      announcements: announcementRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
    );
  }
}
