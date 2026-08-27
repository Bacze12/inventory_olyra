class AppConstants {
  AppConstants._();

  static const String appName = 'Inventario';

  static const String settingStoreName = 'store_name';
  static const String defaultStoreName = 'Mi Negocio';

  /// Silencio total tras cada conteo: evita dobles sumas al sostener el producto.
  static const Duration applyLockout = Duration(milliseconds: 600);

  /// Si la cámara deja de ver CUALQUIER código este tiempo, la siguiente lectura
  /// se trata como nueva sesión (permite re-contar rápido el mismo GTIN).
  static const Duration presenceGap = Duration(milliseconds: 400);

  /// Veces consecutivas que debe aparecer un código nuevo para contárselo
  /// (filtra "fantasmas" de un solo frame al mover la cámara).
  static const int stableDetections = 2;

  static const String pdfFilePrefix = 'inventario_';
  static const String reportsFolderName = 'reportes';
}