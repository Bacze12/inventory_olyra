import '../../data/models/product.dart';

/// Un producto dentro de la venta activa (carrito en memoria).
class CartItem {
  const CartItem({required this.product, this.quantity = 1});

  final Product product;
  final int quantity;

  /// Total de línea: precio unitario × cantidad.
  double get subtotal => product.price * quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, quantity: quantity ?? this.quantity);
}