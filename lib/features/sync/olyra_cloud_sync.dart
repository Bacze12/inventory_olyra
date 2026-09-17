// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/database/app_database.dart';
import '../../data/remote/olyra_pos_api.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/shift_repository.dart';
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

/// True solo para UUIDs canónicos (8-4-4-4-12 hex). Los `shift_id` locales del
/// escritorio son enteros ("7") y NO deben mandarse a una columna uuid.
bool _isValidUuid(String value) {
  if (value.length != 36) return false;
  final hex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  return hex.hasMatch(value);
}

/// Sincronizador/respaldo de la nube Olyra (olyra.cl), basado en las
/// credenciales de la licencia (License Key + JWT) obtenidas en la activación.
///
/// * **Revalidar** → `POST /api/v1/license/validate` con `license_key`,
///   `hwid`, `token` y `device_name`. Confirma que la licencia sigue vigente
///   y deja la UI en "Nube Activa · Sincronizado".
/// * **Sincronizar ahora / Subir respaldo** → `POST /api/v1/pos/sync` con un
///   lote de ventas (`pos_sales` + items), movimientos (`pos_movements`),
///   **el catálogo completo de productos** (`pos_products`) y los turnos
///   (`pos_shifts`) pendientes, vinculados al `user_app_id` (UUID de
///   la `user_apps`, no el `app_id` del producto).
///
/// Offline-first: la app nunca requiere la nube para vender. El respaldo es
/// idempotente (upsert por `user_app_id + local_id`) y al confirmarlo se marcan
/// las ventas/turnos locales como sincronizados (el contador vuelve a 0).
///
/// **Catálogo en cada sync**: a diferencia de ventas/turnos (que solo viajan
/// con `synced = 0`), el inventario local se envía SIEMPRE como foto completa
/// en cada sincronización rutinaria, no solo al pulsar "Subir respaldo". Así la
/// nube converge aunque el equipo nunca haya usado las acciones manuales. La
/// idempotencia la garantiza el servidor con `UNIQUE(user_app_id, local_id)`
/// (el `local_id` es el `id` del SQLite local) y el `updated_at` de cada
/// producto viaja como `local_updated_at` para mantener el last-write-wins.
class OlyraCloudSync extends ChangeNotifier {
  OlyraCloudSync({
    required OlyraLicenseController license,
    required LicenseCredentialStore credentials,
    required OlyraPosApi api,
    required SalesRepository sales,
    required MovementRepository movements,
    required ProductRepository products,
    required SettingsRepository settings,
    required ShiftRepository shifts,
  })  : _license = license,
        _credentials = credentials,
        _api = api,
        _sales = sales,
        _movements = movements,
        _products = products,
        _settings = settings,
        _shifts = shifts;

  static const String kLastSyncTs = 'olyra_cloud_last_sync_ts';

  /// Marca temporal del último envío exitoso del catálogo completo. Permite a
  /// la UI (y a futuros diagnósticos) saber cuándo se sincronizó el inventario
  /// sin depender de que haya cambios: el snapshot se reenvía igual, pero no
  /// repite el trabajo si dos ciclos se solapan.
  static const String kProductsSyncTs = 'olyra_cloud_products_sync_ts';

  final OlyraLicenseController _license;
  final LicenseCredentialStore _credentials;
  final OlyraPosApi _api;
  final SalesRepository _sales;
  final MovementRepository _movements;
  final ProductRepository _products;
  final SettingsRepository _settings;
  final ShiftRepository _shifts;

  OlyraCloudState _state = OlyraCloudState.unconfigured;
  String? _licenseKey;
  String? _deviceName;
  String? _hardwareId;
  String? _userAppId;
  String? _lastError;
  DateTime? _lastSync;
  int _pendingSales = 0;
  int _pendingShifts = 0;
  int _catalogSize = 0;
  int _lastSalesPushed = 0;
  int _lastMovementsPushed = 0;
  int _lastProductsPushed = 0;
  int _lastShiftsPushed = 0;
  String? _lastLocalBackupPath;
  int _lastLocalBackupSize = 0;

  OlyraCloudState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSync => _lastSync;
  int get pendingSales => _pendingSales;
  int get pendingShifts => _pendingShifts;

