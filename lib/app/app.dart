import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/config/olyra_config.dart';
import '../data/cloud/supabase_gateway.dart';
import '../data/database/app_database.dart';
import '../data/remote/olyra_license_api.dart';
import '../data/repositories/movement_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/pairing_service.dart';
import '../data/services/sync_service.dart';
import '../features/activation/olyra_license_controller.dart';
import '../features/activation/startup_gate.dart';
import '../features/activation/license_credential_store.dart';
import '../features/license/license_service.dart';
import '../features/products/product_provider.dart';
import '../features/reports/report_provider.dart';
import '../features/sales/sales_provider.dart';
import '../features/scanner/scanner_provider.dart';
import '../features/sync/backup_service.dart';
import '../features/sync/cloud_sync_manager.dart';
import '../services/hardware_id_service.dart';
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
        ChangeNotifierProvider<ReportProvider>(
          create: (ctx) => ReportProvider(
            productRepository: ctx.read<ProductRepository>(),
            settingsRepository: ctx.read<SettingsRepository>(),
          )..init(),
        ),
        // ---- Nube (Supabase): licencia, sincronización y respaldos. ----
        // Se auto-desactivan cuando no hay credenciales compiladas, así la app
        // nunca pierde su modo 100% local.
        Provider<SupabaseGateway>(
          create: (_) => SupabaseGateway.instance,
        ),
        Provider<HardwareIdService>(
          create: (_) => HardwareIdService(const FlutterSecureStorage()),
        ),
        Provider<LicenseCredentialStore>(
          create: (_) => LicenseCredentialStore(const FlutterSecureStorage()),
        ),
        // ---- Licenciamiento offline (olyra.cl + JWT RS256) ----
        Provider<OlyraLicenseApi>(
          create: (_) => OlyraLicenseApi(
            activationUrl: OlyraConfig.activationUrl,
            validateUrl: OlyraConfig.validateUrl,
          ),
        ),
        ChangeNotifierProvider<OlyraLicenseController>(
          create: (ctx) => OlyraLicenseController(
            hardware: ctx.read<HardwareIdService>(),
            api: ctx.read<OlyraLicenseApi>(),
            credentials: ctx.read<LicenseCredentialStore>(),
            publicKeyPem: OlyraConfig.publicKeyPem,
          )..init(),
        ),
        ChangeNotifierProvider<LicenseService>(
          create: (ctx) => LicenseService(
            gateway: ctx.read<SupabaseGateway>(),
            hardware: ctx.read<HardwareIdService>(),
            settings: ctx.read<SettingsRepository>(),
          )..init(),
        ),
        ChangeNotifierProvider<CloudSyncManager>(
          create: (ctx) => CloudSyncManager(
            gateway: ctx.read<SupabaseGateway>(),
            license: ctx.read<LicenseService>(),
            products: ctx.read<ProductRepository>(),
            movements: ctx.read<MovementRepository>(),
            sales: ctx.read<SalesRepository>(),
            settings: ctx.read<SettingsRepository>(),
          )..start(),
        ),
        ChangeNotifierProvider<BackupService>(
          create: (ctx) => BackupService(
            gateway: ctx.read<SupabaseGateway>(),
            license: ctx.read<LicenseService>(),
            products: ctx.read<ProductRepository>(),
            movements: ctx.read<MovementRepository>(),
            sales: ctx.read<SalesRepository>(),
            settings: ctx.read<SettingsRepository>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const StartupGate(),
      ),
    );
  }
}