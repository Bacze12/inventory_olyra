import 'dart:math';

import 'sale.dart';

enum CashShiftStatus {
  open('open'),
  closed('closed');

  const CashShiftStatus(this.dbValue);

  final String dbValue;

  static CashShiftStatus fromDb(String value) => value == 'closed'
      ? CashShiftStatus.closed
      : CashShiftStatus.open;
}

enum CashMovementType {
  income('income'),
  expense('expense');

  const CashMovementType(this.dbValue);

  final String dbValue;

  static CashMovementType fromDb(String value) => value == 'expense'
      ? CashMovementType.expense
      : CashMovementType.income;
}

/// Turno de caja: apertura con fondo inicial, cierre con cuadre.
///
/// `expected_amount` = fondo inicial + ventas en efectivo + ingresos manuales
/// − egresos manuales. `difference` = `declared − expected`.
class CashShift {
  const CashShift({
    this.id,
    required this.uuid,
    required this.openedAt,
    this.closedAt,
    required this.initialAmount,
    this.declaredAmount,
    this.expectedAmount,
    this.difference,
    required this.status,
    this.synced = false,
  });

  final int? id;
  final String uuid;
  final String openedAt;
  final String? closedAt;
  final double initialAmount;
  final double? declaredAmount;
  final double? expectedAmount;
  final double? difference;
  final CashShiftStatus status;
  final bool synced;

  bool get isOpen => status == CashShiftStatus.open;

  factory CashShift.fromMap(Map<String, Object?> map) => CashShift(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        openedAt: map['opened_at'] as String,
        closedAt: map['closed_at'] as String?,
        initialAmount: (map['initial_amount'] as num?)?.toDouble() ?? 0.0,
        declaredAmount: (map['declared_amount'] as num?)?.toDouble(),
        expectedAmount: (map['expected_amount'] as num?)?.toDouble(),
        difference: (map['difference'] as num?)?.toDouble(),
        status: CashShiftStatus.fromDb(map['status'] as String? ?? 'open'),
        synced: (map['synced'] as int? ?? 0) != 0,
      );
}

/// Movimiento manual de caja: ingreso (efectivo que entra) o egreso (sale).
class CashMovement {
  const CashMovement({
    this.id,
    required this.shiftId,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  final int? id;
  final int shiftId;
  final CashMovementType type;
  final double amount;
  final String description;
  final String createdAt;

  bool get isIncome => type == CashMovementType.income;

  factory CashMovement.fromMap(Map<String, Object?> map) => CashMovement(
        id: map['id'] as int?,
        shiftId: map['shift_id'] as int,
        type: CashMovementType.fromDb(map['type'] as String),
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        description: map['description'] as String? ?? '',
        createdAt: map['created_at'] as String,
      );
}

/// Total y cantidad de ventas completadas por medio de pago dentro de un
/// turno. Se usa para mostrar el desglose del cierre de caja.
class PaymentBreakdown {
  const PaymentBreakdown({
    required this.method,
    required this.count,
    required this.total,
  });

  final PaymentMethod method;
  final int count;
  final double total;
}

/// UUID v4 (RFC 4122-ish) generado sin dependencias externas: identifica el
/// turno de forma única entre dispositivos cuando haya sincronización de caja.
String uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}