import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/cash_repository.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/features/cash/cash_provider.dart';
import 'package:scanflow/features/products/product_provider.dart';
import 'package:scanflow/features/sales/sales_provider.dart';
import 'package:scanflow/views/pos/cart_provider.dart';
import 'package:scanflow/views/pos/pos_desktop_view.dart';

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
      Provider<CashRepository>(
        create: (_) => CashRepository(AppDatabase.instance),
      ),
      ChangeNotifierProvider<ProductProvider>(
        create: (ctx) => ProductProvider(ctx.read<ProductRepository>()),
      ),
      ChangeNotifierProvider<SalesProvider>(
        create: (ctx) => SalesProvider(
          salesRepository: ctx.read<SalesRepository>(),
          movementRepository: ctx.read<MovementRepository>(),
        ),
      ),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider(),
      ),
      ChangeNotifierProvider<CashProvider>(
        create: (ctx) => CashProvider(
          cashRepository: ctx.read<CashRepository>(),
        ),
      ),
    ],
    child: const MaterialApp(home: PosDesktopView()),
  );
}

Future<void> _pumpWindow(
  WidgetTester tester,
  Size size, {
  bool openShift = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_buildApp());
  await tester.pumpAndSettle();

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

  final cash = Provider.of<CashProvider>(
    tester.element(find.byType(PosDesktopView)),
    listen: false,
  );
  if (!cash.isLoaded) await cash.load();
  if (openShift && !cash.isOpen) await cash.openShift(5000);

  await tester.pump();
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    tempDir = Directory.systemTemp.createTempSync('scanflow_pos_test_');
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
    await db.delete('cash_movements');
    await db.delete('cash_shifts');
    await db.delete('movements');
    await db.delete('products');
    await db.delete('settings');
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
      await tester.pumpAndSettle();
      expect(find.text('Finalizar venta'), findsOneWidget);
      expect(find.text('Confirmar venta'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Finalizar venta'), findsNothing);
    });
  }

  testWidgets('Atajo F12 abre el modal de cobro', (tester) async {
    await _pumpWindow(tester, const Size(1280, 720));

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    expect(find.text('Finalizar venta'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('sin turno abierto el cobro bloquea y pide fondo inicial',
      (tester) async {
    await _pumpWindow(tester, const Size(1280, 720), openShift: false);

    await tester.tap(find.text('COBRAR / FINALIZAR VENTA'));
    await tester.pumpAndSettle();

    // No llega al modal de cobro: exige abrir la caja.
    expect(find.text('Apertura de caja'), findsOneWidget);
    expect(find.text('Finalizar venta'), findsNothing);

    // Abre la caja con $10.000 de fondo y entonces sí continúa el cobro.
    await tester.enterText(
      find.widgetWithText(TextField, 'Fondo inicial'),
      '10000',
    );
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();

    expect(find.text('Finalizar venta'), findsOneWidget);

    // La venta registrada quedó asociada al turno abierto.
    final cash = Provider.of<CashProvider>(
      tester.element(find.byType(PosDesktopView)),
      listen: false,
    );
    expect(cash.isOpen, isTrue);
    expect(cash.shift?.initialAmount, 10000);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('el panel de caja muestra turno y Desglose por medio de pago',
      (tester) async {
    await _pumpWindow(tester, const Size(1280, 720));

    // Registra una venta con el carrito precargado para poblar el desglose.
    await tester.tap(find.text('COBRAR / FINALIZAR VENTA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venta'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Turno de caja abierto'));
    await tester.pumpAndSettle();

    expect(find.text('Ventas del turno por medio de pago'), findsOneWidget);
    expect(find.text('Efectivo esperado'), findsOneWidget);
    expect(find.text('Cerrar y cuadrar'), findsOneWidget);

    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
  });
}