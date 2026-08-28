import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/repositories/settings_repository.dart';

class UpdateService {
  UpdateService._();

  static const String kVersionUrl =
      'https://raw.githubusercontent.com/Bacze12/inventory_olyra/main/version.json';

  /// Clave usada para no repetir el aviso de actualización.
  static const String kLastPromptKey = 'last_update_prompt_at';

  /// Periodo de silencio tras mostrar (o rechazar) el aviso.
  static const Duration kPromptCooldown = Duration(hours: 24);

  /// Comprueba si hay una versión más reciente y, si la hay, ofrece actualizar.
  ///
  /// [force] = true omite el cooldown y muestra el aviso siempre que haya
  /// actualización disponible.
  static Future<void> checkForUpdates(
    BuildContext context,
    SettingsRepository settings, {
    bool force = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final remote = await _fetchVersionJson();
      if (remote == null) return;

      final latest = remote['version']?.trim() ?? '';
      final url = remote['apk_url'] ??
          remote['link'] ??
          remote['url'] ??
          remote['download_url'];
      if (latest.isEmpty || url == null || url.trim().isEmpty) return;
      if (!_isNewerVersion(latest, info.version)) return;

      if (!force) {
        final lastPrompt = await settings.get(kLastPromptKey);
        final last = lastPrompt == null ? null : DateTime.tryParse(lastPrompt);
        if (last != null &&
            DateTime.now().difference(last) < kPromptCooldown) {
          return;
        }
      }
      if (!context.mounted) return;

      final update = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Actualización disponible'),
          content: Text(
            'Está disponible la versión $latest (instalada: ${info.version}). '
            '¿Desea descargarla e instalarla ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );

      // No repetir el aviso en las próximas 24 horas, se acepte o no.
      await settings.set(kLastPromptKey, DateTime.now().toIso8601String());

      if (update != true) return;
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDownloadDialog(url: url),
      );
    } catch (e) {
      debugPrint('UPDATE_CHECK_ERROR: $e');
    }
  }

  static Future<Map<String, String>?> _fetchVersionJson() async {
    try {
      final res = await http
          .get(Uri.parse(kVersionUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body);
      if (map is! Map) return null;
      final Map<String, String> out = {};
      for (final entry in map.entries) {
        out[entry.key.toString()] = entry.value?.toString() ?? '';
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Compara versiones numéricas por partes. Tolera prefijos "v" y sufijos
  /// como "+1" o "-beta".
  static bool _isNewerVersion(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    if (l == null || c == null) return false;
    for (var i = 0; i < 3; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }
    return false;
  }

  static List<int>? _parseVersion(String raw) {
    final m = RegExp(
      r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final p1 = int.tryParse(m.group(1) ?? '') ?? 0;
    final p2 = int.tryParse(m.group(2) ?? '') ?? 0;
    final p3 = int.tryParse(m.group(3) ?? '') ?? 0;
    return [p1, p2, p3];
  }
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.url});

  final String url;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  StreamSubscription<OtaEvent>? _sub;
  bool _finished = false;
  int? _percent;
  String _message = 'Preparando la descarga…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final stream = OtaUpdate().execute(
        widget.url,
        androidProviderAuthority:
            '${info.packageName}.ota_update_provider',
        destinationFilename: 'scanflow_update.apk',
      );
      _sub = stream.listen(_onEvent, onError: (Object error) {
        _fail('No se pudo iniciar la descarga: $error');
      });
    } catch (e) {
      _fail('No se pudo iniciar la descarga: $e');
    }
  }

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        setState(() {
          _message = 'Descargando…';
          _percent = int.tryParse(event.value ?? '');
        });
        break;
      case OtaStatus.INSTALLING:
        setState(() {
          _finished = true;
          _message = 'Instalación iniciada.\n'
              'El instalador de Android se abrirá a continuación.';
        });
        break;
      case OtaStatus.INSTALLATION_DONE:
        setState(() {
          _finished = true;
          _message = 'La aplicación se actualizó correctamente.';
        });
        break;
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Permiso de instalación no concedido.\n'
            'Active "Instalar aplicaciones desconocidas" para ScanFlow '
            'en los ajustes del dispositivo e inténtelo de nuevo.');
        break;
      case OtaStatus.DOWNLOAD_ERROR:
      case OtaStatus.INTERNAL_ERROR:
      case OtaStatus.CHECKSUM_ERROR:
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _fail(event.value ?? 'Ocurrió un problema durante la actualización.');
        break;
      default:
        break;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _finished = true;
      _message = message;
    });
  }

  void _close() {
    if (!_finished) {
      _sub?.cancel();
      OtaUpdate().cancel();
    }
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
          Text(_message),
          if (!_finished) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _percent == null ? null : (_percent ?? 0) / 100,
            ),
            if (_percent != null) ...[
              const SizedBox(height: 4),
              Text('$_percent%'),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text(_finished ? 'Cerrar' : 'Cancelar'),
        ),
      ],
    );
  }
}