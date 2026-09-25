import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:scanflow/features/reports/report_provider.dart';
import 'package:scanflow/features/reports/report_screen.dart';

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

/// El provider va por encima del [MaterialApp] para que el paywall, que se
/// empuja como ruta nueva, también herede la licencia.
Widget _buildApp(ProProvider pro, ReportProvider report) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProProvider>.value(value: pro),
        ChangeNotifierProvider<ReportProvider>.value(value: report),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ReportScreen(),
      ),
    );

/// La pantalla de reporte muestra un `PdfPreview`: sin este canal simulado,
/// `Printing.info()` lanza `MissingPluginException` en el test.
void stubPrintingChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('net.nfet.printing'),
    (_) async => <String, dynamic>{},
  );
}

void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeProducts products;
  late _FakeSettings settings;
  late _FakeBilling billing;

  ProProvider buildPro() => ProProvider(
        productRepository: products,
        settingsRepository: settings,
        billing: billing,
      );

  ReportProvider buildReport() => ReportProvider(
        productRepository: products,
        settingsRepository: settings,
      );

  setUp(() {
    products = _FakeProducts();
    settings = _FakeSettings();
    billing = _FakeBilling();
    stubPrintingChannel();
  });

  testWidgets('sin licencia PRO la exportación abre el paywall y no genera el PDF',
      (tester) async {
    useTallViewport(tester);
    final pro = buildPro();
    await pro.init();
    final report = buildReport();
    await report.init();

    await tester.pumpWidget(_buildApp(pro, report));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generar reporte PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Suscribirme a PRO'), findsOneWidget,
        reason: 'el botón de exportar está protegido por ProGate');
    expect(
      find.text('La exportación de reportes PDF es exclusiva de BodegaFlow PRO'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Guardar'), findsNothing,
        reason: 'sin licencia no debe quedar un reporte generado');
    expect(find.text('Genera el reporte para verlo en pantalla.'), findsOneWidget);
  });

  testWidgets('con licencia PRO la exportación genera el reporte sin paywall',
      (tester) async {
    useTallViewport(tester);
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    final pro = buildPro();
    await pro.init();
    final report = buildReport();
    await report.init();

    await tester.pumpWidget(_buildApp(pro, report));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generar reporte PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Suscribirme a PRO'), findsNothing);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Compartir'), findsOneWidget);
    expect(find.text('Imprimir'), findsOneWidget);
    expect(find.text('Genera el reporte para verlo en pantalla.'), findsNothing);
  });

  testWidgets('marca la exportación como función PRO solo en la versión gratis',
      (tester) async {
    useTallViewport(tester);
    final pro = buildPro();
    await pro.init();
    final report = buildReport();
    await report.init();

    await tester.pumpWidget(_buildApp(pro, report));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reportProBadge')), findsOneWidget);

    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    await pro.init();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reportProBadge')), findsNothing,
        reason: 'con licencia activa el aviso de bloqueo sobra');
  });
}
