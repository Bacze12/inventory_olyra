import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'license_about_dialog.dart';
import 'olyra_license_controller.dart';

/// Indicador visual de vencimiento de la licencia offline (JWT `exp`).
///
/// - Restan 7+ días: chip discreto "Licencia válida hasta DD/MM/AAAA".
/// - Faltan menos de 7 días: aviso ámbar sugiriendo renovar en olyra.cl.
/// - Vencida: aviso en rojo.
/// - Estado no activo: no muestra nada.
class LicenseStatusBanner extends StatelessWidget {
  const LicenseStatusBanner({super.key});

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<OlyraLicenseController>();
    if (license.state != OlyraLicenseState.active) {
      return const SizedBox.shrink();
    }
    final expiresAt = license.claims?.expiresAt;
    if (expiresAt == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final diff = expiresAt.difference(DateTime.now());

    final int daysRemaining;
    if (diff.isNegative) {
      daysRemaining = -1;
    } else if (diff.inHours < 24) {
      daysRemaining = 0;
    } else {
      daysRemaining = diff.inDays;
    }

    final dateText = _formatDate(expiresAt);

    String message;
    String subMessage;
    Color background;
    Color foreground;
    IconData icon;

    if (daysRemaining < 0) {
      message = 'Licencia vencida ($dateText)';
      subMessage = 'Renueva tu licencia en olyra.cl para seguir usando la app.';
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
      icon = Icons.block;
    } else if (daysRemaining < 7) {
      message = daysRemaining == 0
          ? 'Tu licencia vence HOY'
          : 'Tu licencia vence en $daysRemaining día${daysRemaining == 1 ? '' : 's'}';
      subMessage = 'Válida hasta $dateText · Renueva en olyra.cl';
      background = const Color(0xFFFFF3CD);
      foreground = const Color(0xFF6E5011);
      icon = Icons.warning_amber_rounded;
    } else {
      message = 'Licencia válida hasta $dateText';
      subMessage = 'Tap para ver el detalle de tu licencia';
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      icon = Icons.verified_user_outlined;
    }

    final bright = daysRemaining >= 0 && daysRemaining < 7;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showLicenseAboutDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subMessage,
                        style: TextStyle(color: foreground, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (bright)
                  const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}