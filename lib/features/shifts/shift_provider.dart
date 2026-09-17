import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart';
import '../../data/models/pos_shift.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';

/// Resultado de un cierre de caja (para el Ticket Z y el aviso de cuadre).
///
/// NOTA: `shift` es el turno PREVIO al cierre (el mismo objeto que estaba
/// abierto) — por eso el cuadre del Ticket Z usa `counted` y `closedAt`
/// explícitos, que sí llevan lo que escribió `closeShift`.
class ShiftCloseResult {
  const ShiftCloseResult({
    required this.shift,
    required this.totals,
    required this.expected,
    required this.counted,
    this.closedAt,
  });

  final PosShift shift;
  final ShiftTotals totals;

  /// Efectivo esperado en caja: fondo inicial + ventas en efectivo del turno.
  final double expected;

  /// Efectivo contado por el cajero (el mismo que se persistió en el cierre).
  final double counted;

  /// Momento del cierre, tal como quedó en `closed_at` de `pos_shifts`.
  final String? closedAt;

  double get difference => counted - expected;
}

/// Estado del módulo Turnos y Cajas para la UI del POS.
///
/// Tiene la caja seleccionada (preferencia local, por defecto "Caja 1"), el
/// turno activo de esa caja y la lista de cajeros. Bloquea el POS cuando la
/// caja elegida no tiene turno abierto.
class ShiftProvider extends ChangeNotifier {
  ShiftProvider(this._repository, this._settings);

  final ShiftRepository _repository;
  final SettingsRepository _settings;

  List<PosRegister> _registers = const [];
  List<PosCashier> _cashiers = const [];
  PosShift? _activeShift;
  String _registerId = AppDatabase.kDefaultRegisterId;
  bool _loading = true;
  bool _working = false;
  String? _error;

  List<PosRegister> get registers => _registers;
  List<PosCashier> get cashiers => _cashiers;

  /// Turno abierto en la caja seleccionada, o `null` si el POS está bloqueado.
  PosShift? get activeShift => _activeShift;

  /// Id de la caja seleccionada (preferencia local).
  String get registerId => _registerId;

  /// Caja seleccionada (por nombre) o "Caja 1" si no existe.
  String get registerName {
    for (final register in _registers) {
      if (register.id == _registerId) return register.name;
    }
    return _registers.isEmpty ? 'Caja 1' : _registers.first.name;
  }

  bool get hasActiveShift => _activeShift?.isOpen ?? false;
  bool get loading => _loading;
  bool get working => _working;
  String? get error => _error;

  Future<void> start() async {
    try {
      _registers = await _repository.listRegisters();
      _registerId =
          await _settings.getOr(AppDatabase.kSettingRegisterId, AppDatabase.kDefaultRegisterId);
      if (!_registers.any((r) => r.id == _registerId)) {
        _registerId = _registers.isEmpty
            ? AppDatabase.kDefaultRegisterId
            : _registers.first.id;
        await _settings.set(AppDatabase.kSettingRegisterId, _registerId);
      }
      _cashiers = await _repository.listCashiers();
      _activeShift = await _repository.activeShift(_registerId);
    } catch (error) {
      _error = 'No se pudieron cargar las cajas: $error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cambia la caja activa (persistido localmente) y recarga su turno.
  Future<void> selectRegister(String registerId) async {
    if (registerId == _registerId) return;
    _registerId = registerId;
    await _settings.set(AppDatabase.kSettingRegisterId, registerId);
    _activeShift = await _repository.activeShift(registerId);
    notifyListeners();
  }

  /// Crea una caja nueva y la selecciona. Devuelve la id.
  Future<String> addRegister(String name) async {
    final id = await _repository.addRegister(name);
    _registers = await _repository.listRegisters();
    await selectRegister(id);
    notifyListeners();
    return id;
  }

  /// Abre el turno en la caja seleccionada con el cajero y PIN dados.
  /// Devuelve `null` si quedó abierto o el mensaje de error.
  Future<String?> openShift({
    required String cashierName,
    required String pin,
    required double openingAmount,
  }) async {
    if (pin.length != 4) return 'El PIN debe tener 4 dígitos.';
    if (hasActiveShift) {
      return 'Ya hay un turno abierto en $registerName';
    }
    _working = true;
    notifyListeners();
    try {
      final cashier =
          await _repository.ensureCashier(cashierName, pin);
      final shift = await _repository.openShift(
        registerId: _registerId,
        cashierId: cashier.id,
        openingAmount: openingAmount,
      );
      _activeShift = shift;
      _cashiers = await _repository.listCashiers();
      return null;
    } catch (error) {
      return 'No se pudo abrir el turno: $error';
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  /// Cierra el turno con el PIN del cajero y el efectivo contado. Devuelve el
  /// resultado del cuadre o un mensaje de error.
  Future<ShiftCloseResult?> closeShift({
    required String pin,
    required double counted,
  }) async {
    final shift = _activeShift;
    if (shift == null || shift.id == null) {
      return null;
    }
    final cashierId = shift.cashierId;
    if (cashierId == null) return null;
    final cashier = await _repository.cashierById(cashierId);
    if (cashier == null) return null;
    if (!ShiftRepository.verifyPin(pin, cashier.pinHash)) {
      return null;
    }
    _working = true;
    notifyListeners();
    try {
      final totals = await _repository.totalsFor(shift.id!);
      final expected = ShiftRepository.expectedFor(shift, totals);
      final closedAt = DateTime.now().toIso8601String();
      final result = ShiftCloseResult(
        shift: shift,
        totals: totals,
        expected: expected,
        counted: counted,
        closedAt: closedAt,
      );
      await _repository.closeShift(
        id: shift.id!,
        closingAmount: counted,
        expectedAmount: expected,
      );
      _activeShift = null;
      notifyListeners();
      return result;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  /// Totales actuales (ventas terminadas) del turno activo.
  Future<ShiftTotals> currentTotals() async {
    final shift = _activeShift;
    if (shift == null || shift.id == null) return const ShiftTotals();
    return _repository.totalsFor(shift.id!);
  }
}