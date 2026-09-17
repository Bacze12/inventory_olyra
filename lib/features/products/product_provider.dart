import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../activation/olyra_license_controller.dart';

class ProductProvider extends ChangeNotifier {
  /// [license] opcional: si se inyecta (nivel superior del árbol), [save] lee
  /// el `user_app_id` de sus claims sin usar Provider frente a un árbol que
  /// todavía no lo provee.
  ProductProvider(this._repository, [this._license]);

  final ProductRepository _repository;
  final OlyraLicenseController? _license;

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
      // Asigna la cuenta actual (user_app_id) al producto antes de persistir,
      // alineando el catálogo local con `pos_products` de la nube. En
      // instalaciones sin licencia activa la resuelve a null y la fila queda
      // sin asignar (columna nullable).
      final scoped = draft.copyWith(userAppId: _currentUserAppId());
      if (scoped.id == null) {
        await _repository.insert(scoped);
      } else {
        await _repository.update(scoped);
      }
      await load();
      return null;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return 'Ya existe un producto con ese código de barras';
      }
      return 'No se pudo guardar el producto: $e';
    } catch (e) {
      return 'No se pudo guardar el producto: $e';
    }
  }

  /// UUID de la `user_apps` (bodega) del claim/acuerdo de licencia. Usa
  /// [OlyraLicenseController.userAppId] para NO confundir el `user_app_id`
  /// con el `app_id` global del producto.
  String? _currentUserAppId() {
    final value = _license?.userAppId;
    return (value == null || value.isEmpty) ? null : value;
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