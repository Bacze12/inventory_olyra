import '../database/app_database.dart';
import '../models/cash.dart';
import '../models/sale.dart';

/// Totales que definen el cuadre de un turno (antes/después de cerrar).
class ShiftAccounting {
  const ShiftAccounting({
    required this.cashSalesTotal,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.expectedAmount,
  });

  /// Suma de los totales de las ventas pagadas en efectivo (completadas).
  final double cashSalesTotal;

  /// Suma de los ingresos manuales del turno.
  final double incomeTotal;

  /// Suma de los egresos manuales del turno.
  final double expenseTotal;

  /// Fondo inicial + efectivo vendido + ingresos − egresos.
  final double expectedAmount;
}

double _rounded(double value) => (value * 100).roundToDouble() / 100;

/// Persistencia y cálculo del arqueo de caja: apertura de turno, movimientos
/// manuales (ingresos/egresos), desglose por medio de pago y cierre con cuadre.
///
/// `expected_amount = initial_amount + ventas en efectivo + ingresos − egresos`
/// `difference      = declared_amount − expected_amount`
class CashRepository {
  const CashRepository(this._db);

  final AppDatabase _db;

  /// Turno abierto en curso; `null` cuando la caja está cerrada.
  Future<CashShift?> getCurrentShift() async {
    final db = await _db.database;
    final rows = await db.query(
      'cash_shifts',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CashShift.fromMap(rows.first);
  }

  Future<CashShift> byId(int id) async {
    final db = await _db.database;
    final rows = await db.query('cash_shifts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Turno de caja no encontrado: $id');
    return CashShift.fromMap(rows.first);
  }

  /// Abre un turno de caja con [initialAmount] de fondo inicial.
  Future<CashShift> openShift(double initialAmount) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('cash_shifts', {
      'uuid': uuidV4(),
      'opened_at': now,
      'initial_amount': initialAmount,
      'status': CashShiftStatus.open.dbValue,
      'synced': 0,
    });
    return byId(id);
  }

  /// Registra un ingreso o egreso manual en el turno.
  Future<CashMovement> addMovement(
    int shiftId,
    CashMovementType type,
    double amount,
    String description,
  ) async {
    if (amount <= 0) {
      throw ArgumentError('El monto del movimiento debe ser mayor a cero');
    }
    final shift = await byId(shiftId);
    if (!shift.isOpen) throw StateError('El turno ya está cerrado');
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('cash_movements', {
      'shift_id': shiftId,
      'type': type.dbValue,
      'amount': amount,
      'description': description,
      'created_at': now,
    });
    return CashMovement(
      id: id,
      shiftId: shiftId,
      type: type,
      amount: amount,
      description: description,
      createdAt: now,
    );
  }

  /// Movimientos manuales del turno, más recientes primero.
  Future<List<CashMovement>> movements(int shiftId) async {
    final db = await _db.database;
    final rows = await db.query(
      'cash_movements',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'id DESC',
    );
    return rows.map(CashMovement.fromMap).toList();
  }

  /// Desglose de las ventas COMPLETADAS del turno por medio de pago, siempre
  /// con fila fija en el orden Efectivo, Débito, Transferencia, Tarjeta.
  Future<List<PaymentBreakdown>> paymentBreakdown(int shiftId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT payment_method, COUNT(*) AS n, SUM(total) AS total
      FROM sales
      WHERE shift_id = ? AND status = 'Completada'
      GROUP BY payment_method
      ''',
      [shiftId],
    );
    final grouped = <String, ({int count, double total})>{};
    for (final row in rows) {
      grouped[row['payment_method'] as String] = (
        count: (row['n'] as num).toInt(),
        total: (row['total'] as num?)?.toDouble() ?? 0.0,
      );
    }
    const order = [
      PaymentMethod.efectivo,
      PaymentMethod.debito,
      PaymentMethod.transferencia,
      PaymentMethod.tarjeta,
    ];
    return [
      for (final method in order)
        PaymentBreakdown(
          method: method,
          count: grouped[method.dbValue]?.count ?? 0,
          total: _rounded(grouped[method.dbValue]?.total ?? 0.0),
        ),
    ];
  }

  /// Totales del arqueo: efectivo vendido, ingresos, egresos y lo esperado.
  Future<ShiftAccounting> accounting(int shiftId) async {
    final db = await _db.database;
    final shift = await byId(shiftId);
    final cashRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) AS total
      FROM sales
      WHERE shift_id = ? AND status = 'Completada'
        AND payment_method = 'Efectivo'
      ''',
      [shiftId],
    );
    final cashSales =
        (cashRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final moveRows = await db.rawQuery(
      '''
      SELECT type, COALESCE(SUM(amount), 0) AS total
      FROM cash_movements
      WHERE shift_id = ?
      GROUP BY type
      ''',
      [shiftId],
    );
    var income = 0.0;
    var expense = 0.0;
    for (final row in moveRows) {
      final value = (row['total'] as num?)?.toDouble() ?? 0.0;
      if (row['type'] == CashMovementType.income.dbValue) income = value;
      if (row['type'] == CashMovementType.expense.dbValue) expense = value;
    }

    final expected =
        shift.initialAmount + cashSales + income - expense;
    return ShiftAccounting(
      cashSalesTotal: _rounded(cashSales),
      incomeTotal: _rounded(income),
      expenseTotal: _rounded(expense),
      expectedAmount: _rounded(expected),
    );
  }

  /// Cierra el turno: cuadra el efectivo esperado contra lo contado.
  Future<CashShift> closeShift(int shiftId, double declaredAmount) async {
    final shift = await byId(shiftId);
    if (!shift.isOpen) throw StateError('El turno ya está cerrado');
    final acc = await accounting(shiftId);
    final expected = acc.expectedAmount;
    final now = DateTime.now().toIso8601String();
    final db = await _db.database;
    await db.update(
      'cash_shifts',
      {
        'closed_at': now,
        'declared_amount': declaredAmount,
        'expected_amount': expected,
        'difference': _rounded(declaredAmount - expected),
        'status': CashShiftStatus.closed.dbValue,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    return byId(shiftId);
  }
}