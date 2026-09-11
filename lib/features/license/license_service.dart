import 'dart:async';

import 'package:flutter/foundation.dart';

// Los constructores inyectan campos privados por nombre (['gateway', ...]).
// ignore_for_file: prefer_initializing_formals

import '../../core/config/app_config.dart';
import '../../data/cloud/supabase_gateway.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/hardware_identity.dart';

/// Estados posibles del licenciamiento del dispositivo.
enum LicenseStatus {
  /// Credenciales no compiladas: la nube está desactivada, no hay licencia.
  unconfigured,

  /// Nube activa pero sin sesión de usuario (RLS no podría filtrar).
  needsLogin,

  /// Validación en curso.
  loading,

  /// Licencia activa (incluye gracia offline).
  active,

  /// Licencia expirada, desactivada o dispositivo no autorizado.
  invalid,
}

/// La operación de nube no se puede completar sin una licencia activa en este
/// equipo (sincronizar, respaldar, etc.).
class CloudLicenseNotReadyException implements Exception {
  CloudLicenseNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Validación de licencia por hardware de BodegaFlow POS.
///
/// Flujo:
///   1. Obtiene el `hardware_id` local (MachineGuid / UUID persistido).
///   2. Exige sesión de usuario (la licencia pertenece a `auth.uid()`).
///   3. Llama a la RPC `fn_validate_device` (SECURITY DEFINER, scopeado al
///      usuario) y guarda el resultado en SQLite para uso offline.
///
/// Política de gracia (offline-first): el último estado válido se respeta
/// hasta 7 días después de la última verificación, así el POS no se bloquea
/// por una caída puntual de internet. Transcurrido ese periodo sin poder
/// re-validar, se bloquean las ventas.
class LicenseService extends ChangeNotifier {
  LicenseService({
    required SupabaseGateway gateway,
    required HardwareIdentity hardware,
    required SettingsRepository settings,
  })  : _gateway = gateway,
        _hardware = hardware,
        _settings = settings;

  final SupabaseGateway _gateway;
  final HardwareIdentity _hardware;
  final SettingsRepository _settings;

  /// Ventana de gracia sin conexión tras una validación exitosa.
  static const Duration offlineGrace = Duration(days: 7);

  static const String kHardwareId = 'license_hardware_id';
  static const String kLicenseKey = 'license_key';
  static const String kLicenseApp = 'license_app_name';
  static const String kLicenseValid = 'license_valid';
  static const String kLicenseCheckedAt = 'license_checked_at';
  static const String kLicenseExpiresAt = 'license_expires_at';
  static const String kUserAppId = 'license_user_app_id';

  LicenseStatus _status = LicenseStatus.unconfigured;
  String _hardwareId = '';
  String? _licenseKey;
  String? _userAppId;
  String? _lastError;

  LicenseStatus get status => _status;
  String get hardwareId => _hardwareId;
  String? get licenseKey => _licenseKey;
  String? get userAppId => _userAppId;
  String? get lastError => _lastError;

  /// `true` si el módulo nube está configurado y activo en la build actual.
  bool get enforced => AppConfig.enableCloudSync && _gateway.isConfigured;

  /// `true` → bloquea ventas en el POS (licencia comprobada e inválida).
  ///
  /// Nunca bloquea por estado ambiguo (`unconfigured`, `needsLogin`,
  /// `loading`): solo cuando la nube respondió que NO hay licencia válida.
  bool get isBlockingSales => _status == LicenseStatus.invalid;

  /// Resuelve el hardware y dispara la validación inicial (no bloqueante).
  Future<void> init() async {
    if (!enforced) {
      _status = LicenseStatus.unconfigured;
      notifyListeners();
      return;
    }
    _hardwareId = await _hardware.id();
    await refresh();
  }

  /// Re-validación contra Supabase. Ante fallo de red usa la cache (gracia).
  /// Lanza [SupabaseSessionMissingException] si no hay sesión.
  Future<void> refresh() async {
    if (!enforced) {
      _status = LicenseStatus.unconfigured;
      notifyListeners();
      return;
    }
    if (_hardwareId.isEmpty) _hardwareId = await _hardware.id();
    _status = LicenseStatus.loading;
    _lastError = null;
    notifyListeners();

    if (!await _gateway.hasSession()) {
      _status = LicenseStatus.needsLogin;
      notifyListeners();
      return;
    }

    try {
      final client = await _gateway.client();
      final rows = await client.rpc(
        'fn_validate_device',
        params: {'p_hardware_id': _hardwareId},
      );

      final first = rows is List && rows.isNotEmpty ? rows.first : null;
      final map = first is Map ? Map<String, dynamic>.from(first) : null;
      final valid = map?['valid'] == true;

      if (valid) {
        await _persistValid(map);
        _status = LicenseStatus.active;
      } else {
        await _persistInvalid();
        _status = LicenseStatus.invalid;
      }
    } catch (error) {
      // Fallo de red / servidor: se respeta la gracia offline si la última
      // validación fue reciente; si no, se bloquea para no vender sin licencia.
      final ok = await _restoreCache();
      _status = ok ? LicenseStatus.active : LicenseStatus.invalid;
      if (!ok) _lastError = '$error';
    }
    notifyListeners();
  }

  /// Inicia sesión con email/contraseña del usuario dueño de la licencia.
  Future<void> signIn({required String email, required String password}) async {
    final client = await _gateway.client();
    await client.auth.signInWithPassword(email: email, password: password);
    await refresh();
  }

  Future<void> signOut() async {
    await _gateway.signOut();
    _status = enforced ? LicenseStatus.needsLogin : LicenseStatus.unconfigured;
    notifyListeners();
  }

  Future<void> _persistValid(Map<String, dynamic>? map) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _settings.set(kHardwareId, _hardwareId);
    await _settings.set(kLicenseValid, '1');
    await _settings.set(kLicenseCheckedAt, now);
    _licenseKey = map?['license_key'] as String?;
    _userAppId = map?['user_app_id'] as String?;
    await _settings.set(kLicenseKey, _licenseKey ?? '');
    await _settings.set(
      kLicenseApp,
      (map?['app_name'] as String?) ?? '',
    );
    await _settings.set(
      kLicenseExpiresAt,
      (map?['expires_at'])?.toString() ?? '',
    );
    await _settings.set(
      kUserAppId,
      (map?['user_app_id'])?.toString() ?? '',
    );
  }

  Future<void> _persistInvalid() async {
    await _settings.set(kHardwareId, _hardwareId);
    await _settings.set(kLicenseValid, '0');
    await _settings.set(kLicenseCheckedAt, DateTime.now().toUtc().toIso8601String());
    _licenseKey = null;
  }

  /// Devuelve `true` si la última validación guardada es válida y está dentro
  /// de la ventana de gracia offline.
  Future<bool> _restoreCache() async {
    final valid = await _settings.get(kLicenseValid);
    if (valid != '1') return false;
    final checked = await _settings.get(kLicenseCheckedAt);
    final checkedAt = DateTime.tryParse(checked ?? '');
    if (checkedAt == null) return false;
    final stale = DateTime.now().toUtc().difference(checkedAt) > offlineGrace;
    if (stale) return false;
    _licenseKey = await _settings.get(kLicenseKey);
    _userAppId = await _settings.get(kUserAppId);
    return true;
  }
}