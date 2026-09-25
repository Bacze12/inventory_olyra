import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/core/i18n/app_strings.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/paywall_screen.dart';
import 'package:scanflow/features/pro/pro_provider.dart';

class _FakeSettings implements SettingsRepository {
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

class _FakeProducts implements ProductRepository {
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

class _FakeBilling implements BillingGateway {
  final List<String> purchasedIds = [];
  int restoreCalls = 0;
  int loadOffersCalls = 0;

  List<SubscriptionOffer> offers = const [
    SubscriptionOffer(
      productId: AppConstants.proProductId,
      title: 'BodegaFlow PRO',
      description: 'Suscripción mensual',
      price: 'CLP 2.990',
    ),
  ];

  ProPurchaseResult purchaseResult = const ProPurchaseResult.purchased();
  ProPurchaseResult restoreResult = const ProPurchaseResult.purchased();

  @override
  Future<List<SubscriptionOffer>> loadOffers() async {
    loadOffersCalls++;
    return offers;
  }

  @override
  Future<ProPurchaseResult> purchase(String productId) async {
    purchasedIds.add(productId);
    return purchaseResult;
  }

  @override
  Future<ProPurchaseResult> restorePurchases() async {
    restoreCalls++;
    return restoreResult;
  }
}

class _Harness extends StatelessWidget {
  const _Harness({required this.provider, required this.onResult});

  final ProProvider provider;
  final ValueChanged<bool?> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider<ProProvider>.value(
                  value: provider,
                  child: const PaywallScreen(
                    trigger: PaywallTrigger.productLimit,
                  ),
                ),
              ),
            );
            onResult(result);
          },
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

Widget _buildPaywall(ProProvider provider) => MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<ProProvider>.value(
        value: provider,
        child: const PaywallScreen(trigger: PaywallTrigger.productLimit),
      ),
    );

Widget _buildHarness(ProProvider provider, ValueChanged<bool?> onResult) =>
    MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _Harness(provider: provider, onResult: onResult),
    );

/// El paywall es una pantalla larga: con el viewport de test por defecto la
/// tabla comparativa y los botones quedan fuera de la vista y `ListView` no los
/// construye.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeProducts products;
  late _FakeSettings settings;
  late _FakeBilling billing;

  ProProvider buildProvider() => ProProvider(
        productRepository: products,
        settingsRepository: settings,
        billing: billing,
      );

  setUp(() {
    products = _FakeProducts();
    settings = _FakeSettings();
    billing = _FakeBilling();
  });

  testWidgets('compara Gratis vs PRO con las funciones clave', (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.text('Gratis'), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('Productos en el catálogo'), findsOneWidget);
    expect(find.text('Lector de códigos y QR'), findsOneWidget);
    expect(find.text('Alertas de stock bajo'), findsOneWidget);
    expect(find.text('Métricas OSA y reposición'), findsOneWidget);
    expect(find.text('Exportación de reportes PDF'), findsOneWidget);
  });

  testWidgets('el plan gratuito muestra los límites de la versión Free',
      (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.text('Hasta 30'), findsOneWidget);
    expect(find.text('Ilimitados'), findsOneWidget);
    expect(find.text('Bloqueado'), findsNWidgets(2),
        reason: 'las métricas OSA y el PDF están bloqueadas en la versión gratis');
    expect(find.text('Avanzado'), findsOneWidget);
  });

  testWidgets('destaca con un icono los tres beneficios de PRO',
      (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bolt), findsNWidgets(3),
        reason: 'productos ilimitados, OSA y PDF son el argumento de venta');
  });

  testWidgets('muestra el precio publicado por Google Play', (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.text('CLP 2.990'), findsOneWidget);
    expect(find.text('BodegaFlow PRO'), findsWidgets);
  });

  testWidgets('muestra los cupos gratuitos que le quedan al usuario',
      (tester) async {
    useTallViewport(tester);
    products.total = 12;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.text('Te quedan 18 de 30 productos gratis'), findsOneWidget);
  });

  testWidgets('explica el motivo del bloqueo al llegar al límite',
      (tester) async {
    useTallViewport(tester);
    products.total = 30;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(
      find.text('Alcanzaste el límite de 30 productos en la versión gratis'),
      findsOneWidget,
    );
    expect(find.text('Te quedan 0 de 30 productos gratis'), findsOneWidget);
  });

  testWidgets('el botón de suscribir compra y confirma con éxito',
      (tester) async {
    useTallViewport(tester);
    bool? result;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildHarness(provider, (value) => result = value));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    expect(billing.purchasedIds, [AppConstants.proProductId]);
    expect(provider.esPro, isTrue);
    expect(find.text('Ya tienes BodegaFlow PRO'), findsOneWidget);
    expect(result, isNull,
        reason: 'la pantalla no se cierra sola: el usuario confirma con Continuar');

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('si la compra falla vuelve al inventario sin licencia',
      (tester) async {
    useTallViewport(tester);
    billing.purchaseResult = ProPurchaseResult.failed('tarjeta rechazada');
    bool? result;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildHarness(provider, (value) => result = value));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    expect(provider.esPro, isFalse);
    expect(result, isNull);
    expect(find.text('No se pudo completar la compra'), findsOneWidget);
  });

  testWidgets('avisa cuando la compra queda pendiente de confirmación',
      (tester) async {
    useTallViewport(tester);
    billing.purchaseResult = const ProPurchaseResult.pending();
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    expect(
      find.text('La compra quedó pendiente de confirmación'),
      findsOneWidget,
    );
  });

  testWidgets('el botón de restaurar busca la licencia en Google Play',
      (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restaurar compras'));
    await tester.pumpAndSettle();

    expect(billing.restoreCalls, 1);
    expect(provider.esPro, isTrue);
    expect(find.text('¡Listo! Ya tienes BodegaFlow PRO'), findsOneWidget);
    expect(find.text('Ya tienes BodegaFlow PRO'), findsOneWidget);
  });

  testWidgets('restaurar desde otra pantalla cierra devolviendo true',
      (tester) async {
    useTallViewport(tester);
    bool? result;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildHarness(provider, (value) => result = value));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restaurar compras'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('avisa cuando Google Play no tiene compras previas',
      (tester) async {
    useTallViewport(tester);
    billing.restoreResult = const ProPurchaseResult.notFound();
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restaurar compras'));
    await tester.pumpAndSettle();

    expect(provider.esPro, isFalse);
    expect(
      find.text('No encontramos ninguna compra activa en Google Play'),
      findsOneWidget,
    );
  });

  testWidgets('avisa cuando la tienda no publica el precio', (tester) async {
    useTallViewport(tester);
    billing.offers = const [];
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos consultar el precio en Google Play'),
      findsOneWidget,
    );
  });

  testWidgets('con licencia PRO muestra el estado activo sin botón de compra',
      (tester) async {
    useTallViewport(tester);
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildPaywall(provider));
    await tester.pumpAndSettle();

    expect(find.text('Ya tienes BodegaFlow PRO'), findsOneWidget);
    expect(find.text('Suscribirme a PRO'), findsNothing);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('traduce toda la pantalla a inglés', (tester) async {
    useTallViewport(tester);
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<ProProvider>.value(
          value: provider,
          child: const PaywallScreen(trigger: PaywallTrigger.productLimit),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Upgrade to PRO'), findsOneWidget);
    expect(find.text('You have 30 of 30 free products left'), findsOneWidget);
    expect(find.text('On-shelf availability metrics'), findsOneWidget);
  });
}
