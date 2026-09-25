import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'paywall_screen.dart';
import 'pro_provider.dart';

/// Aplica las reglas de uso Freemium antes de una acción restringida.
class ProGate {
  ProGate._();

  /// Decide si se puede registrar un producto nuevo y, cuando la versión
  /// gratuita ya agotó sus cupos, frena el guardado y abre el paywall.
  ///
  /// Devuelve `true` cuando el alta puede continuar. Cuando el paywall se abrió
  /// y el usuario terminó con licencia PRO, también devuelve `true` para que
  /// el formulario siga con el guardado que había interrumpido.
  static Future<bool> allowNewProduct(BuildContext context) async {
    final pro = context.read<ProProvider>();
    if (await pro.canRegisterProduct()) return true;
    if (!context.mounted) return false;
    return showPaywall(context, trigger: PaywallTrigger.productLimit);
  }

  /// Deja entrar al módulo de métricas OSA solo con licencia PRO.
  ///
  /// Es una función rotulada como exclusiva en la tabla del paywall, así que la
  /// versión gratuita no puede ni verla: si intenta abrirla aparece el paywall.
  static Future<bool> allowOsaMetrics(BuildContext context) {
    return _allowFeature(context, PaywallTrigger.osa);
  }

  /// Deja exportar el reporte en PDF solo con licencia PRO.
  ///
  /// La generación del documento es la parte cara del módulo de reportes (armar
  /// el PDF completo), así que la comprobación va justo antes de generarlo.
  static Future<bool> allowPdfExport(BuildContext context) {
    return _allowFeature(context, PaywallTrigger.pdfExport);
  }

  /// Guarda común de las funciones exclusivas de PRO: sin licencia abre el
  /// paywall y devuelve `true` solo si el usuario terminó suscribiéndose.
  static Future<bool> _allowFeature(
    BuildContext context,
    PaywallTrigger trigger,
  ) async {
    if (context.read<ProProvider>().esPro) return true;
    if (!context.mounted) return false;
    return showPaywall(context, trigger: trigger);
  }
}
