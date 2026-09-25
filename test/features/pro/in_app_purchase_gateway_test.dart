import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/features/pro/billing.dart';
import 'package:scanflow/features/pro/in_app_purchase_gateway.dart';
import 'package:scanflow/features/pro/purchase_waiter.dart';

ProductDetails _details({
  String id = AppConstants.proProductId,
  String title = 'BodegaFlow PRO',
  String description = 'Suscripción mensual',
  String price = 'CLP 2.990',
}) => ProductDetails(
  id: id,
  title: title,
  description: description,
  price: price,
  rawPrice: 2990,
  currencyCode: 'CLP',
);

PurchaseDetails _purchase({
  String productID = AppConstants.proProductId,
  PurchaseStatus status = PurchaseStatus.purchased,
  IAPError? error,
}) => PurchaseDetails(
  purchaseID: 'order-1',
  productID: productID,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'token',
    serverVerificationData: 'token',
    source: 'GooglePlay',
  ),
  transactionDate: '1700000000000',
  status: status,
)..error = error;

void main() {
  late StreamController<List<PurchaseDetails>> controller;
  late List<List<PurchaseDetails>> acknowledged;

  PurchaseWaiter buildWaiter({
    Duration timeout = const Duration(milliseconds: 200),
    ProPurchaseResult onTimeout = const ProPurchaseResult.pending(),
  }) => PurchaseWaiter(
    controller.stream,
    productId: AppConstants.proProductId,
    onPurchased: acknowledged.add,
    timeout: timeout,
    onTimeout: onTimeout,
  );

  setUp(() {
    // Broadcast para que `close` no quede esperando a un listener que algunos
    // tests cancelan explícitamente.
    controller = StreamController<List<PurchaseDetails>>.broadcast();
    acknowledged = [];
  });

  tearDown(() {
    controller.close();
  });

  test('offerFromProductDetails traduce el precio de Google Play', () {
    final offer = offerFromProductDetails(_details());

    expect(offer.productId, AppConstants.proProductId);
    expect(offer.title, 'BodegaFlow PRO');
    expect(offer.price, 'CLP 2.990');
  });

  test('resultFromPurchases: una compra pagada habilita PRO', () {
    final result = resultFromPurchases([
      _purchase(),
    ], productId: AppConstants.proProductId);

    expect(result.status, ProPurchaseStatus.purchased);
    expect(result.isPro, isTrue);
  });

  test('resultFromPurchases: una compra restaurada también habilita PRO', () {
    final result = resultFromPurchases([
      _purchase(status: PurchaseStatus.restored),
    ], productId: AppConstants.proProductId);

    expect(result.isPro, isTrue);
  });

  test('resultFromPurchases: una compra de otro producto no habilita PRO', () {
    final result = resultFromPurchases([
      _purchase(productID: 'otra_suscripcion'),
    ], productId: AppConstants.proProductId);

    expect(result.status, ProPurchaseStatus.notFound);
    expect(result.isPro, isFalse);
  });

  test('resultFromPurchases: una compra pendiente no habilita PRO', () {
    final result = resultFromPurchases([
      _purchase(status: PurchaseStatus.pending),
    ], productId: AppConstants.proProductId);

    expect(result.status, ProPurchaseStatus.pending);
    expect(result.isPro, isFalse);
  });

  test('resultFromPurchases: propaga el error de la tienda', () {
    final result = resultFromPurchases([
      _purchase(
        status: PurchaseStatus.error,
        error: IAPError(
          source: 'GooglePlay',
          code: 'item_already_owned',
          message: 'Ya tenías esta compra',
        ),
      ),
    ], productId: AppConstants.proProductId);

    expect(result.status, ProPurchaseStatus.failed);
    expect(result.message, 'Ya tenías esta compra');
  });

  test('resultFromPurchases: sin transacciones devuelve notFound', () {
    final result = resultFromPurchases(
      const [],
      productId: AppConstants.proProductId,
    );

    expect(result.status, ProPurchaseStatus.notFound);
  });

  test('la suscripción consultada en Play es la de BodegaFlow', () {
    expect(AppConstants.proProductId, 'bodegaflow_pro_monthly');
  });

  test('resolve purchased cuando Google Play confirma el pago', () async {
    final waiter = buildWaiter();
    addTearDown(waiter.cancel);

    controller.add([_purchase()]);

    expect(
      await waiter.result().then((r) => r.status),
      ProPurchaseStatus.purchased,
    );
  });

  test('una compra pendiente sigue esperando hasta la confirmación', () async {
    final waiter = buildWaiter();
    addTearDown(waiter.cancel);

    controller.add([_purchase(status: PurchaseStatus.pending)]);
    await Future<void>.delayed(Duration.zero);

    expect(
      acknowledged,
      isEmpty,
      reason: 'no se entrega la licencia antes de que Google Play confirme',
    );

    controller.add([_purchase()]);

    expect(
      await waiter.result().then((r) => r.status),
      ProPurchaseStatus.purchased,
    );
  });

  test('ignora las compras de otros productos', () async {
    final waiter = buildWaiter();
    addTearDown(waiter.cancel);

    controller.add([_purchase(productID: 'otra_suscripcion')]);
    await Future<void>.delayed(Duration.zero);

    expect(acknowledged, isEmpty);

    controller.add([_purchase()]);

    expect(
      await waiter.result().then((r) => r.status),
      ProPurchaseStatus.purchased,
    );
  });

  test('propaga el error de la tienda sin esperar al vencimiento', () async {
    final waiter = buildWaiter();
    addTearDown(waiter.cancel);

    controller.add([
      _purchase(
        status: PurchaseStatus.error,
        error: IAPError(
          source: 'GooglePlay',
          code: 'purchase_error',
          message: 'tarjeta rechazada',
        ),
      ),
    ]);

    final result = await waiter.result();
    expect(result.status, ProPurchaseStatus.failed);
    expect(result.message, 'tarjeta rechazada');
  });

  test('entrega las transacciones finales para acusar recibo', () async {
    final waiter = buildWaiter();
    addTearDown(waiter.cancel);

    final paid = _purchase();
    controller.add([paid]);

    await waiter.result();
    expect(acknowledged, hasLength(1));
    expect(acknowledged.single, [paid]);
  });

  test('vence y devuelve el resultado de vencimiento configurado', () async {
    final waiter = buildWaiter(
      timeout: const Duration(milliseconds: 30),
      onTimeout: const ProPurchaseResult.notFound(),
    );
    addTearDown(waiter.cancel);

    final result = await waiter.result();

    expect(result.status, ProPurchaseStatus.notFound);
  });

  test('cancelar cierra la escucha del flujo de compras', () async {
    final waiter = buildWaiter();
    final cancelled = waiter.cancel();

    expect(controller.hasListener, isFalse);
    await cancelled;
  });

  test('cancelar detiene una espera que seguía pendiente', () async {
    final waiter = buildWaiter(timeout: const Duration(minutes: 5));
    await waiter.cancel();

    controller.add([_purchase()]);
    await Future<void>.delayed(Duration.zero);

    expect(acknowledged, isEmpty);
  });
}
