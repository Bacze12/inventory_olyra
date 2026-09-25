import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing.dart';

/// Tiempo por defecto que se espera a que la tienda confirme la operación.
const Duration purchaseWaitTimeout = Duration(seconds: 45);

/// Espera la transacción de Google Play que habilita la licencia PRO.
///
/// Se suscribe al flujo de compras ANTES de abrir el flujo de pago, para no
/// perder una transacción que la tienda confirme de inmediato. Las
/// transacciones que no habilitan la licencia (pendientes, de otro producto o
/// inexistentes) no cierran la espera: el pago diferido se confirma más tarde
/// en la misma sesión.
class PurchaseWaiter {
  PurchaseWaiter(
    this._stream, {
    required this.productId,
    required this.onPurchased,
    this.timeout = purchaseWaitTimeout,
    this.onTimeout = const ProPurchaseResult.pending(),
  }) {
    _subscription = _stream.listen(_onPurchases);
  }

  final Stream<List<PurchaseDetails>> _stream;

  /// Producto que habilita la licencia; el resto se ignora.
  final String productId;

  /// Se invoca con las transacciones finales para que la app les avise a
  /// Google Play que la licencia ya fue entregada.
  final void Function(List<PurchaseDetails> purchases) onPurchased;

  final Duration timeout;

  /// Resultado a devolver si la tienda no responde a tiempo.
  final ProPurchaseResult onTimeout;

  final Completer<ProPurchaseResult> _completer = Completer<ProPurchaseResult>();
  late final StreamSubscription<List<PurchaseDetails>> _subscription;

  void _onPurchases(List<PurchaseDetails> purchases) {
    if (_completer.isCompleted) return;
    final result = resultFromPurchases(purchases, productId: productId);
    if (result.status == ProPurchaseStatus.pending) return;
    if (result.status == ProPurchaseStatus.notFound) return;
    onPurchased(purchases);
    _completer.complete(result);
  }

  /// Resultado de la operación. Vence en [timeout] para no dejar el flujo de
  /// compras abierto indefinidamente.
  Future<ProPurchaseResult> result() =>
      _completer.future.timeout(timeout, onTimeout: () => onTimeout);

  /// Cierra la escucha. Siempre hay que llamar, incluso si la operación terminó
  /// o se abortó, para no dejar una suscripción colgando.
  Future<void> cancel() => _subscription.cancel();
}

/// Resume el lote de transacciones de Google Play en un único resultado.
///
/// Google Play entrega las compras de todos los productos juntos, así que sólo
/// las transacciones de [productId] habilitan la licencia.
ProPurchaseResult resultFromPurchases(
  List<PurchaseDetails> purchases, {
  required String productId,
}) {
  for (final purchase in purchases) {
    if (purchase.productID != productId) continue;
    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        return const ProPurchaseResult.purchased();
      case PurchaseStatus.pending:
        return const ProPurchaseResult.pending();
      case PurchaseStatus.canceled:
        return const ProPurchaseResult.notFound();
      case PurchaseStatus.error:
        return ProPurchaseResult.failed(
          purchase.error?.message ?? 'Error desconocido de Google Play',
        );
    }
  }
  return const ProPurchaseResult.notFound();
}
