import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/cash.dart';
import 'package:scanflow/data/models/sale.dart';
import 'package:scanflow/data/repositories/cash_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_cash_test_');
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

  test('openShift crea un turno abierto con uuid único y fondo inicial',
      () async {
    final repo = CashRepository(AppDatabase.instance);

    final first = await repo.openShift(5000);
    expect(first.id, isNotNull);
    expect(first.isOpen, isTrue);
    expect(first.initialAmount, 5000);
    expect(first.closedAt, isNull);
    expect(first.status, CashShiftStatus.open);

    final second = await repo.openShift(3000);
    expect(second.uuid, isNot(first.uuid));
    // Un solo turno abierto a la vez: el abierto es el último.
    final current = await repo.getCurrentShift();
    expect(current?.id, second.id);
    expect(current?.initialAmount, 3000);
  });

  test('addMovement registra ingresos/egresos y el accounting calcula lo esperado',
      () async {
    final repo = CashRepository(AppDatabase.instance);
    final shift = await repo.openShift(5000);

    await repo.addMovement(
        shift.id!, CashMovementType.income, 1000, 'Cambio reemplazado');
    await repo.addMovement(
        shift.id!, CashMovementType.expense, 300, 'Compra menor');

    final movements = await repo.movements(shift.id!);
    expect(movements, hasLength(2));
    final income =
        movements.where((m) => m.isIncome).single;
    expect(income.amount, 1000);
    expect(income.description, 'Cambio reemplazado');
    final expense =
        movements.where((m) => !m.isIncome).single;
    expect(expense.amount, 300);
    expect(expense.isIncome, isFalse);

    // Sin ventas: esperado = fondo 5000 + 1000 − 300 = 5700.
    final acc = await repo.accounting(shift.id!);
    expect(acc.cashSalesTotal, 0);
    expect(acc.incomeTotal, 1000);
    expect(acc.expenseTotal, 300);
    expect(acc.expectedAmount, 5700);
  });

  test('un monto inválido o un turno cerrado rechazan movimientos', () async {
    final repo = CashRepository(AppDatabase.instance);
    final shift = await repo.openShift(1000);

    expect(
      () => repo.addMovement(
          shift.id!, CashMovementType.income, 0, 'Cero'),
      throwsArgumentError,
    );
    expect(
      () => repo.addMovement(
          shift.id!, CashMovementType.expense, -5, 'Negativo'),
      throwsArgumentError,
    );

    await repo.closeShift(shift.id!, 1000);
    expect(
      () => repo.addMovement(
          shift.id!, CashMovementType.income, 100, 'Tarde'),
      throwsStateError,
    );
    expect(() => repo.closeShift(shift.id!, 1100), throwsStateError);
  });

  test('closeShift cuadra ventas en efectivo + movimientos contra lo contado',
      () async {
    final repo = CashRepository(AppDatabase.instance);
    final sales = SalesRepository(AppDatabase.instance);
    final shift = await repo.openShift(10000);

    Future<int> insertSale(PaymentMethod method, double total, SaleStatus status) {
      return sales.insertSale(
        items: [
          SaleItem(
            productId: null,
            productName: 'Producto',
            barcode: '7800000000000',
            unitPrice: total,
            quantity: 1,
            subtotal: total,
          ),
        ],
        method: method,
        subtotal: total,
        taxRate: 0,
        tax: 0,
        total: total,
        change: 0,
        status: status,
        shiftId: shift.id!,
      );
    }

    await insertSale(PaymentMethod.efectivo, 2000, SaleStatus.completada);
    await insertSale(PaymentMethod.efectivo, 800, SaleStatus.anulada);
    await insertSale(PaymentMethod.tarjeta, 1500, SaleStatus.completada);
    await insertSale(PaymentMethod.transferencia, 1200, SaleStatus.completada);
    await repo.addMovement(shift.id!, CashMovementType.income, 500, 'Ingreso');
    await repo.addMovement(shift.id!, CashMovementType.expense, 200, 'Egreso');

    // Esperado = 10000 + 2000 (solo efectivo, anulada excluida) + 500 − 200.
    final acc = await repo.accounting(shift.id!);
    expect(acc.cashSalesTotal, 2000);
    expect(acc.expectedAmount, 12300);

    final closed = await repo.closeShift(shift.id!, 12400);
    expect(closed.isOpen, isFalse);
    expect(closed.status, CashShiftStatus.closed);
    expect(closed.closedAt, isNotNull);
    expect(closed.expectedAmount, 12300);
    expect(closed.declaredAmount, 12400);
    expect(closed.difference, 100);

    expect(await repo.getCurrentShift(), isNull);
  });

  test('paymentBreakdown agrupa por medio de pago excluyendo anuladas',
      () async {
    final repo = CashRepository(AppDatabase.instance);
    final sales = SalesRepository(AppDatabase.instance);
    final shift = await repo.openShift(0);

    for (final (method, total, status) in [
      (PaymentMethod.efectivo, 2000.0, SaleStatus.completada),
      (PaymentMethod.efectivo, 1500.0, SaleStatus.completada),
      (PaymentMethod.efectivo, 700.0, SaleStatus.anulada),
      (PaymentMethod.transferencia, 1200.0, SaleStatus.completada),
      (PaymentMethod.tarjeta, 900.0, SaleStatus.completada),
    ]) {
      await sales.insertSale(
        items: [
          SaleItem(
            productId: null,
            productName: 'Producto',
            barcode: '7800000000000',
            unitPrice: total,
            quantity: 1,
            subtotal: total,
          ),
        ],
        method: method,
        subtotal: total,
        taxRate: 0,
        tax: 0,
        total: total,
        change: 0,
        status: status,
        shiftId: shift.id!,
      );
    }

    final breakdown = await repo.paymentBreakdown(shift.id!);
    final byMethod = {for (final row in breakdown) row.method: row};
    // Sin anulada: 2 efectivo = 3500.
    expect(byMethod[PaymentMethod.efectivo]!.count, 2);
    expect(byMethod[PaymentMethod.efectivo]!.total, 3500);
    expect(byMethod[PaymentMethod.transferencia]!.count, 1);
    expect(byMethod[PaymentMethod.transferencia]!.total, 1200);
    expect(byMethod[PaymentMethod.tarjeta]!.count, 1);
    expect(byMethod[PaymentMethod.tarjeta]!.total, 900);
    // Fuera del turno o inexistentes: débito en cero.
    expect(byMethod[PaymentMethod.debito]!.count, 0);
    expect(byMethod[PaymentMethod.debito]!.total, 0);
    // Siempre con filas en el orden Efectivo, Débito, Transferencia, Tarjeta.
    expect(
      breakdown.map((row) => row.method).toList(),
      [
        PaymentMethod.efectivo,
        PaymentMethod.debito,
        PaymentMethod.transferencia,
        PaymentMethod.tarjeta,
      ],
    );
  });

  test('la venta guarda el shift_id y el repositorio lo devuelve', () async {
    final repo = CashRepository(AppDatabase.instance);
    final sales = SalesRepository(AppDatabase.instance);
    final shift = await repo.openShift(2500);

    final saleId = await sales.insertSale(
      items: [
        SaleItem(
          productId: null,
          productName: 'Arroz',
          barcode: '7800000000018',
          unitPrice: 1200,
          quantity: 1,
          subtotal: 1200,
        ),
      ],
      method: PaymentMethod.debito,
      subtotal: 1200,
      taxRate: 0,
      tax: 0,
      total: 1200,
      change: 0,
      shiftId: shift.id!,
    );

    final sale = await sales.byId(saleId);
    expect(sale.shiftId, shift.id);

    // Débito/Transferencia se almacenan y se recuperan como tales.
    final debitoSale = await sales.byId(saleId);
    expect(debitoSale.paymentMethod, PaymentMethod.debito);
  });
}