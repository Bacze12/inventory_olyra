import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/core/constants/app_constants.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/reports/report_provider.dart';

void main() {
  late Directory tempDir;

  ReportProvider buildProvider() => ReportProvider(
        productRepository: ProductRepository(AppDatabase.instance),
        settingsRepository: SettingsRepository(AppDatabase.instance),
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_report_test_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final db = await AppDatabase.instance.database;
    await db.delete('products');
    await db.delete('settings');
  });

  test('pdfFileName incluye la fecha y hora en el nombre', () {
    final provider = buildProvider();
    final fileName = provider.pdfFileName();

    expect(fileName.startsWith(AppConstants.pdfFilePrefix), isTrue);
    expect(fileName.endsWith('.pdf'), isTrue);
    expect(
      fileName,
      matches(
        RegExp(r'^inventario_\d{8}_\d{6}\.pdf$'),
      ),
    );
  });

  test('pdfFileName incluye la hora actual (HH MM SS)', () {
    final provider = buildProvider();
    final fileName = provider.pdfFileName();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');

    final stamp = fileName.substring(
      AppConstants.pdfFilePrefix.length,
      fileName.length - '.pdf'.length,
    );
    final parts = stamp.split('_');

    expect(parts, hasLength(2));
    expect(parts[1], startsWith('${two(now.hour)}${two(now.minute)}'));
    expect(parts[1], '${two(now.hour)}${two(now.minute)}${two(now.second)}');
  });
}