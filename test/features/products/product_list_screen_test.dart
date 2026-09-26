import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/core/i18n/app_strings.dart';
import 'package:scanflow/core/utils/formatters.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/pro_provider.dart';
import 'package:scanflow/features/products/product_list_screen.dart';
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

/// Catálogo en memoria que se comporta como la base: el `insert` asigna id y el
/// `delete` saca la fila, así que el contador de cuota y la lista leen lo mismo.
class _FakeProducts implements ProductRepository {
  final List<Product> _rows = [];
  int _nextId = 1;

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<List<Product>> all({String? query}) async => List.of(_rows);

  @override
  Future<List<Product>> lowStock() async =>
      _rows.where((product) => product.isLowStock).toList();

  @override
  Future<Product?> byId(int id) async {
    for (final product in _rows) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  Future<Product?> byBarcode(String barcode) async {
    for (final product in _rows) {
      if (product.barcode == barcode) return product;
    }
    return null;
  }

  @override
  Future<int> insert(Product product) async {
    final row =
        product.id == null ? product.copyWith(id: _nextId) : product;
    _nextId++;
    _rows.add(row);
    return row.id!;
  }

  @override
  Future<int> update(Product product) async => 1;

  @override
  Future<int> delete(int id) async {
    final before = _rows.length;
    _rows.removeWhere((product) => product.id == id);
    return before - _rows.length;
  }
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

/// Los providers van por encima del [MaterialApp] para que las rutas que se
/// empujan, como el paywall, también los hereden.
Widget _buildApp({required ProductProvider products, required ProProvider pro}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductProvider>.value(value: products),
        ChangeNotifierProvider<ProProvider>.value(value: pro),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: ProductListScreen()),
      ),
    );

void main() {
  late _FakeProducts repository;
  late _FakeSettings settings;
  late ProductProvider products;
  late ProProvider pro;

  setUp(() {
    repository = _FakeProducts();
    settings = _FakeSettings();
    products = ProductProvider(repository);
    pro = ProProvider(
      productRepository: repository,
      settingsRepository: settings,
      billing: _NoBilling(),
    );
  });

  Future<void> seed(String name, String barcode) {
    final now = nowIso();
    return repository.insert(Product(
      name: name,
      barcode: barcode,
      quantity: 4,
      minStock: 2,
      createdAt: now,
      updatedAt: now,
    ));
  }

  testWidgets('eliminar un producto libera el cupo y actualiza el contador',
      (tester) async {
    await seed('Leche', '7801234000007');
    await seed('Agua', '7801234000014');
    await pro.init();
    expect(pro.productCount, 2);

    await tester.pumpWidget(_buildApp(products: products, pro: pro));
    await tester.pumpAndSettle();
    expect(find.text('Leche'), findsOneWidget);

    await tester.drag(find.text('Leche'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar producto'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(await repository.count(), 1);
    expect(products.products.map((product) => product.name), ['Agua']);
    expect(pro.productCount, 1,
        reason: 'el contador de cuota debe seguir al catálogo, también al borrar');
    expect(pro.remainingFreeSlots, AppConstants.freeProductLimit - 1);
  });
}
