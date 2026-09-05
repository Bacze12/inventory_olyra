import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/sale.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../views/pos/cart_item.dart';

/// Rangos de filtro rápido del historial de ventas.
enum SalesRange {
  hoy('Hoy'),
  semana('Esta semana'),
  mes('Este mes'),
  todo('Todo');

  const SalesRange(this.label);

  final String label;

  /// Inicio del rango (inclusive); `null` para "Todo".
  DateTime? get start {
    final now = DateTime.now();
    switch (this) {
      case SalesRange.hoy:
        return DateTime(now.year, now.month, now.day);
      case SalesRange.semana:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case SalesRange.mes:
        return DateTime(now.year, now.month, 1);
      case SalesRange.todo:
        return null;
    }
  }
}

class SalesProvider extends ChangeNotifier {
  SalesProvider({
    required this.salesRepository,
    required this.movementRepository,
  });

  final SalesRepository salesRepository;
  final MovementRepository movementRepository;

  List<Sale> _sales = const [];
  bool _loading = false;
  String? _error;
  SalesRange _range = SalesRange.hoy;
  String _query = '';
  Timer? _debounce;

  List<Sale> get sales => _sales;
  bool get loading => _loading;
  String? get error => _error;
  SalesRange get range => _range;
  String get query => _query;

  double get totalAmount =>
      _sales.where((s) => s.status == SaleStatus.completada).fold(
            0.0,
            (sum, sale) => sum + sale.total,
          );

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sales = await salesRepository.getSalesHistory(
        from: _range.start,
        query: _query.trim().isEmpty ? null : _query,
      );
    } catch (_) {
      _error = 'No se pudieron cargar las ventas';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setRange(SalesRange value) {
    if (_range == value) return;
    _range = value;
    load();
  }

  void setQuery(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }

  void clearQuery() {
    _query = '';
    _debounce?.cancel();
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Persiste la venta cobrada (sin reducir stock: eso ya lo hizo el POS).
  /// Devuelve el id de la venta o `null` si falla.
  Future<int?> registrarVenta({
    required List<CartItem> items,
    required PaymentMethod method,
    required double subtotal,
    required double taxRate,
    required double tax,
    required double total,
    double? received,
    required double change,
    int? shiftId,
  }) async {
    try {
      final saleItems = [
        for (final item in items)
          SaleItem(
            productId: item.product.id,
            productName: item.product.name,
            barcode: item.product.barcode,
            unitPrice: item.product.price,
            quantity: item.quantity,
            subtotal: item.subtotal,
          ),
      ];
      return await salesRepository.insertSale(
        items: saleItems,
        method: method,
        subtotal: subtotal,
        taxRate: taxRate,
        tax: tax,
        total: total,
        received: received,
        change: change,
        shiftId: shiftId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Anula la venta: devuelve el stock de cada línea al inventario
  /// (movimientos de entrada) y marca la venta como Anulada.
  Future<String?> anularVenta(Sale sale) async {
    final id = sale.id;
    if (id == null || !sale.canBeAnnulled) return 'La venta no se puede anular';
    try {
      final full = await salesRepository.byId(id);
      for (final item in full.items) {
        final productId = item.productId;
        if (productId == null) continue;
        await movementRepository.adjustStock(productId, item.quantity);
      }
      await salesRepository.setStatus(id, SaleStatus.anulada);
      await load();
      return null;
    } catch (_) {
      return 'No se pudo anular la venta';
    }
  }
}