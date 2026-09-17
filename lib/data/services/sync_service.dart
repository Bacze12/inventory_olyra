import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/utils/formatters.dart';
import '../models/sale.dart';
import '../repositories/product_repository.dart';
import '../repositories/sales_repository.dart';
import 'pairing_service.dart';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

/// Encabezados CORS para que el health check sea accesible desde el navegador
/// del celular y, si algún día se usa una web, no falle el preflight OPTIONS.
const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, x-device-token',
};

/// Middleware CORS: contesta preflights OPTIONS y añade la cabecera de origen
/// permitido a todas las respuestas del servidor local.
Middleware corsMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

/// Producto del catálogo tal como viaja entre la PC y el teléfono.
@immutable
class CatalogProduct {
  const CatalogProduct({
    required this.barcode,
    required this.name,
    required this.quantity,
    required this.minStock,
    required this.price,
    required this.updatedAt,
  });

  const CatalogProduct.empty()
      : barcode = '',
        name = '',
        quantity = 0,
        minStock = 0,
        price = 0.0,
        updatedAt = '';

  final String barcode;
  final String name;
  final int quantity;
  final int minStock;
  final double price;
  final String updatedAt;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        barcode: json['barcode'] as String? ?? '',
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        minStock: (json['min_stock'] as num?)?.toInt() ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        updatedAt: json['updated_at'] as String? ?? nowIso(),
      );

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'quantity': quantity,
        'min_stock': minStock,
        'price': price,
        'updated_at': updatedAt,
      };

  bool get isValid => barcode.trim().isNotEmpty && name.trim().isNotEmpty;
}

/// Línea de ticket tal como viaja en el payload de ventas.
@immutable
class SyncedSaleItem {
  const SyncedSaleItem({
    required this.productName,
    required this.barcode,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
  });

  final String productName;
  final String? barcode;
  final double unitPrice;
  final int quantity;
  final double subtotal;

  factory SyncedSaleItem.fromJson(Map<String, dynamic> json) => SyncedSaleItem(
        productName: json['product_name'] as String? ?? '',
        barcode: json['barcode'] as String?,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'barcode': barcode,
        'unit_price': unitPrice,
        'quantity': quantity,
        'subtotal': subtotal,
      };
}

/// Cabecera de venta tal como viaja del teléfono → PC (`POST /sync/sales`).
@immutable
class SyncedSale {
  const SyncedSale({
    required this.deviceToken,
    required this.method,
    required this.subtotal,
    required this.taxRate,
    required this.tax,
    required this.total,
    required this.received,
    required this.change,
    required this.status,
    required this.createdAt,
    required this.items,
  });

  final String deviceToken;
  final PaymentMethod method;
  final double subtotal;
  final double taxRate;
  final double tax;
  final double total;
  final double? received;
  final double change;
  final SaleStatus status;
  final String createdAt;
  final List<SyncedSaleItem> items;

  static SyncedSale fromSale(Sale sale, {required String deviceToken}) =>
      SyncedSale(
        deviceToken: deviceToken,
        method: sale.paymentMethod,
        subtotal: sale.subtotal,
        taxRate: sale.taxRate,
        tax: sale.taxAmount,
        total: sale.total,
        received: sale.received,
        change: sale.change,
        status: sale.status,
        createdAt: sale.createdAt,
        items: sale.items
            .map(
              (item) => SyncedSaleItem(
                productName: item.productName,
                barcode: item.barcode,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                subtotal: item.subtotal,
              ),
            )
            .toList(),
      );

