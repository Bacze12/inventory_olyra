import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/app_constants.dart';
import 'billing.dart';
import 'purchase_waiter.dart';

/// Traduce la ficha que devuelve Google Play a una [SubscriptionOffer].
SubscriptionOffer offerFromProductDetails(ProductDetails details) =>
    SubscriptionOffer(
      productId: details.id,
      title: details.title,
      description: details.description,
      price: details.price,
    );

/// Implementación de [BillingGateway] sobre el paquete oficial
/// `in_app_purchase`.
///
/// BodegaFlow es 100% offline y no tiene servidor de licencias, así que la
/// verificación de la compra se apoya en lo que entrega el propio Google Play
/// Billing: una transacción en estado `purchased` o `restored` para
/// [AppConstants.proProductId] significa que Google ya cobró y que la
/// suscripción está vigente.
class InAppPurchaseGateway implements BillingGateway {
  InAppPurchaseGateway({this.client});

  /// Cliente inyectable; en `null` se usa [InAppPurchase.instance].
  ///
  /// Queda injectable para que las pruebas puedan ejercitar el adaptador sin
  /// pasar por los canales de plataforma.
  final InAppPurchase? client;

  /// Se resuelve en el primer uso (y no en el constructor) para no registrar
  /// la plataforma de facturación al construir el provider en tests.
  InAppPurchase get _iap => client ?? InAppPurchase.instance;

  @override
  Future<List<SubscriptionOffer>> loadOffers() async {
    final details = await _queryProduct(AppConstants.proProductId);
    return details.map(offerFromProductDetails).toList();
  }

  @override
  Future<ProPurchaseResult> purchase(String productId) async {
    final details = await _queryProduct(productId);
    if (details.isEmpty) return const ProPurchaseResult.notFound();

    final iap = _iap;
    // Se espera ANTES de abrir el flujo de pago para no perder una
    // transacción que la tienda confirme de inmediato.
    final waiter = _waiter(iap, productId);
    try {
      final started = await iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details.first),
      );
      if (!started) {
        return ProPurchaseResult.failed(
          'Google Play no pudo abrir el flujo de pago',
        );
      }
      return await waiter.result();
    } finally {
      await waiter.cancel();
    }
  }

  @override
  Future<ProPurchaseResult> restorePurchases() async {
    final iap = _iap;
    // Sin compra previa la tienda no emite nada: se agota la espera y se
    // informa que no hay licencia que restaurar.
    final waiter = _waiter(
      iap,
      AppConstants.proProductId,
      onTimeout: const ProPurchaseResult.notFound(),
    );
    try {
      await iap.restorePurchases();
      return await waiter.result();
    } finally {
      await waiter.cancel();
    }
  }

  PurchaseWaiter _waiter(
    InAppPurchase iap,
    String productId, {
    ProPurchaseResult onTimeout = const ProPurchaseResult.pending(),
  }) =>
      PurchaseWaiter(
        iap.purchaseStream,
        productId: productId,
        onTimeout: onTimeout,
        onPurchased: (purchases) => _acknowledge(iap, purchases, productId),
      );

  /// Ficha de la suscripción en Google Play, o lista vacía si la tienda no la
  /// tiene publicada.
  Future<List<ProductDetails>> _queryProduct(String productId) async {
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.error != null) return const [];
      return response.productDetails
          .where((details) => details.id == productId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Le dice a Google Play que la licencia ya fue entregada, para que no la
  /// vuelva a entregar en el próximo arranque.
  void _acknowledge(
    InAppPurchase iap,
    List<PurchaseDetails> purchases,
    String productId,
  ) {
    for (final detail in purchases) {
      if (detail.productID != productId) continue;
      if (!detail.pendingCompletePurchase) continue;
      iap.completePurchase(detail);
    }
  }
}
