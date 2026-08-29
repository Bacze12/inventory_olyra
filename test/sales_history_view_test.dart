import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/features/sales/sales_provider.dart';
import 'package:scanflow/views/sales/sales_history_view.dart';

Widget _buildApp(Size size) {
  return ChangeNotifierProvider<SalesProvider>(
    create: (ctx) => SalesProvider(
      salesRepository: SalesRepository(AppDatabase.instance),
      movementRepository: MovementRepository(AppDatabase.instance),
    ),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: SalesHistoryView(),
        ),
      ),
    ),
  );
}

void main() {
  for (final size in const [Size(1440, 900), Size(900, 700), Size(600, 800)]) {
    testWidgets('Historial sin excepciones de layout en '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildApp(size));
      await tester.pumpAndSettle();

      expect(find.text('Historial de ventas'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);

      for (final range in ['Hoy', 'Esta semana', 'Este mes', 'Todo']) {
        await tester.tap(find.widgetWithText(ChoiceChip, range));
        await tester.pumpAndSettle();
      }
    });
  }
}