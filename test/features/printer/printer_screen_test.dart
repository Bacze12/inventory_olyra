import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/features/printer/label_print_service.dart';
import 'package:scanflow/features/printer/printer_screen.dart';
import 'package:scanflow/features/products/product_provider.dart';

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository(this._products) : super(AppDatabase.instance);

  final List<Product> _products;

  @override
  Future<List<Product>> all({String? query}) async => _products;
}

Product _product(
  String name,
  String barcode, {
  int quantity = 5,
  int minStock = 2,
}) =>
    Product(
      name: name,
      barcode: barcode,
      quantity: quantity,
      minStock: minStock,
      createdAt: '2026-01-01T00:00:00',
      updatedAt: '2026-01-01T00:00:00',
    );

class _RecordingLabelPrintService extends LabelPrintService {
  final List<List<Product>> printed = [];

  @override
  Future<void> printAllLabels(List<Product> products) async {
    printed.add(products);
  }
}

Widget _buildApp(ProductProvider provider, LabelPrintService labelService) {
  return ChangeNotifierProvider<ProductProvider>.value(
    value: provider,
    child: MaterialApp(
      home: PrinterScreen(labelService: labelService),
    ),
  );
}

void main() {
  testWidgets('muestra la opción de imprimir todos cuando hay productos',
      (tester) async {
    final provider = ProductProvider(_FakeProductRepository([
      _product('Azúcar', '7501001'),
      _product('Fideo', '7501002'),
    ]));
    await provider.load();

    await tester.pumpWidget(
      _buildApp(provider, const LabelPrintService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Imprimir todos (PDF)'), findsOneWidget);
  });

  testWidgets('oculta la opción de imprimir todos sin productos',
      (tester) async {
    final provider = ProductProvider(_FakeProductRepository(const []));
    await provider.load();

    await tester.pumpWidget(
      _buildApp(provider, const LabelPrintService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Imprimir todos (PDF)'), findsNothing);
  });

  testWidgets('al tocar imprimir todos envía todos los productos del listado',
      (tester) async {
    final products = [
      _product('Azúcar', '7501001'),
      _product('Fideo', '7501002'),
    ];
    final provider = ProductProvider(_FakeProductRepository(products));
    await provider.load();
    final service = _RecordingLabelPrintService();

    await tester.pumpWidget(_buildApp(provider, service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Imprimir todos (PDF)'));
    await tester.pumpAndSettle();

    expect(service.printed, hasLength(1));
    expect(service.printed.single.map((p) => p.barcode).toList(),
        ['7501001', '7501002']);
  });
}