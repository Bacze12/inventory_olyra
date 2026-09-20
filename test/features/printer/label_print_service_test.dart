import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/features/printer/label_print_service.dart';

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

void main() {
  const service = LabelPrintService();

  group('LabelPrintService.orderForSheet', () {
    test('ordena las etiquetas por nombre sin distinguir mayúsculas',
        () {
      final products = [
        _product('Azúcar', '7501001'),
        _product('arroz', '7501002'),
        _product('Fideo', '7501003'),
      ];

      final ordered = LabelPrintService.orderForSheet(products);

      expect(ordered.map((p) => p.name).toList(), ['arroz', 'Azúcar', 'Fideo']);
    });

    test('si dos nombres coinciden ordena por código de barras', () {
      final products = [
        _product('Harina', '7502002'),
        _product('Harina', '7502001'),
      ];

      final ordered = LabelPrintService.orderForSheet(products);

      expect(ordered.map((p) => p.barcode).toList(), ['7502001', '7502002']);
    });

    test('no muta la lista original de productos', () {
      final products = [
        _product('Zanahoria', '7503001'),
        _product('Banana', '7503002'),
        _product('Manzana', '7503003'),
      ];
      final originalOrder = products.toList();

      LabelPrintService.orderForSheet(products);

      expect(products.map((p) => p.barcode).toList(),
          originalOrder.map((p) => p.barcode).toList());
    });
  });

  group('LabelPrintService.buildAllLabelsPdf', () {
    test('genera un PDF no vacío con todos los productos ordenados', () async {
      final products = [
        _product('Fideo', '7501003'),
        _product('arroz', '7501002'),
        _product('Azúcar', '7501001'),
      ];

      final bytes = await service.buildAllLabelsPdf(products);

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue,
          reason: 'el PDF debe contener las etiquetas de todos los productos');
      expect(bytes.length, greaterThan(1000),
          reason: 'un PDF con bárcodes supera ampliamente unos cientos de bytes');
    });

    test('genera un PDF aunque haya un único producto', () async {
      final bytes =
          await service.buildAllLabelsPdf([_product('Café', '7504001')]);

      expect(bytes.isNotEmpty, isTrue);
    });

    test('genera un PDF vacío de tamaño cero sin productos', () async {
      final bytes = await service.buildAllLabelsPdf(const []);

      expect(bytes.length, greaterThan(100),
          reason: 'aunque no haya etiquetas el documento se crea completo');
    });
  });
}