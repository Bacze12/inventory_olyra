import 'package:flutter/foundation.dart';

import '../../data/models/cash.dart';
import '../../data/repositories/cash_repository.dart';

/// Estado de la caja en la UI: el turno abierto y las operaciones de apertura,
/// movimientos manuales y cierre con cuadre.
class CashProvider extends ChangeNotifier {
  CashProvider({required CashRepository cashRepository})
      : _cash = cashRepository;

  final CashRepository _cash;

  CashShift? _shift;
  bool _loaded = false;
  String? _error;

  CashShift? get shift => _shift;
  bool get isOpen => _shift?.isOpen ?? false;
  bool get isLoaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    try {
      _shift = await _cash.getCurrentShift();
      _error = null;
    } catch (_) {
      _error = 'No se pudo leer el estado de la caja';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Abre un turno con [initialAmount] de fondo. Devuelve `null` o un mensaje.
  Future<String?> openShift(double initialAmount) async {
    try {
      _shift = await _cash.openShift(initialAmount);
      _loaded = true;
      _error = null;
      notifyListeners();
      return null;
    } catch (_) {
      return 'No se pudo abrir la caja';
    }
  }

  /// Registra un ingreso o egreso manual. Devuelve `null` o un mensaje.
  Future<String?> addMovement(
    CashMovementType type,
    double amount,
    String description,
  ) async {
    final shift = _shift;
    if (shift == null || !shift.isOpen) {
      return 'No hay un turno de caja abierto';
    }
    if (amount <= 0) return 'El monto debe ser mayor a cero';
    try {
      await _cash.addMovement(shift.id!, type, amount, description);
      notifyListeners();
      return null;
    } catch (_) {
      return 'No se pudo registrar el movimiento';
    }
  }

  /// Cierra el turno cuadrando contra [declaredAmount]. Devuelve el turno
  /// cerrado (para mostrar el desglose final) o un error.
  Future<({CashShift? shift, String? error})> closeShift(
    double declaredAmount,
  ) async {
    final shift = _shift;
    if (shift == null || !shift.isOpen) {
      return (shift: null, error: 'No hay un turno de caja abierto');
    }
    try {
      final closed = await _cash.closeShift(shift.id!, declaredAmount);
      _shift = closed;
      notifyListeners();
      return (shift: closed, error: null);
    } catch (_) {
      return (shift: null, error: 'No se pudo cerrar la caja');
    }
  }
}