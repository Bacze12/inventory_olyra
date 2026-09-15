// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/remote/olyra_pos_api.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../activation/license_credential_store.dart';
import '../activation/olyra_license_controller.dart';

/// Estado visible del sincronizador de nube para la UI.
enum OlyraCloudState { unconfigured, needsActivation, validating, syncing, active, error }

/// La operación de nube no se puede completar sin licencia activa o cuenta
/// vinculada en este equipo (sincronizar, respaldar, etc.).
class OlyraCloudNotReadyException implements Exception {
  OlyraCloudNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sincronizador/respaldo de la nube Olyra (olyra.cl), basado en las
/// credenciales de la licencia (License Key + JWT) obtenidas en la activación.
///
/// * **Revalidar** → `POST /api/v1/license/validate` con `license_key`,
///   `hwid`, `token` y `device_name`. Confirma que la licencia sigue vigente
///   y deja la UI en "Nube Activa · Sincronizado".
/// * **Sincronizar ahora / Subir respaldo** → `POST /api/v1/pos/sync` con un
///   lote de ventas (`pos_sales` + items) y movimientos (`pos_movements`)
///   pendientes, vinculados al `user_app_id` (claim `app_id` del JWT).
///
/// Offline-first: la app nunca requiere la nube para vender. El respaldo es
/// idempotente (upsert por `user_app_id + local_id`) y al confirmarlo se marcan
/// las ventas locales como sincronizadas (el contador vuelve a 0).
class OlyraCloudSync extends ChangeNotifier {
  OlyraCloudSync({
    required OlyraLicenseController license,
    required LicenseCredentialStore credentials,
    required OlyraPosApi api,
    required SalesRepository sales,
    required MovementRepository movements,
    required SettingsRepository settings,
  })  : _license = license,
        _credentials = credentials,
        _api = api,
        _sales = sales,
        _movements = movements,
        _settings = settings;

  static const String kLastSyncTs = 'olyra_cloud_last_sync_ts';

  final OlyraLicenseController _license;
  final LicenseCredentialStore _credentials;
  final OlyraPosApi _api;
  final SalesRepository _sales;
  final MovementRepository _movements;
  final SettingsRepository _settings;

  OlyraCloudState _state = OlyraCloudState.unconfigured;
  String? _licenseKey;
  String? _deviceName;
  String? _hardwareId;
  String? _userAppId;
  String? _lastError;
  DateTime? _lastSync;
  int _pendingSales = 0;
  int _lastSalesPushed = 0;
  int _lastMovementsPushed = 0;

  OlyraCloudState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSync => _lastSync;
  int get pendingSales => _pendingSales;
  int get lastSalesPushed => _lastSalesPushed;
  int get lastMovementsPushed => _lastMovementsPushed;

  /// Cuenta de la nube a la que pertenece esta licencia (claim `app_id`).
  String get userAppId => _userAppId ?? '';
  String get deviceName => _deviceName ?? '';
  String get licenseKey => _licenseKey ?? '';

  bool get _licenseReady => _license.state == OlyraLicenseState.active;

  /// Carga las credenciales de la activación y el contador de pendientes.
  Future<void> start() async {
    final credentials = await _credentials.read();
    _licenseKey = credentials?.licenseKey ?? '';
    _hardwareId =
        _license.hardwareId ?? (credentials?.hardwareId.isNotEmpty == true
            ? credentials!.hardwareId
            : '');
    _deviceName =
        credentials?.deviceName ?? _license.deviceName ?? '';
    _userAppId = _license.claims?.payload['app_id']?.toString() ?? '';
    final storedLastSync = await _settings.get(kLastSyncTs);
    _lastSync = storedLastSync == null
        ? null
        : DateTime.tryParse(storedLastSync)?.toLocal();

    await _refreshPending();
    _state = _licenseReady ? OlyraCloudState.unconfigured : OlyraCloudState.needsActivation;
    notifyListeners();
  }

