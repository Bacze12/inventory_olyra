import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/pro_provider.dart';
import 'package:scanflow/features/printer/label_print_service.dart';
import 'package:scanflow/features/printer/printer_screen.dart';
import 'package:scanflow/features/products/product_provider.dart';

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository(this._products) : super(AppDatabase.instance);

  final List<Product> _products;

  @override
  Future<List<Product>> all({String? query}) async => _products;
}

Product _product(
  String name,
  String barcode, {
  int quantity = 5,
  int minStock = 2,
}) =>
    Product(
      name: name,
      barcode: barcode,
      quantity: quantity,
      minStock: minStock,
      createdAt: '2026-01-01T00:00:00',
      updatedAt: '2026-01-01T00:00:00',
    );

class _RecordingLabelPrintService extends LabelPrintService {
  final List<List<Product>> printed = [];

  @override
  Future<void> printAllLabels(List<Product> products) async {
    printed.add(products);
  }
}

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
  @override
  Future<int> count() async => 0;

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
  @override
  Future<List<SubscriptionOffer>> loadOffers() async => const [];

  @override
  Future<ProPurchaseResult> purchase(String productId) async =>
      const ProPurchaseResult.notFound();

  @override
  Future<ProPurchaseResult> restorePurchases() async =>
      const ProPurchaseResult.notFound();
}

Widget _buildApp(ProductProvider provider, LabelPrintService labelService) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      home: PrinterScreen(labelService: labelService),
    ),
  );
}

/// Igual que [_buildApp] pero con la licencia PRO a mano, para comprobar que
/// la impresión de etiquetas no consulta el estado de la suscripción.
Widget _buildAppWithPro(
  ProductProvider provider,
  LabelPrintService labelService,
  ProProvider pro,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductProvider>.value(value: provider),
      ChangeNotifierProvider<ProProvider>.value(value: pro),
    ],
    child: MaterialApp(
      home: PrinterScreen(labelService: labelService),
    ),
  );
}

void main() {
  testWidgets('muestra la opción de imprimir todos cuando hay productos',
      (tester) async {
    final provider = ProductProvider(_FakeProductRepository([
      _product('Azúcar', '7501001'),
      _product('Fideo', '7501002'),
    ]));
    await provider.load();

    await tester.pumpWidget(
      _buildApp(provider, const LabelPrintService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Imprimir todos (PDF)'), findsOneWidget);
  });

  testWidgets('oculta la opción de imprimir todos sin productos',
      (tester) async {
    final provider = ProductProvider(_FakeProductRepository(const []));
    await provider.load();

    await tester.pumpWidget(
      _buildApp(provider, const LabelPrintService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Imprimir todos (PDF)'), findsNothing);
  });

  testWidgets('al tocar imprimir todos envía todos los productos del listado',
      (tester) async {
    final products = [
      _product('Azúcar', '7501001'),
      _product('Fideo', '7501002'),
    ];
    final provider = ProductProvider(_FakeProductRepository(products));
    await provider.load();
    final service = _RecordingLabelPrintService();

    await tester.pumpWidget(_buildApp(provider, service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Imprimir todos (PDF)'));
    await tester.pumpAndSettle();

    expect(service.printed, hasLength(1));
    expect(service.printed.single.map((p) => p.barcode).toList(),
        ['7501001', '7501002']);
  });

  testWidgets('la impresión de etiquetas no pide licencia PRO al plan gratuito',
      (tester) async {
    final products = [
      _product('Azúcar', '7501001'),
      _product('Fideo', '7501002'),
    ];
    final provider = ProductProvider(_FakeProductRepository(products));
    await provider.load();
    final service = _RecordingLabelPrintService();
    final pro = ProProvider(
      productRepository: _FakeProducts(),
      settingsRepository: _FakeSettings(),
      billing: _FakeBilling(),
    );
    await pro.init();
    expect(pro.esPro, isFalse, reason: 'la prueba arranca en el plan gratuito');

    await tester.pumpWidget(_buildAppWithPro(provider, service, pro));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Imprimir todos (PDF)'));
    await tester.pumpAndSettle();

    expect(service.printed, hasLength(1),
        reason: 'las etiquetas se imprimen igual sin licencia PRO');
    expect(find.text('Suscribirme a PRO'), findsNothing,
        reason: 'la pantalla de etiquetas no abre el paywall');
    expect(find.text('La impresión de reportes PDF es exclusiva de BodegaFlow PRO'),
        findsNothing);
  });
}
