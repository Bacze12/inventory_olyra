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
import 'package:scanflow/features/pro/pro_provider.dart';
import 'package:scanflow/features/products/product_form_screen.dart';
import 'package:scanflow/features/products/product_provider.dart';

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
  final List<Product> inserted = [];
  final List<Product> updated = [];

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
  Future<int> insert(Product product) async {
    inserted.add(product);
    total++;
    return total;
  }

  @override
  Future<int> update(Product product) async {
    updated.add(product);
    return 1;
  }

  @override
  Future<int> delete(int id) async => 0;
}

class _FakeBilling implements BillingGateway {
  ProPurchaseResult purchaseResult = const ProPurchaseResult.purchased();

  @override
  Future<List<SubscriptionOffer>> loadOffers() async => const [
        SubscriptionOffer(
          productId: AppConstants.proProductId,
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

/// El paywall es una pantalla larga: con el viewport de test por defecto los
/// botones de compra quedan fuera de la vista y `ListView` no los construye.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _FormHarness extends StatelessWidget {
  const _FormHarness({required this.products, this.existing});

  final ProductProvider products;
  final Product? existing;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProductProvider>.value(
      value: products,
      child: Scaffold(
        body: ProductFormScreen(product: existing),
      ),
    );
  }
}

Widget _buildApp({required ProductProvider products, Product? existing}) =>
    MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _FormHarness(products: products, existing: existing),
    );

void main() {
  late _FakeProducts repository;
  late _FakeSettings settings;
  late _FakeBilling billing;
  late ProductProvider products;
  late ProProvider pro;

  setUp(() {
    repository = _FakeProducts();
    settings = _FakeSettings();
    billing = _FakeBilling();
    products = ProductProvider(repository);
    pro = ProProvider(
      productRepository: repository,
      settingsRepository: settings,
      billing: billing,
    );
  });

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'), 'Agua mineral');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código de barras'), '7801234567890');
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar producto'));
    await tester.pumpAndSettle();
  }

  testWidgets('registra el producto cuando la versión gratuita tiene cupo',
      (tester) async {
    repository.total = 5;
    await pro.init();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProProvider>.value(value: pro),
        ],
        child: _buildApp(products: products),
      ),
    );

    await fillForm(tester);
    await tapSave(tester);

    expect(repository.inserted, hasLength(1));
    expect(repository.inserted.single.name, 'Agua mineral');
  });

  testWidgets('bloquea el alta y abre el paywall al llegar a 30 productos',
      (tester) async {
    useTallViewport(tester);
    repository.total = 30;
    await pro.init();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProProvider>.value(value: pro),
        ],
        child: _buildApp(products: products),
      ),
    );

    await fillForm(tester);
    await tapSave(tester);

    expect(repository.inserted, isEmpty,
        reason: 'la versión gratuita no debe pasar de 30 productos');
    expect(find.text('Suscribirme a PRO'), findsOneWidget);
  });

  testWidgets('tras suscribirse en el paywall el alta se guarda',
      (tester) async {
    useTallViewport(tester);
    repository.total = 30;
    await pro.init();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProProvider>.value(value: pro),
        ],
        child: _buildApp(products: products),
      ),
    );

    await fillForm(tester);
    await tapSave(tester);

    await tester.tap(find.text('Suscribirme a PRO'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(pro.esPro, isTrue);
    expect(repository.inserted, hasLength(1),
        reason: 'el guardado interrumpido debe continuar solo tras suscribirse');
    expect(repository.inserted.single.name, 'Agua mineral');
  });

  testWidgets('editar un producto existente no se bloquea por el límite',
      (tester) async {
    useTallViewport(tester);
    repository.total = 30;
    await pro.init();
    final existing = Product(
      id: 7,
      name: 'Leche',
      barcode: '7801234000007',
      quantity: 4,
      minStock: 2,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProProvider>.value(value: pro),
        ],
        child: _buildApp(products: products, existing: existing),
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'), 'Leche entera');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    expect(find.text('Suscribirme a PRO'), findsNothing);
    expect(repository.updated, hasLength(1));
    expect(repository.updated.single.name, 'Leche entera');
  });

  testWidgets('con licencia PRO el límite de 30 no aplica', (tester) async {
    useTallViewport(tester);
    repository.total = 120;
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    await pro.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProProvider>.value(value: pro),
        ],
        child: _buildApp(products: products),
      ),
    );

    await fillForm(tester);
    await tapSave(tester);

    expect(repository.inserted, hasLength(1));
    expect(find.text('Suscribirme a PRO'), findsNothing);
  });
}
