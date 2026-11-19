import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
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
    this.latestVersion = SupabaseConfig.appVersion,
    this.minimumSupportedVersion = '1.0.0',
    this.featureFlags = const {},
    this.announcements = const [],
  });

  bool featureEnabled(String key) => featureFlags[key] != false;

  factory AppRemoteConfig.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['feature_flags'];
    final rawAnnouncements = json['announcements'];
    return AppRemoteConfig(
      maintenanceEnabled: json['maintenance_enabled'] == true,
      latestVersion: json['latest_version']?.toString() ?? SupabaseConfig.appVersion,
      minimumSupportedVersion:
          json['minimum_supported_version']?.toString() ?? '1.0.0',
      featureFlags: rawFlags is Map
          ? Map<String, dynamic>.from(rawFlags)
          : const {},
      announcements: rawAnnouncements is List
          ? rawAnnouncements
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'maintenance_enabled': maintenanceEnabled,
        'latest_version': latestVersion,
        'minimum_supported_version': minimumSupportedVersion,
        'feature_flags': featureFlags,
        'announcements': announcements,
      };

  bool get updateAvailable =>
      _compareVersions(latestVersion, SupabaseConfig.appVersion) > 0;

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
  static const _cacheKey = 'app_remote_config_cache_v1';
  static const _requestTimeout = Duration(seconds: 6);

  const AppRemoteConfigService();

  Future<AppRemoteConfig> load() async {
    final cached = await loadCached();
    return refresh(fallback: cached);
  }

  Future<AppRemoteConfig> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_cacheKey);
    if (raw == null) return const AppRemoteConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AppRemoteConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Ignore malformed cache and use the built-in defaults.
    }
    return const AppRemoteConfig();
  }

  Future<AppRemoteConfig> refresh({AppRemoteConfig? fallback}) async {
    final cached = fallback ?? await loadCached();
    if (!SupabaseConfig.isConfigured) return cached;

    try {
      final client = Supabase.instance.client;
      final settings = await client
          .from('app_control_settings')
          .select()
          .eq('id', true)
          .maybeSingle()
          .timeout(_requestTimeout);
      if (settings == null) return cached;

      final flags = settings['feature_flags'];
      final config = AppRemoteConfig(
        maintenanceEnabled: settings['maintenance_enabled'] == true,
        latestVersion: settings['latest_version']?.toString() ?? SupabaseConfig.appVersion,
        minimumSupportedVersion:
            settings['minimum_supported_version']?.toString() ?? '1.0.0',
        featureFlags: flags is Map ? Map<String, dynamic>.from(flags) : const {},
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(config.toJson()));
      return config;
    } catch (_) {
      // Keep the last successful remote settings when the device is offline.
      return cached;
    }
  }
}
