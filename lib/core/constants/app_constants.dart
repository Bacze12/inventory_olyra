class AppConstants {
  AppConstants._();

  static const String appName = 'Inventario';

  static const String settingStoreName = 'store_name';
  static const String defaultStoreName = 'Mi Negocio';

  static const String settingLanguage = 'language';
  static const String defaultLanguage = 'es';

  /// Suscripción PRO publicada en Google Play. Debe coincidir exactamente con
  /// el ID configurado en Play Console.
  static const String proProductId = 'bodegaflow_pro_monthly';

  /// Clave de la tabla `settings` donde queda marcada la licencia PRO.
  static const String settingPro = 'pro_active';
  static const String proEnabled = 'true';

  ///Máximo de productos del catálogo en la versión gratuita. Agotado este
  /// cupo, el alta de un producto nuevo se detiene y se ofrece el paywall.
  static const int freeProductLimit = 30;

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

  static const String privacyUrl = 'https://olyra.cl/projects/4/privacy';
  static const String termsUrl = 'https://olyra.cl/projects/4/terms';
}