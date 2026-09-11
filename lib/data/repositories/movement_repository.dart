import '../database/app_database.dart';
import '../models/movement.dart';
import '../models/product.dart';

class MovementRepository {
  const MovementRepository(this._db);

  final AppDatabase _db;

  Future<Product> adjustStock(int productId, int delta) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Producto no encontrado');
      }
      final product = Product.fromMap(rows.first);
      final newQuantity = clampNonNegative(product.quantity + delta);
      final applied = newQuantity - product.quantity;

      if (applied == 0) {
        return product.copyWith(quantity: newQuantity);
      }

      final now = DateTime.now().toIso8601String();
      await txn.update(
        'products',
        {'quantity': newQuantity, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.insert('movements', {
        'product_id': productId,
        'type': delta >= 0 ? MovementType.entrada.dbValue : MovementType.salida.dbValue,
        'delta': applied.abs(),
        'quantity_after': newQuantity,
        'created_at': now,
      });
      return product.copyWith(quantity: newQuantity, updatedAt: now);
    });
  }

  Future<List<Movement>> byProduct(int productId) async {
    final db = await _db.database;
    final rows = await db.query(
      'movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Movement.fromMap).toList();
  }

  /// Todos los movimientos con su código de barras resuelto (JOIN).
  /// Devuelve mapas crudos listos para mapear a la tabla `pos_movements` de la
  /// nube. El filtrado por cursor se hace en Dart (DateTime) para no depender
  /// de la zona horaria del texto SQLite.
  Future<List<Map<String, Object?>>> allWithBarcode() async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT m.product_id AS product_id, m.type AS type, m.delta AS delta,
             m.quantity_after AS quantity_after, m.created_at AS created_at,
             p.barcode AS barcode
      FROM movements m
      LEFT JOIN products p ON p.id = m.product_id
      ORDER BY m.created_at ASC
      ''',
    );
  }

  static int clampNonNegative(int value) => value < 0 ? 0 : value;
}