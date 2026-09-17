import 'package:flutter/foundation.dart';

import '../../data/models/product.dart';
import 'cart_item.dart';

/// Estado en memoria del carrito de la venta activa.
///
/// No persiste: al cobrar/limpiar, la venta se descarta o se descarga en
/// movimientos de stock vía [MovementRepository].
class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  double _taxRate = 0.0;

  /// Productos añadidos, en orden de agregado.
  List<CartItem> get items => List.unmodifiable(_items);

  /// Fracción de impuesto sobre el subtotal (0.0 = sin impuesto).
  double get taxRate => _taxRate;

  bool get isEmpty => _items.isEmpty;

  int get itemCount => _items.length;

  int get totalUnits => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  double get tax => subtotal * _taxRate;

  double get total => subtotal + tax;

  CartItem? itemFor(int? productId) {
    for (final item in _items) {
      if (item.product.id == productId) return item;
    }
    return null;
  }

  int _indexFor(int? productId) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].product.id == productId) return i;
    }
    return -1;
  }

  /// Agrega [quantity] unidades del producto (o +1 si no se especifica).
  void addProduct(Product product, {int quantity = 1}) {
    if (quantity <= 0) return;
    final index = _indexFor(product.id);
    if (index >= 0) {
      final current = _items[index];
      _items[index] = current.copyWith(
        quantity: current.quantity + quantity,
      );
    } else {
      _items.add(CartItem(product: product, quantity: quantity));
    }
    notifyListeners();
  }

  /// Suma una unidad usando el snapshot más reciente del catálogo para el
  /// precio. Si el ítem no existe, lo agrega.
  void increment(Product product) => addProduct(product);

  /// Resta una unidad. El mínimo es 1: para quitar el ítem se usa
  /// [removeProduct].
  void decrement(Product product) {
    final index = _indexFor(product.id);
    if (index < 0) return;
    final current = _items[index];
    if (current.quantity <= 1) return;
    _items[index] = current.copyWith(quantity: current.quantity - 1);
    notifyListeners();
  }

  /// Fija la cantidad exacta; <= 0 elimina el ítem.
  void setQuantity(Product product, int quantity) {
    final index = _indexFor(product.id);
    if (index < 0) return;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index] = _items[index].copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  void removeProduct(Product product) {
    final index = _indexFor(product.id);
    if (index < 0) return;
    _items.removeAt(index);
    notifyListeners();
  }

  void setTaxRate(double value) {
    final rate = value.clamp(0.0, 1.0);
    if (_taxRate == rate) return;
    _taxRate = rate;
    notifyListeners();
  }

  void clearCart() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}