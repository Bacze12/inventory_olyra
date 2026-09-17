// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/remote/olyra_license_api.dart';
import '../../services/hardware_id_service.dart';
import 'jwt_license_validator.dart';
import 'license_credential_store.dart';
import 'license_file_store.dart';

/// Estado del licenciamiento offline de la app.
enum OlyraLicenseState {
  /// Leyendo/verificando la licencia local al arrancar.
  checking,

  /// No hay licencia válida: hay que activar con un License Key.
  needsActivation,

  /// Licencia activa (firma válida, HWID coincide y fecha vigente).
  active,
}

/// Controlador del licenciamiento por License Key (olyra.cl + JWT RS256).
///
/// En cada apertura valida 100% offline la firma del JWT guardado con la Clave
/// Pública embebida; el acceso nunca depende de la red. Al activar (o al
/// arrancar con licencia válida) se dispara una revalidación silenciosa contra
/// `/api/v1/license/validate`: si el servidor no responde (offline) la app
/// sigue funcionando con el registro local.
class OlyraLicenseController extends ChangeNotifier {
  OlyraLicenseController({
    required HardwareIdService hardware,
    required OlyraLicenseApi api,
    required LicenseCredentialStore credentials,
    required String publicKeyPem,
  })  : _hardware = hardware,
        _api = api,
        _credentials = credentials,
        _publicKeyPem = publicKeyPem;

  final HardwareIdService _hardware;
  final OlyraLicenseApi _api;
  final LicenseCredentialStore _credentials;
  final String _publicKeyPem;

  OlyraLicenseState _state = OlyraLicenseState.checking;
  String? _hardwareId;
  LicenseFileStore? _store;
  LicenseClaims? _claims;
  String? _deviceName;
  String? _userAppId;
  String? _activationError;
  String _lastMessage = '';
  bool _activating = false;
  bool _validating = false;

  /// Round-trip de validación online en vuelo. Comparten la misma petición
  /// la revalidación silenciosa de arranque y el botón "Revalidar" de la nube
  /// (dos llamadas solapadas → una sola request; quien llegue segundo reusa
  /// el resultado en lugar de devolver un falso negativo).
  Future<OlyraValidateResult?>? _pendingValidate;

  OlyraLicenseState get state => _state;
  bool get isUnlocked => _state == OlyraLicenseState.active;
  bool get activating => _activating;
  bool get validating => _validating;
  String? get activationError => _activationError;
  LicenseClaims? get claims => _claims;
  String get lastMessage => _lastMessage;

  /// Identificador de hardware, resuelto al inicializar.
  String? get hardwareId => _hardwareId;

  /// Nombre con el que quedó registrado este equipo (p. ej. "Caja 1").
  String? get deviceName => _deviceName;

  /// UUID de la `user_apps` (la bodega) a la que pertenecen los datos POS.
  ///
  /// Autoridad: claim firmado `user_app_id` del JWT cuando existe; si no
  /// (licencias emitidas antes de v1.4), el valor que el servidor entregó en
  /// activate/validate y que quedó persistido en `LicenseCredentialStore`. A
  /// diferencia de [claims.app_id], NUNCA cae al `app_id` global del producto.
  String? get userAppId {
    final fromClaims = _claims?.payload['user_app_id']?.toString();
    if (fromClaims != null && fromClaims.isNotEmpty) return fromClaims;
    return (_userAppId == null || _userAppId!.isEmpty) ? null : _userAppId;
  }

