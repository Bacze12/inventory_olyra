import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/i18n/app_strings.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/pro_gate.dart';
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
  ProPurchaseResult purchaseResult = const ProPurchaseResult.purchased();

  @override
  Future<List<SubscriptionOffer>> loadOffers() async => const [
        SubscriptionOffer(
          productId: 'bodegaflow_pro_monthly',
          title: 'BodegaFlow PRO',
          description: 'Suscripción mensual',
          price: 'CLP 2.990',
        ),
      ];

  @override
  Future<ProPurchaseResult> purchase(String productId) async => purchaseResult;

  @override
  Future<ProPurchaseResult> restorePurchases() async =>
      const ProPurchaseResult.notFound();
}

class _GateHarness extends StatelessWidget {
  const _GateHarness({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final allowed = await ProGate.allowNewProduct(context);
            onResult(allowed);
          },
          child: const Text('registrar'),
        ),
      ),
    );
  }
}

/// El provider va por encima del [MaterialApp] para que el paywall, que se
/// empuja como ruta nueva, también lo herede.
Widget _buildApp(ProProvider provider, ValueChanged<bool> onResult) =>
    ChangeNotifierProvider<ProProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _GateHarness(onResult: onResult),
      ),
    );

/// El paywall es alto: con el viewport por defecto los botones quedan fuera de
/// la vista y `ListView` no los construye.
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

  testWidgets('deja registrar mientras queden cupos gratuitos', (tester) async {
    useTallViewport(tester);
    products.total = 29;
    bool? allowed;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildApp(provider, (value) => allowed = value));

    await tester.tap(find.text('registrar'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(find.text('BodegaFlow PRO'), findsNothing,
        reason: 'con cupo disponible no hay que interrumpir al usuario');
  });

  testWidgets('frena el registro y abre el paywall al agotar los cupos',
      (tester) async {
    useTallViewport(tester);
    products.total = 30;
    bool? allowed;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildApp(provider, (value) => allowed = value));

    await tester.tap(find.text('registrar'));
    await tester.pumpAndSettle();

    expect(find.text('Suscribirme a PRO'), findsOneWidget);
    expect(
      find.text('Alcanzaste el límite de 30 productos en la versión gratis'),
      findsOneWidget,
    );

    // El bloqueo se mantiene mientras el usuario no suscriba.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(allowed, isFalse);
  });

  testWidgets('deja continuar el registro si el usuario se suscribe',
      (tester) async {
    useTallViewport(tester);
    products.total = 30;
    bool? allowed;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildApp(provider, (value) => allowed = value));

    await tester.tap(find.text('registrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    expect(provider.esPro, isTrue);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
  });

  testWidgets('mantiene el bloqueo si el usuario cierra el paywall sin pagar',
      (tester) async {
    useTallViewport(tester);
    products.total = 30;
    billing.purchaseResult = const ProPurchaseResult.notFound();
    bool? allowed;
    final provider = buildProvider();
    await provider.init();

    await tester.pumpWidget(_buildApp(provider, (value) => allowed = value));

    await tester.tap(find.text('registrar'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(provider.esPro, isFalse);
    expect(allowed, isFalse);
  });
}
