import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Claims mínimos usados por la licencia offline de BodegaFlow.
class LicenseClaims {
  const LicenseClaims({
    required this.payload,
    required this.rawToken,
  });

  final Map<String, dynamic> payload;
  final String rawToken;

  /// Identificador de hardware al que fue emitida la licencia.
  String get hwid => (payload['hwid'] as String?) ?? '';

  /// Instante en que la licencia deja de ser válida (`exp`, seconds).
  DateTime? get expiresAt => _parseDate(payload['exp']);

  /// Instante desde el cual la licencia es válida (`nbf`, opcional).
  DateTime? get notBefore => _parseDate(payload['nbf']);

  /// Suscriptor / licencia emitida (`sub`, opcional).
  String? get subject => payload['sub'] as String?;

  static DateTime? _parseDate(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000,
          isUtc: true);
    }
    if (value is String) {
      final asNum = int.tryParse(value);
      if (asNum != null) {
        return DateTime.fromMillisecondsSinceEpoch(asNum * 1000, isUtc: true);
      }
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }
}

/// Verificación de firma RS256 (RSA PKCS#1 v1.5 + SHA-256) de JWT de licencia.
///
/// Diseñada 100% offline: la Clave Pública está embebida en el ejecutable y
/// aqui solo se hace matemática RSA con librería pura (sin red).
class RsaJwtVerifier {
  RsaJwtVerifier._();

  /// Algoritmo exigido en el header del JWT.
  static const String requiredAlgorithm = 'RS256';

  /// Tolerancia de deriva de reloj para las fechas del token.
  static const Duration clockSkew = Duration(minutes: 1);

  /// DigestInfo de SHA-256 según RFC 3447: `30 31 30 0d 06 09 60 86 48
  /// 01 65 03 04 02 01 05 00 04 20` (19 bytes) + hash (32 bytes).
  static const List<int> _sha256DigestInfo = [
    0x30,
    0x31,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x01,
    0x05,
    0x00,
    0x04,
    0x20,
  ];

  /// Parsea una Clave Pública RSA en formato PEM "PUBLIC KEY"
  /// (SubjectPublicKeyInfo, PKCS#8).
  static RSAPublicKey parsePublicKeyPem(String pem) {
    final body = pem
        .replaceAll(RegExp(r'-----BEGIN [^-]*-----'), '')
        .replaceAll(RegExp(r'-----END [^-]*-----'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
    final der = base64Url.decode(base64Url.normalize(body));
    return _parseSubjectPublicKeyInfo(der);
  }

  /// Verifica un JWT de licencia. Devuelve los claims si la firma es válida,
  /// el `hwid` coincide y las fechas cuadran; `null` en cualquier otro caso.
  static LicenseClaims? verify({
    required String token,
    required RSAPublicKey publicKey,
    String? expectedHwid,
    DateTime? now,
  }) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final header = jsonDecode(utf8.decode(_decodeSegment(parts[0])));
      final payload = jsonDecode(utf8.decode(_decodeSegment(parts[1])));
      if (header is! Map || payload is! Map) return null;
      if (header['alg'] != requiredAlgorithm) return null;

      final message = utf8.encode('${parts[0]}.${parts[1]}');
      final expected = _emPkcs1v15Sha256(message, publicKey.modulus!);
      final signature = _bigEndian(_decodeSegment(parts[2]));
      if (signature >= publicKey.modulus!) return null;

      final recovered = _intToBytesPadded(
        signature.modPow(publicKey.publicExponent!, publicKey.modulus!),
        expected.length,
      );
      if (!_constantTimeEquals(recovered, expected)) return null;

      final claims = LicenseClaims(
        payload: Map<String, dynamic>.from(payload),
        rawToken: token,
      );
      if (claims.hwid.isEmpty) return null;
      if (expectedHwid != null && claims.hwid != expectedHwid) return null;

      final reference = (now ?? DateTime.now()).toUtc();
      final expires = claims.expiresAt;
      if (expires == null || expires.isBefore(reference.subtract(clockSkew))) {
        return null;
      }
      final notBefore = claims.notBefore;
      if (notBefore != null && notBefore.isAfter(reference.add(clockSkew))) {
        return null;
      }
      return claims;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _decodeSegment(String segment) {
    return base64Url.decode(base64Url.normalize(segment));
  }

  static Uint8List _emPkcs1v15Sha256(List<int> message, BigInt modulus) {
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(message));

    final emLen = (modulus.bitLength + 7) ~/ 8;
    final trailer = Uint8List.fromList(
      List<int>.from(_sha256DigestInfo)..addAll(hash),
    );
    if (emLen < trailer.length + 11) {
      throw ArgumentError('Modulus demasiado corto para SHA-256');
    }

    final em = Uint8List(emLen);
    em[0] = 0x00;
    em[1] = 0x01;
    for (var i = 2; i < emLen - trailer.length - 1; i++) {
      em[i] = 0xff;
    }
    em[emLen - trailer.length - 1] = 0x00;
    em.setRange(emLen - trailer.length, emLen, trailer);
    return em;
  }

  static BigInt _bigEndian(Uint8List bytes) {
    if (bytes.isEmpty) return BigInt.zero;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hex, radix: 16);
  }

