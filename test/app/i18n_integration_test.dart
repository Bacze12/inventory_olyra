import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/app/app.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('scanflow_app_i18n_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('al elegir English la pantalla principal cambia a inglés',
      (tester) async {
    await tester.pumpWidget(const InventarioApp());
    await tester.pumpAndSettle();

    expect(find.text('Productos'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsWidgets);
    expect(find.text('Productos'), findsNothing);
  });
}