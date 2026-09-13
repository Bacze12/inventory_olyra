import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'olyra_license_controller.dart';

/// Abre el diálogo "Acerca de / Licencia" con el detalle del JWT local:
/// estado, vencimiento, días restantes e identificador de hardware.
Future<void> showLicenseAboutDialog(BuildContext context) async {
  final license = context.read<OlyraLicenseController>();
  final package = await PackageInfo.fromPlatform();

  if (!context.mounted) return;

  final expiresAt = license.claims?.expiresAt;
  final scheme = Theme.of(context).colorScheme;
  final diff = expiresAt?.difference(DateTime.now());

  String stateText = 'Activa';
  if (diff == null) {
    stateText = 'Verificando…';
  } else if (diff.isNegative) {
    stateText = 'Vencida';
  } else if (diff.inHours < 24 * 7) {
    stateText = 'Por vencer';
  }

  String formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String? daysText;
  if (diff != null) {
    if (diff.isNegative) {
      daysText = 'Vencida';
    } else if (diff.inHours < 24) {
      daysText = 'Vence hoy';
    } else {
      daysText = 'Quedan ${diff.inDays} día${diff.inDays == 1 ? '' : 's'}';
    }
  }

  final rows = <(String, String)>[
    ('Versión', '${package.version} (${package.buildNumber})'),
    ('Estado', stateText),
    if (expiresAt != null) ('Válida hasta', formatDate(expiresAt)),
    if (daysText != null) ('Días restantes', daysText),
    if (license.claims?.subject != null)
      ('Suscriptor', license.claims!.subject!),
    ('Hardware ID', license.hardwareId ?? '—'),
  ];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.verified_user_outlined, size: 40),
      title: const Text('Acerca de · Licencia'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}