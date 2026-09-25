import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/pro_provider.dart';
import 'package:scanflow/features/settings/language_provider.dart';
import 'package:scanflow/features/settings/settings_screen.dart';

class _InMemorySettings implements SettingsRepository {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<String> getOr(String key, String fallback) async {
    final value = _store[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }
}

class _CountingProducts implements ProductRepository {
  int total = 0;

  @override
  Future<int> count() async => total;

  @override
  Future<List<Product>> all({String? query}) async => const [];

  @override
  Future<List<Product>> lowStock() async => const [];

  @override
  Future<Product?> byId(int id) async => null;

  @override
  Future<Product?> byBarcode(String barcode) async => null;

  @override
  Future<int> insert(Product product) async => 0;

  @override
  Future<int> update(Product product) async => 0;

  @override
  Future<int> delete(int id) async => 0;
}

class _NoBilling implements BillingGateway {
  @override
  Future<List<SubscriptionOffer>> loadOffers() async => const [];

  @override
  Future<ProPurchaseResult> purchase(String productId) async =>
      const ProPurchaseResult.notFound();

  @override
  Future<ProPurchaseResult> restorePurchases() async =>
      const ProPurchaseResult.notFound();
}

Future<void> Function(Uri) _recordingOpener(List<String> opened) =>
    (uri) async => opened.add(uri.toString());

/// Los providers van por encima del [MaterialApp] para que el paywall, que se
/// empuja como ruta nueva, también los herede.
Widget _buildApp(
  LanguageProvider provider, {
  Future<void> Function(Uri)? linkOpener,
  ProProvider? pro,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LanguageProvider>.value(value: provider),
        ChangeNotifierProvider<ProProvider>.value(
          value: pro ??
              ProProvider(
                productRepository: _CountingProducts(),
                settingsRepository: _InMemorySettings(),
                billing: _NoBilling(),
              ),
        ),
      ],
      child: MaterialApp(
        locale: provider.locale,
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsScreen(linkOpener: linkOpener),
      ),
    );

void main() {
  late _InMemorySettings repository;

  setUp(() {
    repository = _InMemorySettings();
  });

  testWidgets('muestra el panel de ajustes con Español y English',
      (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('al elegir English persiste la selección', (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(provider.locale.languageCode, 'en');
    expect(
      await repository.get(AppConstants.settingLanguage),
      'en',
      reason: 'la selección debe quedar persistida para el próximo arranque',
    );
  });

  testWidgets('al volver a Español revierte el idioma persistido',
      (tester) async {
    repository.set(AppConstants.settingLanguage, 'en');
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();

    expect(provider.locale.languageCode, 'es');
    expect(await repository.get(AppConstants.settingLanguage), 'es');
  });

  testWidgets('muestra la sección de privacidad y términos', (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    expect(find.text('Privacidad y Términos'), findsOneWidget);
    expect(find.text('Política de Privacidad'), findsOneWidget);
    expect(find.text('Términos y Condiciones'), findsOneWidget);
  });

  testWidgets('en inglés muestra la sección de privacidad y términos traducida',
      (tester) async {
    repository.set(AppConstants.settingLanguage, 'en');
    final provider = LanguageProvider(repository);
    await provider.init();

    await tester.pumpWidget(_buildApp(provider));

    expect(find.text('Privacy & Terms'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms & Conditions'), findsOneWidget);
  });

  testWidgets('al tocar Política de Privacidad abre el enlace de privacidad',
      (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();
    final opened = <String>[];

    await tester.pumpWidget(
      _buildApp(provider, linkOpener: _recordingOpener(opened)),
    );

    await tester.tap(find.text('Política de Privacidad'));
    await tester.pumpAndSettle();

    expect(opened, [AppConstants.privacyUrl]);
  });

  testWidgets('al tocar Términos y Condiciones abre el enlace de términos',
      (tester) async {
    final provider = LanguageProvider(repository);
    await provider.init();
    final opened = <String>[];

    await tester.pumpWidget(
      _buildApp(provider, linkOpener: _recordingOpener(opened)),
    );

    await tester.tap(find.text('Términos y Condiciones'));
    await tester.pumpAndSettle();

    expect(opened, [AppConstants.termsUrl]);
  });

  testWidgets('muestra el plan gratis con los cupos que quedan', (tester) async {
    final products = _CountingProducts()..total = 12;
    final provider = LanguageProvider(repository);
    await provider.init();
    final pro = ProProvider(
      productRepository: products,
      settingsRepository: repository,
      billing: _NoBilling(),
    );
    await pro.init();

    await tester.pumpWidget(_buildApp(provider, pro: pro));

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Gratis'), findsOneWidget);
    expect(find.text('Te quedan 18 de 30 productos gratis'), findsOneWidget);
  });

  testWidgets('con licencia PRO muestra el plan PRO activo', (tester) async {
    repository.set(AppConstants.settingPro, AppConstants.proEnabled);
    final provider = LanguageProvider(repository);
    await provider.init();
    final pro = ProProvider(
      productRepository: _CountingProducts(),
      settingsRepository: repository,
      billing: _NoBilling(),
    );
    await pro.init();

    await tester.pumpWidget(_buildApp(provider, pro: pro));

    expect(find.text('BodegaFlow PRO'), findsOneWidget);
    expect(find.text('Gratis'), findsNothing);
  });

  testWidgets('al tocar el plan abre el paywall', (tester) async {
    // El paywall es alto: con el viewport de test por debajo queda fuera de la
    // vista y `ListView` no construye el encabezado.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = LanguageProvider(repository);
    await provider.init();
    final pro = ProProvider(
      productRepository: _CountingProducts(),
      settingsRepository: repository,
      billing: _NoBilling(),
    );
    await pro.init();

    await tester.pumpWidget(_buildApp(provider, pro: pro));

    await tester.tap(find.text('Gratis'));
    await tester.pumpAndSettle();

    expect(find.text('Tu bodega, sin límites'), findsOneWidget);
    expect(find.text('Suscribirme a PRO'), findsOneWidget);
  });
}