import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/models/sale.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/features/sales/sales_provider.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory tempDir;
  late ProductRepository products;
  late SalesRepository sales;
  late SalesProvider provider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_anular_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
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
    final db = await AppDatabase.instance.database;
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('movements');
    await db.delete('products');
    products = ProductRepository(AppDatabase.instance);
    sales = SalesRepository(AppDatabase.instance);
    provider = SalesProvider(
      salesRepository: sales,
      movementRepository: MovementRepository(AppDatabase.instance),
      productRepository: products,
    );
  });

  test('anular venta remota (sin product_id) repone el stock por barcode',
      () async {
    final productId = await products.insert(Product(
      name: 'Leche',
      barcode: '7801234000014',
      quantity: 10,
      minStock: 2,
      price: 1000,
      createdAt: '2026-09-16T00:00:00.000',
      updatedAt: '2026-09-16T00:00:00.000',
    ));
    // Simula la deducción de una venta remota (teléfono): stock 10 → 7 sin id.
    final db = await AppDatabase.instance.database;
    await db.update(
      'products',
      {'quantity': 7},
      where: 'id = ?',
      whereArgs: [productId],
    );

    final saleId = await sales.insertSale(
      items: [
        SaleItem(
          productId: null,
          productName: 'Leche',
          barcode: '7801234000014',
          unitPrice: 1000,
          quantity: 3,
          subtotal: 3000,
        ),
      ],
      method: PaymentMethod.efectivo,
      subtotal: 3000,
      taxRate: 0,
      tax: 0,
      total: 3000,
      received: 3000,
      change: 0,
    );

    final full = await sales.byId(saleId);
    final error = await provider.anularVenta(full);

    expect(error, isNull, reason: 'La anulación debe reponer el stock');
    final restored = await products.byBarcode('7801234000014');
    expect(restored?.quantity, 10,
        reason: 'stock 7 de la venta + 3 repuestos = 10');
    expect((await sales.byId(saleId)).status, SaleStatus.anulada);
  });

  test('anular venta local (con product_id) repone por id', () async {
    final productId = await products.insert(Product(
      name: 'Pan',
      barcode: '7801234000021',
      quantity: 5,
      minStock: 1,
      price: 500,
      createdAt: '2026-09-16T00:00:00.000',
      updatedAt: '2026-09-16T00:00:00.000',
    ));
    final saleId = await sales.insertSale(
      items: [
        SaleItem(
          productId: productId,
          productName: 'Pan',
          barcode: '7801234000021',
          unitPrice: 500,
          quantity: 2,
          subtotal: 1000,
        ),
      ],
      method: PaymentMethod.tarjeta,
      subtotal: 1000,
      taxRate: 0,
      tax: 0,
      total: 1000,
      change: 0,
    );

    final full = await sales.byId(saleId);
    final error = await provider.anularVenta(full);

    expect(error, isNull);
    expect((await products.byId(productId))?.quantity, 7);
  });
}