  factory SyncedSale.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map<String, dynamic>>()
            .map(SyncedSaleItem.fromJson)
            .toList()
        : <SyncedSaleItem>[];
    return SyncedSale(
      deviceToken: json['device_token'] as String? ?? '',
      method: PaymentMethod.fromDb(json['payment_method'] as String? ?? ''),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      received: (json['received'] as num?)?.toDouble(),
      change: (json['change'] as num?)?.toDouble() ?? 0.0,
      status: SaleStatus.fromDb(json['status'] as String? ?? ''),
      createdAt: json['created_at'] as String? ?? nowIso(),
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_token': deviceToken,
        'payment_method': method.dbValue,
        'subtotal': subtotal,
        'tax_rate': taxRate,
        'tax_amount': tax,
        'total': total,
        'received': received,
        'change': change,
        'status': status.dbValue,
        'created_at': createdAt,
        'items': items.map((item) => item.toJson()).toList(),
      };

  bool get isValid => deviceToken.isNotEmpty && items.isNotEmpty;
}

/// Descripción breve en español para un código HTTP (diagnóstico en UI).
String _httpStatusLabel(int code) {
  switch (code) {
    case 400:
      return 'Solicitud inválida';
    case 401:
      return 'Token inválido';
    case 403:
      return 'Acceso denegado';
    case 404:
      return 'Ruta no encontrada';
    case 405:
      return 'Método no permitido';
    case 500:
      return 'Error interno del servidor';
    case 502:
      return 'Gateway inválido';
    case 503:
      return 'Servicio no disponible';
    default:
      return 'Error del servidor';
  }
}

/// Respuesta HTTP 4xx/5xx del servidor local. NO es un fallo de transporte:
/// la IP respondió, así que no debe dispararse el escaneo de subred.
class SyncRemoteException implements Exception {
  SyncRemoteException(this.message);

  final String message;

  @override
  String toString() => 'SyncRemoteException: $message';
}

/// Resultado de una sincronización, para informar en la UI.
class SyncResult {
  const SyncResult.failure(this.error)
      : isSuccess = false,
        catalogSynced = 0,
        salesSent = 0,
        duplicates = 0,
        stockWarnings = 0,
        remoteSalesReceived = 0;

  const SyncResult.success({
    required this.catalogSynced,
    required this.salesSent,
    required this.duplicates,
    this.stockWarnings = 0,
    this.remoteSalesReceived = 0,
  })  : isSuccess = true,
        error = null;

  final bool isSuccess;
  final String? error;
  final int catalogSynced;
  final int salesSent;
  final int duplicates;

  /// Ventas recibidas con stock insuficiente en el servidor (offline-first).
  final int stockWarnings;

  /// Ventas del historial de la PC descargadas e insertadas en el teléfono.
  final int remoteSalesReceived;

  String describe() {
    if (!isSuccess) return error ?? 'Sincronización fallida.';
    var text = '$catalogSynced producto(s) descargados de la PC';
    if (salesSent > 0) {
      text += ' · $salesSent venta(s) enviada(s)';
    }
    if (remoteSalesReceived > 0) {
      text += ' · $remoteSalesReceived del historial de la PC';
    }
    if (stockWarnings > 0) {
      text += ' · $stockWarnings con stock insuficiente';
    }
    if (duplicates > 0) {
      text += ' · $duplicates duplicada(s)';
    }
    return text;
  }
}

/// Servidor local de la PC (Shelf, puerto 8080).
///
/// Sirve `GET /api/v1/sync/catalog` (catálogo + stock) y recibe
/// `POST /api/v1/sync/sales` (ventas del teléfono). Solo se levanta en
/// escritorio y cuando el dispositivo está vinculado.
class SyncServer {
  SyncServer({
    required this.products,
    required this.sales,
    this.tenantId,
  });

  final ProductRepository products;
  final SalesRepository sales;
  final String? tenantId;

  static const int defaultPort = 8080;

  /// Límite de ventas más recientes que la PC expone al teléfono por GET.
  static const int _historyLimit = 500;

  /// Regla de PowerShell para abrir el puerto del servidor en el Firewall de
  /// Windows (los escaneos entrantes del móvil rebotan si está bloqueado).
  static const String firewallRule =
      'netsh advfirewall firewall add rule name="ScanFlow Sync 8080" '
      'dir=in action=allow protocol=TCP localport=8080';

