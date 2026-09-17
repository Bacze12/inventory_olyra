/// Credenciales de Supabase para BodegaFlow POS.
///
/// Se inyectan en tiempo de compilación con `--dart-define` para NO versionar
/// secretos en el repositorio:
///
///   flutter build windows --release \
///     --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=tu-anon-key
///
/// La `anonKey` es pública por diseño en Supabase (la seguridad real está en
/// Row Level Security vía `auth.uid()`), pero sigue siendo una coordenada de
/// entorno que conviene no mezclar con otros deployments.
class SupabaseConfig {
  SupabaseConfig._();

  /// URL del proyecto. Vacía = modo nube desactivado (app sigue 100% local).
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Anon (public) key del proyecto.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Alias usado por la API actual de Supabase (`publishableKey`).
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Nombre del bucket privado donde se suben los respaldos comprimidos.
  static const String backupBucket = 'pos-backups';

  /// `true` cuando el API Key HTTP del bucket no se está usando (Storage usa
  /// la sesión JWT del usuario).
  static bool get credentialsPresent => url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}