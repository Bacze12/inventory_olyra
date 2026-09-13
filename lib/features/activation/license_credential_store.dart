import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credenciales de licencia persistidas de forma cifrada con
/// `flutter_secure_storage` (DPAPI en Windows).
class LicenseCredentials {
  const LicenseCredentials({
    required this.licenseKey,
    required this.hardwareId,
    required this.activationToken,
    this.deviceName,
  });

  final String licenseKey;
  final String hardwareId;
  final String activationToken;
  final String? deviceName;
}

/// Persistencia cifrada de `license_key`, `hardware_id`, `activation_token` y
/// `device_name` en el almacenamiento seguro del sistema.
class LicenseCredentialStore {
  LicenseCredentialStore(this._storage);

  static const String keyLicenseKey = 'license_key';
  static const String keyHardwareId = 'hardware_id';
  static const String keyActivationToken = 'activation_token';
  static const String keyDeviceName = 'device_name';

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
    );
  }

  /// Guarda (o sobrescribe) las credenciales de la licencia.
  Future<void> save({
    required String licenseKey,
    required String hardwareId,
    required String activationToken,
    String? deviceName,
  }) async {
    await _storage.write(key: keyLicenseKey, value: licenseKey);
    await _storage.write(key: keyHardwareId, value: hardwareId);
    await _storage.write(key: keyActivationToken, value: activationToken);
    if (deviceName != null && deviceName.isNotEmpty) {
      await _storage.write(key: keyDeviceName, value: deviceName);
    }
  }

  /// Elimina todas las credenciales locales (desactivación).
  Future<void> clear() async {
    await _storage.delete(key: keyLicenseKey);
    await _storage.delete(key: keyHardwareId);
    await _storage.delete(key: keyActivationToken);
    await _storage.delete(key: keyDeviceName);
  }
}