  /// Referencia global al servidor activo (para detenerlo al desvincular).
  static SyncServer? appServer;

  HttpServer? _server;
  int _port = defaultPort;

  bool get isRunning => _server != null;
  int get port => _port;

  /// Levanta el servidor en `port`. Devuelve false si el puerto está ocupado.
  Future<bool> start({
    int port = defaultPort,
    InternetAddress? bindAddress,
  }) async {
    if (_server != null) return true;

    final router = Router()
      ..get('/api/v1/sync/health', _health)
      ..get('/api/v1/sync/catalog', _catalog)
      ..get('/api/v1/sync/sales', _salesList)
      ..post('/api/v1/sync/sales', _sales);

    final handler = Pipeline()
        .addMiddleware(logRequests())
        // Responde desde la LAN a otros dispositivos (0.0.0.0) y con CORS.
        .addMiddleware(corsMiddleware())
        .addHandler(router.call);

    try {
      // anyIPv4 (0.0.0.0): NUNCA loopback, para aceptar el móvil de la LAN.
      final server = await shelf_io.serve(
        handler,
        bindAddress ?? InternetAddress.anyIPv4,
        port,
      );
      server.autoCompress = true;
      _server = server;
      _port = port;
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } catch (_) {
      // El servidor ya estaba cerrado.
    }
    _server = null;
    if (identical(appServer, this)) appServer = null;
  }

  Future<Response> _health(Request request) async =>
      Response.ok(
        jsonEncode({
          'status': 'ok',
          'tenant_id': tenantId,
          'sync_ts': nowIso(),
        }),
        headers: _jsonHeaders,
      );