  Future<void> _refreshPending() async {
    _pendingSales = (await _sales.listForSync()).length;
  }

  /// Revalidación manual contra `/api/v1/license/validate`. Devuelve `true` si
  /// el servidor confirmó la licencia (deja la UI en "Nube Activa").
  Future<bool> validate() async {
    if (!_licenseReady) {
      _state = OlyraCloudState.needsActivation;
      notifyListeners();
      return false;
    }
    _state = OlyraCloudState.validating;
    _lastError = null;
    notifyListeners();

    try {
      final ok = await _license.validateNow();
      if (!ok) {
        _state = OlyraCloudState.error;
        _lastError = 'El servidor no confirmó la licencia en este equipo.';
        notifyListeners();
        return false;
      }
      await _storeSyncStamp();
      _state = OlyraCloudState.active;
      notifyListeners();
      return true;
    } catch (error) {
      _state = OlyraCloudState.error;
      _lastError = '$error';
      notifyListeners();
      return false;
    }
  }

  /// Empuja ventas y movimientos locales pendientes a la nube (batch upsert
  /// `pos_sales`/`pos_movements`). Al confirmar, marca las ventas sincronizadas
  /// → el contador de pendientes vuelve a 0.
  ///
  /// Lanza [OlyraCloudNotReadyException] si no hay licencia activa o cuenta
  /// vinculada, u [OlyraSyncException] si la nube rechaza el lote.
  Future<OlyraSyncResult> syncNow() async {
    if (!_licenseReady) {
      throw OlyraCloudNotReadyException(
          'La licencia no está activa en este equipo. Actívala antes de sincronizar.');
    }
    if (_userAppId == null || _userAppId!.isEmpty) {
      throw OlyraCloudNotReadyException(
          'La nube no está vinculada. Usa "Revalidar" para conectar la cuenta.');
    }

    _state = OlyraCloudState.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final pendingSales = await _sales.listForSync();
      final rawMovements = await _movements.allWithBarcode();
      final movements = rawMovements
          .where((m) => (m['barcode'] as String?)?.isNotEmpty ?? false)
          .map(
            (m) => {
              'user_app_id': _userAppId,
              'barcode': m['barcode'],
              'type': m['type'],
              'delta': m['delta'],
              'quantity_after': m['quantity_after'],
              'created_at': m['created_at'],
            },
          )
          .toList();

      final sales = pendingSales
          .where((s) => s.id != null)
          .map(
            (s) => {
              'user_app_id': _userAppId,
              'local_id': s.id,
              'device_hardware_id': _hardwareId,
              'payment_method': s.paymentMethod.dbValue,
              'subtotal': s.subtotal,
              'tax_rate': s.taxRate,
              'tax_amount': s.taxAmount,
              'total': s.total,
              'received': s.received,
              'change': s.change,
              'status': s.status.dbValue,
              'stock_warning': s.stockWarning,
              'created_at': s.createdAt,
            },
          )
          .toList();

      final result = await _api.syncNow(
        licenseKey: _licenseKey ?? '',
        userAppId: _userAppId!,
        hardwareId: _hardwareId ?? '',
        deviceName: _deviceName ?? '',
        sales: sales,
        movements: movements,
      );

      final ids = pendingSales.where((s) => s.id != null).map((s) => s.id!).toList();
      if (ids.isNotEmpty) {
        await _sales.markSynced(ids);
      }
      await _refreshPending();
      await _storeSyncStamp();

      _lastSalesPushed = result.salesPushed;
      _lastMovementsPushed = result.movementsPushed;
      _lastError = null;
      _state = OlyraCloudState.active;
      return result;
    } catch (error) {
      _state = OlyraCloudState.error;
      _lastError = '$error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _storeSyncStamp() async {
    final now = DateTime.now();
    _lastSync = now;
    await _settings.set(kLastSyncTs, now.toUtc().toIso8601String());
  }
}