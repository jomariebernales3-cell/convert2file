import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AppInfoService {
  static const _cacheKey = 'managed_app_info_content_v1';

  Future<Map<String, dynamic>?> fetchContent() async {
    final preferences = await SharedPreferences.getInstance();
    final cached = _decode(preferences.getString(_cacheKey));
    if (!SupabaseConfig.isConfigured) return cached;

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
      return cached;
    }
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
