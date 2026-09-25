import 'package:flutter/widgets.dart';

/// Tabla de traducciones ES/EN usada por las pantallas principales.
///
/// Claves canónicas por cadena; cada locale debe definir el mismo conjunto de
/// claves. Un locale no soportado cae a español y una clave desconocida se
/// devuelve tal cual para que el fallo sea visible.
class AppStrings {
  AppStrings._();

  static const String es = 'es';
  static const String en = 'en';

  static const String appName = 'app.name';
  static const String homeHeroTitle = 'home.hero.title';
  static const String homeHeroSubtitle = 'home.hero.subtitle';
  static const String homeScanNow = 'home.scanNow';
  static const String homeLowStock = 'home.lowStock';
  static const String homeProducts = 'home.products';
  static const String homeProductsSubtitle = 'home.products.subtitle';
  static const String homeReport = 'home.report';
  static const String homeReportSubtitle = 'home.report.subtitle';
  static const String homeLabel = 'home.label';
  static const String homeLabelSubtitle = 'home.label.subtitle';
  static const String homeScanner = 'home.scanner';
  static const String homeScannerSubtitle = 'home.scanner.subtitle';
  static const String homeOsa = 'home.osa';
  static const String homeOsaSubtitle = 'home.osa.subtitle';
  static const String homeSettings = 'home.settings';
  static const String settingsTitle = 'settings.title';
  static const String settingsLanguage = 'settings.language';
  static const String settingsLegal = 'settings.legal';
  static const String settingsPrivacy = 'settings.privacy';
  static const String settingsTerms = 'settings.terms';
  static const String settingsPlan = 'settings.plan';
  static const String settingsPlanFree = 'settings.plan.free';
  static const String settingsPlanPro = 'settings.plan.pro';
  static const String proBadge = 'pro.badge';
  static const String osaTitle = 'osa.title';
  static const String osaSubtitle = 'osa.subtitle';
  static const String osaPendingTitle = 'osa.pending.title';
  static const String osaPendingBody = 'osa.pending.body';
  static const String reportGeneratePdf = 'report.generatePdf';
  static const String paywallTitle = 'paywall.title';
  static const String paywallHeadline = 'paywall.headline';
  static const String paywallSubtitle = 'paywall.subtitle';
  static const String paywallFreeUsage = 'paywall.freeUsage';
  static const String paywallFreeUsagePro = 'paywall.freeUsage.pro';
  static const String paywallLimitReached = 'paywall.limitReached';
  static const String paywallColumnFeature = 'paywall.column.feature';
  static const String paywallColumnFree = 'paywall.column.free';
  static const String paywallColumnPro = 'paywall.column.pro';
  static const String paywallBuy = 'paywall.buy';
  static const String paywallRestore = 'paywall.restore';
  static const String paywallAlreadyPro = 'paywall.alreadyPro';
  static const String paywallClose = 'paywall.close';
  static const String paywallPriceLoading = 'paywall.price.loading';
  static const String paywallPriceUnavailable = 'paywall.price.unavailable';
  static const String paywallLegal = 'paywall.legal';
  static const String paywallOsaLocked = 'paywall.locked.osa';
  static const String paywallPdfLocked = 'paywall.locked.pdf';
  static const String paywallNoticePurchased = 'paywall.notice.purchased';
  static const String paywallNoticePending = 'paywall.notice.pending';
  static const String paywallNoticePrice = 'paywall.notice.price';
  static const String paywallNoticeFailed = 'paywall.notice.failed';
  static const String paywallNoticeNothingToRestore = 'paywall.notice.restore';
  static const String paywallFeatureProducts = 'paywall.feature.products';
  static const String paywallFeatureScanner = 'paywall.feature.scanner';
  static const String paywallFeatureLowStock = 'paywall.feature.lowStock';
  static const String paywallFeatureLabels = 'paywall.feature.labels';
  static const String paywallFeatureOsa = 'paywall.feature.osa';
  static const String paywallFeaturePdf = 'paywall.feature.pdf';
  static const String paywallValueUpTo = 'paywall.value.upTo';
  static const String paywallValueUnlimited = 'paywall.value.unlimited';
  static const String paywallValueIncluded = 'paywall.value.included';
  static const String paywallValueLocked = 'paywall.value.locked';
  static const String paywallValueAdvanced = 'paywall.value.advanced';
  static const String paywallValueComplete = 'paywall.value.complete';

