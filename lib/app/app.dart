import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../data/database/app_database.dart';
import '../data/repositories/cash_repository.dart';
import '../data/repositories/movement_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/pairing_service.dart';
import '../data/services/sync_service.dart';
import '../features/cash/cash_provider.dart';
import '../features/home/home_screen.dart';
import '../features/products/product_provider.dart';
import '../features/reports/report_provider.dart';
import '../features/sales/sales_provider.dart';
import '../features/scanner/scanner_provider.dart';
import '../views/pos/cart_provider.dart';
import 'theme/app_theme.dart';

class InventarioApp extends StatelessWidget {
  const InventarioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ProductRepository>(
          create: (_) => ProductRepository(AppDatabase.instance),
        ),
        Provider<MovementRepository>(
          create: (_) => MovementRepository(AppDatabase.instance),
        ),
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(AppDatabase.instance),
        ),
        Provider<PairingService>(
          create: (ctx) => PairingService(
            settings: DbPairingSettingsSource(ctx.read<SettingsRepository>()),
          ),
        ),
        Provider<SalesRepository>(
          create: (_) => SalesRepository(AppDatabase.instance),
        ),
        Provider<CashRepository>(
          create: (_) => CashRepository(AppDatabase.instance),
        ),
        // Cliente de sincronización Wi-Fi con la PC: disponible en todo el
        // árbol (sobre MaterialApp) para HomeScreen y los flujos de sync.
        Provider<SyncService>(
          create: (ctx) => SyncService(
            products: ctx.read<ProductRepository>(),
            sales: ctx.read<SalesRepository>(),
            pairing: ctx.read<PairingService>(),
          ),
        ),
        ChangeNotifierProvider<SalesProvider>(
          create: (ctx) => SalesProvider(
            salesRepository: ctx.read<SalesRepository>(),
            movementRepository: ctx.read<MovementRepository>(),
          ),
        ),
        ChangeNotifierProvider<ProductProvider>(
          create: (ctx) =>
              ProductProvider(ctx.read<ProductRepository>()),
        ),
        ChangeNotifierProvider<ScannerProvider>(
          create: (ctx) => ScannerProvider(
            productRepository: ctx.read<ProductRepository>(),
            movementRepository: ctx.read<MovementRepository>(),
          ),
        ),
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(),
        ),
        ChangeNotifierProvider<CashProvider>(
          create: (ctx) => CashProvider(
            cashRepository: ctx.read<CashRepository>(),
          ),
        ),
        ChangeNotifierProvider<ReportProvider>(
          create: (ctx) => ReportProvider(
            productRepository: ctx.read<ProductRepository>(),
            settingsRepository: ctx.read<SettingsRepository>(),
          )..init(),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}