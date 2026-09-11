import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:scanflow/features/activation/jwt_license_validator.dart';
import 'package:scanflow/features/activation/license_file_store.dart';

/// Herramienta de desarrollo para el licenciamiento offline (RS256).
///
/// Uso:
///   `dart run tool/rsa_license_util.dart keygen --out DIR`
///       Genera un par RSA-2048, escribe `DIR/private.json` y `DIR/public.pem`
///       e imprime la Clave Pública PEM para incrustarla en
///       `OlyraConfig.publicKeyPem`.
///
///   `dart run tool/rsa_license_util.dart sign --priv PRIVATE_JSON --hwid ID
///       --exp UNIX_O_ISO_DAYS [--sub NOMBRE]`
///       Emite un JWT RS256 de prueba. El servidor real (olyra.cl) firma igual.
///
///   `dart run tool/rsa_license_util.dart verify --token TOKEN --pem PUBLIC_PEM
///       [--hwid ID]`
///       Verifica un token contra la clave pública incrustable.
///
///   `dart run tool/rsa_license_util.dart selfcheck`
///       Prueba end-to-end local (keygen → sign → verify → license.dat).
///
///   `dart run tool/rsa_license_util.dart importpriv --pem CLAVE_PRIVADA.pem
///       [--out DIR]`
///       Importa la clave privada real (PKCS#8) de olyra.cl, escribe
///       `private.json`/`public.pem` e imprime la pública para OlyraConfig.
///       La clave privada NUNCA se versiona.
Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'help' : args[0];
  switch (command) {
    case 'keygen':
      await _keygen(_option(args, 'out') ?? Directory.current.path);
    case 'sign':
      await _sign(
        privPath: _required(args, 'priv'),
        hwid: _required(args, 'hwid'),
        expires: _required(args, 'exp'),
        subject: _option(args, 'sub'),
      );
    case 'verify':
      await _verify(
        token: _required(args, 'token'),
        pemPath: _required(args, 'pem'),
        hwid: _option(args, 'hwid'),
      );
    case 'selfcheck':
      await _selfcheck();
    case 'importpriv':
      await _importPrivateKey(
        pemPath: _required(args, 'pem'),
        outDir: _option(args, 'out') ?? Directory.current.path,
      );
    case 'seed':
      await _seed(
        tokenSource: _required(args, 'token'),
        dir: _option(args, 'dir') ?? Directory.current.path,
      );
    default:
      stdout.writeln('Comando no reconocido. Ver el encabezado del archivo.');
  }
}

/// --- OpenSSL-compatible helpers (DER/SPKI) usados solo por la herramienta. ---

final AutoSeedBlockCtrRandom _random =
    AutoSeedBlockCtrRandom(AESEngine())
      ..seed(KeyParameter(Uint8List.fromList(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)))));

String _b64u(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _derLength(int length) {
  if (length < 0x80) {
    return Uint8List.fromList([length]);
  }
  final bytes = <int>[];
  var value = length;
  while (value > 0) {
    bytes.insert(0, value & 0xff);
    value >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

Uint8List _derTlv(int tag, List<int> content) =>
    Uint8List.fromList([tag, ..._derLength(content.length), ...content]);

Uint8List _derInteger(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  var bytes = List<int>.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  );
  if (bytes[0] & 0x80 != 0) bytes.insert(0, 0);
  return _derTlv(0x02, bytes);
}

String _spkiPem(RSAPublicKey publicKey) {
  const oidRsaEncryption = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];
  final algorithm = _derTlv(0x30, [
    ..._derTlv(0x06, oidRsaEncryption),
    ..._derTlv(0x05, const []),
  ]);
  final rsaKey = _derTlv(0x30, [
    ..._derInteger(publicKey.modulus!),
    ..._derInteger(publicKey.publicExponent!),
  ]);
  final bitString = _derTlv(0x03, [0, ...rsaKey]);
  final spki = _derTlv(0x30, [...algorithm, ...bitString]);

  final b64 = base64.encode(spki);
  final lines = <String>[
    '-----BEGIN PUBLIC KEY-----',
    ...b64.chunks(64),
    '-----END PUBLIC KEY-----',
  ];
  return lines.join('\n');
}

/// EMSA-PKCS1-v1_5 para SHA-256 (misma construcción que la app).
Uint8List _emEncodePkcs1v15Sha256(List<int> hash, int emLength) {
  const digestInfo = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03,
    0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  final trailer = Uint8List.fromList([...digestInfo, ...hash]);
  final em = Uint8List(emLength);
  em[0] = 0x00;
  em[1] = 0x01;
  for (var i = 2; i < emLength - trailer.length - 1; i++) {
    em[i] = 0xff;
  }
  em[emLength - trailer.length - 1] = 0x00;
  em.setRange(emLength - trailer.length, emLength, trailer);
  return em;
}

Uint8List _bigIntToBytes(BigInt value, {int? length}) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = Uint8List.fromList(List.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  ));
  if (length == null || bytes.length >= length) return bytes;
  final padded = Uint8List(length);
  padded.setRange(length - bytes.length, length, bytes);
  return padded;
}

