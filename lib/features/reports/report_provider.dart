import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:pdf/pdf.dart';

import '../../core/constants/app_constants.dart';
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

  /// Nombre de archivo con marca de tiempo: Reporte_ScanFlow_yyyyMMdd_HHmmss.pdf
  String reportFileName({String extension = 'pdf'}) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'Reporte_ScanFlow_$stamp.$extension';
  }

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
      final base = await _baseDirectory();
      final folder = Directory(p.join(base.path, AppConstants.reportsFolderName));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, reportFileName()));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Carpeta de respaldo:
  /// - Android/iOS: almacenamiento externo propio de la app (sin permisos),
  ///   con respaldo en documentos si no está disponible.
  /// - Desktop: carpeta "Descargas" del usuario; si falla, documentos.
  Future<Directory> _baseDirectory() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final external = await path_provider.getExternalStorageDirectory();
        if (external != null) return external;
      } catch (_) {}
      return path_provider.getApplicationDocumentsDirectory();
    }
    try {
      final downloads = await path_provider.getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {}
    return path_provider.getApplicationDocumentsDirectory();
  }

  Future<void> reload() async {
    await loadProducts();
  }
}