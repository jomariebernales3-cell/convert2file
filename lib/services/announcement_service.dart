import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AnnouncementService {
  static const _cacheKey = 'active_announcements_cache_v1';
  static const _fetchTimeKey = 'active_announcements_fetch_time_v1';
  static const _dismissedKey = 'dismissed_announcement_ids_v1';
  static const _refreshInterval = Duration(minutes: 15);

  Future<List<Map<String, dynamic>>> fetchActive() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeRows(prefs.getString(_cacheKey));
    final lastFetch = DateTime.tryParse(prefs.getString(_fetchTimeKey) ?? '');
    final stillFresh = lastFetch != null &&
        DateTime.now().difference(lastFetch) < _refreshInterval;
    if (stillFresh || !SupabaseConfig.isConfigured) return cached;

    await prefs.setString(_fetchTimeKey, DateTime.now().toIso8601String());
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await Supabase.instance.client
          .from('announcements')
          .select(
            'id,title,body,kind,starts_at,ends_at,link_url,link_label,created_at',
          )
          .eq('is_active', true)
          .lte('starts_at', now)
          .or('ends_at.is.null,ends_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(10);
      final values = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      await prefs.setString(_cacheKey, jsonEncode(values));
      return values;
    } catch (_) {
      return cached;
    }
  }

  Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dismissedKey) ?? const <String>[]).toSet();
  }

  Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_dismissedKey) ?? <String>[]).toSet()
      ..add(id);
    await prefs.setStringList(_dismissedKey, ids.toList());
  }

  List<Map<String, dynamic>> _decodeRows(String? raw) {
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
