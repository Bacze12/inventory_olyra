// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

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
        _client = _ManualRedirectClient(client ?? _NoFollowIOClient());

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
  }) async {
    if (licenseKey.isEmpty || token.isEmpty) return false;

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
      return false;
    }

    if (response.statusCode != 200) {
      debugPrint('[OlyraLicense] validate_status=${response.statusCode} '
          'body=${response.body}');
      return false;
    }

    final decoded = _decodeBody(response);
    debugPrint('[OlyraLicense] validate OK '
        'server_status=${decoded?['status']} '
        'expires_at=${decoded?['expires_at']}');
    return true;
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

/// Sigue redirecciones 307/308 (y 301/302) **conservando método y body** del
/// POST original, en lugar de delegar en el auto-follow del cliente HTTP que
/// en algunos casos pierde el body o lee la URL final.
///
/// - 307/308 y 301/302: se reenvía el POST tal cual contra `Location`.
/// - 303: pasa a GET sin body (semántica del código 303).
/// - Sin `Location`, otros 3xx o agotar [maxRedirects]: se devuelve la
///   respuesta como final (el caller la tratará como error si no es 200).
/// - Drena los cuerpos de las respuestas intermedias para no saturar la
///   conexión del `HttpClient` de I/O.
class _ManualRedirectClient extends http.BaseClient {
  _ManualRedirectClient(this._inner);

  final http.Client _inner;
  static const int maxRedirects = 3;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    var method = request.method;
    var url = request.url;
    final headers = Map<String, String>.from(request.headers);

    for (var hop = 0;; hop++) {
      final req = http.Request(method, url)..headers.addAll(headers);
      if (method != 'GET' && method != 'HEAD') {
        req.bodyBytes = bodyBytes;
      }

      final response = await _inner.send(req);
      final status = response.statusCode;
      final location = response.headers['location'];

      if (hop >= maxRedirects ||
          location == null ||
          (status != 301 &&
              status != 302 &&
              status != 303 &&
              status != 307 &&
              status != 308)) {
        return response;
      }

      // Drena el body de la redirección para liberar el socket.
      await response.stream.drain<void>();

      url = url.resolveUri(Uri.parse(location));
      switch (status) {
        case 307:
        case 308:
        case 301:
        case 302:
          // Se conserva POST y su body (seguro para APIs de licencia).
          break;
        case 303:
          method = 'GET';
          break;
      }
    }
  }

  @override
  void close() => _inner.close();
}

/// Transporte `dart:io` con `followRedirects = false` a nivel de request
/// (la API de I/O del SDK actual movió la propiedad al request). Con esto el
/// seguimiento de redirecciones queda 100% en manos de [_ManualRedirectClient],
/// que reconstruye el POST preservando el body en 307/308.
class _NoFollowIOClient extends http.BaseClient {
  final HttpClient _io = HttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ioRequest = await _io.openUrl(request.method, request.url);
    ioRequest.followRedirects = false;
    request.headers.forEach(ioRequest.headers.set);

    final bodyBytes = await request.finalize().toBytes();
    ioRequest.contentLength = bodyBytes.length;
    if (bodyBytes.isNotEmpty) {
      ioRequest.add(bodyBytes);
    }

    final ioResponse = await ioRequest.close();

    final headerMap = <String, String>{};
    ioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) headerMap[name] = values.first;
    });

    return http.StreamedResponse(
      ioResponse,
      ioResponse.statusCode,
      contentLength: ioResponse.contentLength == -1
          ? null
          : ioResponse.contentLength,
      headers: headerMap,
      reasonPhrase: ioResponse.reasonPhrase,
      isRedirect: false,
      request: http.Request(request.method, request.url),
    );
  }

  @override
  void close() => _io.close(force: true);
}