import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanflow/core/config/olyra_config.dart';
import 'package:scanflow/data/database/app_database.dart';
import 'package:scanflow/data/remote/olyra_license_api.dart';
import 'package:scanflow/data/remote/olyra_pos_api.dart';
import 'package:scanflow/data/repositories/movement_repository.dart';
import 'package:scanflow/data/repositories/product_repository.dart';
import 'package:scanflow/data/repositories/sales_repository.dart';
import 'package:scanflow/data/repositories/settings_repository.dart';
import 'package:scanflow/features/activation/license_credential_store.dart';
import 'package:scanflow/features/activation/olyra_license_controller.dart';
import 'package:scanflow/features/products/product_provider.dart';
import 'package:scanflow/features/sync/olyra_cloud_sync.dart';
import 'package:scanflow/services/hardware_id_service.dart';

// Copia el CONTRATO del Ã¡rbol de `app.dart`:
// OlyraLicenseController debe estar ANTES de todo consumidor que lo inyecta
// por constructor (ProductProvider, OlyraCloudSync).
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    Provider.of<OlyraLicenseController>(context, listen: false);
    Provider.of<ProductProvider>(context, listen: false);
    Provider.of<OlyraCloudSync>(context, listen: false);
    return const SizedBox.shrink();
  }
}

OlyraLicenseController _licenseStub() => OlyraLicenseController(
      hardware: HardwareIdService(const FlutterSecureStorage()),
      api: OlyraLicenseApi(
        activationUrl: OlyraConfig.activationUrl,
        validateUrl: OlyraConfig.validateUrl,
      ),
      credentials: LicenseCredentialStore(const FlutterSecureStorage()),
      publicKeyPem: OlyraConfig.publicKeyPem,
    );

List<SingleChildWidget> _repos() => <SingleChildWidget>[
      Provider<ProductRepository>(
        create: (_) => ProductRepository(AppDatabase.instance),
      ),
      Provider<MovementRepository>(
        create: (_) => MovementRepository(AppDatabase.instance),
      ),
      Provider<SalesRepository>(
        create: (_) => SalesRepository(AppDatabase.instance),
      ),
      Provider<SettingsRepository>(
        create: (_) => SettingsRepository(AppDatabase.instance),
      ),
    ];

List<SingleChildWidget> _consumers() => <SingleChildWidget>[
      ChangeNotifierProvider<ProductProvider>(
        create: (ctx) => ProductProvider(
          ctx.read<ProductRepository>(),
          ctx.read<OlyraLicenseController>(),
        ),
      ),
      ChangeNotifierProvider<OlyraCloudSync>(
        create: (ctx) => OlyraCloudSync(
          license: ctx.read<OlyraLicenseController>(),
          credentials: ctx.read<LicenseCredentialStore>(),
          api: ctx.read<OlyraPosApi>(),
          sales: ctx.read<SalesRepository>(),
          movements: ctx.read<MovementRepository>(),
          settings: ctx.read<SettingsRepository>(),
        ),
      ),
    ];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir =
        Directory.systemTemp.createTempSync('scanflow_arch_providers_');
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  testWidgets(
      'contrato: licencia ANTES de los consumidores â†’ sin ProviderNotFoundError',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ..._repos(),
          Provider<LicenseCredentialStore>(
            create: (_) => LicenseCredentialStore(const FlutterSecureStorage()),
          ),
          Provider<OlyraLicenseApi>(
            create: (_) => OlyraLicenseApi(
              activationUrl: OlyraConfig.activationUrl,
              validateUrl: OlyraConfig.validateUrl,
            ),
          ),
          Provider<OlyraPosApi>(
            create: (_) => OlyraPosApi(syncUrl: OlyraConfig.posSyncUrl),
          ),
          ChangeNotifierProvider<OlyraLicenseController>(
            create: (_) => _licenseStub(),
          ),
          ..._consumers(),
        ],
        child: const _Probe(),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'el Ã¡rbol con el orden correcto no debe lanzar nada');
  });

  testWidgets(
      'regresiÃ³n: consumidores ANTES de la licencia â†’ ProviderNotFoundError',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ..._repos(),
          Provider<LicenseCredentialStore>(
            create: (_) => LicenseCredentialStore(const FlutterSecureStorage()),
          ),
          Provider<OlyraLicenseApi>(
            create: (_) => OlyraLicenseApi(
              activationUrl: OlyraConfig.activationUrl,
              validateUrl: OlyraConfig.validateUrl,
            ),
          ),
          Provider<OlyraPosApi>(
            create: (_) => OlyraPosApi(syncUrl: OlyraConfig.posSyncUrl),
          ),
          ..._consumers(),
          // OlyraLicenseController DEMASIADO TARDE: reproduce el bug de v1.3.0.
          ChangeNotifierProvider<OlyraLicenseController>(
            create: (_) => _licenseStub(),
          ),
        ],
        child: const _Probe(),
      ),
    ));
await tester.pump();
    final error = tester.takeException();
    expect(error, isNotNull,
        reason: 'el orden roto debe fallar en tiempo de creación');
    expect(error.toString(), contains('OlyraLicenseController'));

    // Desmonta el árbol roto AQUÍ (el ChangeNotifierProvider cuyo create
    // falló deja un valor null y al finalizar el test lanzaría un cast).
    await tester.pumpWidget(const SizedBox());
    tester.takeException();
  });
}
