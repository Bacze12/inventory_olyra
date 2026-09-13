import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../data/repositories/settings_repository.dart';
import 'update_service.dart' show UpdateService;

/// Metadatos de una versión publicada en el manifest de olyra.cl.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.downloadUrl,
    this.buildNumber,
    this.releaseNotes,
    this.mandatory = false,
    this.fileName,
  });

  /// Versión remota (SemVer: major.minor.patch, p. ej. "1.5.0").
  final String version;

  /// Build remota (entero como string, opcional; desempata SemVer iguales).
  final String? buildNumber;

  /// URL pública del instalador `.exe`.
  final String downloadUrl;

  /// Notas de la versión mostradas en el diálogo.
  final String? releaseNotes;

  /// Si es obligatoria, no se ofrece "Recordar más tarde".
  final bool mandatory;

  /// Nombre sugerido para el archivo temporal (default: scanflow_update.exe).
  final String? fileName;
}

/// Sistema de actualización automática para Windows (instalador `.exe`).
///
/// 1. Consulta `https://www.olyra.cl/api/v1/app/version`.
/// 2. Compara SemVer contra la versión instalada ([package_info_plus]).
/// 3. Si hay una versión más nueva, ofrece descargar; descarga en
///    `Directory.systemTemp` con barra de progreso.
/// 4. Ejecuta el instalador silencioso (Inno Setup) y cierra la app
///    (`exit(0)`) para liberar los binarios y permitir la sobrescritura.
class WindowsUpdateService {
  WindowsUpdateService._();

  static const String kManifestUrl = 'https://www.olyra.cl/api/v1/app/version';
  static const Duration kTimeout = Duration(seconds: 15);

  /// Clave de cooldown compartida con [UpdateService].
  static const String kLastPromptKey = UpdateService.kLastPromptKey;
  static const Duration kPromptCooldown = UpdateService.kPromptCooldown;

  /// Consulta y parsea el manifest de versión. Devuelve `null` ante cualquier
  /// error de red/formato (la app arranca igual, sin bloquearse).
  static Future<UpdateManifest?> fetchManifest() async {
    try {
      final res = await http.get(Uri.parse(kManifestUrl)).timeout(kTimeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final version = (map['version'] ?? map['latest'] ?? '')
          .toString()
          .trim();
      final url = (map['download_url'] ??
              map['url'] ??
              map['download'] ??
              map['file_url'] ??
              '')
          .toString()
          .trim();
      if (version.isEmpty || url.isEmpty) return null;

      final mandatoryValue = map['mandatory'] ?? map['force'] ?? false;

      return UpdateManifest(
        version: version,
        buildNumber:
            (map['build_number'] ?? map['build'] ?? '').toString().trim(),
        downloadUrl: url,
        releaseNotes: (map['release_notes'] ??
                map['notes'] ??
                map['changelog'] ??
                '')
            .toString()
            .trim(),
        mandatory: mandatoryValue is bool && mandatoryValue,
        fileName: (map['file_name'] ?? '').toString().trim(),
      );
    } catch (error) {
      debugPrint('UPDATE_MANIFEST_ERROR: $error');
      return null;
    }
  }

  /// `true` si la versión remota es más nueva que la instalada.
  ///
  /// Compara SemVer por partes (major.minor.patch) y, en empate, la build
  /// numérica cuando ambas existan.
  static bool isNewer(
    UpdateManifest remote,
    String installedVersion,
    String installedBuild,
  ) {
    final r = _parseVersion(remote.version);
    final c = _parseVersion(installedVersion);
    if (r == null || c == null) return false;
    for (var i = 0; i < 3; i++) {
      if (r[i] != c[i]) return r[i] > c[i];
    }
    final remoteBuild = int.tryParse(remote.buildNumber ?? '');
    final localBuild = int.tryParse(installedBuild);
    if (remoteBuild != null && localBuild != null) {
      return remoteBuild > localBuild;
    }
    return false;
  }

  static List<int>? _parseVersion(String raw) {
    final match = RegExp(
      r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final p1 = int.tryParse(match.group(1) ?? '') ?? 0;
    final p2 = int.tryParse(match.group(2) ?? '') ?? 0;
    final p3 = int.tryParse(match.group(3) ?? '') ?? 0;
    return [p1, p2, p3];
  }

  /// Unico punto de entrada: comprueba el manifest y, si corresponde, muestra
  /// el diálogo de actualización. [force] omite el cooldown de 24 h.
  static Future<void> checkAndPrompt(
    BuildContext context,
    SettingsRepository settings, {
    bool force = false,
  }) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final manifest = await fetchManifest();
      if (manifest == null) return;

      final info = await PackageInfo.fromPlatform();
      if (!isNewer(manifest, info.version, info.buildNumber)) return;

      if (!force) {
        final lastPrompt = await settings.get(kLastPromptKey);
        final last =
            lastPrompt == null ? null : DateTime.tryParse(lastPrompt);
        if (last != null &&
            DateTime.now().difference(last) < kPromptCooldown) {
          return;
        }
      }
      if (!context.mounted) return;

      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _UpdateAvailableDialog(
          manifest: manifest,
          installedVersion: info.version,
        ),
      );

      // Cooldown: no volver a preguntar en 24 h (acepte o rechace).
      await settings.set(kLastPromptKey, DateTime.now().toIso8601String());

      if (go != true) return;
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WindowsDownloadDialog(manifest: manifest),
      );
    } catch (error) {
      debugPrint('UPDATE_CHECK_ERROR: $error');
    }
  }
}

