import 'package:flutter/foundation.dart';

/// Oferta de suscripción tal como la publica la tienda.
@immutable
class SubscriptionOffer {
  const SubscriptionOffer({
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
  });

  /// ID del producto en la tienda.
  final String productId;

  /// Nombre visible en la ficha de Google Play.
  final String title;

  /// Descripción publicada por la tienda.
  final String description;

  /// Precio ya formateado con su moneda (`CLP 2.990`), listo para mostrar.
  final String price;
}

/// Cómo terminó un intento de compra o de restauración.
enum ProPurchaseStatus {
  /// La tienda confirmó el pago: la licencia queda activa.
  purchased,

  /// Google Play todavía no confirma el pago (pago diferido, saldo, etc.).
  pending,

  /// No hay ninguna transacción de la suscripción en la cuenta.
  notFound,

  /// La tienda rechazó la compra o falló la consulta.
  failed,
}

/// Resultado de un intento de compra o restauración de la licencia PRO.
@immutable
class ProPurchaseResult {
  const ProPurchaseResult._(this.status, [this.message]);

  const ProPurchaseResult.purchased() : this._(ProPurchaseStatus.purchased);

  const ProPurchaseResult.pending() : this._(ProPurchaseStatus.pending);

  const ProPurchaseResult.notFound() : this._(ProPurchaseStatus.notFound);

  const ProPurchaseResult.failed(String message)
      : this._(ProPurchaseStatus.failed, message);

  final ProPurchaseStatus status;

  /// Detalle de la tienda cuando [status] es [ProPurchaseStatus.failed].
  final String? message;

  /// `true` cuando la operación deja activa la licencia PRO.
  bool get isPro => status == ProPurchaseStatus.purchased;
}

/// Aviso de la última operación de compra o restauración, listo para que la
/// UI lo traduzca. Se mantiene como enum (y no como texto) para que los
/// mensajes del paywall salgan en el idioma activo.
enum ProNotice {
  /// Sin operaciones todavía.
  none,

  /// Compra confirmada por la tienda.
  purchased,

  /// El pago quedó pendiente de confirmación.
  pending,

  /// No se pudo obtener el precio del producto en la tienda.
  priceUnavailable,

  /// La tienda rechazó la compra.
  purchaseFailed,

  /// La cuenta de Google Play no tiene ninguna compra de la suscripción.
  nothingToRestore,
}

/// Contrato de la tienda para comprar y restaurar la licencia PRO.
///
/// Existe para que la lógica de restrictionFreemium se pueda probar sin tocar
/// los canales de plataforma de Google Play.
abstract class BillingGateway {
  /// Consulta las ofertas de la suscripción PRO publicadas en la tienda.
  Future<List<SubscriptionOffer>> loadOffers();

  /// Abre el flujo de pago oficial de Google Play para [productId].
  Future<ProPurchaseResult> purchase(String productId);

  /// Busca en la cuenta de Google Play una compra previa de la suscripción.
  Future<ProPurchaseResult> restorePurchases();
}
