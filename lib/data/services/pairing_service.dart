import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/formatters.dart';
import '../repositories/settings_repository.dart';

/// Resultado del intento de vinculación desde el dispositivo móvil.
enum PairingOutcome { ok, invalidPayload, expired, sendFailed }

/// Credenciales guardadas tras vincular este dispositivo con la tienda.
@immutable
class PairingCredentials {
  const PairingCredentials({
    required this.tenantId,
    required this.deviceToken,
    required this.pairedAt,
  });

  factory PairingCredentials.fromJson(Map<String, dynamic> json) {
    return PairingCredentials(
      tenantId: json['tenant_id'] as String? ?? '',
      deviceToken: json['device_token'] as String? ?? '',
      pairedAt: json['paired_at'] as String? ?? nowIso(),
    );
  }

  final String tenantId;
  final String deviceToken;
  final String pairedAt;

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'device_token': deviceToken,
        'paired_at': pairedAt,
      };
}

/// Payload escaneado desde el QR de la PC (JSON temporal).
///
/// Shape: `{"tenant_id": "STORE_123", "pair_code": "482910", "expires_at": ms}`.
@immutable
class PairPayload {
  const PairPayload({
    required this.tenantId,
    required this.pairCode,
    required this.expiresAt,
  });

  final String tenantId;
  final String pairCode;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'pair_code': pairCode,
        'expires_at': expiresAt.millisecondsSinceEpoch,
      };
}

/// Sesión de emparejamiento iniciada en la PC.
@immutable
class PairingSession {
  const PairingSession({
    required this.tenantId,
    required this.pairCode,
    required this.expiresAt,
  });

  final String tenantId;
  final String pairCode;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  PairPayload get payload => PairPayload(
        tenantId: tenantId,
        pairCode: pairCode,
        expiresAt: expiresAt,
      );
}

/// Resultado de una comprobación de emparejamiento en la PC.
@immutable
class PairingCheckResult {
  const PairingCheckResult({this.credentials, this.expired = false});

  const PairingCheckResult.confirmed(PairingCredentials this.credentials)
      : expired = false;

  const PairingCheckResult.expired() : this(expired: true);

  const PairingCheckResult.waiting() : this();

  final PairingCredentials? credentials;
  final bool expired;

  bool get confirmed => credentials != null;
}

/// Almacenamiento seguro de secrets (abstraído para pruebas).
abstract class PairingSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Implementación con `flutter_secure_storage`, con caché en memoria y
/// tolerancia a plataformas sin el plugin nativo (escritorio en debug/tests).
class SecurePairingStore implements PairingSecretStore {
  SecurePairingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _memory = {};

  @override
  Future<String?> read(String key) async {
    final memo = _memory[key];
    if (memo != null) return memo;
    try {
      final value = await _storage.read(key: key);
      if (value != null) _memory[key] = value;
      return value;
    } catch (_) {
      return _memory[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _memory[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Caché en memoria mantiene el valor si el plugin no está disponible.
    }
  }

  @override
  Future<void> delete(String key) async {
    _memory.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Sin plugin: la caché en memoria ya queda limpia.
    }
  }
}

/// Fuente de ajustes persistente (abstracción sobre [SettingsRepository]).
abstract class PairingSettingsSource {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DbPairingSettingsSource implements PairingSettingsSource {
  const DbPairingSettingsSource(this._settings);

  final SettingsRepository _settings;

  @override
  Future<String?> read(String key) => _settings.get(key);

  @override
  Future<void> write(String key, String value) => _settings.set(key, value);
}

/// Servicio de vinculación PC ⇄ Móvil por QR / PIN.
///
/// Genera sesiones temporales (PIN de 6 dígitos + JSON para el QR),
/// valida el payload escaneado, y persiste las credenciales de la tienda
/// (`device_token` + `tenant_id`) en [PairingSecretStore].
///
/// Cuando `pairing_server_url` está configurado actúa como relay: el móvil
/// publica su `device_token` y la PC lo confirma por polling. Sin servidor,
/// ambos dispositivos guardan localmente sus credenciales y la PC puede
/// cerrar la sesión con confirmación manual.
class PairingService {
  PairingService({
    required this.settings,
    PairingSecretStore? secrets,
    http.Client? httpClient,
  })  : _secrets = secrets ?? SecurePairingStore(),
        _http = httpClient ?? http.Client();

  static const kTenantKey = 'tenant_id';
  static const kServerUrlKey = 'pairing_server_url';
  static const kCredentialsKey = 'pairing_credentials';
  static const kDeviceTokenKey = 'device_token';
  static const kTenantIdSecretKey = 'tenant_id';

  static const defaultTtl = Duration(minutes: 10);

  final PairingSettingsSource settings;
  final PairingSecretStore _secrets;
  final http.Client _http;

  static final RegExp _pinPattern = RegExp(r'^\d{6}$');

  /// Devuelve el `tenant_id` de esta tienda, generándolo si aún no existe.
  Future<String> resolveTenantId() async {
    final stored = await settings.read(kTenantKey);
    final tenant = stored?.trim();
    if (tenant != null && tenant.isNotEmpty) return tenant;
    final generated = 'STORE_${_randomHex(4).toUpperCase()}';
    await settings.write(kTenantKey, generated);
    return generated;
  }

