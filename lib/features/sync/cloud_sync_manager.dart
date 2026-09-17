import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';
import '../../data/cloud/supabase_gateway.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_service.dart';

// Los constructores inyectan campos privados por nombre.
// ignore_for_file: prefer_initializing_formals

/// Estado visible del sincronizador para la UI.
enum CloudSyncState { unconfigured, needsLogin, idle, syncing, error }

/// Resultado de un ciclo de sincronización.
class CloudSyncResult {
  const CloudSyncResult({
    required this.productsPushed,
    required this.movementsPushed,
    required this.salesPushed,
    required this.productsPulled,
    required this.salesPulled,
    required this.stockWarnings,
  });

  final int productsPushed;
  final int movementsPushed;
  final int salesPushed;
  final int productsPulled;
  final int salesPulled;
  final int stockWarnings;

  bool get hasChanges =>
      productsPushed + movementsPushed + salesPushed + productsPulled +
          salesPulled >
      0;

  String describe() {
    if (!hasChanges) return 'Sin cambios pendientes.';
    return [
      if (productsPushed > 0) '$productsPushed producto(s) subidos',
      if (movementsPushed > 0) '$movementsPushed movimiento(s) subidos',
      if (salesPushed > 0) '$salesPushed venta(s) subidas',
      if (productsPulled > 0) '$productsPulled producto(s) descargados',
      if (salesPulled > 0) '$salesPulled venta(s) de otros equipos',
      if (stockWarnings > 0) '$stockWarnings con stock insuficiente',
    ].join(' · ');
  }
}

/// Sincronizador offline-first (SQLite local <-> Supabase).
///
/// Principios:
///  * La app es la fuente local: las ventas se escriben SIEMPRE en SQLite con
///    `synced = 0` y aquí se empujan en lotes cuando hay red (upsert
///    idempotente por `user_app_id + local_id`).
///  * Catálogo/stock: **last-write-wins** por `updated_at` (comparación en
///    Dart con `DateTime`, no en texto).
///  * Si un ítem de una venta remota no alcanza stock local, la venta se
///    registra igual y se marca `stock_warning` (filosofía offline-first).
///  * Reintentos con backoff exponencial (5s → 15min) al fallar, además de
///    un disparador por cambio de conectividad y un temporizador periódico.
///  * Todo acceso pasa por RLS con `auth.uid()` (requiere sesión).
class CloudSyncManager extends ChangeNotifier {
  CloudSyncManager({
    required SupabaseGateway gateway,
    required LicenseService license,
    required ProductRepository products,
    required MovementRepository movements,
    required SalesRepository sales,
    required SettingsRepository settings,
    Connectivity? connectivity,
  })  : _gateway = gateway,
        _license = license,
        _products = products,
        _movements = movements,
        _sales = sales,
        _settings = settings,
        _connectivity = connectivity ?? Connectivity();

  static const String kLastSyncTs = 'cloud_last_sync_ts';
  static const String kLastBackupAt = 'cloud_last_backup_at';

  static const Duration _periodicInterval = Duration(minutes: 15);
  static const Duration _backoffBase = Duration(seconds: 5);
  static const Duration _backoffMax = Duration(minutes: 15);
  static const int _backoffCapExponent = 8;

  final SupabaseGateway _gateway;
  final LicenseService _license;
  final ProductRepository _products;
  final MovementRepository _movements;
  final SalesRepository _sales;
  final SettingsRepository _settings;
  final Connectivity _connectivity;

  CloudSyncState _state = CloudSyncState.unconfigured;
  String? _lastError;
  DateTime? _lastSuccess;
  int _pendingSales = 0;
  bool _running = false;
  int _consecutiveFailures = 0;

  Timer? _retryTimer;
  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectionSub;

  CloudSyncState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSuccess => _lastSuccess;
  int get pendingSales => _pendingSales;

  bool get enabled => AppConfig.enableCloudSync && _gateway.isConfigured;

