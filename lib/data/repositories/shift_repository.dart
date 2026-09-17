import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../database/app_database.dart';
import '../models/pos_shift.dart';

/// Persistencia del módulo Turnos y Cajas: cajas, cajeros y turnos locales.
///
/// El turno activo bloquea el POS: no se vende sin turno abierto en la caja
/// configurada. Cada venta queda marcada con `sales.shift_id` para el cuadre.
class ShiftRepository {
  const ShiftRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------- Cajas

  Future<List<PosRegister>> listRegisters() async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_registers',
      orderBy: 'created_at ASC, name ASC',
    );
    return rows.map(PosRegister.fromMap).toList();
  }

  Future<PosRegister?> registerById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_registers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PosRegister.fromMap(rows.first);
  }

  /// Crea una caja nueva y devuelve su id (UUID local).
  Future<String> addRegister(String name) async {
    final db = await _db.database;
    final id = _uuid();
    await db.insert('pos_registers', {
      'id': id,
      'user_app_id': null,
      'name': name.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  // --------------------------------------------------------------- Cajeros

  Future<List<PosCashier>> listCashiers() async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_cashiers',
      orderBy: 'created_at ASC, name ASC',
    );
    return rows.map(PosCashier.fromMap).toList();
  }

  Future<PosCashier?> cashierById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_cashiers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PosCashier.fromMap(rows.first);
  }

/// Devuelve el cajero con ese nombre o crea uno nuevo con el PIN. Si el nombre
/// ya existe y el PIN no coincide, lanza [StateError] (no se rehace el hash).
Future<PosCashier> ensureCashier(String name, String pin) async {
    final db = await _db.database;
    final clean = name.trim();
    final rows = await db.query(
      'pos_cashiers',
      where: 'name = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final cashier = PosCashier.fromMap(rows.first);
      if (!verifyPin(pin, cashier.pinHash)) {
        throw StateError('PIN incorrecto para el cajero "$clean".');
      }
      return cashier;
    }
    final id = _uuid();
    final pinHash = hashPin(pin);
    await db.insert('pos_cashiers', {
      'id': id,
      'user_app_id': null,
      'name': clean,
      'pin_hash': pinHash,
      'role': 'cajero',
      'created_at': DateTime.now().toIso8601String(),
    });
    return PosCashier(id: id, name: clean, pinHash: pinHash);
  }

  /// Hash SHA-256 hex del PIN (nunca se almacena en claro).
  static String hashPin(String pin) {
    final digest =
        SHA256Digest().process(Uint8List.fromList(utf8.encode(pin)));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool verifyPin(String pin, String expectedHash) =>
      hashPin(pin) == expectedHash;

  // ---------------------------------------------------------------- Turnos

  Future<PosShift?> activeShift(String registerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_shifts',
      where: 'register_id = ? AND status = ?',
      whereArgs: [registerId, ShiftStatus.abierto.dbValue],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PosShift.fromMap(rows.first);
  }

  Future<PosShift> openShift({
    required String registerId,
    required String cashierId,
    required double openingAmount,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('pos_shifts', {
      'register_id': registerId,
      'cashier_id': cashierId,
      'opening_amount': openingAmount,
      'expected_amount': openingAmount,
      'status': ShiftStatus.abierto.dbValue,
      'opened_at': now,
      'closed_at': null,
      'synced': 0,
    });
    return PosShift(
      id: id,
      registerId: registerId,
      cashierId: cashierId,
      openingAmount: openingAmount,
      expectedAmount: openingAmount,
      openedAt: now,
    );
  }

  /// Cierra el turno con el monto contado y el esperado calculado, y lo marca
  /// pendiente de respaldo en la nube (`synced = 0` aunque antes lo estuviera).
  Future<void> closeShift({
    required int id,
    required double closingAmount,
    required double expectedAmount,
  }) async {
    final db = await _db.database;
    await db.update(
      'pos_shifts',
      {
        'status': ShiftStatus.cerrado.dbValue,
        'closing_amount': closingAmount,
        'expected_amount': expectedAmount,
        'closed_at': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PosShift>> listForSync() async {
    final db = await _db.database;
    final rows = await db.query(
      'pos_shifts',
      where: 'synced = 0',
      orderBy: 'id ASC',
    );
    return rows.map(PosShift.fromMap).toList();
  }

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.generate(ids.length, (_) => '?').join(',');
    await db.update(
      'pos_shifts',
      {'synced': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Totales de ventas terminadas asociadas al turno (para el cuadre).
  Future<ShiftTotals> totalsFor(int shiftId) async {
    final db = await _db.database;
    final rows = await db.query(
      'sales',
      where: 'shift_id = ? AND status = ?',
      whereArgs: [shiftId.toString(), 'Completada'],
    );
    var count = 0;
    var cash = 0.0;
    var card = 0.0;
    for (final row in rows) {
      count++;
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;
      if (row['payment_method'] == 'Efectivo') {
        cash += total;
      } else {
        card += total;
      }
    }
    return ShiftTotals(salesCount: count, cashTotal: cash, cardTotal: card);
  }

  /// Efectivo esperado en caja: fondo de apertura + ventas en efectivo
  /// (sin retiros: aún no existe un flujo de sangrías).
  static double expectedFor(PosShift shift, ShiftTotals totals) =>
      shift.openingAmount + totals.cashTotal;

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}