BigInt _bytesToBigInt(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return BigInt.parse(hex, radix: 16);
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateKeyPair() {
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom<RSAKeyGeneratorParameters>(
      RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
      _random,
    ));
  return generator.generateKeyPair();
}

String _signToken(RSAPrivateKey privateKey, Map<String, dynamic> claims) {
  final header = {'alg': 'RS256', 'typ': 'JWT'};
  final h = _b64u(utf8.encode(jsonEncode(header)));
  final p = _b64u(utf8.encode(jsonEncode(claims)));
  final message = utf8.encode('$h.$p');

  final hash = SHA256Digest().process(Uint8List.fromList(message));
  final emLength = (privateKey.modulus!.bitLength + 7) ~/ 8;
  final em = _emEncodePkcs1v15Sha256(hash, emLength);

  final signature = _bytesToBigInt(em)
      .modPow(privateKey.privateExponent!, privateKey.modulus!);
  final sigBytes = _bigIntToBytes(signature, length: emLength);
  return '$h.$p.${_b64u(sigBytes)}';
}

Future<String> _machineHwid() async {
  try {
    final result = await Process.run('reg', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
    ]);
    if (result.exitCode == 0) {
      final out = result.stdout?.toString() ?? '';
      final match =
          RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F\-]{36})').firstMatch(out);
      if (match != null) return match.group(1)!;
    }
  } catch (_) {}
  return 'test-hwid-0000-0000-0000-000000000000';
}

DateTime _parseExpiry(String raw) {
  if (raw.startsWith('+')) {
    final days = int.tryParse(raw.substring(1));
    if (days != null) {
      return DateTime.now().toUtc().add(Duration(days: days));
    }
  }
  final intValue = int.tryParse(raw);
  if (intValue != null) {
    return DateTime.fromMillisecondsSinceEpoch(intValue * 1000, isUtc: true);
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) return parsed.toUtc();
  throw ArgumentError('--exp debe ser unix, ISO-8601 o +días');
}

Future<void> _keygen(String outDir) async {
  final dir = Directory(outDir);
  await dir.create(recursive: true);

  final pair = _generateKeyPair();
  final priv = pair.privateKey;
  final pem = _spkiPem(pair.publicKey);

  final json = jsonEncode({
    'modulus': priv.modulus!.toRadixString(16),
    'privateExponent': priv.privateExponent!.toRadixString(16),
    'p': priv.p!.toRadixString(16),
    'q': priv.q!.toRadixString(16),
  });
  await File('${dir.path}${Platform.pathSeparator}private.json')
      .writeAsString('$json\n', flush: true);
  await File('${dir.path}${Platform.pathSeparator}public.pem')
      .writeAsString('$pem\n', flush: true);

  stdout.writeln('Generado en: ${dir.path}');
  stdout.writeln('(private.json NO debe distribuirse ni versionarse)');
  stdout.writeln();
  stdout.writeln('Clave pública para OlyraConfig.publicKeyPem:');
  stdout.writeln(pem);
}

RSAPrivateKey _loadPrivate(String path) {
  final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  BigInt hex(String key) => BigInt.parse(map[key] as String, radix: 16);
  final priv = RSAPrivateKey(
    hex('modulus'),
    hex('privateExponent'),
    hex('p'),
    hex('q'),
  );
  return priv;
}

/// Lector minimalista de TLV ASN.1 DER para el bloque PKCS#8 del proveedor.
class _DerCursor {
  _DerCursor(this._data);
  final List<int> _data;
  int _pos = 0;
  bool get isEnd => _pos >= _data.length;

  (int tag, List<int> content) read() {
    final tag = _data[_pos++];
    var length = _data[_pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _data[_pos++];
      }
    }
    final content = _data.sublist(_pos, _pos + length);
    _pos += length;
    return (tag, content);
  }
}

