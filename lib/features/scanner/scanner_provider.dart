import 'package:flutter/foundation.dart';

import '../../core/audio/sound_feedback.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';
import '../../data/repositories/movement_repository.dart';
import '../../data/repositories/product_repository.dart';

enum ScanOperation { entrada, salida }

enum ScanResult { idle, ok, lowStock, notFound, blocked, error }

class ScannerProvider extends ChangeNotifier {
  ScannerProvider({
    required ProductRepository productRepository,
    required MovementRepository movementRepository,
  })  : _products = productRepository,
        _movements = movementRepository;

  final ProductRepository _products;
  final MovementRepository _movements;

  ScanOperation _operation = ScanOperation.entrada;
  ScanOperation get operation => _operation;

  Product? _lastProduct;
  Product? get lastProduct => _lastProduct;

  ScanResult _lastResult = ScanResult.idle;
  ScanResult get lastResult => _lastResult;

  String _lastBarcode = '';
  String get lastBarcode => _lastBarcode;

  int _lastApplied = 0;
  int get lastApplied => _lastApplied;

  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get lastScan => _lastScan;

  bool _processing = false;
  bool get processing => _processing;

  String? _pendingCode;
  int _pendingCount = 0;

  String? _lastAppliedCode;
  DateTime _lastAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);

  void setOperation(ScanOperation value) {
    if (_operation == value) return;
    _operation = value;
    notifyListeners();
  }

  void clearResult() {
    _lastResult = ScanResult.idle;
    _lastProduct = null;
    _lastApplied = 0;
    _lastBarcode = '';
    _pendingCode = null;
    _pendingCount = 0;
    notifyListeners();
  }

  Future<void> handleScannedCodes(List<String> codes) async {
    if (codes.isEmpty || _processing) return;
    final code = codes.first.trim();
    if (code.isEmpty) return;

    // Identidad canónica del código: evita que frames con el mismo GTIN en
    // distinta forma (UPC vs EAN, check digit) se cuenten como distintos.
    final key = canonicalBarcode(code);
    final now = DateTime.now();

    // Nueva sesión de lectura: si la cámara dejó de ver cualquier código
    // durante el gap, el próximo código (aunque sea el mismo GTIN de otra caja)
    // se considera "nuevo" y puede contarse de inmediato.
    final freshSession =
        now.difference(_lastDetectionAt) > AppConstants.presenceGap;
    _lastDetectionAt = now;
    if (freshSession) {
      _lastAppliedCode = null;
      _lastAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    // Silencio total justo después de un conteo: evita que al sostener el
    // producto la cámara (que sigue detectando el mismo código) lo sume otra vez.
    if (now.difference(_lastAppliedAt) < AppConstants.applyLockout) {
      _pendingCode = null;
      _pendingCount = 0;
      return;
    }

    // Mientras el último código siga enfrente sin pausa, no se recuenta.
    if (!freshSession && key == _lastAppliedCode) return;

    // Confirmación de estabilidad: un código nuevo sólo se procesa si aparece
    // varias veces de forma seguida. Un frame aislado (código "fantasma" al
    // mover la cámara) no genera un conteo.
    if (key == _pendingCode) {
      _pendingCount += 1;
      if (_pendingCount < AppConstants.stableDetections) return;

      _pendingCode = null;
      _pendingCount = 0;
      _lastScan = now;
      _processing = true;
      notifyListeners();
      try {
        await _apply(code);
      } finally {
        _processing = false;
        notifyListeners();
      }
    } else {
      _pendingCode = key;
      _pendingCount = 1;
    }
  }

  Future<void> _apply(String barcode) async {
    _lastBarcode = barcode;

    Product? product;
    try {
      product = await _products.byBarcode(barcode);
    } catch (_) {
      _lastResult = ScanResult.error;
      _lastProduct = null;
      await SoundFeedback.error();
      return;
    }

    if (product == null) {
      _lastResult = ScanResult.notFound;
      _lastProduct = null;
      await SoundFeedback.error();
      return;
    }

    final delta = _operation == ScanOperation.entrada ? 1 : -1;
    try {
      final updated = await _movements.adjustStock(product.id!, delta);
      final applied = updated.quantity - product.quantity;

      _lastProduct = updated;
      _lastApplied = applied;

      if (applied == 0) {
        _lastResult = ScanResult.blocked;
        await SoundFeedback.error();
      } else {
        _lastAppliedCode = canonicalBarcode(barcode);
        _lastAppliedAt = DateTime.now();
        if (updated.isLowStock) {
          _lastResult = ScanResult.lowStock;
          await SoundFeedback.lowStock();
        } else {
          _lastResult = ScanResult.ok;
          if (delta > 0) {
            await SoundFeedback.success();
          } else {
            await SoundFeedback.operation();
          }
        }
      }
    } catch (_) {
      _lastResult = ScanResult.error;
      _lastProduct = null;
      await SoundFeedback.error();
    }
  }
}