  /// Carga y verifica la licencia local. Bloquea el uso si no es válida.
  Future<void> init() async {
    try {
      _hardwareId = await _hardware.id();
      final dir = await getApplicationSupportDirectory();
      _store = LicenseFileStore(dir, hardwareId: _hardwareId!);

      // 1) Fuente preferida: credenciales cifradas (flutter_secure_storage).
      final credentials = await _credentials.read();
      if (credentials != null) {
        final claims = _verifyLocal(credentials.activationToken);
        if (claims != null) {
          _userAppId = credentials.userAppId;
          _accept(claims, deviceName: credentials.deviceName, backfillFile: true);
          _scheduleSilentValidate(credentials);
          return;
        }
      }

      // 2) Fallback histórico: license.dat cifrado con DAC por HWID.
      final saved = await _store!.read();
      if (saved == null) {
        _state = OlyraLicenseState.needsActivation;
        return;
      }

      final claims = _verifyLocal(saved);
      if (claims == null) {
        // Firma inválida / HWID distinto / vencida o archivo comprometido.
        await _store!.clear();
        await _credentials.clear();
        _state = OlyraLicenseState.needsActivation;
        _lastMessage =
            'La licencia local no es válida en este equipo. Activa de nuevo.';
        return;
      }

      _accept(claims);
      _scheduleSilentValidate();
    } catch (error) {
      debugPrint('[OlyraLicense] init falló: $error');
      _state = OlyraLicenseState.needsActivation;
    } finally {
      notifyListeners();
    }
  }

  /// Activación online (primer uso). Devuelve `true` si quedó activada.
  Future<bool> activate(String licenseKey, {String deviceName = ''}) async {
    if (_activating || _hardwareId == null) return false;
    _activating = true;
    _activationError = null;
    _lastMessage = 'Activando…';
    notifyListeners();

    try {
      final token = await _api.activate(
        hwid: _hardwareId!,
        licenseKey: licenseKey,
        deviceName: deviceName,
      );
      debugPrint(
        '[OlyraLicense] token length=${token.length} '
        'hwid_sent=$_hardwareId',
      );

      final claims = _verifyLocal(token);
      if (claims == null) {
        debugPrint('[OlyraLicense] _verifyLocal devolvió null — '
            'token inválido para este equipo');
        throw const LicenseServerException(
          'El servidor entregó un token inválido para este equipo. '
          'Contacta soporte.',
        );
      }
      debugPrint(
        '[OlyraLicense] claims OK app_id=${claims.payload["app_id"]} '
        'exp=${claims.expiresAt}',
      );

      await _store!.write(token);
      final claimsUserAppId = claims.payload['user_app_id']?.toString();
      await _credentials.save(
        licenseKey: licenseKey.trim(),
        hardwareId: _hardwareId!,
        activationToken: token,
        deviceName: deviceName.isNotEmpty ? deviceName.trim() : null,
        userAppId: (claimsUserAppId == null || claimsUserAppId.isEmpty)
            ? null
            : claimsUserAppId,
      );
      debugPrint('[OlyraLicense] token guardado en license.dat y secure storage');

      _claims = claims;
      _userAppId =
          (claimsUserAppId == null || claimsUserAppId.isEmpty) ? null : claimsUserAppId;
      _deviceName = deviceName.isNotEmpty ? deviceName.trim() : null;
      _state = OlyraLicenseState.active;
      _lastMessage = '¡Activado! Licencia válida hasta '
          '${_formatDate(claims.expiresAt)}.';
      notifyListeners();
      _scheduleSilentValidate();
      return true;
    } on LicenseServerException catch (error, stack) {
      debugPrint('[OlyraLicense] LicenseServerException: ${error.message} '
          'status=${error.statusCode} code=${error.code}');
      debugPrint('$stack');
      _activationError = _friendlyError(error);
    } catch (error, stack) {
      debugPrint('[OlyraLicense] activación falló: $error');
      debugPrint('$stack');
      _activationError =
          'No se pudo activar. Reintenta en unos segundos.';
    } finally {
      _activating = false;
      notifyListeners();
    }
    return false;
  }

  /// Revalidación silenciosa en segundo plano contra `/api/v1/license/validate`.
  ///
  /// Nunca bloquea ni cambia de estado: el arranque offline se mantiene con el
  /// registro local. Si el servidor confirma, se actualiza la marca de última
  /// verificación y la fecha de vencimiento conocida.
  Future<void> validateSilently() async {
    if (_state != OlyraLicenseState.active || _hardwareId == null) return;
    final result = await _validateOnline();
    if (result != null && result.ok && result.userAppId != null) {
      _userAppId = result.userAppId;
      await _credentials.saveUserAppId(result.userAppId!);
    }
    debugPrint('[OlyraLicense] validate_silently=${result?.ok} '
        '(offline → se respeta el registro local)');
  }

