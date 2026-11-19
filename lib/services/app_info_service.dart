import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AppInfoService {
  static const _cacheKey = 'managed_app_info_content_v1';

  static String? latestVersionFromContent(Map<String, dynamic>? content) {
    final releaseNotes = content?['release_notes'];
    if (releaseNotes is! List) return null;

    for (final entry in releaseNotes) {
      if (entry is! Map || entry['is_latest'] != true) continue;
      final version = entry['version']?.toString().trim();
      if (version != null && version.isNotEmpty) return version;
    }
    return null;
  }

  Future<Map<String, dynamic>?> loadCachedContent() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_cacheKey));
  }

  Future<Map<String, dynamic>?> refreshContent() async {
    if (!SupabaseConfig.isConfigured) return null;
    final preferences = await SharedPreferences.getInstance();

    try {
      final result = await Supabase.instance.client
          .from('app_info_content')
          .select('sections,release_notes')
          .eq('id', true)
          .single();
      final content = Map<String, dynamic>.from(result);
      await preferences.setString(_cacheKey, jsonEncode(content));
      return content;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchContent() async {
    final cached = await loadCachedContent();
    return await refreshContent() ?? cached;
  }

  Map<String, dynamic>? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }
}
