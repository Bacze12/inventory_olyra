// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'olyra_http_client.dart';

/// Error de activación con mensaje legible (del servidor o transporte).
class LicenseServerException implements Exception {
  const LicenseServerException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Código de error de negocio del servidor (p. ej. `MAX_DEVICES_REACHED`).
  final String? code;

  @override
  String toString() => message;
}

/// Resultado de una revalidación online incluyendo el `user_app_id` que el
/// servidor entrega (UUID de la fila `user_apps`, no el `app_id` del producto).
class OlyraValidateResult {
  const OlyraValidateResult({required this.ok, this.userAppId});

  final bool ok;
  final String? userAppId;
}

/// Cliente HTTP de licencia (olyra.cl).
///
/// - [activate]: POST `{ license_key, hwid, device_name }` → `{ token }`.
///   El token emitido es un JWT RS256 verificado offline por la app.
/// - [validate]: POST `{ license_key, hwid, token }` → revalidación silenciosa
///   en segundo plano. Ante cualquier fallo de red/servidor devuelve `false`;
///   el arranque offline NUNCA depende de esta llamada.
class OlyraLicenseApi {
  OlyraLicenseApi({
    required String activationUrl,
    String? validateUrl,
    http.Client? client,
  })  : _activationUrl = activationUrl.replaceFirst(RegExp(r'/+$'), ''),
        _validateUrl = (validateUrl ?? activationUrl)
            .replaceFirst(RegExp(r'/activate$'), '/validate')
            .replaceFirst(RegExp(r'/+$'), ''),
        _client = OlyraRedirectClient(inner: client ?? NoFollowIOClient());

  static const Duration timeout = Duration(seconds: 20);

  final String _activationUrl;
  final String _validateUrl;
  final http.Client _client;

  /// Activa un License Key para el [hwid] y devuelve el JWT firmado.
  Future<String> activate({
    required String hwid,
    required String licenseKey,
    String deviceName = '',
  }) async {
    final normalized = licenseKey.trim();
    if (normalized.isEmpty) {
      throw const LicenseServerException(
          'Ingresa el License Key recibido al comprar.');
    }

    final payload = jsonEncode({
      'license_key': normalized,
      'hwid': hwid,
      if (deviceName.isNotEmpty) 'device_name': deviceName.trim(),
    });
    debugPrint('[OlyraLicense] POST $_activationUrl body=$payload');

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_activationUrl),
            headers: const {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const LicenseServerException(
          'El servidor tardó demasiado. Reintenta en unos segundos.');
    } on http.ClientException {
      throw const LicenseServerException(
          'No se pudo contactar el servidor de licencias. Revisa tu conexión.');
    }

    debugPrint(
      '[OlyraLicense] status=${response.statusCode} body=${response.body}',
    );

    final body = _decodeBody(response);

    final message =
        (body?['message'] as String?) ?? (body?['error'] as String?);
    if (response.statusCode != 200) {
      throw LicenseServerException(
        message ?? 'El servidor respondió con código ${response.statusCode}.',
        statusCode: response.statusCode,
        code: body?['code'] as String?,
      );
    }

    final token = body?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const LicenseServerException(
          'El servidor no entregó un token válido. Contacta soporte.');
    }
    return token;
  }

  /// Validación de segundo plano. Devuelve `false` si el servidor no confirmó
  /// la licencia (revocada, expirada, sin red…). Nunca lanza.
  Future<bool> validate({
    required String licenseKey,
    required String hwid,
    required String token,
    String deviceName = '',
  }) async =>
      (await validateWithMeta(
        licenseKey: licenseKey,
        hwid: hwid,
        token: token,
        deviceName: deviceName,
      ))
          .ok;

  /// Igual que [validate] pero además expone los metadatos frescos de la
  /// respuesta (p. ej. `user_app_id`, ya emitido por el servidor).
  Future<OlyraValidateResult> validateWithMeta({
    required String licenseKey,
    required String hwid,
    required String token,
    String deviceName = '',
  }) async {
    if (licenseKey.isEmpty || token.isEmpty) {
      return const OlyraValidateResult(ok: false);
    }

    final payload = jsonEncode({
      'license_key': licenseKey,
      'hwid': hwid,
      'token': token,
      if (deviceName.isNotEmpty) 'device_name': deviceName,
    });
    final body = payload;

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_validateUrl),
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } catch (_) {
      return const OlyraValidateResult(ok: false);
    }

    if (response.statusCode != 200) {
      debugPrint('[OlyraLicense] validate_status=${response.statusCode} '
          'body=${response.body}');
      return const OlyraValidateResult(ok: false);
    }

    final decoded = _decodeBody(response);
    final freshUserAppId = decoded?['user_app_id'] as String?;
    debugPrint('[OlyraLicense] validate OK '
        'server_status=${decoded?['status']} '
        'expires_at=${decoded?['expires_at']} '
        'user_app_id=${freshUserAppId?.isNotEmpty == true}');
    return OlyraValidateResult(
      ok: true,
      userAppId:
          (freshUserAppId == null || freshUserAppId.isEmpty) ? null : freshUserAppId,
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