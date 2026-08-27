import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  // URL raw de GitHub con el archivo version.json.
  // Debe contener: { "version": "1.0.1", "link": "https://.../app.apk" }
  static const String versionUrl =
      'https://raw.githubusercontent.com/Bacze12/inventory_olyra/main/version.json';

  /// Comprueba si hay una versión más reciente y, de existir, muestra el
  /// diálogo para descargarla e instalarla. Devuelve true si la mostró.
  static Future<bool> checkAndApplyUpdate(BuildContext context) async {
    // La instalación OTA sólo aplica a Android.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode != 200) return false;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final latest = _stringValue(data, const ['version']);
      // El campo del enlace puede llamarse distinto según el version.json.
      final link = _stringValue(
        data,
        const ['link', 'url', 'download_url', 'apk_url'],
      );
      if (latest == null || link == null) {
        debugPrint('version.json inválido: faltan version y/o link');
        return false;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version;

      if (!_isNewerVersion(current, latest)) return false;
      if (!context.mounted) return false;

      _showUpdateDialog(context, link, latest);
      return true;
    } catch (e) {
      debugPrint('Error comprobando actualizaciones: $e');
      return false;
    }
  }

  static String? _stringValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final raw = json[key];
      if (raw != null) {
        final value = raw.toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Compara versiones numéricas (ej. "1.0.0+3" vs "1.0.10"),
  /// tolerando sufijos "v" y build numbers.
  static bool _isNewerVersion(String current, String latest) {
    final cur = _parseVersion(current);
    final lat = _parseVersion(latest);
    final length = cur.length > lat.length ? cur.length : lat.length;
    for (var i = 0; i < length; i++) {
      final a = i < cur.length ? cur[i] : 0;
      final b = i < lat.length ? lat[i] : 0;
      if (a != b) return b > a;
    }
    return false;
  }

  static List<int> _parseVersion(String value) {
    final core =
        value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    return core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  }

  static void _showUpdateDialog(
    BuildContext context,
    String apkUrl,
    String version,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Actualización v$version disponible'),
        content: const Text(
          'Hay una nueva versión de ScanFlow. ¿Deseas descargarla e instalarla ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _downloadAndInstallApk(apkUrl);
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  static void _downloadAndInstallApk(String url) {
    try {
      OtaUpdate()
          .execute(url, destinationFilename: 'scanflow_update.apk')
          .listen((OtaEvent event) {
        debugPrint(
          'Progreso de descarga: ${event.status} - ${event.value}%',
        );
      });
    } catch (e) {
      debugPrint('Error en la descarga OTA: $e');
    }
  }
}