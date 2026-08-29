import '../database/app_database.dart';
import '../models/sale.dart';

/// Persistencia de ventas del POS: cabecera + líneas del ticket.
///
/// Las ventas se guardan con una copia (snapshot) del nombre, código y precio
/// de cada producto, de modo que el historial no se altera si el catálogo
/// cambia o un producto se elimina.
class SalesRepository {
  const SalesRepository(this._db);

  final AppDatabase _db;

  /// Inserta la venta con sus líneas en una única transacción y devuelve el id.
  Future<int> insertSale({
    required List<SaleItem> items,
    required PaymentMethod method,
    required double subtotal,
    required double taxRate,
    required double tax,
    required double total,
    double? received,
    required double change,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('sales', {
        'payment_method': method.dbValue,
        'subtotal': subtotal,
        'tax_rate': taxRate,
        'tax_amount': tax,
        'total': total,
        'received': received,
        'change': change,
        'status': SaleStatus.completada.dbValue,
        'created_at': now,
      });
      for (final item in items) {
        await txn.insert('sale_items', {
          'sale_id': id,
          'product_id': item.productId,
          'product_name': item.productName,
          'barcode': item.barcode,
          'unit_price': item.unitPrice,
          'quantity': item.quantity,
          'subtotal': item.subtotal,
        });
      }
      return id;
    });
  }

  /// Historial de ventas (cabeceras) con filtros opcionales:
  /// rango de fechas y/o búsqueda por folio, producto o código de barras.
  Future<List<Sale>> getSalesHistory({
    DateTime? from,
    DateTime? to,
    String? query,
  }) async {
    final db = await _db.database;

    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('s.created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('s.created_at < ?');
      args.add(to.toIso8601String());
    }

    final q = query?.trim();
    if (q != null && q.isNotEmpty) {
      final folio = int.tryParse(q);
      where.add('(EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = s.id '
          'AND (si.product_name LIKE ? OR si.barcode LIKE ?)) '
          'OR s.id = ?)');
      final like = '%$q%';
      args..add(like)..add(like)..add(folio ?? -1);
    }

    final sql = 'SELECT s.* FROM sales s'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY s.created_at DESC, s.id DESC';
    final rows = await db.rawQuery(sql, args);
    return rows.map(Sale.fromMap).toList();
  }

  /// Devuelve la venta completa con sus líneas del ticket.
  Future<Sale> byId(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Venta no encontrada');
    final itemRows = await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    final sale = Sale.fromMap(rows.first);
    return sale.copyWith(items: itemRows.map(SaleItem.fromMap).toList());
  }

  Future<void> setStatus(int id, SaleStatus status) async {
    final db = await _db.database;
    await db.update(
      'sales',
      {'status': status.dbValue},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}