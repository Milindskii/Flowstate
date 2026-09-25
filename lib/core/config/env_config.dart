/// Environment Configuration for Flowstate Flutter Client
/// Compiles with --dart-define or falls back safely in local development.
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://drfjprhnynktjkiplbzy.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_LDiD72aRDOVKMwD5AMoU5Q_oNntJRrv',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
}
