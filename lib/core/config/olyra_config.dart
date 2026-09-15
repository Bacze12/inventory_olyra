/// Configuración del licenciamiento offline por License Key (olyra.cl).
class OlyraConfig {
  OlyraConfig._();

  /// Endpoint de activación online (primer uso únicamente).
  static const String activationUrl = 'https://olyra.cl/api/v1/license/activate';

  /// Endpoint de revalidación silenciosa en segundo plano (offline-safe).
  static const String validateUrl = 'https://olyra.cl/api/v1/license/validate';

  /// Endpoint de respaldo/sincronización de la nube (ventas + movimientos).
  /// Acepta `POST` batch upsert hacia las tablas `pos_sales`/`pos_movements`
  /// vinculadas al `user_app_id` de la licencia.
  static const String posSyncUrl = 'https://olyra.cl/api/v1/pos/sync';

  /// Nombre del archivo de licencia cifrado en el directorio local.
  static const String licenseFileName = 'license.dat';

  /// Clave pública RSA-2048 (PEM SubjectPublicKeyInfo) embebida en el binario.
  ///
  /// Corresponde a la clave privada que firma los JWT del proveedor (olyra.cl).
  /// La validación offline (camino crítico) solo usa esta clave; nunca hace
  /// peticiones de red. La privada nunca viaja en la app ni se versiona.
  static const String publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA62tNn7jAmk6L7klpCWON
7qsJCsDkjEqWge9QqEkEtWVzp+tykN/68oSBawaBLBxHJsIxpsLBnE05t6sucThZ
3teCWykr5lvInSaZLQAqGhXgaSjKF3DrXDhMJutFbn5uEnzzbILZLO4efEbaFsVa
alQe1UTgAQn7fejnVdwPzssf8co1hResD2rc29mqeNx+hoWV8i+sRDyY7UBE+69g
V+pQ0ywonwsyVAW9dFRV7jFLRFWNoPLDzqLrmmAvKXbm9LSmLhvrGDlD3FldIdKZ
iOaYGgPKVwO9unZgxQ8IvluDTuRqNwYrwZY0zCeqBOCHXmfXO0SJ9ZRmiHt7ifNR
XwIDAQAB
-----END PUBLIC KEY-----''';
}