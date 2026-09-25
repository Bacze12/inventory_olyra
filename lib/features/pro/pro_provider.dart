import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'billing.dart';

/// Controla el derecho de uso de BodegaFlow (Free vs PRO).
///
/// La app es 100% offline, así que la licencia vive en la tabla `settings`: si
/// el usuario compró y restauró su compra en este o en otro dispositivo, la
/// marca queda persistida y `esPro` sigue en `true` aunque la tienda no esté
/// disponible.
class ProProvider extends ChangeNotifier {
  ProProvider({
    required ProductRepository productRepository,
    required SettingsRepository settingsRepository,
    required this.billing,
  })  : _products = productRepository,
        _settings = settingsRepository;

  final ProductRepository _products;
  final SettingsRepository _settings;

  /// Tienda desde la que se compran y restauran las licencias PRO.
  final BillingGateway billing;

  bool _esPro = false;

  /// `true` cuando el usuario tiene la licencia PRO activa.
  bool get esPro => _esPro;

  int _productCount = 0;

  /// Productos registrados en el inventario local.
  int get productCount => _productCount;

  /// Cupos que le quedan en la versión gratuita, o `null` si es PRO (en PRO los
  /// productos son ilimitados y el contador no aplica).
  int? get remainingFreeSlots {
    if (_esPro) return null;
    final left = AppConstants.freeProductLimit - _productCount;
    return left < 0 ? 0 : left;
  }

  List<SubscriptionOffer> _offers = const [];
  List<SubscriptionOffer> get offers => _offers;

  bool _loadingOffers = false;
  bool get loadingOffers => _loadingOffers;

  ProNotice _notice = ProNotice.none;
  ProNotice get notice => _notice;

  bool _busy = false;

  /// `true` mientras se procesa una compra o restauración: la UI bloquea los
  /// botones para no abrir dos flujos de pago a la vez.
  bool get busy => _busy;

  /// Carga la licencia persistida y el tamaño actual del catálogo.
  Future<void> init() async {
    try {
      _esPro = await _settings.get(AppConstants.settingPro) ==
          AppConstants.proEnabled;
    } catch (_) {
      _esPro = false;
    }
    await refreshProductCount();
  }

  /// Vuelve a contar el catálogo local.
  ///
  /// Si la base no se puede leer se asume un catálogo vacío: el guardado del
  /// producto fallaría igual con su propio mensaje, y así un cliente PRO nunca
  /// queda bloqueado por un problema de la base.
  Future<int> refreshProductCount() async {
    try {
      _productCount = await _products.count();
    } catch (_) {
      _productCount = 0;
    }
    notifyListeners();
    return _productCount;
  }

  /// Decide si se puede registrar un producto nuevo.
  ///
  /// Se ejecuta ANTES de guardar: si la versión gratuita ya tiene
  /// [AppConstants.freeProductLimit] productos y no hay licencia PRO, el
  /// registro se frena para que la UI abra el paywall.
  Future<bool> canRegisterProduct() async {
    await refreshProductCount();
    return _esPro || _productCount < AppConstants.freeProductLimit;
  }

  /// Abre el flujo de pago de Google Play para la suscripción PRO.
  ///
  /// Devuelve `true` solo si la tienda confirmó la compra.
  Future<bool> purchasePro() async {
    if (_busy) return _esPro;
    _busy = true;
    _notice = ProNotice.none;
    notifyListeners();
    try {
      final offers = await _ensureOffers();
      if (offers.isEmpty) {
        _notice = ProNotice.priceUnavailable;
        return false;
      }

      final result = await billing.purchase(offers.first.productId);
      if (result.isPro) {
        await _grantPro();
        return true;
      }
      _notice = _noticeFor(result);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Busca en Google Play una compra previa de la suscripción y la reactiva.
  Future<bool> restorePurchases() async {
    if (_busy) return _esPro;
    _busy = true;
    _notice = ProNotice.none;
    notifyListeners();
    try {
      final result = await billing.restorePurchases();
      if (result.isPro) {
        await _grantPro();
        return true;
      }
      _notice = _noticeFor(result);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Consulta el precio de la suscripción en Google Play.
  ///
  /// Se invoca al abrir el paywall: pedirlo en cada arranque costaría una
  /// llamada de red innecesaria para un usuario que no quiere comprar.
  Future<List<SubscriptionOffer>> loadOffers() => _ensureOffers();

  /// Consulta el precio en la tienda una sola vez y lo cachea.
  Future<List<SubscriptionOffer>> _ensureOffers() async {
    if (_offers.isNotEmpty) return _offers;
    _loadingOffers = true;
    notifyListeners();
    try {
      _offers = await billing.loadOffers();
    } catch (_) {
      _offers = const [];
    } finally {
      _loadingOffers = false;
      notifyListeners();
    }
    return _offers;
  }

  /// Persiste la licencia para que sobreviva al próximo arranque.
  Future<void> _grantPro() async {
    _esPro = true;
    _notice = ProNotice.purchased;
    try {
      await _settings.set(AppConstants.settingPro, AppConstants.proEnabled);
    } catch (_) {
      // Sin persistencia la licencia vive solo en memoria: el usuario mantiene
      // PRO en esta sesión y puede restaurarla desde la tienda.
    }
  }

  ProNotice _noticeFor(ProPurchaseResult result) {
    switch (result.status) {
      case ProPurchaseStatus.purchased:
        return ProNotice.purchased;
      case ProPurchaseStatus.pending:
        return ProNotice.pending;
      case ProPurchaseStatus.notFound:
        return ProNotice.nothingToRestore;
      case ProPurchaseStatus.failed:
        return ProNotice.purchaseFailed;
    }
  }
}