  /// Historial de ventas de la PC para el teléfono, en el mismo shape que
  /// `POST /sales`. Excluye las ventas originadas por el dispositivo que las
  /// pide (vienen de vuelta re-descargadas; el teléfono además deduplica).
  Future<Response> _salesList(Request request) async {
    final auth = request.headers['x-device-token'];
    if (auth == null || !auth.startsWith('dvt_')) {
      return Response(401,
          body: jsonEncode({'error': 'unauthenticated'}),
          headers: _jsonHeaders);
    }

    final remote = <Map<String, dynamic>>[];
    var count = 0;
    for (final header in await sales.getSalesHistory()) {
      final skipOwn = header.deviceToken == auth;
      if (skipOwn || header.id == null) continue;
      final sale = (await sales.byId(header.id!)).copyWith(
        deviceToken: header.deviceToken ?? '',
      );
      remote.add(
        SyncedSale.fromSale(sale, deviceToken: sale.deviceToken ?? '').toJson(),
      );
      count++;
      if (count >= _historyLimit) break;
    }

    return Response.ok(
      jsonEncode({
        'tenant_id': tenantId,
        'count': remote.length,
        'sales': remote,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _catalog(Request request) async {
    final all = await products.all();
    final payload = {
      'tenant_id': tenantId,
      'generated_at': nowIso(),
      'products': all
          .map(
            (product) => CatalogProduct(
              barcode: product.barcode,
              name: product.name,
              quantity: product.quantity,
              minStock: product.minStock,
              price: product.price,
              updatedAt: product.updatedAt,
            ),
          )
          .toList()
          .map((p) => p.toJson())
          .toList(),
    };
    return Response.ok(jsonEncode(payload), headers: _jsonHeaders);
  }

  Future<Response> _sales(Request request) async {
    final auth = request.headers['x-device-token'];
    if (auth == null || !auth.startsWith('dvt_')) {
      return Response(401,
          body: jsonEncode({'error': 'unauthenticated'}),
          headers: _jsonHeaders);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } on FormatException {
      return Response(400,
          body: jsonEncode({'error': 'invalid json'}), headers: _jsonHeaders);
    }

    final rawList = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? decoded['sales']
            : null;
    if (rawList is! List) {
      return Response(400,
          body: jsonEncode({'error': 'expected a list of sales'}),
          headers: _jsonHeaders);
    }

    var inserted = 0;
    var duplicates = 0;
    var skipped = 0;
    var stockWarnings = 0;
    for (final entry in rawList) {
      if (entry is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final remote = SyncedSale.fromJson(entry);
      if (!remote.isValid) {
        skipped++;
        continue;
      }

      final alreadyStored = await sales.findRemoteDuplicate(
        remote.deviceToken,
        remote.createdAt,
        remote.total,
      );
      if (alreadyStored) {
        duplicates++;
        continue;
      }

      // Descuenta el stock (offline-first): si un ítem no alcanza se registra
      // igual la venta y se marca con stock_warning para avisar luego.
      var stockWarning = false;
      for (final item in remote.items) {
        final barcode = item.barcode?.trim() ?? '';
        if (barcode.isEmpty) continue;
        final applied = await products.deductStockFromSync(
          barcode,
          item.quantity,
        );
        stockWarning = stockWarning || !applied;
      }

      await sales.insertSale(
        items: remote.items
            .map(
              (item) => SaleItem(
                productId: null,
                productName: item.productName,
                barcode: item.barcode,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                subtotal: item.subtotal,
              ),
            )
            .toList(),
        method: remote.method,
        subtotal: remote.subtotal,
        taxRate: remote.taxRate,
        tax: remote.tax,
        total: remote.total,
        received: remote.received,
        change: remote.change,
        deviceToken: remote.deviceToken,
        status: remote.status,
        createdAt: remote.createdAt,
        stockWarning: stockWarning,
      );
      inserted++;
      if (stockWarning) stockWarnings++;
    }

    return Response.ok(
      jsonEncode({
        'tenant_id': tenantId,
        'received': rawList.length,
        'inserted': inserted,
        'duplicates': duplicates,
        'skipped': skipped,
        'stock_warnings': stockWarnings,
      }),
      headers: _jsonHeaders,
    );
  }
}

/// Cliente de sincronización del teléfono.
///
/// Descarga el catálogo completo de la PC y actualiza el SQLite local;
/// además envía las ventas locales pendientes hacia la PC.
class SyncService {
  SyncService({
    required this.products,
    required this.sales,
    required this.pairing,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final ProductRepository products;
  final SalesRepository sales;
  final PairingService pairing;
  final http.Client _http;

  /// Timeout por petición directa (10 s): tolera latencia de Wi-Fi/DHCP e
  /// intentos de síntesis del SO hacia la IP guardada.
  static const _timeout = Duration(seconds: 10);

  /// Timeout por IP en el barrido de la subred. 1200 ms tolera la resolución
  /// ARP del Wi-Fi real (a 600 ms las IPs vivas no respondían a tiempo).
  static const _discoveryTimeout = Duration(milliseconds: 1200);
  static const int _discoveryBatchSize = 32;

  /// Diagnóstico visible para el usuario: comprueba la URL guardada, hace un
  /// `Socket.connect` de verdad al puerto (distingue "firewall/subred
  /// bloqueando" de "servidor alcanzable") y valida el health check HTTP.
  ///
  /// Devuelve un texto multilínea listo para mostrar en un diálogo.
  Future<String> diagnoseConnection() async {
    final buf = StringBuffer('[Diagnóstico de conexión Wi-Fi]\n');
    final url = await pairing.syncServerUrl();
    if (url == null || url.isEmpty) {
      buf
        ..writeln('No hay servidor configurado.')
        ..writeln('Vincula primero con la PC por QR y verifica que ambos estén '
            'en la misma red Wi-Fi.');
      return buf.toString();
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      buf.writeln('URL inválida almacenada: "$url".');
      return buf.toString();
    }
    buf.writeln('URL configurada: $url');
    buf.writeln('Destino: ${uri.host}:${uri.port}\n');

    // 1) TCP real: si conecta, el firewall/subred están OK.
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      buf.writeln('TCP ${uri.host}:${uri.port} → CONECTA (red/firewall OK)');
    } catch (e) {
      buf
        ..writeln('TCP ${uri.host}:${uri.port} → FALLA: $e')
        ..writeln()
        ..writeln('=> Firewall o subred: revisa la regla 8080 de la PC y que '
            'el celular esté en la MISMA red Wi-Fi que la PC.');
      return buf.toString();
    }

    // 2) Health check HTTP.
    try {
      final token = await pairing.deviceToken();
      final response = await _http
          .get(
            Uri.parse('$url/api/v1/sync/health'),
            headers: {
              'content-type': 'application/json',
              'x-device-token': token,
            },
          )
          .timeout(const Duration(seconds: 5));
      buf.writeln('HTTP /api/v1/sync/health → ${response.statusCode}');
      buf.writeln(response.body);
      if (response.statusCode == 200) {
        buf.writeln('\n=> Servidor OK: la sincronización debería funcionar.');
      } else {
        buf
          ..writeln()
          ..writeln('=> El servidor respondió pero con código inesperado: '
              'revisa la app de la PC.');
      }
    } catch (e) {
      buf.writeln('HTTP /api/v1/sync/health → FALLA: $e');
      buf.writeln('\n=> El puerto está abierto pero la app de la PC no '
          'respondió correctamente.');
    }
    return buf.toString();
  }

  /// Sincroniza catálogo (PC → teléfono) y ventas (teléfono → PC) con
  /// reintento automático si la PC cambió de IP por DHCP.
  ///
  /// Ante un fallo de red, barre la subred local buscando `/api/v1/sync/health`
  /// con el mismo `tenant_id`; si lo encuentra actualiza `sync_server_url` en
  /// el almacén de vinculación y reintenta una vez.
  Future<SyncResult> syncNow() async {
    final serverUrl = await pairing.syncServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      return SyncResult.failure(
        'Servidor no configurado. Vincula primero con la PC por QR y '
        'verifica que ambos estén en la misma red Wi-Fi.',
      );
    }
    // Defensa: normaliza y persiste el formato canónico http://IP:puerto.
    final normalized = PairingService.normalizeSyncServerUrl(serverUrl);
    if (normalized != serverUrl) {
      await pairing.saveSyncServerUrl(normalized);
      debugPrint('[SyncClient] URL normalizada a: $normalized');
    }
    final deviceToken = await pairing.deviceToken();
    debugPrint('[Sync] URL Base: $normalized');
    debugPrint('[Sync] Device Token: $deviceToken');

    var currentUrl = normalized;
    for (var attempt = 0; attempt < 2; attempt++) {
      debugPrint('[SyncClient] Intentando conectar a: $currentUrl');
      final outcome = await _syncOnce(currentUrl, deviceToken);
      if (!outcome.networkFailure || attempt == 1) {
        return outcome.result;
      }

      final discovered = await _discoverServerUrl(currentUrl, deviceToken);
      if (discovered == null) {
        return SyncResult.failure(
          'No se pudo conectar a la PC en $currentUrl.\n'
          'Verifique que ambos dispositivos estén en la misma red Wi-Fi y que '
          'el Firewall de Windows permita el puerto 8080.',
        );
      }
      currentUrl = discovered;
    }
    return SyncResult.failure('Sincronización fallida.');
  }

  /// Intento único de sincronización. `networkFailure = true` SOLO cuando el
  /// servidor no respondió a nivel de transporte (IP inalcanzable), caso
  /// reintentable vía escaneo de subred tras un cambio de IP por DHCP.
  Future<({SyncResult result, bool networkFailure})> _syncOnce(
    String serverUrl,
    String deviceToken,
  ) async {
    try {
      // Paso 1: el health check válido confirma que la URL responde el
      // contrato esperado. Si no, el escaneo de subred NO debe dispararse.
      await _fetchHealth(serverUrl, deviceToken);

      // Paso 2: catálogo completo y ventas pendientes.
      final catalog = await _fetchCatalog(serverUrl, deviceToken);
      var updated = 0;
      for (final product in catalog) {
        if (!product.isValid) continue;
        await products.upsertFromSync(
          barcode: product.barcode,
          name: product.name,
          quantity: product.quantity,
          minStock: product.minStock,
          price: product.price,
          updatedAt: product.updatedAt,
        );
        updated++;
      }

      final pending = await sales.listForSync();
      var sent = pending.length;
      var duplicates = 0;
      var stockWarnings = 0;
      if (pending.isNotEmpty) {
        final report = await _pushSales(serverUrl, deviceToken, pending);
        if (report == null) {
          return (
            result: SyncResult.failure(
              'La PC recibió el catálogo, pero falló el envío de las ventas.',
            ),
            networkFailure: false,
          );
        }
        duplicates = report['duplicates'] as int? ?? 0;
        stockWarnings = report['stock_warnings'] as int? ?? 0;
        await sales.markSynced(
          pending.where((sale) => sale.id != null).map((s) => s.id!).toList(),
        );
      }

      // Historial de la PC → teléfono (ventas originadas en la PC se bajan y
      // se marcan sincronizadas para NO re-subirlas al servidor).
      final remoteHistory = await _fetchRemoteSales(serverUrl, deviceToken);
      final downloadedIds = <int>[];
      var downloaded = 0;
      for (final remote in remoteHistory) {
        if (remote.items.isEmpty) continue;
        final already = await sales.findRemoteDuplicate(
          remote.deviceToken,
          remote.createdAt,
          remote.total,
        );
        if (already) continue;
        final id = await sales.insertSale(
          items: remote.items
              .map(
                (item) => SaleItem(
                  productId: null,
                  productName: item.productName,
                  barcode: item.barcode,
                  unitPrice: item.unitPrice,
                  quantity: item.quantity,
                  subtotal: item.subtotal,
                ),
              )
              .toList(),
          method: remote.method,
          subtotal: remote.subtotal,
          taxRate: remote.taxRate,
          tax: remote.tax,
          total: remote.total,
          received: remote.received,
          change: remote.change,
          deviceToken: remote.deviceToken,
          status: remote.status,
          createdAt: remote.createdAt,
        );
        downloadedIds.add(id);
        downloaded++;
      }
      if (downloadedIds.isNotEmpty) {
        await sales.markSynced(downloadedIds);
      }

      return (
        result: SyncResult.success(
          catalogSynced: updated,
          salesSent: sent,
          duplicates: duplicates,
          stockWarnings: stockWarnings,
          remoteSalesReceived: downloaded,
        ),
        networkFailure: false,
      );
    } on SocketException catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure(
          'No se pudo conectar a la PC en $serverUrl.\n'
          'Verifique que ambos dispositivos estén en la misma red Wi-Fi y que '
          'el Firewall de Windows permita el puerto 8080.',
        ),
        networkFailure: true,
      );
    } on TimeoutException catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure(
          'La PC no respondió a tiempo en $serverUrl.\n'
          'Verifique la conexión Wi-Fi y que el Firewall de Windows permita '
          'el puerto 8080.',
        ),
        networkFailure: true,
      );
    } on http.ClientException catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure('Error de red hacia la PC: ${e.message}'),
        networkFailure: true,
      );
    } on SyncRemoteException catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure('La PC respondió ${e.message}.'),
        networkFailure: false,
      );
    } on FormatException catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure('La PC respondió con datos inválidos.'),
        networkFailure: false,
      );
    } on Exception catch (e) {
      debugPrint('[SyncClient] Error capturado: $e');
      return (
        result: SyncResult.failure('Error de sincronización inesperado.'),
        networkFailure: false,
      );
    }
  }

  /// Comprueba el health check de la PC (`GET /api/v1/sync/health`).
  ///
  /// Acepta HTTP 200 solo si `status == "ok"`; compara el `tenant_id` de forma
  /// insensible a mayúsculas cuando la PC lo expone. Los errores de transporte
  /// se propagan (SocketException/TimeoutException/ClientException) para que el
  /// llamador active el escaneo; un 200 con payload inválido lanza
  /// [FormatException] (se descarta el escaneo).
  Future<void> _fetchHealth(String serverUrl, String deviceToken) async {
    final response = await _http
        .get(
          Uri.parse('$serverUrl/api/v1/sync/health'),
          headers: {
            'content-type': 'application/json',
            'x-device-token': deviceToken,
          },
        )
        .timeout(_timeout);
    debugPrint(
      '[SyncClient] Respuesta Health: '
      '${response.statusCode} - ${response.body}',
    );
    if (response.statusCode != 200) {
      throw SyncRemoteException(
        'Error ${response.statusCode}: '
        '${_httpStatusLabel(response.statusCode)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['status'] != 'ok') {
      throw const FormatException('health inválido');
    }
    final remoteTenant = decoded['tenant_id'];
    if (remoteTenant is String && remoteTenant.trim().isNotEmpty) {
      final credentials = await pairing.credentials();
      if (credentials != null &&
          credentials.tenantId.trim().isNotEmpty &&
          remoteTenant.trim().toUpperCase() !=
              credentials.tenantId.trim().toUpperCase()) {
        throw const FormatException('tenant_id no coincide');
      }
    }
  }

  /// Barrido de las subredes donde está conectado el TELÉFONO (su Wi-Fi),
  /// buscando el `tenant_id` de esta tienda tras una IP caída/cambiada.
  ///
  /// NO barre la subred de la URL guardada (podría ser 192.168.56.x de un
  /// adaptador virtual de la PC, invisible para el celular): primero escanea
  /// sus propias interfaces y añade la subred de la URL como respaldo.
  ///
  /// Devuelve la URL encontrada y actualiza `sync_server_url`, o null.
  Future<String?> _discoverServerUrl(
    String currentUrl,
    String deviceToken,
  ) async {
    final credentials = await pairing.credentials();
    if (credentials == null || credentials.tenantId.isEmpty) return null;

    final uri = Uri.tryParse(currentUrl);
    final port = uri != null && uri.hasPort
        ? uri.port
        : PairingService.defaultSyncPort;

    // Subredes propias del teléfono (Wi-Fi/móvil), excluyendo loopback.
    final subnets = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback ||
              addr.isMulticast ||
              addr.isLinkLocal) {
            continue;
          }
          final octets = addr.address.split('.');
          if (octets.length == 4) {
            final subnet = '${octets[0]}.${octets[1]}.${octets[2]}.';
            if (!subnets.contains(subnet)) subnets.add(subnet);
          }
        }
      }
    } catch (_) {
      // Sin permisos de red: se intenta la subred de la URL guardada.
    }
    // Respaldo: añade la subred de la URL guardada al final (p. ej. loopback
    // en pruebas o si el teléfono no enumera interfaces).
    if (uri != null && uri.host.isNotEmpty) {
      final octets = uri.host.split('.');
      if (octets.length == 4) {
        final fallback = '${octets[0]}.${octets[1]}.${octets[2]}.';
        if (!subnets.contains(fallback)) subnets.add(fallback);
      }
    }
    if (subnets.isEmpty) return null;
    debugPrint('[Sync] Escaneando subredes: $subnets');

    Future<String?> probe(String subnet, int last) async {
      final candidate = 'http://$subnet$last:$port';
      try {
        final response = await _http
            .get(
              Uri.parse('$candidate/api/v1/sync/health'),
              headers: {
                'content-type': 'application/json',
                'x-device-token': deviceToken,
              },
            )
            .timeout(_discoveryTimeout);
        if (response.statusCode != 200) return null;
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final remoteTenant = body['tenant_id'];
          if (remoteTenant is String &&
              remoteTenant.toUpperCase() ==
                  credentials.tenantId.toUpperCase()) {
            return candidate;
          }
        }
      } catch (_) {
        // IP apagada, puerto cerrado o sin servicio: se sigue con la siguiente.
      }
      return null;
    }

    for (final subnet in subnets) {
      for (var start = 1; start <= 254; start += _discoveryBatchSize) {
        final end = (start + _discoveryBatchSize - 1 > 254)
            ? 254
            : start + _discoveryBatchSize - 1;
        final results =
            await Future.wait([for (var i = start; i <= end; i++) probe(subnet, i)]);
        for (final found in results) {
          if (found != null) {
            debugPrint('[Sync] PC encontrada en: $found');
            await pairing.saveSyncServerUrl(found);
            return found;
          }
        }
      }
    }
    return null;
  }

  Future<List<SyncedSale>> _fetchRemoteSales(
    String serverUrl,
    String deviceToken,
  ) async {
    final uri = Uri.parse('$serverUrl/api/v1/sync/sales');
    debugPrint('[Sync] Consultando historial en: $uri');
    final response = await _http
        .get(
          uri,
          headers: {
            'content-type': 'application/json',
            'x-device-token': deviceToken,
          },
        )
        .timeout(_timeout);
    debugPrint('[Sync] Respuesta Historial Code: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw SyncRemoteException(
        'Error ${response.statusCode}: '
        '${_httpStatusLabel(response.statusCode)}',
      );
    }
    final bodyPreview = response.body.length > 600
        ? '${response.body.substring(0, 600)}…'
        : response.body;
    debugPrint('[Sync] Respuesta Historial Body: $bodyPreview');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final raw = decoded['sales'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SyncedSale.fromJson)
        .toList();
  }

  Future<List<CatalogProduct>> _fetchCatalog(
    String serverUrl,
    String deviceToken,
  ) async {
    final uri = Uri.parse('$serverUrl/api/v1/sync/catalog');
    debugPrint('[Sync] Consultando catálogo en: $uri');
    final response = await _http
        .get(
          uri,
          headers: {
            'content-type': 'application/json',
            'x-device-token': deviceToken,
          },
        )
        .timeout(_timeout);
    debugPrint('[Sync] Respuesta Catálogo Code: ${response.statusCode}');
    debugPrint('[Sync] Respuesta Catálogo Body: ${response.body}');
    if (response.statusCode != 200) {
      throw SyncRemoteException(
        'Error ${response.statusCode}: '
        '${_httpStatusLabel(response.statusCode)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['products'] is! List) {
      throw const FormatException('no products field');
    }
    final products = decoded['products'] as List<dynamic>;
    return products
        .whereType<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>?> _pushSales(
    String serverUrl,
    String deviceToken,
    List<Sale> pending,
  ) async {
    final uri = Uri.parse('$serverUrl/api/v1/sync/sales');
    final body = jsonEncode({
      'sales': pending
          .map((sale) => SyncedSale.fromSale(sale, deviceToken: deviceToken))
          .map((s) => s.toJson())
          .toList(),
    });
    debugPrint('[Sync] Consultando ventas en: $uri '
        '(${pending.length} pendientes)');
    final response = await _http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'x-device-token': deviceToken,
          },
          body: body,
        )
        .timeout(_timeout);
    debugPrint('[Sync] Respuesta Ventas Code: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw SyncRemoteException(
        'Error ${response.statusCode}: '
        '${_httpStatusLabel(response.statusCode)}',
      );
    }
    debugPrint('[Sync] Respuesta Ventas Body: ${response.body}');
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }
}