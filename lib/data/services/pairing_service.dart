import 'dart:convert';
import 'dart:io';
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
/// Shape:
/// `{"tenant_id": "STORE_123", "pair_code": "482910", "expires_at": ms}`.
/// Además incluye (opcional) `server_host`/`server_port` con la IP local de
/// la PC, para que el teléfono pueda sincronizar sin configurar nada más.
@immutable
class PairPayload {
  const PairPayload({
    required this.tenantId,
    required this.pairCode,
    required this.expiresAt,
    this.serverHost,
    this.serverPort,
  });

  final String tenantId;
  final String pairCode;
  final DateTime expiresAt;

  /// IP local de la PC (ej. `192.168.1.50`), si fue detectada.
  final String? serverHost;

  final int? serverPort;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'pair_code': pairCode,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        if (serverHost != null && serverHost!.isNotEmpty) ...{
          'server_host': serverHost,
          'server_port': serverPort ?? PairingService.defaultSyncPort,
        },
      };
}

/// Sesión de emparejamiento iniciada en la PC.
@immutable
class PairingSession {
  const PairingSession({
    required this.tenantId,
    required this.pairCode,
    required this.expiresAt,
    this.serverHost,
    this.serverPort,
  });

  final String tenantId;
  final String pairCode;
  final DateTime expiresAt;

  /// IP local de la PC (para que el teléfono encuentre el servidor de sync).
  final String? serverHost;

  final int? serverPort;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  PairPayload get payload => PairPayload(
        tenantId: tenantId,
        pairCode: pairCode,
        expiresAt: expiresAt,
        serverHost: serverHost,
        serverPort: serverPort,
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
  static const kSyncServerUrlKey = 'sync_server_url';
  static const kCredentialsKey = 'pairing_credentials';
  static const kDeviceTokenKey = 'device_token';
  static const kTenantIdSecretKey = 'tenant_id';

  static const defaultTtl = Duration(minutes: 10);
  static const defaultSyncPort = 8080;

  final PairingSettingsSource settings;
  final PairingSecretStore _secrets;
  final http.Client _http;

  static final RegExp _pinPattern = RegExp(r'^\d{6}$');

  /// Adaptadores de red virtuales/banda a descartar al detectar la IP.
  static final RegExp _virtualAdapter = RegExp(
    r'(virtual|vbox|vmware|vmnet|hyper-v|vethernet|docker|wintun|tunnel|bluetooth)',
    caseSensitive: false,
  );

  /// Adaptadores con nombre de red real (Wi-Fi/Ethernet/LAN/WLAN).
  static final RegExp _wiredWifi = RegExp(
    r'(wi[ -]?fi|ethernet|wlan|lan)',
    caseSensitive: false,
  );

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

  /// URL del servidor local de la PC (`http://IP:8080`), aprendida desde el
  /// QR vinculado. Es lo que usa el teléfono para sincronizar por Wi-Fi.
  ///
  /// La lectura devuelve SIEMPRE el formato completo `http://<host>[:porte]`
  /// (sin slash final ni rutas), vía [normalizeSyncServerUrl].
  Future<String?> syncServerUrl() async {
    final stored = await settings.read(kSyncServerUrlKey);
    final trimmed = stored?.trim();
    return (trimmed == null || trimmed.isEmpty)
        ? null
        : normalizeSyncServerUrl(trimmed);
  }

  Future<void> saveSyncServerUrl(String url) async {
    await settings.write(kSyncServerUrlKey, normalizeSyncServerUrl(url));
  }

  /// Normaliza una URL de servidor al formato canónico `http://<host>:<puerto>`
  /// con puerto por defecto 8080.
  ///
  /// - Añade el esquema `http://` si falta (p. ej. `192.168.1.50:8080`).
  /// - Añade el puerto `:8080` si la URL no lo trae.
  /// - Descarta el slash final y cualquier ruta, evitando rutas duplicadas
  ///   como `http://IP:8080//api/...`.
  static String normalizeSyncServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      url = 'http://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final port = uri.hasPort ? uri.port : defaultSyncPort;
    return '${uri.scheme}://${uri.host}:$port';
  }

  Future<void> clearSyncServerUrl() async {
    await settings.write(kSyncServerUrlKey, '');
  }

  /// Detecta la IP LAN IPv4 de este equipo descartando adaptadores virtuales
  /// (VirtualBox/VMware/Hyper-V/Docker/túneles). Devuelve null si no se pudo.
  ///
  /// El nombre del adaptador (Windows) permite excluir "VirtualBox Host-Only",
  /// "vEthernet (Default Switch)", "VMware Network Adapter", etc. y priorizar
  /// Wi-Fi/Ethernet reales, donde el teléfono sí puede llegar.
  Future<String?> detectLanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String? privateReal;
      String? privateVirtual;
      String? anyReal;
      String? bestRank4;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isVirtual = _virtualAdapter.hasMatch(name);
        final isWiredWifi = _wiredWifi.hasMatch(name);
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isMulticast || addr.isLinkLocal) {
            continue;
          }
          final raw = addr.rawAddress;
          final first = raw.isNotEmpty ? raw.first : 0;
          final isPrivate = first == 192 || first == 10 || first == 172;
          final ip = addr.address;

          if (!isVirtual && isPrivate && isWiredWifi && bestRank4 == null) {
            bestRank4 = ip; // Wi-Fi/Ethernet privada: candidata ideal.
          } else if (!isVirtual && isPrivate && privateReal == null) {
            privateReal = ip;
          } else if (isVirtual && isPrivate && privateVirtual == null) {
            privateVirtual = ip;
          } else if (!isVirtual && anyReal == null) {
            anyReal = ip;
          }
        }
      }

      // Orden de preferencia: Wi-Fi/Ethernet privada → privada real →
      // cualquiera real → privada de adaptador virtual (último recurso).
      return bestRank4 ?? privateReal ?? anyReal ?? privateVirtual;
    } catch (_) {
      // Sin red o sin permisos: el QR se genera sin host (modo PIN/local).
    }
    return null;
  }

  /// Inicia una nueva sesión de emparejamiento con PIN aleatorio de 6 dígitos.
  ///
  /// No realiza I/O de red para poder usarse en cualquier entorno; la IP LAN de
  /// la PC (necesaria para el modo Wi-Fi) la resuelve [detectLanIpv4] quien
  /// inicie la sesión y la incorpora al QR cuando esté disponible.
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

    final serverHost = decoded['server_host'];
    final serverPort = decoded['server_port'];
    var host = serverHost is String && serverHost.trim().isNotEmpty
        ? serverHost.trim()
        : null;
    if (host != null && !_looksLikeHost(host)) host = null;

    final port = serverPort is int
        ? serverPort
        : int.tryParse('$serverPort');
    final validPort = port != null && port > 0 && port <= 65535;

    return PairPayload(
      tenantId: tenantId.trim(),
      pairCode: pairCode,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresMs),
      serverHost: host,
      serverPort: validPort ? port : null,
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
    // El QR trae la IP local de la PC: el teléfono la guarda como endpoint de
    // sincronización (descubrimiento sin mDNS).
    final host = payload.serverHost;
    if (host != null) {
      final port = payload.serverPort ?? defaultSyncPort;
      await saveSyncServerUrl('http://$host:$port');
    }
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

  static bool _looksLikeHost(String value) =>
      RegExp(r'^[a-zA-Z0-9.\-]+$').hasMatch(value);

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