/// Importa una clave privada PKCS#8 PEM (la firmware real de olyra.cl),
/// extrae módulo/exponentes y deja `private.json` + `public.pem` en `outDir`,
/// imprimiendo la clave pública para pegar en `OlyraConfig.publicKeyPem`.
///
/// La clave privada NO se versiona: guardarla fuera del repositorio.
Future<void> _importPrivateKey({
  required String pemPath,
  required String outDir,
}) async {
  final dir = Directory(outDir);
  await dir.create(recursive: true);

  final pem = File(pemPath).readAsStringSync().trim();
  final b64 = pem
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  final der = base64.decode(b64);

  final privateKeyInfo = _DerCursor(der);
  final (pkiTag, pkiContent) = privateKeyInfo.read();
  if (pkiTag != 0x30) throw FormatException('PKCS#8: falta SEQUENCE raíz');
  final pki = _DerCursor(pkiContent);
  pki.read(); // INTEGER version.
  pki.read(); // AlgorithmIdentifier (rsaEncryption + NULL).
  final (octetTag, octetContent) = pki.read();
  if (octetTag != 0x04) throw FormatException('PKCS#8: falta OCTET STRING');
  if (!pki.isEnd) throw FormatException('PKCS#8: datos sobrantes');

  final rsa = _DerCursor(octetContent);
  final (rsaTag, rsaContent) = rsa.read();
  if (rsaTag != 0x30) throw FormatException('RSAPrivateKey: falta SEQUENCE');
  final fields = _DerCursor(rsaContent);
  fields.read(); // INTEGER version.
  final modulus = _bytesToBigInt(fields.read().$2);
  final exponent = _bytesToBigInt(fields.read().$2);
  final privateExponent = _bytesToBigInt(fields.read().$2);
  final p = _bytesToBigInt(fields.read().$2);
  final q = _bytesToBigInt(fields.read().$2);

  final json = jsonEncode({
    'modulus': modulus.toRadixString(16),
    'privateExponent': privateExponent.toRadixString(16),
    'p': p.toRadixString(16),
    'q': q.toRadixString(16),
  });
  await File('${dir.path}${Platform.pathSeparator}private.json')
      .writeAsString('$json\n', flush: true);

  final publicPem = _spkiPem(RSAPublicKey(modulus, exponent));
  await File('${dir.path}${Platform.pathSeparator}public.pem')
      .writeAsString('$publicPem\n', flush: true);

  stdout.writeln('Importada en: ${dir.path}');
  stdout.writeln('(private.json NO debe distribuirse ni versionarse)');
  stdout.writeln();
  stdout.writeln('Clave pública para OlyraConfig.publicKeyPem:');
  stdout.writeln(publicPem);
}

Future<void> _sign({
  required String privPath,
  required String hwid,
  required String expires,
  String? subject,
}) async {
  final privateKey = _loadPrivate(privPath);
  final claims = <String, dynamic>{
    'sub': subject ?? 'bodegaflow',
    'hwid': hwid,
    'iat': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    'exp': _parseExpiry(expires).millisecondsSinceEpoch ~/ 1000,
    'app': 'bodegaflow-pos',
  };
  stdout.writeln('Token RS256 (para LICENSE_FILE_TEST o pegar en license.dat):');
  stdout.writeln(_signToken(privateKey, claims));
}

Future<void> _verify({
  required String token,
  required String pemPath,
  String? hwid,
}) async {
  final publicKey = RsaJwtVerifier.parsePublicKeyPem(
    File(pemPath).readAsStringSync().trim(),
  );
  final claims = RsaJwtVerifier.verify(
    token: token,
    publicKey: publicKey,
    expectedHwid: hwid,
  );
  if (claims == null) {
    stdout.writeln('Token INVÁLIDO.');
    exitCode = 1;
    return;
  }
  stdout.writeln('Token VÁLIDO.');
  stdout.writeln('  hwid = ${claims.hwid}');
  stdout.writeln('  exp  = ${claims.expiresAt?.toLocal()}');
  stdout.writeln('  sub  = ${claims.subject}');
}