  Future<String?> readServerUrl() async {
    final server = await settings.read(kServerUrlKey);
    final trimmed = server?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Inicia una nueva sesión de emparejamiento con PIN aleatorio de 6 dígitos.
  Future<PairingSession> startSession({
    Duration ttl = defaultTtl,
  }) async {
    final tenantId = await resolveTenantId();
    return PairingSession(
      tenantId: tenantId,
      pairCode: _generatePin(),
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// Codifica la sesión como JSON para incrustar en el QR.
  String encodePayload(PairingSession session) =>
      jsonEncode(session.payload.toJson());

  /// Valida el payload escaneado / pegado.
  PairPayload? parsePayload(String raw) {
    final rawTrimmed = raw.trim();
    if (rawTrimmed.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(rawTrimmed);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final tenantId = decoded['tenant_id'];
    final pairCode = decoded['pair_code'];
    if (tenantId is! String || tenantId.trim().isEmpty) return null;
    if (pairCode is! String || !_pinPattern.hasMatch(pairCode)) return null;

    final expiresAt = decoded['expires_at'];
    final expiresMs = expiresAt is int ? expiresAt : int.tryParse('$expiresAt');
    if (expiresMs == null) return null;

    return PairPayload(
      tenantId: tenantId.trim(),
      pairCode: pairCode,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresMs),
    );
  }

  /// Token estable de este dispositivo (se reutiliza entre vinculaciones).
  Future<String> deviceToken() async {
    final existing = await _secrets.read(kDeviceTokenKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = 'dvt_${_randomHex(32)}';
    await _secrets.write(kDeviceTokenKey, created);
    return created;
  }

  /// Credenciales actuales de la vinculación, o null si no está vinculado.
  Future<PairingCredentials?> credentials() async {
    try {
      final raw = await _secrets.read(kCredentialsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final credentials = PairingCredentials.fromJson(decoded);
          if (credentials.tenantId.isNotEmpty &&
              credentials.deviceToken.isNotEmpty) {
            return credentials;
          }
        }
      }
      final token = await _secrets.read(kDeviceTokenKey);
      final tenant = await _secrets.read(kTenantIdSecretKey);
      if (token != null && token.isNotEmpty && tenant != null && tenant.isNotEmpty) {
        return PairingCredentials(
          tenantId: tenant,
          deviceToken: token,
          pairedAt: nowIso(),
        );
      }
    } catch (_) {
      // Corrupción de credenciales: se trata como no vinculado.
    }
    return null;
  }

  Future<bool> get isPaired async => (await credentials()) != null;

  /// Flujo del MÓVIL: valida el payload y vincula este dispositivo.
  Future<PairingOutcome> linkWithPayload(PairPayload payload) async {
    return _link(payload, token: await deviceToken());
  }

  Future<PairingOutcome> _link(
    PairPayload payload, {
    required String token,
  }) async {
    if (payload.isExpired) return PairingOutcome.expired;

    final server = await readServerUrl();
    if (server != null) {
      var posted = false;
      try {
        final response = await _http.post(
          _pairingUri(server, '/pairings'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'tenant_id': payload.tenantId,
            'pair_code': payload.pairCode,
            'device_token': token,
          }),
        );
        posted = response.statusCode >= 200 && response.statusCode < 300;
      } on Exception {
        posted = false;
      }
      if (!posted) return PairingOutcome.sendFailed;
    }

    await _saveCredentials(token, payload.tenantId);
    return PairingOutcome.ok;
  }

  /// Comprobación periódica del lado de la PC (relay HTTP si está configurado).
  Future<PairingCheckResult> checkPairing(PairingSession session) async {
    if (session.isExpired) return const PairingCheckResult.expired();

    final server = await readServerUrl();
    if (server == null) return const PairingCheckResult.waiting();

    try {
      final uri = _pairingUri(server, '/pairings').replace(
        queryParameters: {
          'tenant_id': session.tenantId,
          'pair_code': session.pairCode,
        },
      );
      final response = await _http.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> &&
            decoded['device_token'] is String) {
          final credentials = PairingCredentials.fromJson(decoded);
          await _saveCredentials(
            credentials.deviceToken,
            credentials.tenantId.isEmpty
                ? session.tenantId
                : credentials.tenantId,
          );
          return PairingCheckResult.confirmed(credentials);
        }
      }
    } on Exception {
      // Sin red: seguimos en espera.
      return const PairingCheckResult.waiting();
    }
    return const PairingCheckResult.waiting();
  }

  /// Cierra la sesión de forma local (modo sin servidor o validación manual).
  Future<void> confirmManually(PairingSession session) async {
    final token = await deviceToken();
    await _saveCredentials(token, session.tenantId);
  }

  /// Desvincula el dispositivo conservando su `device_token` (permite
  /// re-vincular con el mismo token en el futuro).
  Future<void> unlink() async {
    await _secrets.delete(kCredentialsKey);
    await _secrets.delete(kTenantIdSecretKey);
  }

  Future<void> _saveCredentials(String token, String tenantId) async {
    final credentials = PairingCredentials(
      tenantId: tenantId,
      deviceToken: token,
      pairedAt: nowIso(),
    );
    await _secrets.write(kCredentialsKey, jsonEncode(credentials.toJson()));
    await _secrets.write(kDeviceTokenKey, token);
    await _secrets.write(kTenantIdSecretKey, tenantId);
  }

  Uri _pairingUri(String base, String path) {
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized$path');
  }

  String _generatePin() =>
      Random.secure().nextInt(1000000).toString().padLeft(6, '0');

  String _randomHex(int length) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}