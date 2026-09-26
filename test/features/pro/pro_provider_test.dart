import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/core/utils/formatters.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/pro/billing.dart';
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

class _FakeBilling implements BillingGateway {
  final List<String> purchasedIds = [];
  int restoreCalls = 0;

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
  Object? loadOffersError;

  @override
  Future<List<SubscriptionOffer>> loadOffers() async {
    if (loadOffersError != null) throw loadOffersError!;
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

void main() {
  late ProductRepository products;
  late _FakeSettings settings;
  late _FakeBilling billing;
  late Directory tempDir;

  Future<void> seedProducts(int total) async {
    final now = nowIso();
    for (var i = 0; i < total; i++) {
      await products.insert(Product(
        name: 'Producto $i',
        barcode: '780123456${i.toString().padLeft(4, '0')}',
        quantity: 10,
        minStock: 2,
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  ProProvider buildProvider() => ProProvider(
        productRepository: products,
        settingsRepository: settings,
        billing: billing,
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_pro_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    products = ProductRepository(AppDatabase.instance);
    final db = await AppDatabase.instance.database;
    await db.delete('products');
    await db.delete('movements');
    await db.delete('settings');
    settings = _FakeSettings();
    billing = _FakeBilling();
  });

  test('sin licencia persistida la app arranca en la versión gratuita', () async {
    final provider = buildProvider();
    await provider.init();

    expect(provider.esPro, isFalse);
  });

  test('init recupera la licencia PRO guardada en el dispositivo', () async {
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);

    final provider = buildProvider();
    await provider.init();

    expect(provider.esPro, isTrue,
        reason: 'un usuario que ya pagó debe conservar sus derechos al reiniciar');
  });

  test('con el catálogo vacío la versión gratuita puede registrar', () async {
    final provider = buildProvider();
    await provider.init();

    expect(await provider.canRegisterProduct(), isTrue);
  });

  test('con 29 productos la versión gratuita alcanza para el 30', () async {
    await seedProducts(29);
    final provider = buildProvider();
    await provider.init();

    expect(await provider.canRegisterProduct(), isTrue);
    expect(provider.remainingFreeSlots, 1);
  });

  test('con 30 productos la versión gratuita frena el registro', () async {
    await seedProducts(30);
    final provider = buildProvider();
    await provider.init();

    expect(await provider.canRegisterProduct(), isFalse,
        reason: 'el límite gratuito es de 30 productos registrados');
  });

  test('con licencia PRO el registro nunca se frena', () async {
    await seedProducts(30);
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    final provider = buildProvider();
    await provider.init();

    expect(await provider.canRegisterProduct(), isTrue);
  });

  test('remainingFreeSlots nunca baja de cero con más de 30 productos', () async {
    await seedProducts(34);
    final provider = buildProvider();
    await provider.init();

    expect(provider.remainingFreeSlots, 0);
    expect(await provider.canRegisterProduct(), isFalse);
  });

  test('remainingFreeSlots es nulo para la licencia PRO', () async {
    await settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    final provider = buildProvider();
    await provider.init();

    expect(provider.remainingFreeSlots, isNull,
        reason: 'PRO no tiene cupo porque los productos son ilimitados');
  });

  test('canRegisterProduct cuenta el catálogo local antes de decidir', () async {
    final provider = buildProvider();
    await provider.init();
    expect(provider.productCount, 0);

    await seedProducts(30);
    expect(await provider.canRegisterProduct(), isFalse);
    expect(provider.productCount, 30);
  });

  test('canRegisterProduct notifica a los listeners con el conteo', () async {
    final provider = buildProvider();
    await provider.init();

    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.canRegisterProduct();

    expect(notifications, greaterThan(0));
  });

  test('refreshProductCount descuenta el cupo al guardar un producto nuevo',
      () async {
    final provider = buildProvider();
    await provider.init();
    expect(provider.remainingFreeSlots, AppConstants.freeProductLimit);

    await seedProducts(1);
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.refreshProductCount();

    expect(provider.productCount, 1);
    expect(provider.remainingFreeSlots, AppConstants.freeProductLimit - 1,
        reason: 'el cupo libre debe bajar apenas el catálogo crece');
    expect(notifications, greaterThan(0),
        reason: 'la UI se entera del nuevo conteo por notifyListeners');
  });

  test('refreshProductCount libera el cupo al eliminar un producto', () async {
    await seedProducts(30);
    final provider = buildProvider();
    await provider.init();
    expect(provider.remainingFreeSlots, 0);
    expect(await provider.canRegisterProduct(), isFalse);

    final catalog = await products.all();
    await products.delete(catalog.first.id!);
    await provider.refreshProductCount();

    expect(provider.productCount, 29);
    expect(provider.remainingFreeSlots, 1);
    expect(await provider.canRegisterProduct(), isTrue,
        reason: 'eliminar un producto devuelve un cupo al plan gratuito');
  });

  test('purchasePro compra la suscripción publicada por la tienda', () async {
    final provider = buildProvider();
    await provider.init();

    expect(await provider.purchasePro(), isTrue);
    expect(billing.purchasedIds, [AppConstants.proProductId]);
  });

  test('purchasePro deja esPro en true y avisa la compra', () async {
    final provider = buildProvider();
    await provider.init();

    await provider.purchasePro();

    expect(provider.esPro, isTrue);
    expect(provider.notice, ProNotice.purchased);
  });

  test('purchasePro persiste la licencia para el próximo arranque', () async {
    final provider = buildProvider();
    await provider.init();
    await provider.purchasePro();

    expect(await settings.get(AppConstants.settingPro),
        AppConstants.proEnabled);

    final reopened = buildProvider();
    await reopened.init();
    expect(reopened.esPro, isTrue);
  });

  test('purchasePro no guarda licencia si la compra queda pendiente', () async {
    billing.purchaseResult = const ProPurchaseResult.pending();
    final provider = buildProvider();
    await provider.init();

    expect(await provider.purchasePro(), isFalse);
    expect(provider.esPro, isFalse);
    expect(provider.notice, ProNotice.pending);
    expect(await settings.get(AppConstants.settingPro), isNull);
  });

  test('purchasePro no guarda licencia si Google Play rechaza el pago', () async {
    billing.purchaseResult = ProPurchaseResult.failed('tarjeta rechazada');
    final provider = buildProvider();
    await provider.init();

    expect(await provider.purchasePro(), isFalse);
    expect(provider.esPro, isFalse);
    expect(provider.notice, ProNotice.purchaseFailed);
  });

  test('purchasePro avisa cuando la tienda no publica el precio', () async {
    billing.offers = const [];
    final provider = buildProvider();
    await provider.init();

    expect(await provider.purchasePro(), isFalse);
    expect(provider.notice, ProNotice.priceUnavailable);
    expect(billing.purchasedIds, isEmpty,
        reason: 'sin precio conocido no se puede abrir el flujo de pago');
  });

  test('purchasePro avisa cuando la consulta de la tienda falla', () async {
    billing.loadOffersError = StateError('sin conexión');
    final provider = buildProvider();
    await provider.init();

    expect(await provider.purchasePro(), isFalse);
    expect(provider.notice, ProNotice.priceUnavailable);
  });

  test('purchasePro consulta el precio una sola vez entre intentos', () async {
    final provider = buildProvider();
    await provider.init();

    await provider.purchasePro();
    await provider.purchasePro();

    expect(billing.purchasedIds, [AppConstants.proProductId, AppConstants.proProductId]);
  });

  test('restorePurchases reactiva la licencia de otro dispositivo', () async {
    final provider = buildProvider();
    await provider.init();

    expect(await provider.restorePurchases(), isTrue);
    expect(billing.restoreCalls, 1);
    expect(provider.esPro, isTrue);
    expect(provider.notice, ProNotice.purchased);
  });

  test('restorePurchases avisa cuando no hay compras previas', () async {
    billing.restoreResult = const ProPurchaseResult.notFound();
    final provider = buildProvider();
    await provider.init();

    expect(await provider.restorePurchases(), isFalse);
    expect(provider.esPro, isFalse);
    expect(provider.notice, ProNotice.nothingToRestore);
  });

  test('el precio publicado por la tienda queda disponible para la UI', () async {
    final provider = buildProvider();
    await provider.init();
    await provider.purchasePro();

    expect(provider.offers, hasLength(1));
    expect(provider.offers.first.price, 'CLP 2.990');
    expect(provider.offers.first.title, 'BodegaFlow PRO');
  });
}
