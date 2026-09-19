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
}