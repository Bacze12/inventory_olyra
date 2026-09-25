import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/i18n/app_strings.dart';
import '../data/database/app_database.dart';
import '../data/repositories/movement_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../features/home/home_screen.dart';
import '../features/pro/in_app_purchase_gateway.dart';
import '../features/pro/pro_provider.dart';
import '../features/products/product_provider.dart';
import '../features/reports/report_provider.dart';
import '../features/scanner/scanner_provider.dart';
import '../features/settings/language_provider.dart';
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
        ChangeNotifierProvider<ReportProvider>(
          create: (ctx) => ReportProvider(
            productRepository: ctx.read<ProductRepository>(),
            settingsRepository: ctx.read<SettingsRepository>(),
          )..init(),
        ),
        ChangeNotifierProvider<LanguageProvider>(
          create: (ctx) => LanguageProvider(ctx.read<SettingsRepository>())
            ..init(),
        ),
        ChangeNotifierProvider<ProProvider>(
          create: (ctx) => ProProvider(
            productRepository: ctx.read<ProductRepository>(),
            settingsRepository: ctx.read<SettingsRepository>(),
            billing: InAppPurchaseGateway(),
          )..init(),
        ),
      ],
      child: Builder(
        builder: (context) {
          final language = context.watch<LanguageProvider>();
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: language.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}