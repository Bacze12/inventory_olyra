import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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

  final String version;
  final String? buildNumber;
  final String downloadUrl;
  final String? releaseNotes;
  final bool mandatory;
  final String? fileName;
}

/// Resultado de una comprobación manual de actualizaciones, para que la UI
/// pueda dar feedback según el caso.
enum UpdateCheckResult { notAvailable, updateAvailable, failed }

/// Sistema de actualización automática para Windows (instalador `.exe`).
///
/// * **Chequeo único**: se invoca una sola vez al arrancar la app (tras el
///   primer frame con licencia activa); no existen timers ni polling.
/// * **Silencioso**: errores de red/parseo quedan atrapados en try/catch y
///   debugPrint; la app nunca se bloquea por el comprobador.
/// * **Cooldown 24 h**: solo se muestra el diálogo de actualización una vez
///   cada [kPromptCooldown]. La marca temporal se almacena en
///   `SharedPreferences` y se escribe **antes** de presentar el modal para
///   que, si la app se cierra durante la descarga, no vuelva a preguntar.
class WindowsUpdateService {
  WindowsUpdateService._();

  static const String kManifestUrl =
      'https://olyra.cl/api/v1/app/version?slug=bodegaflow';

  /// Timeout corto: máximo 5 segundos para no ralentizar el arranque.
  static const Duration kTimeout = Duration(seconds: 5);

  static const String kLastPromptKey = 'last_update_prompt_timestamp';
  static const Duration kPromptCooldown = Duration(hours: 24);

  // ------------------------------------------------------------------
  // 1. Consulta al servidor
  // ------------------------------------------------------------------

  /// GET al manifest. Devuelve `null` ante cualquier error de red o formato.
  static Future<UpdateManifest?> fetchManifest() async {
    try {
      final res = await http.get(Uri.parse(kManifestUrl)).timeout(kTimeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final version =
          (map['version'] ?? map['latest'] ?? '').toString().trim();
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

  // ------------------------------------------------------------------
  // 2. Comparación SemVer
  // ------------------------------------------------------------------

  /// `true` si la versión remota es más nueva que la instalada.
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
    return [
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  // ------------------------------------------------------------------
  // 3. Punto de entrada único (llamado al arrancar la app)
  // ------------------------------------------------------------------

  /// Comprueba el manifest una sola vez y, si corresponde y pasó el cooldown
  /// de 24 h, muestra el diálogo de actualización.
  ///
  /// Si la petición falla, el usuario está offline o el parseo da inválido,
  /// el error queda silenciado y la app continúa sin interrupciones.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool force = false,
  }) async {
    await _performCheck(context, force: force);
  }

  /// Comprobación manual desde la UI: ignora el cooldown de 24 h
  /// ([kLastPromptKey]) y devuelve [UpdateCheckResult] para que la interfaz
  /// muestre "última versión", abra el modal o avise de falla de conexión.
  static Future<UpdateCheckResult> forceCheckForUpdates(
    BuildContext context,
  ) =>
      _performCheck(context, force: true);

  static Future<UpdateCheckResult> _performCheck(
    BuildContext context, {
    required bool force,
  }) async {
    if (kIsWeb || !Platform.isWindows) return UpdateCheckResult.failed;
    try {
      final manifest = await fetchManifest();
      if (manifest == null) return UpdateCheckResult.failed;

      final info = await PackageInfo.fromPlatform();
      if (!isNewer(manifest, info.version, info.buildNumber)) {
        return UpdateCheckResult.notAvailable;
      }

      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(kLastPromptKey);
        final last = raw == null ? null : DateTime.tryParse(raw);
        if (last != null &&
            DateTime.now().difference(last).abs() < kPromptCooldown) {
          return UpdateCheckResult.notAvailable;
        }
      }

      if (!context.mounted) return UpdateCheckResult.failed;

      // Se persiste la marca ANTES de mostrar el diálogo: si la app se cierra
      // durante la descarga, no volverá a preguntar dentro de 24 h.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLastPromptKey, DateTime.now().toIso8601String());

      if (!context.mounted) return UpdateCheckResult.failed;

      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateAvailableDialog(
          manifest: manifest,
          installedVersion: info.version,
        ),
      );

      if (go != true || !context.mounted) return UpdateCheckResult.updateAvailable;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WindowsDownloadDialog(manifest: manifest),
      );
      return UpdateCheckResult.updateAvailable;
    } catch (error) {
      debugPrint('UPDATE_CHECK_ERROR: $error');
      return UpdateCheckResult.failed;
    }
  }
}

// ------------------------------------------------------------------
// Diálogo de "Actualización disponible"
// ------------------------------------------------------------------

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
      title: Text('Nueva actualización disponible (v${manifest.version})'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una versión nueva disponible. '
              'Instalada: v$installedVersion.',
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
                child: SingleChildScrollView(child: Text(notes)),
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

// ------------------------------------------------------------------
// Diálogo de descarga con progreso → instalador silencioso → exit(0)
// ------------------------------------------------------------------

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
    final process = await Process.start(
      installerPath,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES'],
      mode: ProcessStartMode.detachedWithStdio,
      workingDirectory: Directory.systemTemp.path,
    );
    debugPrint('UPDATE_INSTALLER_PID=${process.pid}');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _finished = true);
    exit(0);
  }

  void _close() => Navigator.of(context).pop();

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
          child: Text(
            _failed || _finished ? 'Cerrar' : 'Cancelar',
          ),
        ),
      ],
    );
  }
}
