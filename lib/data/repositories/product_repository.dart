import 'package:sqflite/sqflite.dart';

import '../../core/utils/formatters.dart';
import '../database/app_database.dart';
import '../models/product.dart';

class ProductRepository {
  const ProductRepository(this._db);

  final AppDatabase _db;

  Future<List<Product>> all({String? query}) async {
    final db = await _db.database;
    final like = '%${query?.trim()}%';
    final rows = (query == null || query.trim().isEmpty)
        ? await db.query(
            'products',
            orderBy: 'name COLLATE NOCASE ASC',
          )
        : await db.query(
            'products',
            where: 'name LIKE ? OR barcode LIKE ?',
            whereArgs: [like, like],
            orderBy: 'name COLLATE NOCASE ASC',
          );
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> lowStock() async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      where: 'quantity <= min_stock',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> byId(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<Product?> byBarcode(String barcode) async {
    final db = await _db.database;
    final variants = barcodeLookupVariants(barcode);
    final placeholders = List.generate(variants.length, (_) => '?').join(',');
    final rows = await db.query(
      'products',
      where: 'barcode IN ($placeholders)',
      whereArgs: variants,
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> insert(Product product) async {
    final db = await _db.database;
    return db.insert('products', product.toMap());
  }

  Future<int> update(Product product) async {
    final db = await _db.database;
    return db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM products');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Copia un producto recibido del catálogo de la PC (sync local). Si el
  /// código ya existe actualiza nombre/stock/precio; si no, lo inserta.
  Future<int> upsertFromSync({
    required String barcode,
    required String name,
    required int quantity,
    required int minStock,
    required double price,
    required String updatedAt,
  }) async {
    final existing = await byBarcode(barcode);
    if (existing == null) {
      return insert(
        Product(
          name: name,
          barcode: barcode,
          quantity: quantity,
          minStock: minStock,
          price: price,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        ),
      );
    }
    await update(
      existing.copyWith(
        name: name,
        quantity: quantity,
        minStock: minStock,
        price: price,
        updatedAt: updatedAt,
      ),
    );
    return existing.id!;
  }

  /// Descuenta `quantity` del stock al recibir una venta remota (sync Wi-Fi).
  ///
  /// Devuelve false si el producto no existe o el stock actual no alcanza;
  /// en ese caso la venta igual se registra y se marca con `stock_warning`.
  Future<bool> deductStockFromSync(String barcode, int quantity) async {
    final existing = await byBarcode(barcode);
    if (existing == null || quantity <= 0) return false;

    final db = await _db.database;
    final updated = await db.update(
      'products',
      {
        'quantity': existing.quantity - quantity,
        'updated_at': nowIso(),
      },
      where: 'id = ? AND quantity >= ?',
      whereArgs: [existing.id, quantity],
    );
    return updated > 0;
  }
}