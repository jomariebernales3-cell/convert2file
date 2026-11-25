import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'app_version_service.dart';
import 'supabase_config.dart';

class AnnouncementService {
  // Bump the cache namespace so notices cached by older releases are dropped
  // after an app update instead of resurfacing if the first refresh fails.
  static const _cacheKey = 'active_announcements_cache_v3';
  static const _fetchTimeKey = 'active_announcements_fetch_time_v3';
  static const _dismissedKey = 'dismissed_announcement_ids_v1';
  static const _seenKey = 'seen_announcement_ids_v1';
  static const _refreshInterval = Duration(minutes: 15);

  Future<List<Map<String, dynamic>>> fetchActive(
      {bool forceRefresh = false}) async {
    final installedVersion = await AppVersionService.loadInstalledVersion();
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _scopedKey(_cacheKey);
    final fetchTimeKey = _scopedKey(_fetchTimeKey);
    final cached = _filterForInstalledVersion(
      _decodeRows(prefs.getString(cacheKey)),
      installedVersion,
    );
    final lastFetch = DateTime.tryParse(prefs.getString(fetchTimeKey) ?? '');
    final stillFresh = lastFetch != null &&
        DateTime.now().difference(lastFetch) < _refreshInterval;
    if ((!forceRefresh && stillFresh) || !SupabaseConfig.isConfigured) {
      return cached;
    }

    final client = Supabase.instance.client;
    final now = DateTime.now().toUtc().toIso8601String();

    // The current admin portal writes to `announcements`. Do not merge the
    // retired `admin_announcements` table, which can keep old notices active.
    List<dynamic> rows;
    try {
      try {
        rows = await client
            .from('announcements')
            .select(
              'id,title,body,kind,starts_at,ends_at,link_url,link_label,created_at,hide_after_version',
            )
            .eq('is_active', true)
            .lte('starts_at', now)
            .or('ends_at.is.null,ends_at.gt.$now')
            .order('created_at', ascending: false)
            .limit(10);
      } catch (_) {
        // Older Supabase projects can keep serving notices until the optional
        // version-targeting migration has been applied.
        rows = await client
            .from('announcements')
            .select(
              'id,title,body,kind,starts_at,ends_at,link_url,link_label,created_at',
            )
            .eq('is_active', true)
            .lte('starts_at', now)
            .or('ends_at.is.null,ends_at.gt.$now')
            .order('created_at', ascending: false)
            .limit(10);
      }
    } catch (_) {
      return cached;
    }

    final values = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    final userId = AuthService().currentUser?.supabaseUserId;
    if (userId != null) {
      try {
        final personalRows = await client
            .from('user_announcements')
            .select('id,title,body,created_at')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100);
        values.addAll(personalRows.map((row) => {
              ...Map<String, dynamic>.from(row),
              'kind': 'important',
            }));
      } catch (_) {
        // Keep public announcements available if a private-inbox fetch fails.
      }
    }
    values.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    final active = _filterForInstalledVersion(values, installedVersion);
    await prefs.setString(cacheKey, jsonEncode(values));
    await prefs.setString(fetchTimeKey, DateTime.now().toIso8601String());
    return active;
  }

  List<Map<String, dynamic>> _filterForInstalledVersion(
    Iterable<Map<String, dynamic>> items,
    String? installedVersion,
  ) {
    if (installedVersion == null || installedVersion.isEmpty) {
      return items.toList(growable: false);
    }
    return items.where((item) {
      final hideAfter = item['hide_after_version']?.toString().trim() ?? '';
      return hideAfter.isEmpty ||
          !AppVersionService.isAtLeast(installedVersion, hideAfter);
    }).toList(growable: false);
  }

  Future<Set<String>> seenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_scopedKey(_seenKey)) ?? const <String>[])
        .toSet();
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedKey(_seenKey);
    final seen = (prefs.getStringList(key) ?? <String>[]).toSet()..addAll(ids);
    await prefs.setStringList(key, seen.toList());
  }

  Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_scopedKey(_dismissedKey)) ?? const <String>[])
        .toSet();
  }

  Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedKey(_dismissedKey);
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()..add(id);
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
          .where((row) => !row['id'].toString().startsWith('legacy-'))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
