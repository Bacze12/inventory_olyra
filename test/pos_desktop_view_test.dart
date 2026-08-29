import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/models/product.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/features/products/product_provider.dart';
import 'package:scanflow/views/pos/cart_provider.dart';
import 'package:scanflow/views/pos/pos_desktop_view.dart';

Product _product(int id, String name, int stock) => Product(
      id: id,
      name: name,
      barcode: '78012345678$id',
      quantity: stock,
      minStock: 1,
      price: 1490.5,
      createdAt: '2026-01-01T00:00:00',
      updatedAt: '2026-01-01T00:00:00',
    );

Widget _buildApp() {
  return MultiProvider(
    providers: [
      Provider<ProductRepository>(
        create: (_) => ProductRepository(AppDatabase.instance),
      ),
      Provider<MovementRepository>(
        create: (_) => MovementRepository(AppDatabase.instance),
      ),
      ChangeNotifierProvider<ProductProvider>(
        create: (ctx) => ProductProvider(ctx.read<ProductRepository>()),
      ),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider(),
      ),
    ],
    child: const MaterialApp(home: PosDesktopView()),
  );
}

Future<void> _pumpWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_buildApp());
  await tester.pumpAndSettle();

  final cart = Provider.of<CartProvider>(
    tester.element(find.byType(PosDesktopView)),
    listen: false,
  );
  cart.addProduct(_product(1, 'Agua mineral 500 ml', 24));
  cart.addProduct(_product(1, 'Agua mineral 500 ml', 24));
  cart.addProduct(
    _product(2, 'Pan amasado grande ultra premium familiar', 6),
  );
  cart.setTaxRate(0.19);
  await tester.pump();
}

void main() {
  final sizes = <Size>[
    const Size(1440, 900),
    const Size(1280, 720),
    const Size(1024, 768),
    const Size(830, 620),
    const Size(640, 480),
  ];

  for (final size in sizes) {
    testWidgets('POS sin excepciones de layout en '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _pumpWindow(tester, size);

      await tester.tap(find.text('COBRAR / FINALIZAR VENTA'));
      await tester.pumpAndSettle();
      expect(find.text('Finalizar venta'), findsOneWidget);
      expect(find.text('Confirmar venta'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Finalizar venta'), findsNothing);
    });
  }

  testWidgets('Atajo F12 abre el modal de cobro', (tester) async {
    await _pumpWindow(tester, const Size(1280, 720));

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    expect(find.text('Finalizar venta'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
}