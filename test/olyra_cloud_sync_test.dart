import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/models/sale.dart';
import 'package:scanflow/data/remote/olyra_license_api.dart';
import 'package:scanflow/data/remote/olyra_pos_api.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/data/repositories/shift_repository.dart';
import 'package:scanflow/features/activation/license_credential_store.dart';
import 'package:scanflow/features/activation/olyra_license_controller.dart';
import 'package:scanflow/features/sync/olyra_cloud_sync.dart';
import 'package:scanflow/services/hardware_id_service.dart';

// ---------------------------------------------------------------------------
// Fixture de licencia: genera un par RSA de prueba, firma un JWT RS256 válido
// y arma el PEM de la clave pública que el controlador verifica offline.
// ---------------------------------------------------------------------------

class _Keys {
  _Keys(this.privateKey, this.publicPem);

  final RSAPrivateKey privateKey;
  final String publicPem;
}

_Keys _generateKeys() {
  final random = Random.secure();
  final seed =
      Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
  final secureRandom = FortunaRandom()..seed(KeyParameter(seed));
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
      secureRandom,
    ));
  final pair = generator.generateKeyPair();
  final publicKey = pair.publicKey;
  final privateKey = pair.privateKey;

  final rsaSeq = _tlv(0x30, [
    ..._derInteger(publicKey.modulus!),
    ..._derInteger(publicKey.publicExponent!),
  ]);
  final bitString = _tlv(0x03, [0x00, ...rsaSeq]);
  final oid = _tlv(
      0x06, [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]);
  final nullTag = _tlv(0x05, []);
  final spki = _tlv(0x30, [..._tlv(0x30, [...oid, ...nullTag]), ...bitString]);

  final pem = '-----BEGIN PUBLIC KEY-----\n'
      '${_wrapBase64(base64Encode(spki))}'
      '-----END PUBLIC KEY-----\n';
  return _Keys(privateKey, pem);
}

