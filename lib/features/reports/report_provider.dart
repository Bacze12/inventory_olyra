import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:pdf/pdf.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'pdf_report_service.dart';

class ReportProvider extends ChangeNotifier {
  ReportProvider({
    required ProductRepository productRepository,
    required SettingsRepository settingsRepository,
  })  : _products = productRepository,
        _settings = settingsRepository;

  final ProductRepository _products;
  final SettingsRepository _settings;

  bool _generating = false;
  bool get generating => _generating;

  String _storeName = AppConstants.defaultStoreName;
  String get storeName => _storeName;

  String? _error;
  String? get error => _error;

  List<Product> _snapshot = const [];
  List<Product> get snapshot => _snapshot;

  int get lowStockCount =>
      _snapshot.where((product) => product.isLowStock).length;

  int get totalUnits =>
      _snapshot.fold(0, (sum, product) => sum + product.quantity);

  Future<void> init() async {
    try {
      _storeName = await _settings.getOr(
        AppConstants.settingStoreName,
        AppConstants.defaultStoreName,
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setStoreName(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _storeName = trimmed;
    notifyListeners();
    try {
      await _settings.set(AppConstants.settingStoreName, trimmed);
    } catch (_) {}
  }

  Future<List<Product>> loadProducts() async {
    _snapshot = await _products.all();
    notifyListeners();
    return _snapshot;
  }

  Future<Uint8List> buildReport() async {
    _generating = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await _products.all();
      final service = const PdfReportService();
      return await service.build(
        PdfPageFormat.a4,
        _snapshot,
        storeName: _storeName,
      );
    } catch (_) {
      _error = 'No se pudo generar el reporte';
      rethrow;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  Future<Uint8List> buildForFormat(PdfPageFormat format) async {
    final service = const PdfReportService();
    return service.build(format, _snapshot, storeName: _storeName);
  }

  Future<String?> saveToDevice(Uint8List bytes) async {
    try {
      final documents = await path_provider.getApplicationDocumentsDirectory();
      final folder = Directory(p.join(documents.path, AppConstants.reportsFolderName));
      await folder.create(recursive: true);
      final file = File(
        p.join(folder.path, '${AppConstants.pdfFilePrefix}${fileStamp()}.pdf'),
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> reload() async {
    await loadProducts();
  }
}