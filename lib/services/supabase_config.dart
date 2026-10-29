/// Values are supplied at build time so keys are never committed to source.
/// Never use a Supabase service-role key in a mobile app.
class SupabaseConfig {
  // These defaults let local development run with `flutter run -d <device>`.
  // Build-time values may still override them for another Supabase project.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yozxhgdypifkllfuljge.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable__FkqIT1Ng6zTT8jFYnlRtw_jfM0KDnw',
  );

  static bool get isConfigured =>
      url.startsWith('https://') && anonKey.trim().isNotEmpty;
}