/// Escribe un token JWT ya firmado en `license.dat` del directorio indicado,
/// cifrado con el HWID real de esta máquina (igual que haría la app al
/// activarse). Útil para desarrollo y demos locales.
Future<void> _seed({
  required String tokenSource,
  required String dir,
}) async {
  final raw = File(tokenSource).existsSync()
      ? (await File(tokenSource).readAsString()).trim()
      : tokenSource.trim();
  if (raw.isEmpty) throw ArgumentError('--token vacío (¿ruta o JWT inline?)');

  final hwid = await _machineHwid();
  final store = LicenseFileStore(Directory(dir), hardwareId: hwid);
  await store.write(raw);
  stdout.writeln('license.dat creado en: $dir');
  stdout.writeln('  hwid   = $hwid');
  stdout.writeln('  token  = ${raw.substring(0, min(24, raw.length))}…');
  stdout.writeln('  archivo solo leíble en este equipo (AES-256-GCM + HWID).');
}

Future<void> _selfcheck() async {
  var failures = 0;
  void check(String label, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label${detail.isEmpty ? '' : '  ($detail)'}');
    if (!ok) failures++;
  }

  final hwid = await _machineHwid();
  stdout.writeln('HWID del equipo: $hwid');
  stdout.writeln();

  final pair = _generateKeyPair();
  final publicKey = pair.publicKey;
  final privateKey = pair.privateKey;
  final pem = _spkiPem(publicKey);

  check('keygen → parse SPKI PEM', () {
    final parsed = RsaJwtVerifier.parsePublicKeyPem(pem);
    return parsed.modulus == publicKey.modulus &&
        parsed.publicExponent == publicKey.publicExponent;
  }());

  final now = DateTime.now().toUtc();
  final token = _signToken(privateKey, {
    'sub': 'bodegaflow',
    'hwid': hwid,
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000,
    'app': 'bodegaflow-pos',
  });

  final valid = RsaJwtVerifier.verify(
    token: token,
    publicKey: publicKey,
    expectedHwid: hwid,
  );
  check('verify token válido', valid != null);

  final wrongHwid = RsaJwtVerifier.verify(
    token: token,
    publicKey: publicKey,
    expectedHwid: 'otro-hwid',
  );
  check('hwid distinto → rechaza', wrongHwid == null);

  final badSig =
      '${token.substring(0, token.length - 4)}AAAA';
  final sigTampered = RsaJwtVerifier.verify(
    token: badSig,
    publicKey: publicKey,
    expectedHwid: hwid,
  );
  check('firma alterada → rechaza', sigTampered == null);

  final expiredToken = _signToken(privateKey, {
    'hwid': hwid,
    'iat': 1,
    'exp': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
  });
  final expired = RsaJwtVerifier.verify(
    token: expiredToken,
    publicKey: publicKey,
    expectedHwid: hwid,
  );
  check('expirado → rechaza', expired == null);

  final temp = await Directory.systemTemp
      .createTemp('bodegaflow_license_selfcheck');
  try {
    final store = LicenseFileStore(temp, hardwareId: hwid);
    check('license.dat sin archivo → null', await store.read() == null);

    await store.write(token);
    final reread = await store.read();
    check('license.dat roundtrip', reread == token);

    final raw = await File(
      '${temp.path}${Platform.pathSeparator}license.dat',
    ).readAsBytes();
    raw[20] = raw[20] ^ 0xff;
    await File('${temp.path}${Platform.pathSeparator}license.dat')
        .writeAsBytes(raw);
    var tampered = false;
    try {
      await store.read();
    } catch (_) {
      tampered = true;
    }
    check('license.dat alterado → error', tampered);

    await store.write(token); // restaurar un archivo válido.
    final otherStore = LicenseFileStore(temp, hardwareId: 'otra-maquina');
    var wrongMachine = false;
    try {
      await otherStore.read();
    } catch (_) {
      wrongMachine = true;
    }
    check('otro HWID no puede leer (clave distinta)', wrongMachine);
  } finally {
    await temp.delete(recursive: true);
  }

  stdout.writeln();
  if (failures == 0) {
    stdout.writeln('SELFCHECK OK (${pair.publicKey.modulus!.bitLength}-bits RSA).');
  } else {
    stdout.writeln('SELFCHECK: $failures fallo(s).');
    exitCode = 1;
  }
}

String? _option(List<String> args, String name) {
  final idx = args.indexOf('--$name');
  if (idx < 0 || idx + 1 >= args.length) return null;
  return args[idx + 1];
}

String _required(List<String> args, String name) {
  final value = _option(args, name);
  if (value == null) {
    throw ArgumentError('Falta --$name');
  }
  return value;
}

extension on String {
  List<String> chunks(int size) {
    final result = <String>[];
    for (var i = 0; i < length; i += size) {
      result.add(substring(i, i + size > length ? length : i + size));
    }
    return result;
  }
}