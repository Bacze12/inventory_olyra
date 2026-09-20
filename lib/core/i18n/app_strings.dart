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
  static const String homeSettings = 'home.settings';
  static const String settingsTitle = 'settings.title';
  static const String settingsLanguage = 'settings.language';
  static const String settingsLegal = 'settings.legal';
  static const String settingsPrivacy = 'settings.privacy';
  static const String settingsTerms = 'settings.terms';

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
      homeSettings: 'Ajustes',
      settingsTitle: 'Ajustes',
      settingsLanguage: 'Idioma',
      settingsLegal: 'Privacidad y Términos',
      settingsPrivacy: 'Política de Privacidad',
      settingsTerms: 'Términos y Condiciones',
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
      homeSettings: 'Settings',
      settingsTitle: 'Settings',
      settingsLanguage: 'Language',
      settingsLegal: 'Privacy & Terms',
      settingsPrivacy: 'Privacy Policy',
      settingsTerms: 'Terms & Conditions',
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