  static Uint8List _intToBytesPadded(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(
      List<int>.generate(length, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Parsea una SubjectPublicKeyInfo (SPKI) con algoritmo RSA.
  static RSAPublicKey _parseSubjectPublicKeyInfo(Uint8List der) {
    final cursor = _DerCursor(der);
    final outer = cursor.readTlv();
    if (outer.tag != 0x30) throw const FormatException('SPKI no es SEQUENCE');

    final inner = _DerCursor(outer.content);
    final algorithm = inner.readTlv();
    if (algorithm.tag != 0x30) {
      throw const FormatException('SPKI sin AlgorithmIdentifier');
    }
    final algorithmParams = _DerCursor(algorithm.content);
    algorithmParams.readTlv(); // OID rsaEncryption.
    algorithmParams.readTlv(); // NULL.

    final bitString = inner.readTlv();
    if (bitString.tag != 0x03) {
      throw const FormatException('SPKI sin BIT STRING');
    }
    if (bitString.content.isEmpty || bitString.content[0] != 0) {
      throw const FormatException('BIT STRING inválida');
    }

    final rsa = _DerCursor(bitString.content.sublist(1));
    final seq = rsa.readTlv();
    if (seq.tag != 0x30) throw const FormatException('RSA key no es SEQUENCE');

    final rsaCursor = _DerCursor(seq.content);
    final modulusDer = rsaCursor.readTlv();
    final exponentDer = rsaCursor.readTlv();
    if (modulusDer.tag != 0x02 || exponentDer.tag != 0x02) {
      throw const FormatException('INTEGER esperado en RSA key');
    }
    return RSAPublicKey(
      _bigEndian(modulusDer.content),
      _bigEndian(exponentDer.content),
    );
  }
}

class _Tlv {
  const _Tlv(this.tag, this.content);

  final int tag;
  final Uint8List content;
}

class _DerCursor {
  _DerCursor(this._data) : _pos = 0;

  final Uint8List _data;
  int _pos;

  _Tlv readTlv() {
    if (_pos >= _data.length) throw const FormatException('DER truncado');
    final tag = _data[_pos++];
    if (_pos >= _data.length) throw const FormatException('DER sin longitud');
    var length = _data[_pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || _pos + count > _data.length) {
        throw const FormatException('Longitud DER inválida');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _data[_pos++];
      }
    }
    if (_pos + length > _data.length) {
      throw const FormatException('Contenido DER truncado');
    }
    final content = Uint8List.fromList(_data.sublist(_pos, _pos + length));
    _pos += length;
    return _Tlv(tag, content);
  }
}