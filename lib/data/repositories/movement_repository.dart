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

  static int clampNonNegative(int value) => value < 0 ? 0 : value;
}