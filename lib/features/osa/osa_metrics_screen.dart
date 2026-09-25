import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';

/// Módulo de métricas OSA (disponibilidad en anaquel).
///
/// Es una de las funciones que el paywall vende como exclusivas de PRO, así que
/// el acceso lo controla `ProGate` desde el menú de inicio: sin licencia el
/// usuario nunca llega a abrir esta pantalla, ve el paywall en su lugar.
///
/// El cálculo de los indicadores se habilita en una entrega posterior
/// (#20); aquí queda la pantalla y el contrato que van a necesitar las
/// métricas.
class OsaMetricsScreen extends StatelessWidget {
  const OsaMetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    String tr(String key) => AppStrings.translate(languageCode, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(AppStrings.osaTitle)),
        actions: const [_ProBadge()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(AppStrings.osaSubtitle),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insights_outlined, size: 72, color: scheme.outline),
                const SizedBox(height: 16),
                Text(
                  tr(AppStrings.osaPendingTitle),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(AppStrings.osaPendingBody),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Distintivo de función exclusiva de PRO.
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    final label = AppStrings.translate(languageCode, AppStrings.proBadge);

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
