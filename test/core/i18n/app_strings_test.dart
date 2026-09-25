import 'package:flutter_test/flutter_test.dart';

import 'package:scanflow/core/i18n/app_strings.dart';

void main() {
  test('es y en definen exactamente las mismas claves', () {
    expect(
      AppStrings.translations[AppStrings.es]!.keys.toSet(),
      AppStrings.translations[AppStrings.en]!.keys.toSet(),
    );
  });

  test('translate devuelve la traducción en inglés cuando se pide en', () {
    expect(
      AppStrings.translate(AppStrings.en, AppStrings.homeHeroTitle),
      'Inventory at a glance',
    );
  });

  test('translate: idioma desconocido cae a español', () {
    expect(
      AppStrings.translate('fr', AppStrings.homeHeroTitle),
      'Inventario al instante',
    );
  });

  test('translate: clave desconocida se devuelve tal cual', () {
    expect(AppStrings.translate(AppStrings.es, 'clave.inexistente'),
        'clave.inexistente');
  });

  test('el botón de exportar reporte está traducido en ambos idiomas', () {
    expect(
      AppStrings.translate(AppStrings.es, AppStrings.reportGeneratePdf),
      'Generar reporte PDF',
    );
    expect(
      AppStrings.translate(AppStrings.en, AppStrings.reportGeneratePdf),
      isNot('Generar reporte PDF'),
      reason: 'en inglés la etiqueta tiene que estar traducida, no copiada del ES',
    );
    expect(
      AppStrings.translate(AppStrings.en, AppStrings.reportGeneratePdf),
      'Generate PDF report',
    );
  });

  test('la impresión de etiquetas se anuncia como incluida en ambos planes', () {
    expect(
      AppStrings.translate(AppStrings.es, AppStrings.paywallFeatureLabels),
      'Impresión de etiquetas',
    );
    expect(
      AppStrings.translate(AppStrings.en, AppStrings.paywallFeatureLabels),
      'Label printing',
    );
  });

  test('interpolate reemplaza los parámetros en la traducción', () {
    expect(
      AppStrings.interpolate(
        AppStrings.es,
        AppStrings.homeLowStock,
        args: const {'count': 3},
      ),
      '3 producto(s) llegaron a su stock mínimo',
    );
    expect(
      AppStrings.interpolate(
        AppStrings.en,
        AppStrings.homeLowStock,
        args: const {'count': 5},
      ),
      '5 product(s) reached minimum stock',
    );
  });
}