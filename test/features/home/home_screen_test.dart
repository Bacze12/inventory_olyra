import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/core/i18n/app_strings.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/home/home_screen.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/pro_provider.dart';
import 'package:scanflow/features/products/product_provider.dart';

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository() : super(AppDatabase.instance);

  @override
  Future<List<Product>> all({String? query}) async => const [];

  @override
  Future<List<Product>> lowStock() async => const [];
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

class _FakeBilling implements BillingGateway {
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
  Future<ProPurchaseResult> purchase(String productId) async =>
      const ProPurchaseResult.notFound();

  @override
  Future<ProPurchaseResult> restorePurchases() async =>
      const ProPurchaseResult.notFound();
}

/// Los providers van por encima del [MaterialApp] para que el paywall, que se
/// empuja como ruta nueva, herede la licencia.
Widget _buildApp(ProProvider pro, ProductProvider products) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProProvider>.value(value: pro),
        ChangeNotifierProvider<ProductProvider>.value(value: products),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    );

void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeSettings settings;
  late _FakeBilling billing;
  late ProProvider pro;
  late ProductProvider products;

  setUp(() async {
    settings = _FakeSettings();
    billing = _FakeBilling();
    pro = ProProvider(
      productRepository: _FakeProductRepository(),
      settingsRepository: settings,
      billing: billing,
    );
    products = ProductProvider(_FakeProductRepository());
    await pro.init();
    await products.load();
  });

  testWidgets('ofrece el acceso a métricas OSA con distintivo PRO en la versión gratis',
      (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(_buildApp(pro, products));
    await tester.pumpAndSettle();

    expect(find.text('Métricas OSA'), findsOneWidget);
    expect(find.byKey(const Key('menuProBadge')), findsOneWidget);
  });

  testWidgets('sin licencia PRO el acceso a métricas OSA abre el paywall',
      (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(_buildApp(pro, products));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Métricas OSA'));
    await tester.pumpAndSettle();

    expect(find.text('Suscribirme a PRO'), findsOneWidget,
        reason: 'el menú OSA pasa por ProGate antes de navegar');
    expect(find.text('Estamos calculando tu primera medición'), findsNothing,
        reason: 'el módulo no debe quedar visible sin licencia');
  });

  testWidgets('con licencia PRO el acceso a métricas OSA abre el módulo',
      (tester) async {
    useTallViewport(tester);
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    await pro.init();

    await tester.pumpWidget(_buildApp(pro, products));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Métricas OSA'));
    await tester.pumpAndSettle();

    expect(find.text('Estamos calculando tu primera medición'), findsOneWidget);
    expect(find.text('Suscribirme a PRO'), findsNothing);
    expect(find.byKey(const Key('menuProBadge')), findsNothing,
        reason: 'con licencia el distintivo de bloqueo ya no aplica');
  });
}