  /// Carga el contador de ventas pendientes y arranca ciclos periódicos.
  Future<void> start() async {
    if (!enabled) {
      _state = CloudSyncState.unconfigured;
      notifyListeners();
      return;
    }
    await _refreshPending();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) => maybeSyncNow());

    _connectionSub = _connectivity.onConnectivityChanged.listen(
      (results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) maybeSyncNow();
      },
    );

    maybeSyncNow();
  }

  Future<void> _refreshPending() async {
    _pendingSales = (await _sales.listForSync()).length;
  }

  /// Disparo seguro (no reentrante, sin sesión no hace nada).
  ///
  /// Devuelve el resultado del ciclo cuando se ejecutó, o `null` si el disparo
  /// se omitió (nube desactivada, ciclo en curso, sin sesión o error).
  Future<CloudSyncResult?> maybeSyncNow() async {
    if (!enabled) {
      _state = CloudSyncState.unconfigured;
      notifyListeners();
      return null;
    }
    if (_running) return null;
    if (!await _gateway.hasSession()) {
      _state = CloudSyncState.needsLogin;
      notifyListeners();
      return null;
    }

    _running = true;
    _state = CloudSyncState.syncing;
    notifyListeners();

    try {
      final result = await syncNow();
      if (!enabled) return null;
      _consecutiveFailures = 0;
      _lastError = null;
      _lastSuccess = DateTime.now();
      _state = CloudSyncState.idle;
      return result;
    } catch (error) {
      if (!enabled) return null;
      _consecutiveFailures++;
      _lastError = '$error';
      _state = CloudSyncState.error;
      _scheduleRetry();
      return null;
    } finally {
      _running = false;
      await _refreshPending();
      notifyListeners();
    }
  }

  /// Programa el siguiente intento con backoff exponencial.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final exponent = math.min(_consecutiveFailures - 1, _backoffCapExponent);
    final delay = Duration(
      milliseconds:
          math.min(_backoffBase.inMilliseconds * (1 << exponent), _backoffMax.inMilliseconds),
    );
    debugPrint('[CloudSync] Reintento en ${delay.inSeconds}s '
        '(fallo #$_consecutiveFailures)');
    _retryTimer = Timer(delay, maybeSyncNow);
  }

  /// Ejecuta un ciclo completo de sincronización. Idempotente.
  ///
  /// Orden: subir cambios locales (productos, movimientos, ventas) → bajar
  /// cambios de otros dispositivos (productos, ventas) → avanzar cursor.
  Future<CloudSyncResult> syncNow() async {
    await _gateway.requireUid();
    final userAppId = _license.userAppId;
    if (userAppId == null || userAppId.isEmpty) {
      throw CloudLicenseNotReadyException(
        'Licencia no válida: valida el dispositivo antes de sincronizar.',
      );
    }
    final hardwareId = _license.hardwareId;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final cursor = DateTime.tryParse(
      await _settings.getOr(kLastSyncTs, ''),
    );

    var productsPushed = 0;
    var movementsPushed = 0;
    var salesPushed = 0;
    var productsPulled = 0;
    var salesPulled = 0;
    var stockWarnings = 0;

    final client = await _gateway.client();

    // ---- 1) POS productos: changelog local → nube (LWW upser).
    final localProducts = await _products.all();
    final dirtyProducts = cursor == null
        ? localProducts
        : localProducts
              .where((p) => _afterIso(p.updatedAt, cursor))
              .toList();
    if (dirtyProducts.isNotEmpty) {
      final payload = dirtyProducts
          .map(
            (p) => {
              'user_app_id': userAppId,
              'barcode': p.barcode,
              'name': p.name,
              'quantity': p.quantity,
              'min_stock': p.minStock,
              'price': p.price,
              'image_path': p.imagePath,
              'updated_by': hardwareId,
              'updated_at': p.updatedAt,
            },
          )
          .toList();
      await client
          .from('pos_products')
          .upsert(payload, onConflict: 'user_app_id,barcode');
      productsPushed = payload.length;
    }

    // ---- 2) POS movimientos: réplica histórica de transacciones.
    final allMovements = await _movements.allWithBarcode();
    final dirtyMovements = cursor == null
        ? allMovements
        : allMovements
              .where((m) => _afterIso((m['created_at'] as String?), cursor))
              .toList();
    if (dirtyMovements.isNotEmpty) {
      final payload = dirtyMovements
          .where((m) => (m['barcode'] as String?)?.isNotEmpty ?? false)
          .map(
            (m) => {
              'user_app_id': userAppId,
              'barcode': m['barcode'],
              'type': m['type'],
              'delta': m['delta'],
              'quantity_after': m['quantity_after'],
              'created_at': m['created_at'],
            },
          )
          .toList();
      await _batchUpsert(
        client,
        'pos_movements',
        payload,
        onConflict: 'id',
      );
      movementsPushed = payload.length;
    }

    // ---- 3) Ventas pendientes (synced = 0) → nube (upsert idempotente).
    final pendingSales = await _sales.listForSync();
    if (pendingSales.isNotEmpty) {
      final headers = pendingSales
          .where((s) => s.id != null)
          .map(
            (s) => {
              'user_app_id': userAppId,
              'local_id': s.id,
              'device_hardware_id': hardwareId,
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

      // Devuelve los ids uuid de la nube para enlazar las líneas.
      final upserted = await _batchUpsert(
        client,
        'pos_sales',
        headers,
        onConflict: 'user_app_id,local_id',
        select: 'id,local_id',
      );
      final cloudIdByLocal = <int, String>{
        for (final row in upserted)
          (row['local_id'] as num).toInt(): row['id'] as String,
      };

      final items = <Map<String, dynamic>>[];
      for (final sale in pendingSales) {
        final cloudSaleId = cloudIdByLocal[sale.id];
        if (cloudSaleId == null) continue;
        for (final item in sale.items) {
          items.add({
            'sale_id': cloudSaleId,
            'barcode': item.barcode,
            'product_name': item.productName,
            'unit_price': item.unitPrice,
            'quantity': item.quantity,
            'subtotal': item.subtotal,
          });
        }
      }
      if (items.isNotEmpty) {
        await _batchUpsert(
          client,
          'pos_sale_items',
          items,
          onConflict: 'id',
        );
      }
      await _sales.markSynced(
        pendingSales.where((s) => s.id != null).map((s) => s.id!).toList(),
      );
      salesPushed = pendingSales.length;
    }

    // ---- 4) Productos de otros equipos → local (LWW gana el más nuevo).
    final productsSource = client
        .from('pos_products')
        .select('barcode,name,quantity,min_stock,price,updated_at');
    if (cursor != null) {
      productsSource.gt('updated_at', cursor.toIso8601String());
    }
    final remoteProducts = await productsSource.order('updated_at');
    for (final row in remoteProducts) {
      final barcode = row['barcode'] as String? ?? '';
      if (barcode.isEmpty) continue;
      final cloudUpdated = DateTime.tryParse((row['updated_at'] as String?) ?? '');
      final local = await _products.byBarcode(barcode);
      final localUpdated = local != null ? DateTime.tryParse(local.updatedAt) : null;
      final cloudNewer = cloudUpdated != null &&
          (localUpdated == null || cloudUpdated.isAfter(localUpdated));
      if (!cloudNewer) continue;
      await _products.upsertFromSync(
        barcode: barcode,
        name: row['name'] as String? ?? '',
        quantity: (row['quantity'] as num?)?.toInt() ?? 0,
        minStock: (row['min_stock'] as num?)?.toInt() ?? 0,
        price: (row['price'] as num?)?.toDouble() ?? 0.0,
        updatedAt: (row['updated_at'] as String?) ?? nowIso(),
      );
      productsPulled++;
    }

    // ---- 5) Ventas de OTROS dispositivos → local (réplica + stock).
    final remoteSalesSource = client.from('pos_sales').select(
        'id,local_id,device_hardware_id,payment_method,subtotal,tax_rate,tax_amount,total,received,change,status,stock_warning,created_at');
    if (cursor != null) {
      remoteSalesSource.gt('created_at', cursor.toIso8601String());
    }
    final remoteSales = await remoteSalesSource.order('created_at');
    for (final row in remoteSales) {
      final remoteDevice = row['device_hardware_id'] as String? ?? '';
      if (remoteDevice == hardwareId) continue; // es la nuestra.

      final createdAt = row['created_at'] as String? ?? '';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;
      final duplicates = await _sales.findRemoteDuplicate(
        remoteDevice,
        createdAt,
        total,
      );
      if (duplicates) continue;

      // Líneas del objeto remoto.
      final itemRows = await client
          .from('pos_sale_items')
          .select('barcode,product_name,unit_price,quantity,subtotal')
          .eq('sale_id', row['id']);

      var stockWarning = row['stock_warning'] == true;
      for (final item in itemRows) {
        final barcode = item['barcode'] as String? ?? '';
        if (barcode.isEmpty) continue;
        final applied = await _products.deductStockFromSync(
          barcode,
          (item['quantity'] as num?)?.toInt() ?? 1,
        );
        stockWarning = stockWarning || !applied;
      }
      if (stockWarning) stockWarnings++;

      final insertedId = await _sales.insertSale(
        items: itemRows
            .map(
              (item) => SaleItem(
                productId: null,
                productName: item['product_name'] as String? ?? '',
                barcode: item['barcode'] as String?,
                unitPrice: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
                quantity: (item['quantity'] as num?)?.toInt() ?? 1,
                subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0.0,
              ),
            )
            .toList(),
        method: PaymentMethod.fromDb(row['payment_method'] as String? ?? ''),
        subtotal: (row['subtotal'] as num?)?.toDouble() ?? 0.0,
        taxRate: (row['tax_rate'] as num?)?.toDouble() ?? 0.0,
        tax: (row['tax_amount'] as num?)?.toDouble() ?? 0.0,
        total: total,
        received: (row['received'] as num?)?.toDouble(),
        change: (row['change'] as num?)?.toDouble() ?? 0.0,
        deviceToken: remoteDevice,
        status: SaleStatus.fromDb(row['status'] as String? ?? ''),
        createdAt: createdAt,
        stockWarning: stockWarning,
      );
      // Se marca sincronizada para no re-subirla al servidor.
      await _sales.markSynced([insertedId]);
      salesPulled++;
    }

    // ---- 6) Avanza el cursor solo tras un ciclo completo exitoso.
    await _settings.set(kLastSyncTs, timestamp);
    debugPrint('[CloudSync] Ciclo completado: $timestamp');
    return CloudSyncResult(
      productsPushed: productsPushed,
      movementsPushed: movementsPushed,
      salesPushed: salesPushed,
      productsPulled: productsPulled,
      salesPulled: salesPulled,
      stockWarnings: stockWarnings,
    );
  }

  /// Upsert en lotes; devuelve las filas de vuelta si `select` no es nulo.
  Future<List<Map<String, dynamic>>> _batchUpsert(
    dynamic client,
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
    String? select,
  }) async {
    if (rows.isEmpty) return const [];
    const chunkSize = 200;
    final all = <Map<String, dynamic>>[];
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = math.min(start + chunkSize, rows.length);
      final chunk = rows.sublist(start, end);
      final result = await client
          .from(table)
          .upsert(chunk, onConflict: onConflict)
          .select(select ?? '*');
      if (result is List<dynamic>) {
        all.addAll(result.whereType<Map<String, dynamic>>());
      }
    }
    return all;
  }

  static bool _afterIso(String? iso, DateTime bound) {
    final value = iso == null ? null : DateTime.tryParse(iso);
    return value != null && value.isAfter(bound);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _periodicTimer?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }
}