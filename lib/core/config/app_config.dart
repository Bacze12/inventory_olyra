/// Configuración global de la aplicación.
///
/// El cliente de escritorio opera en modo *standalone* (100% local): ventas,
/// inventario y caja trabajan únicamente contra la base de datos SQLite del
/// dispositivo, sin levantar servidores de red, sin esperar al teléfono y sin
/// mostrar la interfaz de vinculación/sincronización con el móvil.
class AppConfig {
  AppConfig._();

  /// `true` → modo independiente: la app no depende del móvil.
  /// Cambia a `false` para reactivar la sincronización/vinculación con Android.
  static const bool isStandalone = true;

  /// `true` cuando la sincronización con el móvil está habilitada.
  static bool get enableMobileSync => !isStandalone;

  /// Sincronización en la nube (Supabase) y licenciamiento por hardware.
  ///
  /// Aunque esté en `true`, todo el módulo se auto-desactiva si no hay
  /// credenciales compiladas (ver `SupabaseConfig.credentialsPresent`),
  /// así que la app nunca deja de funcionar en local.
  static const bool enableCloudSync = true;
}