  /// Total de productos en el inventario local que viaja en cada sincronización.
  int get catalogSize => _catalogSize;
  int get lastSalesPushed => _lastSalesPushed;
  int get lastMovementsPushed => _lastMovementsPushed;
  int get lastProductsPushed => _lastProductsPushed;
  int get lastShiftsPushed => _lastShiftsPushed;

  /// Ruta del último respaldo físico `.db` generado (o `null` si nunca).
  String? get lastLocalBackupPath => _lastLocalBackupPath;
  int get lastLocalBackupSize => _lastLocalBackupSize;

  /// UUID de la `user_apps` (la bodega) dueña de los datos de esta licencia.
  ///
  /// Prefiere el valor que el controlador de licencia conoce EN VIVO (última
  /// activación/revalidación: claim firmado del JWT o respuesta del servidor);
  /// solo si no existe usa el leído por esta clase al arrancar.
  String get userAppId {
    final live = _license.userAppId;
    if (live != null && live.isNotEmpty) return live;
    return _userAppId ?? '';
  }

  String get deviceName => _deviceName ?? '';
  String get licenseKey => _licenseKey ?? '';

  bool get _licenseReady => _license.state == OlyraLicenseState.active;

  /// Resuelve el `user_app_id` al momento de enviar, sin confiar en el valor
  /// estaleado por [start]: autoridad = licencia (claims/JWT o lo persistido
  /// por Revalidar), luego lo leído por esta clase, luego el credencial local.
  /// Devuelve `''` si aún no existe (el backend lo resuelve desde la licencia).
  Future<String> _resolveUserAppId() async {
    final live = _license.userAppId;
    if (live != null && live.isNotEmpty) return live;
    if (_userAppId != null && _userAppId!.isNotEmpty) return _userAppId!;
    final credentials = await _credentials.read();
    final stored = credentials?.userAppId;
    return (stored == null || stored.isEmpty) ? '' : stored;
  }

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
    _userAppId = _license.userAppId ?? credentials?.userAppId;
    final storedLastSync = await _settings.get(kLastSyncTs);
    _lastSync = storedLastSync == null
        ? null
        : DateTime.tryParse(storedLastSync)?.toLocal();