  /// Revalidación online explícita (botón "Revalidar" de la nube).
  ///
  /// A diferencia de [validateSilently], devuelve si el servidor confirmó la
  /// licencia; la UI usa el resultado para pintar "Nube Activa · Sincronizado".
  /// El `user_app_id` fresco queda PERSISTIDO de inmediato (secure storage) y
  /// el estado se notifica para que el modal se refresque al instante.
  Future<bool> validateNow() async {
    if (_state != OlyraLicenseState.active || _hardwareId == null) return false;
    final result = await _validateOnline();
    if (result != null && result.ok && result.userAppId != null) {
      final userAppId = result.userAppId!;
      if (_userAppId != userAppId) {
        _userAppId = userAppId;
        await _credentials.saveUserAppId(userAppId);
        notifyListeners();
      }
    }
    debugPrint('[OlyraLicense] validate_now=${result?.ok}');
    return result?.ok ?? false;
  }

  /// Empuja la validación online contra `/api/v1/license/validate` y devuelve
  /// su resultado (o `null` si no hubo respuesta). Si ya hay una en vuelo, se
  /// reusa: jamás se disparan dos POST simultáneos ni se responde falso por
  /// solapamiento.
  Future<OlyraValidateResult?> _validateOnline() async {
    final inFlight = _pendingValidate;
    if (inFlight != null) return inFlight;

    _validating = true;
    final hwid = _hardwareId!;
    late final Future<OlyraValidateResult?> request;
    request = () async {
      try {
        final credentials = await _credentials.read();
        return await _api.validateWithMeta(
          licenseKey: credentials?.licenseKey ?? '',
          hwid: hwid,
          token: _claims?.rawToken ?? credentials?.activationToken ?? '',
          deviceName: credentials?.deviceName ?? _deviceName ?? '',
        );
      } catch (error) {
        debugPrint('[OlyraLicense] validate online falló: $error');
        return null;
      } finally {
        _validating = false;
      }
    }();
    _pendingValidate = request;
    try {
      return await request;
    } finally {
      if (identical(_pendingValidate, request)) _pendingValidate = null;
    }
  }

  /// Quita la licencia local (desactivación manual).
  Future<void> deactivate() async {
    await _store?.clear();
    await _credentials.clear();
    _claims = null;
    _deviceName = null;
    _userAppId = null;
    _state = OlyraLicenseState.needsActivation;
    _lastMessage = 'Licencia local eliminada.';
    notifyListeners();
  }

  LicenseClaims? _verifyLocal(String token) {
    final publicKey = RsaJwtVerifier.parsePublicKeyPem(_publicKeyPem);
    return RsaJwtVerifier.verify(
      token: token,
      publicKey: publicKey,
      expectedHwid: _hardwareId,
    );
  }

  void _accept(LicenseClaims claims, {String? deviceName, bool backfillFile = false}) {
    _claims = claims;
    _deviceName = deviceName;
    _state = OlyraLicenseState.active;
    _lastMessage =
        'Licencia activa hasta ${_formatDate(claims.expiresAt)}.';
    if (backfillFile && _store != null) {
      // Migración desde secure storage hacia el archivo máquina-vinculado.
      unawaited(_store!.write(claims.rawToken).catchError((_) {}));
    }
  }

  void _scheduleSilentValidate([LicenseCredentials? credentials]) {
    if (credentials != null && credentials.licenseKey.isEmpty) return;
    unawaited(validateSilently());
  }

  String _friendlyError(LicenseServerException error) {
    if (error.code == 'MAX_DEVICES_REACHED') {
      return 'Límite de computadores alcanzado para esta licencia. '
          'Administra tus dispositivos en tu panel de olyra.cl.';
    }
    if (error.code == 'KEY_EXPIRED') {
      return 'Esta licencia está vencida. Renueva tu suscripción en olyra.cl.';
    }
    if (error.code == 'KEY_REVOKED') {
      return 'Esta licencia fue revocada. Contacta soporte en olyra.cl.';
    }
    final code = error.statusCode;
    if (code == null) return error.message;
    return 'Error $code: ${error.message}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'fecha por definir';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}