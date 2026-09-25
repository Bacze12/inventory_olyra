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
}
