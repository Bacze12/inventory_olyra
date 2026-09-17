import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanflow/data/cloud/supabase_gateway.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/data/repositories/shift_repository.dart';
import 'package:scanflow/features/license/license_service.dart';
import 'package:scanflow/features/products/product_provider.dart';
import 'package:scanflow/features/sales/sales_provider.dart';
import 'package:scanflow/features/shifts/shift_provider.dart';
import 'package:scanflow/services/hardware_id_service.dart';
import 'package:scanflow/views/pos/cart_provider.dart';
import 'package:scanflow/views/pos/pos_desktop_view.dart';

/// path_provider no se registra en pruebas: en lugar de colgar la apertura de
/// la BD (ver `AppDatabase._ensureDatabaseDirectory`), se fuerza el fallback al
/// override de sqflite (`databaseFactoryFfi.setDatabasesPath`).
class _ThrowingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() =>
      throw UnimplementedError('test: path_provider no disponible');

  @override
  Future<String?> getApplicationDocumentsPath() =>
      throw UnimplementedError('test: path_provider no disponible');

  @override
  Future<String?> getTemporaryPath() =>
      throw UnimplementedError('test: path_provider no disponible');
}

Product _product(int id, String name, int stock) => Product(
      id: id,
      name: name,
      barcode: '78012345678$id',
      quantity: stock,
      minStock: 1,
      price: 1490.5,
      createdAt: '2026-01-01T00:00:00',
      updatedAt: '2026-01-01T00:00:00',
    );

Widget _buildApp() {
  return MultiProvider(
    providers: [
      Provider<ProductRepository>(
        create: (_) => ProductRepository(AppDatabase.instance),
      ),
      Provider<MovementRepository>(
        create: (_) => MovementRepository(AppDatabase.instance),
      ),
      Provider<SalesRepository>(
        create: (_) => SalesRepository(AppDatabase.instance),
      ),
      Provider<SettingsRepository>(
        create: (_) => SettingsRepository(AppDatabase.instance),
      ),
      Provider<ShiftRepository>(
        create: (_) => ShiftRepository(AppDatabase.instance),
      ),
      Provider<HardwareIdService>(
        create: (_) => HardwareIdService(const FlutterSecureStorage()),
      ),
      Provider<SupabaseGateway>(
        create: (_) => SupabaseGateway.instance,
      ),
      ChangeNotifierProvider<LicenseService>(
        create: (ctx) => LicenseService(
          gateway: ctx.read<SupabaseGateway>(),
          hardware: ctx.read<HardwareIdService>(),
          settings: ctx.read<SettingsRepository>(),
        ),
      ),
      ChangeNotifierProvider<ProductProvider>(
        create: (ctx) => ProductProvider(ctx.read<ProductRepository>()),
      ),
      ChangeNotifierProvider<SalesProvider>(
        create: (ctx) => SalesProvider(
          salesRepository: ctx.read<SalesRepository>(),
          movementRepository: ctx.read<MovementRepository>(),
          productRepository: ctx.read<ProductRepository>(),
        ),
      ),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider(),
      ),
      ChangeNotifierProvider<ShiftProvider>(
        create: (ctx) => ShiftProvider(
          ctx.read<ShiftRepository>(),
          ctx.read<SettingsRepository>(),
        )..start(),
      ),
    ],
    child: const MaterialApp(home: PosDesktopView()),
  );
}

/// Bombea `n` frames con duraciones fijas. No usa pumpAndSettle: el cursor del
/// buscador (enfocado por el POS) y los futuribles de sqflite (zona FakeAsync)
/// impiden el "settle".
Future<void> _pumpFrames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pumpWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_buildApp());
  await _pumpFrames(tester);

  // Las cargas de ShiftProvider.start/ProductProvider usan sqflite_common_ffi:
  // sus queries NO avanzan dentro del FakeAsync (quedan timer de 10s pendientes
  // y rompen el teardown del test). Ejecuta pump + refresco con async REAL.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await _pumpFrames(tester);

  // Abre el turno de la caja sembrada ("Caja 1"): sin turno el POS se bloquea.
  // runAsync: los reads/writes de sqflite_common_ffi solo avanzan fuera del
  // FakeAsync de los testWidgets.
  final shifts = Provider.of<ShiftProvider>(
    tester.element(find.byType(PosDesktopView)),
    listen: false,
  );
  await tester.runAsync(() async {
    await shifts.start();
    await shifts.openShift(
      cashierName: 'Cajero Test',
      pin: '1234',
      openingAmount: 0,
    );
  });
  await _pumpFrames(tester);

  final cart = Provider.of<CartProvider>(
    tester.element(find.byType(PosDesktopView)),
    listen: false,
  );
  cart.addProduct(_product(1, 'Agua mineral 500 ml', 24));
  cart.addProduct(_product(1, 'Agua mineral 500 ml', 24));
  cart.addProduct(
    _product(2, 'Pan amasado grande ultra premium familiar', 6),
  );
  cart.setTaxRate(0.19);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    PathProviderPlatform.instance = _ThrowingPathProvider();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir =
        Directory.systemTemp.createTempSync('scanflow_pos_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
    // Abre la BD FUERA del FakeAsync de los testWidgets: sqflite_common_ffi
    // no completa su open dentro de pumpAndSettle (timers falsos). Una vez
    // cacheado en AppDatabase, los tests usan la instancia ya abierta.
    await AppDatabase.instance.database;
  });

  final sizes = <Size>[
    const Size(1440, 900),
    const Size(1280, 720),
    const Size(1024, 768),
    const Size(830, 620),
    const Size(640, 480),
  ];

  for (final size in sizes) {
    testWidgets('POS sin excepciones de layout en '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _pumpWindow(tester, size);

      await tester.tap(find.text('COBRAR / FINALIZAR VENTA'));
      await _pumpFrames(tester);
      expect(find.text('Finalizar venta'), findsOneWidget);
      expect(find.text('Confirmar venta'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await _pumpFrames(tester);
      expect(find.text('Finalizar venta'), findsNothing);
    });
  }

  testWidgets('Atajo F12 abre el modal de cobro', (tester) async {
    await _pumpWindow(tester, const Size(1280, 720));

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await _pumpFrames(tester);
    expect(find.text('Finalizar venta'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await _pumpFrames(tester);
  });
}