    await refreshPending();
    _state = _licenseReady ? OlyraCloudState.unconfigured : OlyraCloudState.needsActivation;
    notifyListeners();
  }

  /// Recarga los contadores de pendientes DIRECTAMENTE de la BD local
  /// (`getUnsyncedSales()` / `synced = 0`). Público para que la tarjeta de
  /// "Nube y respaldo" refresque al abrirse, sin esperar al sync ni al
  /// arranque: si se insertaron ventas después del start(), aquí se ven.
  Future<void> refreshPending() async {
    _pendingSales = await _sales.countUnsyncedSales();
    _pendingShifts = (await _shifts.listForSync()).length;
    _catalogSize = await _products.count();
  }

  /// Resuelve el archivo físico `.db` (SQLite) de la app:
  /// `getApplicationSupportDirectory()/databases/inventory.db`.
  ///
  /// Devuelve `null` si aún no existe en disco (primera ejecución sin datos).
  Future<File?> locateDatabaseFile() async {
    File? file;
    try {
      final support = await getApplicationSupportDirectory()
          .timeout(const Duration(seconds: 10));
      file = File(p.join(support.path, 'databases', AppDatabase.databaseFileName));
    } catch (_) {
      return null;
    }
    return (await file.exists()) ? file : null;
  }

  /// Respaldo FÍSICO del SQLite local: vuelca la base abierta con `VACUUM INTO`
  /// a `getApplicationSupportDirectory()/backups/scanflow-<timestamp>.db`, de
  /// modo que el archivo capturado es una copia consistente (incluye las
  /// tablas `sales`, `sale_items`, `movements`, `pos_shifts`, `products`,
  /// `settings`).
  ///
  /// Es el complemento local del respaldo JSON a la nube: el "Subir respaldo"
  /// primero crea esta copia física y luego sincroniza el payload a olyra.cl.
  Future<File> createLocalBackup() async {
    final db = await AppDatabase.instance.database;
    final support = await getApplicationSupportDirectory()
        .timeout(const Duration(seconds: 10));
    final dir = Directory(p.join(support.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final output = File(p.join(dir.path, 'scanflow-${fileStamp()}.db'));
    if (await output.exists()) {
      await output.delete();
    }
    // VACUUM INTO toma una foto consistente aunque la BD esté abierta (a
    // diferencia de copiar el archivo, que podría quedar a mitad de escritura).
    final escaped = output.path.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");

    _lastLocalBackupPath = output.path;
    _lastLocalBackupSize = await output.length();
    debugPrint('[OlyraSync] Respaldo físico: ${output.path} '
        '($_lastLocalBackupSize bytes)');
    return output;
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
      // La revalidación pudo entregar (o re-confirmar) el `user_app_id` en el
      // controlador de licencia: reflejalo acá y guarédalo en credenciales al
      // instante para que "Sincronizar ahora / Subir respaldo" no vuelva a
      // verse bloqueado por un valor local vacío.
      final freshUserAppId = _license.userAppId;
      if (freshUserAppId != null && freshUserAppId.isNotEmpty) {
        _userAppId = freshUserAppId;
        await _credentials.saveUserAppId(freshUserAppId);
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

  /// Empuja a la nube el catálogo completo, las ventas/movimientos/turnos
  /// pendientes (batch upsert `pos_products`/`pos_sales`/`pos_movements`/
  /// `pos_shifts`). Al confirmar, marca ventas y turnos como sincronizados →
  /// sus contadores de pendientes vuelven a 0. El catálogo no usa flag local:
  /// se reenvía entero en cada ciclo y el servidor lo deduplica por
  /// `(user_app_id, local_id)`.
  ///
  /// Lanza [OlyraCloudNotReadyException] si en disco no hay una licencia para
  /// respaldar, u [OlyraSyncException] si la nube rechaza el lote (¿tablas sin
  /// crear? → 50x). El `user_app_id` NO bloquea: se resuelve en vivo y si el
  /// local aún no lo conoce, se envía vacío y el backend lo resuelve desde la
  /// licencia (hay que dejar que la nube responda, no cancelar acá).
  Future<OlyraSyncResult> syncNow() async {
    if (_licenseKey == null || _licenseKey!.isEmpty) {
      throw OlyraCloudNotReadyException(
          'No hay una licencia activa en este equipo. Actívala para usar la nube.');
    }
    if (_hardwareId == null || _hardwareId!.isEmpty) {
      throw OlyraCloudNotReadyException(
          'No se pudo identificar este equipo. Reabre la app para regenerar el HWID.');
    }

    _state = OlyraCloudState.syncing;
    _lastError = null;
    notifyListeners();

    final resolvedUserAppId = await _resolveUserAppId();

    try {
      final pendingSales = await _sales.getUnsyncedSales();
      final pendingMovements = await _movements.listForSync();
      final movements = pendingMovements
          .where((m) => (m['barcode'] as String?)?.isNotEmpty ?? false)
          .map(
            (m) => {
              'user_app_id': resolvedUserAppId,
              'local_id': m['local_id'].toString(),
              'local_created_at': m['created_at'],
              'barcode': m['barcode'],
              'type': m['type'],
              'delta': m['delta'],
              'quantity_after': m['quantity_after'],
            },
          )
          .toList();

      // Payload con nombres de clave del contrato backend:
      //   'sales'      → ventas `synced = 0` (WITH items del ticket)
      //   'movements'  → movimientos `synced = 0`
      //   'shifts'     → turnos `synced = 0`
      //   'products'   → catálogo completo (foto, siempre)
      final sales = pendingSales
          .where((s) => s.id != null)
          .map(
            (s) => {
              'user_app_id': resolvedUserAppId,
              'local_id': s.id.toString(),
              'local_created_at': s.createdAt,
              'local_updated_at': s.createdAt,
              'device_id': _hardwareId,
              'payment_method': s.paymentMethod.dbValue,
              'subtotal': s.subtotal,
              'discount': 0.0,
              'total': s.total,
              'status': s.status.dbValue,
              // El `shift_id` local es un entero (p.ej. "7") y en la nube la
              // columna es UUID: mandar el entero rompía el upsert de TODAS las
              // ventas ('invalid input syntax for type uuid'). Solo viaja si es
              // un UUID real; si no, se omite y la venta igual se respalda.
              'shift_id': _isValidUuid(s.shiftId ?? '') ? s.shiftId : null,
              'items': s.items
                  .where((item) => item.id != null)
                  .map(
                    (item) => {
                      'local_item_id': item.id.toString(),
                      'product_sku': item.barcode,
                      'product_name': item.productName,
                      'quantity': item.quantity,
                      'unit_price': item.unitPrice,
                      'subtotal': item.subtotal,
                    },
                  )
                  .toList(),
            },
          )
          .toList();

      final pendingShifts = await _shifts.listForSync();
      final shifts = pendingShifts
          .where((shift) => shift.id != null)
          .map(
            (shift) => {
              'user_app_id': resolvedUserAppId,
              'local_id': shift.id.toString(),
              'register_id': shift.registerId,
              'cashier_id': shift.cashierId,
              'opening_amount': shift.openingAmount,
              'closing_amount': shift.closingAmount,
              'expected_amount': shift.expectedAmount,
              'status': shift.status.dbValue,
              'opened_at': shift.openedAt,
              'closed_at': shift.closedAt,
            },
          )
          .toList();

      // ---- Catálogo completo: se envía SIEMPRE (foto de inventario), no solo
      // al pulsar "Subir respaldo". El backend lo upserta de forma idempotente
      // por (user_app_id, local_id); el `updated_at` local viaja como
      // `local_updated_at` para conservar el last-write-wins entre equipos.
      final catalog = await _products.all();
      final products = catalog
          .where((p) => p.id != null && p.barcode.isNotEmpty)
          .map(
            (p) => {
              'user_app_id': resolvedUserAppId,
              'local_id': p.id.toString(),
              'local_created_at': p.createdAt,
              'local_updated_at': p.updatedAt,
              'barcode': p.barcode,
              'name': p.name,
              'price': p.price,
              'stock': p.quantity,
            },
          )
          .toList();

      debugPrint('Enviando a sync: ${sales.length} ventas, ${movements.length} movimientos');

      final result = await _api.syncNow(
        licenseKey: _licenseKey ?? '',
        userAppId: resolvedUserAppId,
        hardwareId: _hardwareId ?? '',
        deviceName: _deviceName ?? '',
        sales: sales,
        movements: movements,
        products: products,
        shifts: shifts,
      );

      // El server responde 200 aunque alguna fila puntual haya fallado (no es
      // fatal para el resto del lote). No marcar como sincronizadas las que el
      // server reportó con error: seguirían pendientes y NO se pierden.
      final failedSales = <int>{};
      final failedMovements = <int>{};
      final ventaRe = RegExp(r'^venta (\d+):');
      final movimientoRe = RegExp(r'^movimiento (\d+):');
      for (final err in result.errors) {
        final m = movimientoRe.firstMatch(err);
        if (m != null) {
          failedMovements.add(int.tryParse(m.group(1)!) ?? -1);
          continue;
        }
        final v = ventaRe.firstMatch(err);
        if (v != null) failedSales.add(int.tryParse(v.group(1)!) ?? -1);

      }

      final ids = pendingSales
          .where((s) => s.id != null && !failedSales.contains(s.id))
          .map((s) => s.id!)
          .toList();
      if (ids.isNotEmpty) {
        await _sales.markSynced(ids);
      }
      final movementIds = movements
          .map((m) => int.tryParse(m['local_id'] as String? ?? ''))
          .whereType<int>()
          .where((id) => !failedMovements.contains(id))
          .toSet()
          .toList();
      if (movementIds.isNotEmpty) {
        await _movements.markSynced(movementIds);
      }
      final shiftIds =
          pendingShifts.where((shift) => shift.id != null).map((s) => s.id!).toList();
      if (shiftIds.isNotEmpty) {
        await _shifts.markSynced(shiftIds);
      }
      await refreshPending();
      await _storeSyncStamp();

      _lastSalesPushed = result.salesPushed;
      _lastMovementsPushed = result.movementsPushed;
      _lastProductsPushed = result.productsPushed;
      _lastShiftsPushed = result.shiftsPushed;
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

  /// Sella el ciclo completado. El catálogo viaja en cada ciclo, así que su
  /// marca temporal (`kProductsSyncTs`) avanza junto a la del sync general.
  Future<void> _storeSyncStamp() async {
    final now = DateTime.now();
    _lastSync = now;
    final iso = now.toUtc().toIso8601String();
    await _settings.set(kLastSyncTs, iso);
    await _settings.set(kProductsSyncTs, iso);
  }
}