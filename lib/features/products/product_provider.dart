import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';

class ProductProvider extends ChangeNotifier {
  ProductProvider(this._repository);

  final ProductRepository _repository;

  List<Product> _products = const [];
  List<Product> get products => _products;

  bool _loading = false;
  bool get loading => _loading;

  String _query = '';
  String get query => _query;

  String? _error;
  String? get error => _error;

  int get lowStockCount =>
      _products.where((product) => product.isLowStock).length;

  int get totalUnits =>
      _products.fold(0, (sum, product) => sum + product.quantity);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _products = await _repository.all(
        query: _query.trim().isEmpty ? null : _query,
      );
    } catch (_) {
      _error = 'No se pudo cargar el inventario';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    _query = value;
    load();
  }

  Future<String?> save(Product draft) async {
    try {
      if (draft.id == null) {
        await _repository.insert(draft);
      } else {
        await _repository.update(draft);
      }
      await load();
      return null;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return 'Ya existe un producto con ese código de barras';
      }
      return 'No se pudo guardar el producto';
    } catch (_) {
      return 'No se pudo guardar el producto';
    }
  }

  Future<String?> delete(Product product) async {
    final id = product.id;
    if (id == null) return null;
    try {
      await _repository.delete(id);
      await load();
      return null;
    } catch (_) {
      return 'No se pudo eliminar el producto';
    }
  }
}