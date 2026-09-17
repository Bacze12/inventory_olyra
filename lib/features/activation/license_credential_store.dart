import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credenciales de licencia persistidas de forma cifrada con
/// `flutter_secure_storage` (DPAPI en Windows).
class LicenseCredentials {
  const LicenseCredentials({
    required this.licenseKey,
    required this.hardwareId,
    required this.activationToken,
    this.deviceName,
    this.userAppId,
  });

  final String licenseKey;
  final String hardwareId;
  final String activationToken;
  final String? deviceName;

  /// UUID de la fila `user_apps` (la "bodega") al que pertenecen los datos
  /// POS. Lo entrega el servidor (JWT claim `user_app_id` o respuesta de
  /// activate/validate) y es DISTINTO del `app_id` global del producto.
  final String? userAppId;
}

/// Persistencia cifrada de `license_key`, `hardware_id`, `activation_token`,
/// `device_name` y `user_app_id` en el almacenamiento seguro del sistema.
class LicenseCredentialStore {
  LicenseCredentialStore(this._storage);

  static const String keyLicenseKey = 'license_key';
  static const String keyHardwareId = 'hardware_id';
  static const String keyActivationToken = 'activation_token';
  static const String keyDeviceName = 'device_name';
  static const String keyUserAppId = 'user_app_id';

  final FlutterSecureStorage _storage;

  /// Lee todas las credenciales guardadas. Devuelve `null` si no hay token.
  Future<LicenseCredentials?> read() async {
    final token = await _storage.read(key: keyActivationToken);
    if (token == null || token.isEmpty) return null;
    return LicenseCredentials(
      licenseKey: (await _storage.read(key: keyLicenseKey)) ?? '',
      hardwareId: (await _storage.read(key: keyHardwareId)) ?? '',
      activationToken: token,
      deviceName: await _storage.read(key: keyDeviceName),
      userAppId: await _storage.read(key: keyUserAppId),
    );
  }

  /// Guarda (o sobrescribe) las credenciales de la licencia.
  Future<void> save({
    required String licenseKey,
    required String hardwareId,
    required String activationToken,
    String? deviceName,
    String? userAppId,
  }) async {
    await _storage.write(key: keyLicenseKey, value: licenseKey);
    await _storage.write(key: keyHardwareId, value: hardwareId);
    await _storage.write(key: keyActivationToken, value: activationToken);
    if (deviceName != null && deviceName.isNotEmpty) {
      await _storage.write(key: keyDeviceName, value: deviceName);
    }
    if (userAppId != null && userAppId.isNotEmpty) {
      await _storage.write(key: keyUserAppId, value: userAppId);
    }
  }

  /// Refresca solo el `user_app_id` (p. ej. lo que devolvió una revalidación);
  /// no toca el token ni el nombre del equipo.
  Future<void> saveUserAppId(String value) async {
    if (value.isEmpty) return;
    await _storage.write(key: keyUserAppId, value: value);
  }

  /// Elimina todas las credenciales locales (desactivación).
  Future<void> clear() async {
    await _storage.delete(key: keyLicenseKey);
    await _storage.delete(key: keyHardwareId);
    await _storage.delete(key: keyActivationToken);
    await _storage.delete(key: keyDeviceName);
    await _storage.delete(key: keyUserAppId);
  }
}