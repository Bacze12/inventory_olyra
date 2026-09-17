import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/constants/app_constants.dart';
import '../../data/cloud/supabase_gateway.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_service.dart';

// Los constructores inyectan campos privados por nombre.
// ignore_for_file: prefer_initializing_formals

/// Copias de seguridad de la bodega en la nube.
///
/// Toma un snapshot completo de la base local (inventario, catálogo de
/// precios y el historial de ventas con sus líneas), lo serializa en JSON y
/// lo sube **comprimido (gzip)** al bucket privado `pos-backups`, bajo el
/// prefijo `{auth.uid()}/backups/...` (la política RLS de Storage solo admite
/// ese path), de modo que cada usuario respalda en su propio espacio.
class BackupService extends ChangeNotifier {
  BackupService({
    required SupabaseGateway gateway,
    required LicenseService license,
    required ProductRepository products,
    required MovementRepository movements,
    required SalesRepository sales,
    required SettingsRepository settings,
  })  : _gateway = gateway,
        _license = license,
        _products = products,
        _movements = movements,
        _sales = sales,
        _settings = settings;

  final SupabaseGateway _gateway;
  final LicenseService _license;
  final ProductRepository _products;
  final MovementRepository _movements;
  final SalesRepository _sales;
  final SettingsRepository _settings;

  static const String kLastBackupAt = 'cloud_last_backup_at';

  bool _running = false;
  DateTime? _lastBackupAt;
  String? _lastBackupPath;
  String? _lastError;

  bool get running => _running;
  DateTime? get lastBackupAt => _lastBackupAt;
  String? get lastBackupPath => _lastBackupPath;
  String? get lastError => _lastError;

  /// Genera el snapshot, lo comprime y lo sube. Devuelve el path de Storage.
  Future<String> createBackup() async {
    final uid = await _gateway.requireUid();
    if (_license.userAppId == null) {
      throw CloudLicenseNotReadyException(
        'Licencia no válida: valida el dispositivo antes de respaldar.',
      );
    }
    if (_running) return _lastBackupPath ?? '';

    _running = true;
    _lastError = null;
    notifyListeners();
    try {
      final payload = await _buildSnapshot();
      final json = jsonEncode(payload);
      final compressed = gzip.encode(utf8.encode(json));
      final upload = Uint8List.fromList(compressed);

      final ts = DateTime.now().toUtc();
      final fileName = 'bodegaflow-${ts.millisecondsSinceEpoch}.json.gz';
      final path = '$uid/backups/$fileName';

      final client = await _gateway.client();
      await client.storage
          .from(SupabaseConfig.backupBucket)
          .uploadBinary(
            path,
            upload,
            fileOptions: FileOptions(contentType: 'application/gzip', upsert: true),
          );

      _lastBackupAt = ts;
      _lastBackupPath = path;
      await _settings.set(
        kLastBackupAt,
        ts.toIso8601String(),
      );
      debugPrint('[Backup] Subido: $path (${compressed.length} bytes)');
      return path;
    } catch (error) {
      _lastError = '$error';
      debugPrint('[Backup] Error: $error');
      rethrow;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Armado del snapshot JSON de la bodega.
  Future<Map<String, dynamic>> _buildSnapshot() async {
    final products = (await _products.all())
        .map((p) => p.toMap())
        .toList();

    final movements = await _movements.allWithBarcode();

    final sales = <Map<String, dynamic>>[];
    for (final header in await _sales.getSalesHistory()) {
      if (header.id == null) continue;
      final full = await _sales.byId(header.id!);
      sales.add({
        'payment_method': full.paymentMethod.dbValue,
        'subtotal': full.subtotal,
        'tax_rate': full.taxRate,
        'tax_amount': full.taxAmount,
        'total': full.total,
        'received': full.received,
        'change': full.change,
        'status': full.status.dbValue,
        'device_token': full.deviceToken,
        'synced': full.synced,
        'stock_warning': full.stockWarning,
        'created_at': full.createdAt,
        'items': full.items
            .map(
              (item) => {
                'product_name': item.productName,
                'barcode': item.barcode,
                'unit_price': item.unitPrice,
                'quantity': item.quantity,
                'subtotal': item.subtotal,
              },
            )
            .toList(),
      });
    }

    return {
      'app': 'BodegaFlow POS',
      'app_package': AppConstants.appName,
      'hardware_id': _license.hardwareId,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'products': products,
      'movements': movements,
      'sales': sales,
    };
  }
}