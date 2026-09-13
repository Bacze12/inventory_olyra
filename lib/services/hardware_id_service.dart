import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Identidad de hardware estable para el licenciamiento.
///
/// Fuente única de verdad (sticky): el valor elegido se persiste en
/// `flutter_secure_storage` y siempre se reutiliza entre reinicios.
///
///   1. Ya hay un valor guardado → se usa tal cual (nunca cambia).
///   2. Primera vez en Windows → SHA-256 (lint) de un sello compuesto por
///      componentes de la máquina leídos vía WMI/CIM:
///        - UUID del sistema (Win32_ComputerSystemProduct) → placa/BIOS.
///        - ProcessorId (Win32_Processor, primera CPU).
///        - SerialNumber (Win32_BaseBoard).
///      El hash es inmutable: aunque una pieza cambie (o el serial del
///      motherboard venga vacío en OEMs), el sello persiste.
///   3. Sin los componentes básicos → `MachineGuid` de
///      `HKLM\SOFTWARE\Microsoft\Cryptography` (legacy, estable).
///   4. Fallback final → UUID v4 generado una sola vez y persistido.
class HardwareIdService {
  HardwareIdService(this._storage);

  /// Clave de persistencia en secure storage (compartida con el tag legado
  /// 'device_hardware_id' para no re-activar máquinas ya vinculadas).
  static const String storageKey = 'device_hardware_id';

  final FlutterSecureStorage _storage;

  String? _cached;

  Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _storage.read(key: storageKey);
    if (stored != null && stored.isNotEmpty) return _cached = stored;

    final componentsHash = await _windowsComponentsHash();
    if (componentsHash != null) {
      await _storage.write(key: storageKey, value: componentsHash);
      return _cached = componentsHash;
    }

    final machineGuid = await _windowsMachineGuid();
    if (machineGuid != null) {
      await _storage.write(key: storageKey, value: machineGuid);
      return _cached = machineGuid;
    }

    final generated = _uuidV4();
    await _storage.write(key: storageKey, value: generated);
    return _cached = generated;
  }

  /// Sella los componentes de la máquina (placa + CPU + serial) en un único
  /// hash SHA-256 (hex minúsculas). Devuelve `null` si no se pudieron leer.
  Future<String?> _windowsComponentsHash() async {
    if (!Platform.isWindows) return null;
    const script =
        "\$ErrorActionPreference='SilentlyContinue'; "
        "\$p=Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1; "
        "\$u=(Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID; "
        "\$b=(Get-CimInstance -ClassName Win32_BaseBoard).SerialNumber; "
        "\$pp=\$p.ProcessorId; "
        "\$seal=if(\$pp){\$u; \$pp; \$b}else{''}; "
        "Write-Output \$seal";
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        stdoutEncoding: Encoding.getByName('utf8') ?? utf8,
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) return null;
      final lines = (result.stdout?.toString() ?? '')
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      // Se exige, al menos, UUID de placa y ProcessorId de CPU.
      if (lines.length < 2) return null;

      return _sha256Hex(utf8.encode(lines.join('|')));
    } on Exception {
      return null;
    }
  }

  /// HWID legado: identificador único de máquina del registro de Windows.
  Future<String?> _windowsMachineGuid() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid'],
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

  static String _sha256Hex(List<int> input) {
    final digest = SHA256Digest();
    final out = Uint8List(32);
    digest.update(Uint8List.fromList(input), 0, input.length);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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