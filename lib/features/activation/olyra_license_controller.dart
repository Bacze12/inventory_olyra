// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/remote/olyra_license_api.dart';
import '../../services/hardware_identity.dart';
import 'jwt_license_validator.dart';
import 'license_file_store.dart';

/// Estado del licenciamiento offline de la app.
enum OlyraLicenseState {
  /// Leyendo/verificando el archivo de licencia local al arrancar.
  checking,

  /// No hay licencia válida: hay que activar con un License Key.
  needsActivation,

  /// Licencia activa (firma válida, HWID coincide y fecha vigente).
  active,
}

/// Controlador del licenciamiento por License Key (olyra.cl + JWT RS256).
///
/// En cada apertura de la app valida 100% offline la firma del JWT guardado
/// con la Clave Pública embebida; nunca consulta la red salvo en el primer
/// uso (activación online) o revalidación manual.
class OlyraLicenseController extends ChangeNotifier {
  OlyraLicenseController({
    required HardwareIdentity hardware,
    required OlyraLicenseApi api,
    required String publicKeyPem,
  })  : _hardware = hardware,
        _api = api,
        _publicKeyPem = publicKeyPem;

  final HardwareIdentity _hardware;
  final OlyraLicenseApi _api;
  final String _publicKeyPem;

  OlyraLicenseState _state = OlyraLicenseState.checking;
  String? _hardwareId;
  LicenseFileStore? _store;
  LicenseClaims? _claims;
  bool _activating = false;
  String? _activationError;
  String _lastMessage = '';

  OlyraLicenseState get state => _state;
  bool get isUnlocked => _state == OlyraLicenseState.active;
  bool get activating => _activating;
  String? get activationError => _activationError;
  LicenseClaims? get claims => _claims;
  String get lastMessage => _lastMessage;

  /// Identificador de hardware, resuelto al inicializar.
  String? get hardwareId => _hardwareId;

  /// Carga y verifica la licencia local. Bloquea el uso si no es válida.
  Future<void> init() async {
    try {
      _hardwareId = await _hardware.id();
      final dir = await getApplicationSupportDirectory();
      _store = LicenseFileStore(dir, hardwareId: _hardwareId!);

      final saved = await _store!.read();
      if (saved == null) {
        _state = OlyraLicenseState.needsActivation;
        return;
      }

      final claims = _verifyLocal(saved);
      if (claims == null) {
        // Firma inválida / HWID distinto / vencida o archivo comprometido.
        await _store!.clear();
        _state = OlyraLicenseState.needsActivation;
        _lastMessage =
            'La licencia local no es válida en este equipo. Activa de nuevo.';
        return;
      }

      _claims = claims;
      _state = OlyraLicenseState.active;
      _lastMessage = 'Licencia activa hasta '
          '${_formatDate(claims.expiresAt)}.';
    } catch (error) {
      debugPrint('[OlyraLicense] init falló: $error');
      _state = OlyraLicenseState.needsActivation;
    } finally {
      notifyListeners();
    }
  }

  /// Activación online (primer uso). Devuelve `true` si quedó activada.
  Future<bool> activate(String licenseKey) async {
    if (_activating || _hardwareId == null) return false;
    _activating = true;
    _activationError = null;
    _lastMessage = 'Activando…';
    notifyListeners();

    try {
      final token = await _api.activate(
        hwid: _hardwareId!,
        licenseKey: licenseKey,
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
      debugPrint('[OlyraLicense] token guardado en license.dat');

      _claims = claims;
      _state = OlyraLicenseState.active;
      _lastMessage = '¡Activado! Licencia válida hasta '
          '${_formatDate(claims.expiresAt)}.';
      return true;
    } on LicenseServerException catch (error, stack) {
      debugPrint('[OlyraLicense] LicenseServerException: ${error.message} '
          'status=${error.statusCode}');
      debugPrint('$stack');
      final code = error.statusCode;
      _activationError = code == null
          ? error.message
          : 'Error $code: ${error.message}';
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

  /// Quita la licencia local (desactivación manual).
  Future<void> deactivate() async {
    await _store?.clear();
    _claims = null;
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

  String _formatDate(DateTime? value) {
    if (value == null) return 'fecha por definir';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}