/// Firma un JWT RS256 con PKCS#1 v1.5 + SHA-256 (misma matemática que
/// `RsaJwtVerifier` invierte con la clave pública).
String _signJwt(RSAPrivateKey key, Map<String, Object?> payload) {
  String seg(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final message =
      '${seg({'alg': 'RS256', 'typ': 'JWT'})}.${seg(payload)}';
  final hash = SHA256Digest().process(Uint8List.fromList(utf8.encode(message)));

  const digestInfo = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65,
    0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  final trailer = <int>[...digestInfo, ...hash];
  final modulus = key.modulus!;
  final emLen = (modulus.bitLength + 7) ~/ 8;
  final em = Uint8List(emLen);
  em[0] = 0x00;
  em[1] = 0x01;
  var i = 2;
  while (i < emLen - trailer.length - 1) {
    em[i++] = 0xff;
  }
  em[i++] = 0x00;
  em.setRange(i, i + trailer.length, trailer);

  final signature =
      _bytesToBigInt(em).modPow(key.privateExponent!, modulus);
  return '$message.${base64Url.encode(_bigIntToBytes(signature, emLen)).replaceAll('=', '')}';
}

List<int> _tlv(int tag, List<int> content) =>
    [tag, ..._derLength(content.length), ...content];

List<int> _derLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  var value = length;
  while (value > 0) {
    bytes.insert(0, value & 0xff);
    value >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

List<int> _derInteger(BigInt value) {
  var bytes = _bigIntToBytes(value, (value.bitLength + 7) ~/ 8);
  if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
  if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
  return _tlv(0x02, bytes);
}

BigInt _bytesToBigInt(Uint8List bytes) => bytes.isEmpty
    ? BigInt.zero
    : BigInt.parse(
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      );

Uint8List _bigIntToBytes(BigInt value, int length) {
  final hex = value.toRadixString(16).padLeft(length * 2, '0');
  return Uint8List.fromList(
    List<int>.generate(
        length, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
  );
}

String _wrapBase64(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i += 64) {
    buffer.writeln(value.substring(i, min(i + 64, value.length)));
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------

class _FakeLicenseApi extends OlyraLicenseApi {
  _FakeLicenseApi()
      : super(activationUrl: 'http://olyra.test/api/v1/license/activate');

  OlyraValidateResult next = const OlyraValidateResult(ok: true);
  int calls = 0;

  @override
  Future<OlyraValidateResult> validateWithMeta({
    required String licenseKey,
    required String hwid,
    required String token,
    String deviceName = '',
  }) async {
    calls++;
    return next;
  }
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  const hwid = 'test-hwid-0123456789';
  late Directory tempDir;
  late _Keys keys;
  late String licenseKey;
  late String token;
  late Map<String, String> storage;
  late _FakeLicenseApi licenseApi;
  late OlyraLicenseController license;
  late FlutterSecureStorage secrets;
  late SalesRepository sales;
  late ProductRepository products;
  late MovementRepository movements;
  late ShiftRepository shifts;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_cloud_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
    keys = _generateKeys();
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // La BD pudo quedar abierta; el SO limpia el resto.
    }
  });

  setUp(() async {
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    licenseKey = 'SCAN-TEST-0001';
    token = _signJwt(keys.privateKey, {
      'hwid': hwid,
      // Sin claim `user_app_id`: el servidor lo entrega recién en validate,
      // que es exactamente el escenario del bug de Revalidar.
      'exp': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
    });

    storage = {
      HardwareIdService.storageKey: hwid,
      LicenseCredentialStore.keyLicenseKey: licenseKey,
      LicenseCredentialStore.keyHardwareId: hwid,
      LicenseCredentialStore.keyActivationToken: token,
      LicenseCredentialStore.keyDeviceName: 'Caja Test',
    };
    FlutterSecureStorage.setMockInitialValues(storage);

    final db = await AppDatabase.instance.database;
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('movements');
    await db.delete('pos_shifts');
    await db.delete('products');
    await db.delete('settings');

    secrets = const FlutterSecureStorage();
    sales = SalesRepository(AppDatabase.instance);
    products = ProductRepository(AppDatabase.instance);
    movements = MovementRepository(AppDatabase.instance);
    shifts = ShiftRepository(AppDatabase.instance);
    licenseApi = _FakeLicenseApi();
    license = OlyraLicenseController(
      hardware: HardwareIdService(secrets),
      api: licenseApi,
      credentials: LicenseCredentialStore(secrets),
      publicKeyPem: keys.publicPem,
    );
    await license.init();
    // Deja terminar la revalidación silenciosa que dispara `init`.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(license.state, OlyraLicenseState.active);
  });

  OlyraCloudSync buildCloud({http.Client? client}) => OlyraCloudSync(
        license: license,
        credentials: LicenseCredentialStore(secrets),
        api: OlyraPosApi(
          syncUrl: 'http://olyra.test/api/v1/pos/sync',
          client: client,
        ),
        sales: sales,
        movements: MovementRepository(AppDatabase.instance),
        products: products,
        settings: SettingsRepository(AppDatabase.instance),
        shifts: shifts,
      );

  test('Revalidar refresca el user_app_id en memoria y lo persiste al instante',
      () async {
    licenseApi.next = const OlyraValidateResult(ok: true);
    final cloud = buildCloud();
    await cloud.start();

    // Aún sin cuenta vinculada (el JWT no la trae y no se ha revalidado).
    expect(cloud.userAppId, isEmpty);
    expect(cloud.state, OlyraCloudState.unconfigured);

    // Revalidar: el servidor confirma y entrega el user_app_id.
    const freshUserAppId = '2f4a1b3c-5d6e-4f70-8a91-b2c3d4e5f601';
    licenseApi.next =
        const OlyraValidateResult(ok: true, userAppId: freshUserAppId);

    expect(await cloud.validate(), isTrue);

    // 1) Estado global refrescado en memoria (sin reabrir el modal).
    expect(cloud.state, OlyraCloudState.active);
    expect(cloud.userAppId, freshUserAppId);
    expect(license.userAppId, freshUserAppId);
    // 2) Persistido de inmediato para sobrevivir al reinicio.
    expect(storage[LicenseCredentialStore.keyUserAppId], freshUserAppId);
  });

  test('Revalidar solapado con la validación silenciosa usa un solo round-trip',
      () async {
    licenseApi.next = const OlyraValidateResult(ok: true);
    licenseApi.calls = 0;

    final results =
        await Future.wait([license.validateNow(), license.validateNow()]);

    expect(results, everyElement(isTrue));
    expect(licenseApi.calls, 1,
        reason: 'el flag _validating ya no debe devolver un falso negativo');
  });

  test('Sincronizar ahora sube 2 ventas + 1 turno sin bloquear por user_app_id',
      () async {
    licenseApi.next = const OlyraValidateResult(ok: true);
    final shift = await shifts.openShift(
      registerId: 'caja-1',
      cashierId: 'cajero-1',
      openingAmount: 0,
    );
    await shifts.closeShift(id: shift.id!, closingAmount: 0, expectedAmount: 0);

    for (var i = 0; i < 2; i++) {
      await sales.insertSale(
        items: [
          const SaleItem(
            productId: null,
            productName: 'Arroz',
            barcode: '7800000000018',
            unitPrice: 1200,
            quantity: 1,
            subtotal: 1200,
          ),
        ],
        method: PaymentMethod.efectivo,
        subtotal: 1200,
        taxRate: 0,
        tax: 0,
        total: 1200,
        received: 1200,
        change: 0,
        shiftId: shift.id.toString(),
      );
    }

    // Movimiento de inventario pendiente (synced = 0) con barcode resuelto.
    final now = DateTime.now().toIso8601String();
    final productId = await products.insert(Product(
      name: 'Coca',
      barcode: '7800000000118',
      quantity: 10,
      minStock: 1,
      price: 1500,
      createdAt: now,
      updatedAt: now,
    ));
    await movements.adjustStock(productId, -1);

    late Map<String, dynamic> sentBody;
    final mockClient = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'synced_sales': 2,
          'synced_movements': 1,
          'synced_products_count': 1,
          'synced_shifts': 1,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final cloud = buildCloud(client: mockClient);
    await cloud.start();
    expect(cloud.userAppId, isEmpty);
    expect(cloud.pendingSales, 2);
    expect(cloud.pendingShifts, 1);

    // No debe lanzar OlyraCloudNotReadyException: la petición SALE al backend.
    final result = await cloud.syncNow();

    expect(result.salesPushed, 2);
    expect(result.shiftsPushed, 1);
    expect(sentBody['user_app_id'], isEmpty,
        reason: 'sin cuenta local, el backend la resuelve desde la licencia');

    final sentSales = sentBody['sales'] as List;
    expect(sentSales, hasLength(2));
    final sale = sentSales.first as Map<String, dynamic>;
    expect(sale['local_id'], isA<String>(),
        reason: 'el backend exige local_id como string (str()): si va como int, '
            'se salta la venta y Vercel muestra sales=0');
    expect(sale['local_created_at'], isNotNull,
        reason: 'el backend lee local_created_at, no created_at');
    final items = sale['items'] as List;
    expect(items, hasLength(1));
    final firstItem = items.first as Map<String, dynamic>;
    expect(firstItem['local_item_id'], isA<String>());
    expect(firstItem['product_sku'], '7800000000018');

    final sentMovements = sentBody['movements'] as List;
    expect(sentMovements, hasLength(1));
    final movement = sentMovements.first as Map<String, dynamic>;
    expect(movement['local_id'], isA<String>(),
        reason: 'un movimiento sin local_id se descarta -> movements=0');
    expect(movement['local_created_at'], isNotNull);
    expect(movement['barcode'], '7800000000118');
    expect(movement['type'], 'OUT');

    expect((sentBody['shifts'] as List), hasLength(1));

    // El contador local volvió a 0: quedó marcado como respaldado.
    expect(await sales.listForSync(), isEmpty);
    expect(await shifts.listForSync(), isEmpty);
    expect(await movements.listForSync(), isEmpty,
        reason: 'solo se marca tras el 200; un 5xx dejaría el movimiento pendiente');
    expect(cloud.pendingSales, 0);
    expect(cloud.pendingShifts, 0);
    expect(cloud.state, OlyraCloudState.active);
    expect(cloud.lastSalesPushed, 2);
    expect(cloud.lastShiftsPushed, 1);
  });

  test('El catálogo completo viaja en cada sincronización, aunque no haya ventas',
      () async {
    licenseApi.next = const OlyraValidateResult(ok: true);
    final now = DateTime.now().toIso8601String();
    for (var i = 1; i <= 3; i++) {
      await products.insert(
        Product(
          name: 'Producto $i',
          barcode: '78000000000$i',
          quantity: i * 2,
          minStock: 1,
          price: 100.0 * i,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    late Map<String, dynamic> sentBody;
    final mockClient = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'synced_sales': 0,
          'synced_movements': 0,
          'synced_products_count': 3,
          'synced_shifts': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final cloud = buildCloud(client: mockClient);
    await cloud.start();
    expect(cloud.catalogSize, 3);

    final result = await cloud.syncNow();

    // Sin ventas ni turnos, la sincronización rutinaria igual empuja el
    // inventario: "Subir respaldo" ya no es el único camino que sube catálogo.
    expect(result.productsPushed, 3);
    expect(result.hasChanges, isTrue);
    expect(cloud.lastProductsPushed, 3);

    final sentProducts = sentBody['products'] as List;
    expect(sentProducts, hasLength(3));
    final first = sentProducts.first as Map<String, dynamic>;
    expect(first['local_id'], isA<String>(),
        reason: 'el backend exige local_id como string (upsert idempotente)');
    expect(first['barcode'], '780000000001');
    expect(first['name'], 'Producto 1');
    expect(first['stock'], 2);
    expect(first['price'], 100.0);
    expect(first['local_updated_at'], now);
    expect(first['user_app_id'], isEmpty,
        reason: 'se resuelve en el backend desde la licencia');

    // La marca temporal del catálogo queda persistida tras el ciclo.
    final settings = SettingsRepository(AppDatabase.instance);
    expect(await settings.get(OlyraCloudSync.kProductsSyncTs), isNotNull);
  });

  test('Los pendientes se releen de la BD local (synced=0), no del arranque',
      () async {
    final cloud = buildCloud(client: MockClient((request) async => http.Response(
        jsonEncode(const {'success': true}),
        200,
        headers: {'content-type': 'application/json'})));
    await cloud.start();
    expect(cloud.pendingSales, 0);

    // 3 ventas insertadas DESPUÉS del start(): el bug del panel que decía 0.
    for (var i = 0; i < 3; i++) {
      await sales.insertSale(
        items: [
          const SaleItem(
            productId: null,
            productName: 'Arroz',
            barcode: '7800000000018',
            unitPrice: 1200,
            quantity: 1,
            subtotal: 1200,
          ),
        ],
        method: PaymentMethod.efectivo,
        subtotal: 1200,
        taxRate: 0,
        tax: 0,
        total: 1200,
        received: 1200,
        change: 0,
      );
    }

    // El DAO explícito lee la MISMA tabla donde el POS inserta al cobrar.
    expect(await sales.getUnsyncedSales(), hasLength(3));
    expect(await sales.countUnsyncedSales(), 3);

    // El snapshot del arranque sigue en 0 hasta que el panel refresque…
    expect(cloud.pendingSales, 0,
        reason: 'start() solo corre al abrir la app');
    // …y el panel llama refreshPending() al abrirse:
    await cloud.refreshPending();
    expect(cloud.pendingSales, 3);
  });

  test('Subir respaldo genera un .db físico restaurable con sales/movements/turnos',
      () async {
    final shift = await shifts.openShift(
      registerId: 'caja-1',
      cashierId: 'cajero-1',
      openingAmount: 0,
    );
    final now = DateTime.now().toIso8601String();
    final productId = await products.insert(Product(
      name: 'Coca',
      barcode: '7800000000118',
      quantity: 10,
      minStock: 1,
      price: 1500,
      createdAt: now,
      updatedAt: now,
    ));
    await movements.adjustStock(productId, -1);
    for (var i = 0; i < 2; i++) {
      await sales.insertSale(
        items: [
          const SaleItem(
            productId: null,
            productName: 'Arroz',
            barcode: '7800000000018',
            unitPrice: 1200,
            quantity: 1,
            subtotal: 1200,
          ),
        ],
        method: PaymentMethod.efectivo,
        subtotal: 1200,
        taxRate: 0,
        tax: 0,
        total: 1200,
        received: 1200,
        change: 0,
        shiftId: shift.id.toString(),
      );
    }

    final cloud = buildCloud(client: MockClient((request) async => http.Response(
        jsonEncode(const {'success': true}),
        200,
        headers: {'content-type': 'application/json'})));
    await cloud.start();

    final backup = await cloud.createLocalBackup();

    // Ubica el archivo físico en el directorio de la app y lo empaqueta.
    expect(await cloud.locateDatabaseFile(), isNotNull);
    expect(backup.path, contains('backups'));
    expect(backup.path, endsWith('.db'));
    expect(await backup.exists(), isTrue);
    expect(await backup.length(), greaterThan(0));
    expect(cloud.lastLocalBackupPath, backup.path);
    expect(cloud.lastLocalBackupSize, greaterThan(0));

    // Restaurable: abrir la copia con el mismo engine y cuadrar las tablas.
    final restored = await databaseFactory.openDatabase(backup.path);
    Future<int> count(String table) async {
      final rows =
          await restored.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as int?) ?? 0;
    }

    expect(await count('sales'), 2);
    expect(await count('sale_items'), 2);
    expect(await count('movements'), 1);
    expect(await count('pos_shifts'), 1);
    expect(await count('products'), 1);
    await restored.close();
    await backup.delete();
  });
}
