import '../database/app_database.dart';

/// Estado de un turno de caja.
enum ShiftStatus {
  abierto('abierto'),
  cerrado('cerrado');

  const ShiftStatus(this.dbValue);

  final String dbValue;

  static ShiftStatus fromDb(String value) =>
      value == 'cerrado' ? ShiftStatus.cerrado : ShiftStatus.abierto;
}

/// Una caja (register) local: la misma PC/bookkeeping puede manejar varias.
class PosRegister {
  const PosRegister({
    required this.id,
    this.userAppId,
    required this.name,
  });

  final String id;
  final String? userAppId;
  final String name;

  factory PosRegister.fromMap(Map<String, Object?> map) => PosRegister(
        id: map['id'] as String,
        userAppId: map['user_app_id'] as String?,
        name: map['name'] as String,
      );
}

/// Un cajero local. El PIN nunca viaja en claro: se guarda como hash SHA-256.
class PosCashier {
  const PosCashier({
    required this.id,
    this.userAppId,
    required this.name,
    required this.pinHash,
    this.role = 'cajero',
  });

  final String id;
  final String? userAppId;
  final String name;
  final String pinHash;
  final String role;

  PosCashier copyWith({String? userAppId, String? pinHash, String? role}) =>
      PosCashier(
        id: id,
        userAppId: userAppId ?? this.userAppId,
        name: name,
        pinHash: pinHash ?? this.pinHash,
        role: role ?? this.role,
      );

  factory PosCashier.fromMap(Map<String, Object?> map) => PosCashier(
        id: map['id'] as String,
        userAppId: map['user_app_id'] as String?,
        name: map['name'] as String,
        pinHash: map['pin_hash'] as String,
        role: (map['role'] as String?) ?? 'cajero',
      );
}

/// Un turno de caja (apertura → ventas → cierre con cuadre).
class PosShift {
  const PosShift({
    this.id,
    this.registerId = AppDatabase.kDefaultRegisterId,
    this.cashierId,
    this.openingAmount = 0.0,
    this.closingAmount,
    this.expectedAmount = 0.0,
    this.status = ShiftStatus.abierto,
    required this.openedAt,
    this.closedAt,
    this.synced = false,
  });

  final int? id;
  final String registerId;
  final String? cashierId;
  final double openingAmount;
  final double? closingAmount;
  final double expectedAmount;
  final ShiftStatus status;
  final String openedAt;
  final String? closedAt;
  final bool synced;

  bool get isOpen => status == ShiftStatus.abierto;

  factory PosShift.fromMap(Map<String, Object?> map) => PosShift(
        id: map['id'] as int?,
        registerId: (map['register_id'] as String?) ??
            AppDatabase.kDefaultRegisterId,
        cashierId: map['cashier_id'] as String?,
        openingAmount: (map['opening_amount'] as num?)?.toDouble() ?? 0.0,
        closingAmount: (map['closing_amount'] as num?)?.toDouble(),
        expectedAmount: (map['expected_amount'] as num?)?.toDouble() ?? 0.0,
        status: ShiftStatus.fromDb((map['status'] as String?) ?? 'abierto'),
        openedAt: map['opened_at'] as String,
        closedAt: map['closed_at'] as String?,
        synced: (map['synced'] as int? ?? 0) != 0,
      );
}

/// Totales de un turno según sus ventas registradas (para el cuadre/Ticket Z).
class ShiftTotals {
  const ShiftTotals({
    this.salesCount = 0,
    this.cashTotal = 0.0,
    this.cardTotal = 0.0,
  });

  final int salesCount;
  final double cashTotal;
  final double cardTotal;

  double get total => cashTotal + cardTotal;
}