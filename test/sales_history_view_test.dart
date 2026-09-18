import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/features/sales/sales_provider.dart';
import 'package:scanflow/l10n/app_localizations.dart';
import 'package:scanflow/views/sales/sales_history_view.dart';

/// path_provider no se registra en pruebas: en lugar de colgar la apertura de
/// la BD (ver `AppDatabase._ensureDatabaseDirectory`), se fuerza el fallback al
/// override de sqflite (`databaseFactoryFfi.setDatabasesPath`).
class _ThrowingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() =>
      throw UnimplementedError('test: path_provider no disponible');

  @override
  Future<String?> getApplicationDocumentsPath() =>
      throw UnimplementedError('test: path_provider no disponible');

  @override
  Future<String?> getTemporaryPath() =>
      throw UnimplementedError('test: path_provider no disponible');
}

Widget _buildApp(Size size) {
  return ChangeNotifierProvider<SalesProvider>(
    create: (ctx) => SalesProvider(
      salesRepository: SalesRepository(AppDatabase.instance),
      movementRepository: MovementRepository(AppDatabase.instance),
      productRepository: ProductRepository(AppDatabase.instance),
    ),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('es'), Locale('en')],
      locale: const Locale('es'),
      home: Scaffold(
        body: SizedBox.expand(
          child: SalesHistoryView(),
        ),
      ),
    ),
  );
}

/// Bombea `n` frames con duraciones fijas. No usa pumpAndSettle: el cursor del
/// buscador y los futuribles de sqflite (zona FakeAsync) impiden el "settle".
Future<void> _pumpFrames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUpAll(() async {
    PathProviderPlatform.instance = _ThrowingPathProvider();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir =
        Directory.systemTemp.createTempSync('scanflow_sh_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
    // Abre la BD FUERA del FakeAsync de los testWidgets: sqflite_common_ffi
    // no completa su open dentro de pumpAndSettle (timers falsos). Una vez
    // cacheado en AppDatabase, los tests usan la instancia ya abierta.
    await AppDatabase.instance.database;
  });
  for (final size in const [Size(1440, 900), Size(900, 700), Size(600, 800)]) {
    testWidgets('Historial sin excepciones de layout en '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
      // pumpWidget dentro de runAsync: la carga de SalesProvider usa
      // sqflite_common_ffi, cuyas queries NO avanzan dentro del FakeAsync y
      // dejan timers de 10s pendientes que rompen el teardown. El delay real
      // deja terminar la consulta con async real.
      await tester.pumpWidget(_buildApp(size));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await _pumpFrames(tester);

    expect(find.text('Historial de ventas'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);

      for (final range in ['Hoy', 'Esta semana', 'Este mes', 'Todo']) {
        await tester.tap(find.widgetWithText(ChoiceChip, range));
        await _pumpFrames(tester);
        // Deja terminar la consulta (async REAL) y cancela el lock-timer de
        // sqflite; si no, queda un FakeTimer de 10s pendiente al terminar.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await _pumpFrames(tester, 4);
      }
    });
  }
}