  static const Map<String, Map<String, String>> translations = {
    es: {
      appName: 'Inventario',
      homeHeroTitle: 'Inventario al instante',
      homeHeroSubtitle: 'Escanea y actualiza existencias sin conexión.',
      homeScanNow: 'Escanear ahora',
      homeLowStock: '{count} producto(s) llegaron a su stock mínimo',
      homeProducts: 'Productos',
      homeProductsSubtitle: 'Catálogo y stock',
      homeReport: 'Reporte PDF',
      homeReportSubtitle: 'Exportar y guardar',
      homeLabel: 'Imprimir etiqueta',
      homeLabelSubtitle: 'Bluetooth / PDF',
      homeScanner: 'Escáner',
      homeScannerSubtitle: 'Entradas y salidas',
      homeOsa: 'Métricas OSA',
      homeOsaSubtitle: 'Disponibilidad en anaquel',
      homeSettings: 'Ajustes',
      settingsTitle: 'Ajustes',
      settingsLanguage: 'Idioma',
      settingsLegal: 'Privacidad y Términos',
      settingsPrivacy: 'Política de Privacidad',
      settingsTerms: 'Términos y Condiciones',
      settingsPlan: 'Plan',
      settingsPlanFree: 'Gratis',
      settingsPlanPro: 'BodegaFlow PRO',
      proBadge: 'PRO',
      osaTitle: 'Métricas OSA',
      osaSubtitle: 'Disponibilidad en anaquel y reposición',
      osaPendingTitle: 'Estamos calculando tu primera medición',
      osaPendingBody:
          'Tu licencia PRO está activa. Los indicadores de disponibilidad en '
              'anaquel se habilitan en la próxima actualización.',
      reportGeneratePdf: 'Generar reporte PDF',
      paywallTitle: 'BodegaFlow PRO',
      paywallHeadline: 'Tu bodega, sin límites',
      paywallSubtitle:
          'BodegaFlow PRO está pensado para el pequeño comercio que ya grewció '
              'y necesita saber qué falta reponer en la bodega y en el anaquel.',
      paywallFreeUsage: 'Te quedan {count} de {limit} productos gratis',
      paywallFreeUsagePro: 'Tienes BodegaFlow PRO activo: productos ilimitados',
      paywallLimitReached:
          'Alcanzaste el límite de {limit} productos en la versión gratis',
      paywallColumnFeature: 'Función',
      paywallColumnFree: 'Gratis',
      paywallColumnPro: 'PRO',
      paywallBuy: 'Suscribirme a PRO',
      paywallRestore: 'Restaurar compras',
      paywallAlreadyPro: 'Ya tienes BodegaFlow PRO',
      paywallClose: 'Continuar',
      paywallPriceLoading: 'Consultando precio en Google Play…',
      paywallPriceUnavailable: 'Precio no disponible',
      paywallLegal:
          'Suscripción mensual administrada por Google Play. Se renueva '
              'automáticamente hasta que la canceles desde los ajustes de tu '
              'cuenta de Google.',
      paywallOsaLocked:
          'Las métricas OSA y la reposición son exclusivas de BodegaFlow PRO',
      paywallPdfLocked:
          'La exportación de reportes PDF es exclusiva de BodegaFlow PRO',
      paywallNoticePurchased: '¡Listo! Ya tienes BodegaFlow PRO',
      paywallNoticePending: 'La compra quedó pendiente de confirmación',
      paywallNoticePrice: 'No pudimos consultar el precio en Google Play',
      paywallNoticeFailed: 'No se pudo completar la compra',
      paywallNoticeNothingToRestore:
          'No encontramos ninguna compra activa en Google Play',
      paywallFeatureProducts: 'Productos en el catálogo',
      paywallFeatureScanner: 'Lector de códigos y QR',
      paywallFeatureLowStock: 'Alertas de stock bajo',
      paywallFeatureLabels: 'Impresión de etiquetas',
      paywallFeatureOsa: 'Métricas OSA y reposición',
      paywallFeaturePdf: 'Exportación de reportes PDF',
      paywallValueUpTo: 'Hasta {limit}',
      paywallValueUnlimited: 'Ilimitados',
      paywallValueIncluded: 'Completo',
      paywallValueLocked: 'Bloqueado',
      paywallValueAdvanced: 'Avanzado',
      paywallValueComplete: 'Completo',
    },
    en: {
      appName: 'Inventory',
      homeHeroTitle: 'Inventory at a glance',
      homeHeroSubtitle: 'Scan and update stock offline.',
      homeScanNow: 'Scan now',
      homeLowStock: '{count} product(s) reached minimum stock',
      homeProducts: 'Products',
      homeProductsSubtitle: 'Catalog & stock',
      homeReport: 'PDF Report',
      homeReportSubtitle: 'Export and save',
      homeLabel: 'Print label',
      homeLabelSubtitle: 'Bluetooth / PDF',
      homeScanner: 'Scanner',
      homeScannerSubtitle: 'Entries and exits',
      homeOsa: 'OSA metrics',
      homeOsaSubtitle: 'On-shelf availability',
      homeSettings: 'Settings',
      settingsTitle: 'Settings',
      settingsLanguage: 'Language',
      settingsLegal: 'Privacy & Terms',
      settingsPrivacy: 'Privacy Policy',
      settingsTerms: 'Terms & Conditions',
      settingsPlan: 'Plan',
      settingsPlanFree: 'Free',
      settingsPlanPro: 'BodegaFlow PRO',
      proBadge: 'PRO',
      osaTitle: 'OSA metrics',
      osaSubtitle: 'On-shelf availability and restocking',
      osaPendingTitle: 'We are calculating your first measurement',
      osaPendingBody:
          'Your PRO license is active. The on-shelf availability indicators are '
              'enabled in the next update.',
      reportGeneratePdf: 'Generate PDF report',
      paywallTitle: 'BodegaFlow PRO',
      paywallHeadline: 'Your store, no limits',
      paywallSubtitle:
          'BodegaFlow PRO is built for small shops that already outgrew '
              'spreadsheets and need to know what to restock in the stockroom '
              'and on the shelf.',
      paywallFreeUsage: 'You have {count} of {limit} free products left',
      paywallFreeUsagePro: 'BodegaFlow PRO is active: unlimited products',
      paywallLimitReached:
          'You reached the {limit} product limit of the free version',
      paywallColumnFeature: 'Feature',
      paywallColumnFree: 'Free',
      paywallColumnPro: 'PRO',
      paywallBuy: 'Upgrade to PRO',
      paywallRestore: 'Restore purchases',
      paywallAlreadyPro: 'You already have BodegaFlow PRO',
      paywallClose: 'Continue',
      paywallPriceLoading: 'Fetching price on Google Play…',
      paywallPriceUnavailable: 'Price unavailable',
      paywallLegal:
          'Monthly subscription handled by Google Play. It renews automatically '
              'until you cancel it from your Google account settings.',
      paywallOsaLocked:
          'OSA metrics and restocking are exclusive to BodegaFlow PRO',
      paywallPdfLocked: 'PDF report export is exclusive to BodegaFlow PRO',
      paywallNoticePurchased: 'All set! You now have BodegaFlow PRO',
      paywallNoticePending: 'The purchase is still pending confirmation',
      paywallNoticePrice: 'We could not fetch the price from Google Play',
      paywallNoticeFailed: 'The purchase could not be completed',
      paywallNoticeNothingToRestore:
          'We found no active purchase on Google Play',
      paywallFeatureProducts: 'Catalog products',
      paywallFeatureScanner: 'Barcode & QR scanner',
      paywallFeatureLowStock: 'Low stock alerts',
      paywallFeatureLabels: 'Label printing',
      paywallFeatureOsa: 'On-shelf availability metrics',
      paywallFeaturePdf: 'PDF report export',
      paywallValueUpTo: 'Up to {limit}',
      paywallValueUnlimited: 'Unlimited',
      paywallValueIncluded: 'Included',
      paywallValueLocked: 'Locked',
      paywallValueAdvanced: 'Advanced',
      paywallValueComplete: 'Full',
    },
  };

  static const List<Locale> supportedLocales = [Locale(es), Locale(en)];

  /// Traducción de [key] para el código de idioma [languageCode]. Los locales
  /// no soportados resuelven a español; una clave desconocida se devuelve tal
  /// cual.
  static String translate(String languageCode, String key) {
    final table = translations[languageCode];
    final value = table?[key];
    if (value != null) return value;
    final fallback = translations[es]?[key];
    return fallback ?? key;
  }

  /// Interpola la traducción de [key] reemplazando `{param}` con [args].
  static String interpolate(
    String languageCode,
    String key, {
    Map<String, Object> args = const {},
  }) {
    var value = translate(languageCode, key);
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }
}