/// Diálogo de "Actualización disponible" con notas de versión y acciones.
class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({
    required this.manifest,
    required this.installedVersion,
  });

  final UpdateManifest manifest;
  final String installedVersion;

  @override
  Widget build(BuildContext context) {
    final notes = manifest.releaseNotes;
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt, size: 40),
      title: const Text('Actualización disponible'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una versión nueva (${manifest.version}). '
              'Instalada: $installedVersion.',
            ),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Novedades:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(notes),
                ),
              ),
            ],
            if (manifest.mandatory) ...[
              const SizedBox(height: 12),
              const Text(
                'Esta actualización es obligatoria: la app se cerrará al '
                'instalar la nueva versión.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!manifest.mandatory)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Recordar más tarde'),
          ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Actualizar ahora'),
        ),
      ],
    );
  }
}

/// Diálogo de descarga con barra de progreso; al terminar ejecuta el
/// instalador y cierra la aplicación.
class _WindowsDownloadDialog extends StatefulWidget {
  const _WindowsDownloadDialog({required this.manifest});

  final UpdateManifest manifest;

  @override
  State<_WindowsDownloadDialog> createState() =>
      _WindowsDownloadDialogState();
}

class _WindowsDownloadDialogState extends State<_WindowsDownloadDialog> {
  double? _progress; // 0..1 · null = indeterminado
  String _status = 'Descargando actualización…';
  bool _finished = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _progress = null;
      _status = 'Descargando actualización…';
      _failed = false;
      _finished = false;
    });
    try {
      final path = await _download();
      if (!mounted) return;
      await _launchInstaller(path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _finished = true;
        _status = 'No se pudo completar la actualización:\n$error';
      });
    }
  }

  Future<String> _download() async {
    final manifest = widget.manifest;
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(manifest.downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          'El servidor respondió HTTP ${response.statusCode}',
        );
      }

      final total = response.contentLength ?? 0;
      var fileName = manifest.fileName?.trim() ?? '';
      if (fileName.isEmpty ||
          p.basename(fileName) != fileName ||
          !fileName.toLowerCase().endsWith('.exe')) {
        fileName = 'scanflow_update.exe';
      }
      final target = File(p.join(Directory.systemTemp.path, fileName));
      final sink = target.openWrite();

      var received = 0;
      var lastUpdateAt = DateTime.now();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          final now = DateTime.now();
          // Actualizar la UI a lo sumo cada 120 ms para no saturar el árbol.
          if (total > 0 &&
              now.difference(lastUpdateAt).inMilliseconds >= 120) {
            lastUpdateAt = now;
            if (mounted) {
              setState(() => _progress = received / total);
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (mounted) {
        setState(() {
          _progress = total > 0 ? 1 : null;
          _status = 'Descarga completada. Iniciando instalador…';
        });
      }
      return target.path;
    } finally {
      client.close();
    }
  }

  Future<void> _launchInstaller(String installerPath) async {
    try {
      final process = await Process.start(
        installerPath,
        const ['/VERYSILENT', '/SUPPRESSMSGBOXES'],
        mode: ProcessStartMode.detachedWithStdio,
        workingDirectory: Directory.systemTemp.path,
      );
      debugPrint('UPDATE_INSTALLER_PID=${process.pid}');

      // Espera mínima para que el instalador tome el control y luego cierra
      // la app: así el .exe actual queda libre y el instalador puede
      // sobrescribirlo sin bloqueo de archivo.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _finished = true);
      exit(0);
    } catch (error) {
      throw Exception('No se pudo ejecutar el instalador: $error');
    }
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualizando ScanFlow'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          if (_progress != null) ...[
            const SizedBox(height: 4),
            Text('${(_progress! * 100).round()}%'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _failed || _finished ? _close : null,
          child: Text(_failed ? 'Cerrar' : (_progress == 1 ? 'Cerrar' : 'Cancelar')),
        ),
      ],
    );
  }
}