/// Defaults target the new project. Build-time values can still override them.
/// Never use a Supabase service-role key in a mobile app.
class SupabaseConfig {
  static const appVersion = '1.0.25';
  // These defaults let local development run with `flutter run -d <device>`.
  // Build-time values may still override them for another Supabase project.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lklihnzfwlkifsdbxfkv.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_uyyamBQ1Ga0WudUc40y1Mg_G77GhamY',
  );

  static bool get isConfigured =>
      url.startsWith('https://') && anonKey.trim().isNotEmpty;
}
