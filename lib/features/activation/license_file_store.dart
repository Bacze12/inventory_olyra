import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Persistencia del token de licencia en un archivo local cifrado
/// (`license.dat`) en el directorio de soporte de la app.
///
/// Cifrado: AES-256-GCM con asociación del archivo a la máquina. La clave se
/// deriva del HWID con HKDF-SHA256 para que el archivo sea ilegible fuera del
/// equipo (y cambiar el HWID invalide el archivo).
class LicenseFileStore {
  LicenseFileStore(this._dir, {required String hardwareId})
      : assert(hardwareId.isNotEmpty, 'hwid vacío'),
        _hardwareId = hardwareId;

  static const String fileName = 'license.dat';
  static const List<int> _magic = [0x42, 0x46, 0x4c, 0x59]; // "BFLY".
  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _macBits = 128;

  final Directory _dir;
  final String _hardwareId;

  Uint8List? _aesKey;
  File get _file => File('${_dir.path}${Platform.pathSeparator}$fileName');

  /// `true` si existe un archivo de licencia guardado.
  Future<bool> exists() async => _file.exists();

  /// Lee y desencripta el token. Devuelve `null` si no hay archivo.
  ///
  /// Lanza [InvalidCipherTextException] si el archivo fue alterado o la clave
  /// AES derivada no coincide (por ejemplo, tras un clon de disco en otra
  /// máquina).
  Future<String?> read() async {
    if (!await _file.exists()) return null;
    final blob = await _file.readAsBytes();
    if (blob.length < 4 + 1 + _nonceLength + 16) {
      throw InvalidCipherTextException('Archivo de licencia corrupto');
    }

    var offset = 0;
    for (final byte in _magic) {
      if (blob[offset++] != byte) {
        throw InvalidCipherTextException('Archivo de licencia corrupto');
      }
    }
    if (blob[offset++] != _version) {
      throw InvalidCipherTextException('Versión de licencia no soportada');
    }

    final nonce = blob.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;
    final ciphertext = blob.sublist(offset);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, _params(_aesKeyFor(), nonce));
    final plain = utf8.decode(cipher.process(ciphertext), allowMalformed: false);
    return plain;
  }

  /// Cifra y escribe el token en disco. Crea el directorio si no existe.
  Future<void> write(String token) async {
    await _dir.create(recursive: true);
    final nonce = _secureRandomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, _params(_aesKeyFor(), nonce));

    final ciphertext = cipher.process(Uint8List.fromList(utf8.encode(token)));

    final blob = BytesBuilder()
      ..add(_magic)
      ..add([_version])
      ..add(nonce)
      ..add(ciphertext);
    await _file.writeAsBytes(blob.toBytes(), flush: true);
  }

  /// Elimina el archivo de licencia local (desactivación).
  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  AEADParameters<KeyParameter> _params(Uint8List key, List<int> nonce) {
    return AEADParameters<KeyParameter>(
      KeyParameter(key),
      _macBits,
      Uint8List.fromList(nonce),
      Uint8List(0),
    );
  }

  /// Clave AES-256 derivada del HWID (HKDF-SHA256, cacheada).
  Uint8List _aesKeyFor() {
    if (_aesKey != null) return _aesKey!;
    final ikm = Uint8List.fromList(utf8.encode(_hardwareId));
    final salt = utf8.encode('olyra.bodegaflow');
    final info = utf8.encode('bodegaflow:license:file:v1');

final kdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(ikm, 32, salt, info));
    final key = Uint8List(32);
    kdf.deriveKey(Uint8List(0), 0, key, 0);
    return _aesKey = key;
  }

  static Uint8List _secureRandomBytes(int count) => Uint8List.fromList(
      List<int>.generate(count, (_) => Random.secure().nextInt(256)));
}