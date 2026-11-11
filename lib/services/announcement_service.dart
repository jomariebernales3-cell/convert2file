import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_config.dart';

class AnnouncementService {
  static const _cacheKey = 'active_announcements_cache_v2';
  static const _fetchTimeKey = 'active_announcements_fetch_time_v2';
  static const _dismissedKey = 'dismissed_announcement_ids_v1';
  static const _seenKey = 'seen_announcement_ids_v1';
  static const _refreshInterval = Duration(minutes: 15);

  Future<List<Map<String, dynamic>>> fetchActive({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeRows(prefs.getString(_cacheKey));
    final lastFetch = DateTime.tryParse(prefs.getString(_fetchTimeKey) ?? '');
    final stillFresh = lastFetch != null &&
        DateTime.now().difference(lastFetch) < _refreshInterval;
    if ((!forceRefresh && stillFresh) || !SupabaseConfig.isConfigured) {
      return cached;
    }

    final client = Supabase.instance.client;
    final values = <Map<String, dynamic>>[];
    var readSucceeded = false;
    final now = DateTime.now().toUtc().toIso8601String();

    // The current admin page writes to `announcements`.
    try {
      final rows = await client
          .from('announcements')
          .select(
            'id,title,body,kind,starts_at,ends_at,link_url,link_label,created_at',
          )
          .eq('is_active', true)
          .lte('starts_at', now)
          .or('ends_at.is.null,ends_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(10);
      values.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
      readSucceeded = true;
    } catch (_) {
      // Continue to check the legacy table used by the previously published admin site.
    }

    // Older GitHub Pages versions publish through admin_publish_announcement().
    try {
      final legacyRows = await client
          .from('admin_announcements')
          .select('id,title,message,created_at')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(10);
      values.addAll(legacyRows.map((row) {
        final legacy = Map<String, dynamic>.from(row);
        return <String, dynamic>{
          'id': 'legacy-${legacy['id']}',
          'title': legacy['title'],
          'body': legacy['message'],
          'kind': 'info',
          'starts_at': legacy['created_at'],
          'ends_at': null,
          'link_url': null,
          'link_label': null,
          'created_at': legacy['created_at'],
        };
      }));
      readSucceeded = true;
    } catch (_) {
      // This table may not exist in projects set up with only the new schema.
    }

    if (!readSucceeded) return cached;
    values.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    final active = values.take(10).toList(growable: false);
    await prefs.setString(_cacheKey, jsonEncode(active));
    await prefs.setString(_fetchTimeKey, DateTime.now().toIso8601String());
    return active;
  }

  Future<Set<String>> seenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_scopedKey(_seenKey)) ?? const <String>[]).toSet();
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedKey(_seenKey);
    final seen = (prefs.getStringList(key) ?? <String>[]).toSet()..addAll(ids);
    await prefs.setStringList(key, seen.toList());
  }

  Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_scopedKey(_dismissedKey)) ?? const <String>[]).toSet();
  }

  Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedKey(_dismissedKey);
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()
      ..add(id);
    await prefs.setStringList(key, ids.toList());
  }

  String _scopedKey(String key) {
    final userId = AuthService().currentUser?.supabaseUserId;
    return '${key}_${userId ?? 'guest'}';
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
