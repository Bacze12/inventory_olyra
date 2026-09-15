// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'olyra_http_client.dart';

/// Error de sincronización con mensaje legible (del servidor o transporte).
class OlyraSyncException implements Exception {
  const OlyraSyncException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Resultado de un ciclo de respaldo/sincronización contra `POST /pos/sync`.
class OlyraSyncResult {
  const OlyraSyncResult({
    required this.salesPushed,
    required this.movementsPushed,
    this.errors = const [],
  });

  final int salesPushed;
  final int movementsPushed;
  final List<String> errors;

  bool get hasChanges => salesPushed + movementsPushed > 0;

  String describe() {
    final parts = <String>[
      if (salesPushed > 0) '$salesPushed venta(s) subidas a la nube',
      if (movementsPushed > 0) '$movementsPushed movimiento(s) subidos',
      if (!hasChanges) 'Sin cambios pendientes.',
    ];
    if (errors.isNotEmpty) parts.add('Con ${errors.length} advertencia(s)');
    return parts.join(' · ');
  }
}

/// Cliente REST de la nube Olyra (`https://olyra.cl/api/v1/pos/sync`).
///
/// No requiere usuario/contraseña: la identidad la aportan las credenciales de
/// licencia obtenidas en la activación (`license_key`, `user_app_id`, `hwid`).
/// El servidor enruta los lotes a las tablas `pos_sales`/`pos_movements`
/// vinculadas al `user_app_id` y hace revalidación de licencia por request.
class OlyraPosApi {
  OlyraPosApi({
    required String syncUrl,
    http.Client? client,
  })  : _syncUrl = syncUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? OlyraRedirectClient();

  static const Duration timeout = Duration(seconds: 30);

  final String _syncUrl;
  final http.Client _client;

  /// Empuja en un solo lote las ventas y movimientos locales pendientes.
  ///
  /// Lanza [OlyraSyncException] si el servidor responde con código distinto a
  /// 200 (incluye licencia revocada/vencida o `user_app_id` inválido).
  Future<OlyraSyncResult> syncNow({
    required String licenseKey,
    required String userAppId,
    required String hardwareId,
    String deviceName = '',
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> movements,
  }) async {
    final payload = jsonEncode({
      'license_key': licenseKey,
      'user_app_id': userAppId,
      'hwid': hardwareId,
      if (deviceName.isNotEmpty) 'device_name': deviceName,
      'sales': sales,
      'movements': movements,
    });
    debugPrint('[OlyraSync] POST $_syncUrl '
        'sales=${sales.length} movements=${movements.length} '
        'user_app_id=$userAppId');

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_syncUrl),
            headers: const {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const OlyraSyncException(
          'La nube tardó demasiado. Reintenta en unos segundos.');
    } on http.ClientException {
      throw const OlyraSyncException(
          'No se pudo conectar a la nube. Revisa tu conexión a internet.');
    }

    final body = _decodeBody(response);
    final rawMessage =
        (body?['message'] as String?) ?? (body?['error'] as String?);

    if (response.statusCode != 200) {
      debugPrint('[OlyraSync] status=${response.statusCode} body=${response.body}');
      throw OlyraSyncException(
        rawMessage ?? 'El servidor respondió con código ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final salesPushed =
        (body?['synced_sales'] as num?)?.toInt() ?? sales.length;
    final movementsPushed =
        (body?['synced_movements'] as num?)?.toInt() ?? movements.length;
    final errors = <String>[];
    final rawErrors = body?['errors'];
    if (rawErrors is List) {
      for (final item in rawErrors) {
        if (item != null) errors.add(item.toString());
      }
    }
    debugPrint('[OlyraSync] OK sales=$salesPushed movements=$movementsPushed');

    return OlyraSyncResult(
      salesPushed: salesPushed,
      movementsPushed: movementsPushed,
      errors: errors,
    );
  }

  Map<String, dynamic>? _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }
}