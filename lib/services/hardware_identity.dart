import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Identidad de hardware estable para licenciamiento.
///
/// Estrategia (fuente única de verdad): el valor elegido se persiste en
/// `flutter_secure_storage` y siempre se reutiliza.
///   1. Si ya existe un valor guardado → se usa tal cual (nunca cambia entre
///      reinicios ni llamadas).
///   2. Primera vez en Windows → `MachineGuid` de
///      `HKLM\SOFTWARE\Microsoft\Cryptography` (identificador de la máquina,
///      estable entre perfiles y actualizaciones) y se persiste.
///   3. Fallback (otras plataformas o lectura fallida) → UUID v4 generado una
///      sola vez y persistentes.
///
/// Lo crítico para el licenciamiento: el misma equipo DEBE reportar el mismo
/// identificador en cada activación; si "reg query" falla ocasionalmente ya no
/// se genera otra identidad, porque el valor guardado gana.
class HardwareIdentity {
  HardwareIdentity(this._storage);

  static const String fallbackKey = 'device_hardware_id';

  final FlutterSecureStorage _storage;

  String? _cached;

  Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _storage.read(key: fallbackKey);
    if (stored != null && stored.isNotEmpty) return _cached = stored;

    final windowsGuid = await _windowsMachineGuid();
    if (windowsGuid != null) {
      await _storage.write(key: fallbackKey, value: windowsGuid);
      return _cached = windowsGuid;
    }

    final generated = _uuidV4();
    await _storage.write(key: fallbackKey, value: generated);
    return _cached = generated;
  }

  Future<String?> _windowsMachineGuid() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'reg',
        [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ],
      );
      if (result.exitCode != 0) return null;
      final out = result.stdout?.toString() ?? '';
      final match =
          RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F\-]{36})').firstMatch(out);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4.
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant.
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
        '-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}