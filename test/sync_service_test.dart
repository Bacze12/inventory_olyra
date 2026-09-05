import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/models/sale.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/data/services/pairing_service.dart';
import 'package:scanflow/data/services/sync_service.dart';

class _FakeSettings implements PairingSettingsSource {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FakeSecrets implements PairingSecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_sync_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // La base pudo estar abierta; el SO limpiará el resto.
    }
  });

  setUp(() async {
    final db = await AppDatabase.instance.database;
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('movements');
    await db.delete('products');
    await db.delete('settings');
  });

  int randomPort() => 20000 + Random().nextInt(20000);

  Future<void> seedProducts() async {
    final products = ProductRepository(AppDatabase.instance);
    final t0 = DateTime.now().toIso8601String();
    await products.insert(
      Product(
        name: 'Arroz',
        barcode: '7800000000018',
        quantity: 10,
        minStock: 2,
        price: 1200,
        createdAt: t0,
        updatedAt: t0,
      ),
    );
    await products.insert(
      Product(
        name: 'Azúcar',
        barcode: '7800000000025',
        quantity: 5,
        minStock: 1,
        price: 800,
        createdAt: t0,
        updatedAt: t0,
      ),
    );
  }

  test('servidor local sirve catálogo y recibe ventas deduplicando', () async {
    final db = AppDatabase.instance;
    final products = ProductRepository(db);
    final sales = SalesRepository(db);
    await seedProducts();

    final port = randomPort();
    final server = SyncServer(
      products: products,
      sales: sales,
      tenantId: 'STORE_TEST',
    );
    final started = await server.start(port: port);
    expect(started, isTrue);
    addTearDown(server.stop);

    // --- GET /catalog ---
    final catalog =
        await http.get(
          Uri.parse('http://127.0.0.1:$port/api/v1/sync/catalog'),
          headers: {'x-device-token': 'dvt_reader'},
        );
    expect(catalog.statusCode, 200);
    final body = jsonDecode(catalog.body) as Map<String, dynamic>;
    expect(body['tenant_id'], 'STORE_TEST');
    final productIds =
        (body['products'] as List).cast<Map<String, dynamic>>();
    expect(productIds.length, 2);
    expect(productIds.map((e) => e['barcode']), contains('7800000000018'));

    // --- POST /sales ---
    final sale = SyncedSale(
      deviceToken: 'dvt_phone1',
      method: PaymentMethod.efectivo,
      subtotal: 2400,
      taxRate: 0.19,
      tax: 456,
      total: 2856,
      received: 2856,
      change: 0,
      status: SaleStatus.completada,
      createdAt: DateTime.now().toIso8601String(),
      items: [
        SyncedSaleItem(
          productName: 'Arroz',
          barcode: '7800000000018',
          unitPrice: 1200,
          quantity: 2,
          subtotal: 2400,
        ),
      ],
    );
    final postHeaders = {
      'content-type': 'application/json',
      'x-device-token': 'dvt_phone1',
    };
    final post = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: postHeaders,
      body: jsonEncode([sale.toJson()]),
    );
    expect(post.statusCode, 200);
    final report = jsonDecode(post.body) as Map<String, dynamic>;
    expect(report['inserted'], 1);

    // Reenvío → duplicado, no se inserta otra vez.
    final post2 = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: postHeaders,
      body: jsonEncode([sale.toJson()]),
    );
    final report2 = jsonDecode(post2.body) as Map<String, dynamic>;
    expect(report2['duplicates'], 1);

    expect(
      await sales.findRemoteDuplicate('dvt_phone1', sale.createdAt, sale.total),
      isTrue,
    );

    // Sin token de dispositivo → 401.
    final unauth = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode([sale.toJson()]),
    );
    expect(unauth.statusCode, 401);

    // --- GET /sales: el propio dispositivo NO se re-descarga su venta,
    // pero otro visor sí la ve (historial de la PC).
    final own = await http.get(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: {'x-device-token': 'dvt_phone1'},
    );
    expect(own.statusCode, 200);
    expect((jsonDecode(own.body) as Map<String, dynamic>)['sales'], isEmpty);

    final other = await http.get(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: {'x-device-token': 'dvt_phone2'},
    );
    expect(other.statusCode, 200);
    final otherSales =
        ((jsonDecode(other.body) as Map<String, dynamic>)['sales'] as List)
            .cast<Map<String, dynamic>>();
    expect(otherSales, hasLength(1));
    expect(otherSales.first['device_token'], 'dvt_phone1');
    expect(otherSales.first['items'], isNotEmpty);
  });

  test('el teléfono descarga el historial de la PC, sin duplicados ni reenvío',
      () async {
    final db = AppDatabase.instance;
    final products = ProductRepository(db);
    final sales = SalesRepository(db);
    await seedProducts();

    // Venta ORIGINADA EN LA PC: sin device_token, marcada como del servidor.
    final createdAt = '2026-08-29T10:00:00.000';
    final pcSaleId = await sales.insertSale(
      items: [
        const SaleItem(
          productId: null,
          productName: 'Arroz',
          barcode: '7800000000018',
          unitPrice: 1200,
          quantity: 2,
          subtotal: 2400,
        ),
      ],
      method: PaymentMethod.efectivo,
      subtotal: 2400,
      taxRate: 0.19,
      tax: 456,
      total: 2856,
      received: 2856,
      change: 0,
      deviceToken: null,
      createdAt: createdAt,
    );
    // Pertenece a la PC: nunca es "pendiente de enviar" (el servidor no sube
    // nada). En este test solo hay una BD compartida, así que la marcamos
    // sincronizada para que el teléfono no la re-envíe.
    await sales.markSynced([pcSaleId]);

    final port = randomPort();
    final server = SyncServer(products: products, sales: sales);
    expect(await server.start(port: port), isTrue);
    addTearDown(server.stop);

    final settings = _FakeSettings();
    settings.values[PairingService.kSyncServerUrlKey] =
        'http://127.0.0.1:$port';
    final pairing = PairingService(
      settings: settings,
      secrets: _FakeSecrets(),
    );

    final service =
        SyncService(products: products, sales: sales, pairing: pairing);
    final result = await service.syncNow();

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(result.remoteSalesReceived, 1);

    final history = await sales.getSalesHistory();
    // El seed simula la BD de la PC; la descarga inserta una COPIA nueva en
    // el teléfono (misma fecha original, sin token, sincronizada).
    final downloadedRows = history.where((s) => s.id != pcSaleId).toList();
    expect(downloadedRows, hasLength(1));
    expect(downloadedRows.single.createdAt, createdAt);
    expect(downloadedRows.single.deviceToken, isEmpty);
    expect(downloadedRows.single.synced, isTrue);
    // Nada queda pendiente de re-subir al servidor.
    expect(await sales.listForSync(), isEmpty);
    expect(history.where((s) => !s.synced), isEmpty);

    // Una segunda sincronización no la duplica (dedupe por token+fecha+total).
    final result2 = await service.syncNow();
    expect(result2.isSuccess, isTrue, reason: result2.error);
    expect(result2.remoteSalesReceived, 0);
    expect(await sales.getSalesHistory(), hasLength(history.length));
  });

  test('SyncService descarga el catálogo y sube las ventas pendientes',
      () async {
    final db = AppDatabase.instance;
    final products = ProductRepository(db);
    final sales = SalesRepository(db);
    final settings = _FakeSettings();
    final pairing = PairingService(
      settings: settings,
      secrets: _FakeSecrets(),
    );

    // Catálogo autoritativo en la "PC".
    await seedProducts();

    // Venta local del "teléfono" pendiente de sincronizar.
    final token = await pairing.deviceToken();
    final saleId = await sales.insertSale(
      items: [
        const SaleItem(
          productId: null,
          productName: 'Azúcar',
          barcode: '7800000000025',
          unitPrice: 800,
          quantity: 3,
          subtotal: 2400,
        ),
      ],
      method: PaymentMethod.tarjeta,
      subtotal: 2400,
      taxRate: 0,
      tax: 0,
      total: 2400,
      received: 2400,
      change: 0,
      deviceToken: token,
    );
    final localSale = await sales.byId(saleId);

    // Levantamos el servidor en una IP local y simulamos una URL GUARDADA
    // MALFORMADA (legacy): sin esquema y con slash final. La normalización de
    // `syncServerUrl()` + reescritura en `syncNow()` la deja en
    // `http://127.0.0.1:<port>`.
    final port = randomPort();
    final server = SyncServer(products: products, sales: sales);
    expect(await server.start(port: port), isTrue);
    addTearDown(server.stop);
    settings.values[PairingService.kSyncServerUrlKey] = '127.0.0.1:$port/';

    final service =
        SyncService(products: products, sales: sales, pairing: pairing);
    final result = await service.syncNow();

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(result.catalogSynced, 2);
    expect(result.salesSent, 1);
    // La URL quedó normalizada y persistida en el formato canónico.
    expect(await pairing.syncServerUrl(), 'http://127.0.0.1:$port');

    // La venta quedó marcada como sincronizada...
    final pending = await sales.listForSync();
    expect(pending, isEmpty);

    // ...y quedó registrada (con su token) en el servidor.
    expect(
      await sales.findRemoteDuplicate(token, localSale.createdAt, localSale.total),
      isTrue,
    );
  });

  test('SyncService informa error si no hay servidor configurado', () async {
    final pairing = PairingService(
      settings: _FakeSettings(),
      secrets: _FakeSecrets(),
    );
    final service = SyncService(
      products: ProductRepository(AppDatabase.instance),
      sales: SalesRepository(AppDatabase.instance),
      pairing: pairing,
    );

    final result = await service.syncNow();

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('Servidor no configurado'));
  });

  test('venta remota descuenta stock y marca advertencia si no alcanza',
      () async {
    final db = AppDatabase.instance;
    final products = ProductRepository(db);
    final sales = SalesRepository(db);
    await seedProducts(); // Arroz qty 10, Azúcar qty 5

    final port = randomPort();
    final server = SyncServer(
      products: products,
      sales: sales,
      tenantId: 'STORE_TEST',
    );
    expect(await server.start(port: port), isTrue);
    addTearDown(server.stop);

    final sale = SyncedSale(
      deviceToken: 'dvt_phone_warn',
      method: PaymentMethod.efectivo,
      subtotal: 62400,
      taxRate: 0.19,
      tax: 11856,
      total: 74256,
      received: 74256,
      change: 0,
      status: SaleStatus.completada,
      createdAt: DateTime.now().toIso8601String(),
      items: [
        const SyncedSaleItem(
          productName: 'Arroz',
          barcode: '7800000000018',
          unitPrice: 1200,
          quantity: 2,
          subtotal: 2400,
        ),
        // Pedido mayor al stock: se vende igual pero con advertencia.
        const SyncedSaleItem(
          productName: 'Arroz',
          barcode: '7800000000018',
          unitPrice: 1200,
          quantity: 50,
          subtotal: 60000,
        ),
      ],
    );

    final response = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/sync/sales'),
      headers: {
        'content-type': 'application/json',
        'x-device-token': 'dvt_phone_warn',
      },
      body: jsonEncode([sale.toJson()]),
    );
    expect(response.statusCode, 200);
    final report = jsonDecode(response.body) as Map<String, dynamic>;
    expect(report['inserted'], 1);
    expect(report['stock_warnings'], 1);

    // El ítem con stock suficiente se descontó (10 - 2 = 8); el otro no.
    final arroz = await products.byBarcode('7800000000018');
    expect(arroz!.quantity, 8);

    // La venta quedó persistida con la advertencia visible.
    final history = await sales.getSalesHistory();
    expect(history.single.stockWarning, isTrue);
  });

  test('normalización de URL de sync (esquema, slash final y rutas)', () {
    expect(
      PairingService.normalizeSyncServerUrl('192.168.1.50:8080'),
      'http://192.168.1.50:8080',
    );
    expect(
      PairingService.normalizeSyncServerUrl('http://192.168.1.50:8080/'),
      'http://192.168.1.50:8080',
    );
    expect(
      PairingService.normalizeSyncServerUrl('http://192.168.1.50:8080/x/'),
      'http://192.168.1.50:8080',
    );
    expect(
      PairingService.normalizeSyncServerUrl('192.168.1.50'),
      'http://192.168.1.50:8080',
    );
    expect(PairingService.normalizeSyncServerUrl(''), '');
  });

  test('IP dinámica: falla de red detecta la PC en la subred y reconfigura la '
      'URL de sync', () async {
    final settings = _FakeSettings();
    final secrets = _FakeSecrets();
    // tenant_id en minúsculas: la comparación del discovery debe ser
    // insensible a mayúsculas (el servidor responde "STORE_DISCOVERY").
    secrets.values[PairingService.kTenantIdSecretKey] = 'store_discovery';
    secrets.values[PairingService.kDeviceTokenKey] = 'dvt_phone_dhcp';
    final pairing = PairingService(settings: settings, secrets: secrets);

    final db = AppDatabase.instance;
    final products = ProductRepository(db);
    final sales = SalesRepository(db);
    await seedProducts();

    // Servidor atado SOLO a loopback: cualquier otra 127.0.0.x falla,
    // simulando que la URL guardada apunta a una IP vieja (DHCP).
    final port = randomPort();
    final server = SyncServer(
      products: products,
      sales: sales,
      tenantId: 'STORE_DISCOVERY',
    );
    expect(await server.start(port: port, bindAddress: InternetAddress.loopbackIPv4),
        isTrue);
    addTearDown(server.stop);

    await pairing.saveSyncServerUrl('http://127.0.0.250:$port');

    final service = SyncService(products: products, sales: sales, pairing: pairing);
    final result = await service.syncNow();

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(await pairing.syncServerUrl(), 'http://127.0.0.1:$port');
  });
}